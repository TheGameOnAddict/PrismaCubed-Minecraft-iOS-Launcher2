#import "CubicDownloadsController.h"
#import "DownloadTaskManager.h"
#import "DownloadHistoryStore.h"
#import "DownloadTasksViewController.h"
#import "PLTaskProgressViewController.h"
#import "CubicProfileArtwork.h"
#import "ZL2Theme.h"

static NSString *TaskSummary(DownloadTaskItem *task) {
    PLTaskStage *stage = task.currentStage;
    NSMutableArray *parts = [NSMutableArray arrayWithObject:task.stateLabel];
    if (stage.title.length) [parts addObject:NSLocalizedString(stage.title, nil)];
    if (stage.totalFileCount > 0)
        [parts addObject:[NSString stringWithFormat:@"%ld/%ld files", (long)stage.completedFileCount, (long)stage.totalFileCount]];
    if (task.speed > 0 && task.state == DownloadTaskStateDownloading)
        [parts addObject:[[NSByteCountFormatter stringFromByteCount:task.speed countStyle:NSByteCountFormatterCountStyleFile] stringByAppendingString:@"/s"]];
    return [parts componentsJoinedByString:@" · "];
}

@interface CubicDownloadLog : UIViewController
@property(nonatomic,strong) DownloadTaskItem *task;
@property(nonatomic,strong) UITextView *logView;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UIProgressView *progress;
@end

@implementation CubicDownloadLog
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.task.displayName;
    self.view.backgroundColor = ZL2Theme.surface;
    self.status = [UILabel new];
    self.status.numberOfLines = 0;
    self.status.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.status.textColor = ZL2Theme.onSurface;
    self.progress = [UIProgressView new];
    self.progress.progressTintColor = ZL2Theme.primary;
    self.logView = [UITextView new];
    self.logView.editable = NO;
    self.logView.backgroundColor = ZL2Theme.surfaceContainer;
    self.logView.textColor = ZL2Theme.onSurface;
    self.logView.layer.cornerRadius = 10;
    self.logView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.logView.textContainerInset = UIEdgeInsetsMake(12, 8, 12, 8);
    self.logView.accessibilityLabel = @"Download log";
    UILabel *heading = [UILabel new];
    heading.text = @"Activity log";
    heading.textColor = ZL2Theme.onSurface;
    heading.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.status,self.progress,heading,self.logView]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16]
    ]];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Copy log" style:UIBarButtonItemStylePlain target:self action:@selector(copyLog)];
    if ([DownloadTaskManager.sharedManager taskWithId:self.task.taskId]) {
        self.toolbarItems = @[[[UIBarButtonItem alloc] initWithTitle:@"Task details & controls" style:UIBarButtonItemStylePlain target:self action:@selector(controls)]];
    }
    [self refresh];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updated:) name:DownloadTaskManagerDidUpdateTaskNotification object:nil];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.navigationController setToolbarHidden:self.toolbarItems.count == 0 animated:animated]; }
- (void)controls { [PLTaskProgressViewController presentForTaskId:self.task.taskId]; }
- (void)copyLog { UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%@\n%@\n%@", self.title, self.status.text, self.logView.text]; }
- (void)updated:(NSNotification *)note {
    DownloadTaskItem *item = note.userInfo[DownloadTaskManagerTaskKey];
    if ([item.taskId isEqual:self.task.taskId]) [self refresh];
}
- (void)refresh {
    DownloadTaskItem *task = self.task;
    self.progress.progress = task.installProgress;
    self.status.text = TaskSummary(task);
    NSMutableArray *lines = [task.activityLines mutableCopy];
    // Older builds saved stage messages even when they discarded the top-level error.
    if (!lines.count) {
        for (PLTaskStage *stage in task.stages) {
            if (stage.status == PLTaskStageStatusPending) continue;
            [lines addObject:NSLocalizedString(stage.title, nil)];
            if (stage.message.length) [lines addObject:stage.message];
        }
    }
    if (task.currentFile.length) [lines addObject:task.currentFile];
    if (task.errorInfo) {
        NSString *reason = task.errorInfo.localizedDescription;
        if (![lines.lastObject containsString:reason]) [lines addObject:reason];
    }
    if (!lines.count) [lines addObject:TaskSummary(task)];
    NSString *body = [lines componentsJoinedByString:@"\n"];
    if ([self.logView.text isEqual:body]) return;
    BOOL follow = self.logView.contentOffset.y + self.logView.bounds.size.height >= self.logView.contentSize.height - 28;
    self.logView.text = body;
    if (follow && body.length) [self.logView scrollRangeToVisible:NSMakeRange(body.length - 1, 1)];
}
@end

@interface CubicDownloadsController ()
@property(nonatomic,copy) NSArray<NSArray<DownloadTaskItem *> *> *groups;
@property(nonatomic,copy) NSArray<NSString *> *headings;
@property(nonatomic) BOOL refreshPending;
@end

@implementation CubicDownloadsController
+ (void)showFrom:(UIViewController *)presenter task:(DownloadTaskItem *)task {
    CubicDownloadsController *list = [[self alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:list];
    nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    nav.view.tintColor = ZL2Theme.primary;
    if (task) {
        CubicDownloadLog *log = [CubicDownloadLog new];
        log.task = task;
        [nav pushViewController:log animated:NO];
    }
    [presenter presentViewController:nav animated:YES completion:nil];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Downloads";
    self.tableView.backgroundColor = ZL2Theme.surface;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 76;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Manage" style:UIBarButtonItemStylePlain target:self action:@selector(manage)];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(scheduleRefresh:) name:DownloadTaskManagerDidUpdateTaskNotification object:nil];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setToolbarHidden:YES animated:animated];
    [self reload];
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)manage { [self presentViewController:[DownloadTasksViewController new] animated:YES completion:nil]; }
- (void)scheduleRefresh:(NSNotification *)note {
    if (self.refreshPending || !self.viewIfLoaded.window) return;
    self.refreshPending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC/3),dispatch_get_main_queue(), ^{
        self.refreshPending = NO;
        if (self.view.window) [self reload];
    });
}
- (void)reload {
    NSMutableArray *running = [NSMutableArray array], *queue = [NSMutableArray array], *failed = [NSMutableArray array], *finished = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    NSArray *live = [DownloadTaskManager.sharedManager.allTasks sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"createdDate" ascending:NO]]];
    for (DownloadTaskItem *task in live) {
        [seen addObject:task.taskId];
        if (task.parentTaskId.length) continue;
        switch (task.state) {
            case DownloadTaskStateDownloading: [running addObject:task]; break;
            case DownloadTaskStatePaused: case DownloadTaskStatePending: [queue addObject:task]; break;
            case DownloadTaskStateFailed: [failed addObject:task]; break;
            default: [finished addObject:task]; break;
        }
    }
    for (NSDictionary *entry in DownloadHistoryStore.sharedStore.allEntries) {
        if (!entry[@"taskId"] || [seen containsObject:entry[@"taskId"]]) continue;
        DownloadTaskItem *task = [[DownloadTaskItem alloc] initWithSnapshotDictionary:entry[@"snapshot"]];
        if (!task || task.parentTaskId.length) continue;
        [seen addObject:task.taskId];
        [(task.state == DownloadTaskStateFailed ? failed : finished) addObject:task];
    }
    NSArray *buckets = @[running,queue,failed,finished];
    NSArray *titles = @[@"In progress",@"Queue",@"Failed",@"Recent downloads"];
    NSMutableArray *groups = [NSMutableArray array], *headings = [NSMutableArray array];
    for (NSUInteger i=0; i<buckets.count; i++) {
        if (![buckets[i] count]) continue;
        [groups addObject:buckets[i]];
        [headings addObject:titles[i]];
    }
    [self showFeaturedTransfer:running.firstObject ?: failed.firstObject ?: finished.firstObject];
    self.groups = groups;
    self.headings = headings;
    UILabel *empty = [UILabel new];
    empty.text = @"No downloads yet";
    empty.textAlignment = NSTextAlignmentCenter;
    empty.textColor = ZL2Theme.onSurfaceVariant;
    self.tableView.backgroundView = groups.count ? nil : empty;
    [self.tableView reloadData];
}
- (void)showFeaturedTransfer:(DownloadTaskItem *)task {
    if (!task) { self.tableView.tableHeaderView = nil; return; }
    UIView *hero = [[UIView alloc] initWithFrame:CGRectMake(0,0,self.tableView.bounds.size.width,134)];
    UIImageView *cover = [[UIImageView alloc] initWithImage:CubicProfileArtwork(nil,task.displayName)];
    cover.frame = hero.bounds;
    cover.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    cover.contentMode = UIViewContentModeScaleAspectFill;
    cover.clipsToBounds = YES;
    [hero addSubview:cover];
    UIView *shade = [[UIView alloc] initWithFrame:hero.bounds];
    shade.autoresizingMask = cover.autoresizingMask;
    shade.backgroundColor = [UIColor colorWithWhite:0.04 alpha:0.78];
    [hero addSubview:shade];
    UILabel *name = [UILabel new];
    name.text = task.displayName;
    name.font = [UIFont boldSystemFontOfSize:24];
    name.textColor = UIColor.whiteColor;
    UILabel *status = [UILabel new];
    status.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    status.textColor = UIColor.whiteColor;
    status.text = TaskSummary(task);
    UILabel *metric = [UILabel new];
    metric.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    metric.textColor = UIColor.whiteColor;
    metric.text = [NSString stringWithFormat:@"%.0f%%",task.installProgress * 100];
    if (task.downloadedSize > 0) metric.text = [metric.text stringByAppendingFormat:@"   %@",[NSByteCountFormatter stringFromByteCount:task.downloadedSize countStyle:NSByteCountFormatterCountStyleFile]];
    UIProgressView *bar = [UIProgressView new];
    bar.progressTintColor = ZL2Theme.primary;
    bar.trackTintColor = [UIColor colorWithWhite:1 alpha:0.27];
    bar.progress = task.installProgress;
    UIStackView *info = [[UIStackView alloc] initWithArrangedSubviews:@[name,status,metric,bar]];
    info.axis = UILayoutConstraintAxisVertical;
    info.spacing = 6;
    info.translatesAutoresizingMaskIntoConstraints = NO;
    [hero addSubview:info];
    [NSLayoutConstraint activateConstraints:@[
        [info.leadingAnchor constraintEqualToAnchor:hero.leadingAnchor constant:20],
        [info.trailingAnchor constraintEqualToAnchor:hero.trailingAnchor constant:-20],
        [info.centerYAnchor constraintEqualToAnchor:hero.centerYAnchor]
    ]];
    self.tableView.tableHeaderView = hero;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.groups.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.groups[section].count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return self.headings[section]; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    DownloadTaskItem *task = self.groups[path.section][path.row];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"transfer"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"transfer"];
    UIListContentConfiguration *row = cell.defaultContentConfiguration;
    row.text = task.displayName;
    row.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    row.textProperties.color = ZL2Theme.onSurface;
    row.secondaryTextProperties.color = task.state == DownloadTaskStateFailed ? UIColor.systemRedColor : ZL2Theme.onSurfaceVariant;
    row.secondaryTextProperties.numberOfLines = 3;
    NSString *detail = task.errorInfo.localizedDescription ?: task.currentStage.message ?: task.currentFile;
    row.secondaryText = [NSString stringWithFormat:@"%@%@%@",TaskSummary(task),detail.length ? @"\n" : @"",detail ?: @""];
    if (task.state == DownloadTaskStateDownloading) row.secondaryText = [NSString stringWithFormat:@"%.0f%% · %@", task.installProgress * 100,row.secondaryText];
    row.image = task.isProfileInstall ? CubicProfileArtwork(nil,task.displayName) : [UIImage systemImageNamed:@"arrow.down.circle"];
    row.imageProperties.maximumSize = CGSizeMake(52,52);
    row.imageProperties.cornerRadius = 7;
    row.imageProperties.tintColor = ZL2Theme.primary;
    cell.contentConfiguration = row;
    cell.backgroundColor = ZL2Theme.surfaceContainer;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    CubicDownloadLog *log = [CubicDownloadLog new];
    log.task = self.groups[path.section][path.row];
    [self.navigationController pushViewController:log animated:YES];
}
@end
