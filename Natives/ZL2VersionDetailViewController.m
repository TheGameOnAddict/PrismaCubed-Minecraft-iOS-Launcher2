#import "FolderBrowserViewController.h"
#import "ZL2AssetSearchViewController.h"
//
// ZL2VersionDetailViewController.m — ZL2 版本详情容器实现（7.0-UI-13-V）
//
// 视觉对标（ZalithLauncher2 VersionSettingsScreen.kt L95-246 实证）：
//   · 头卡 = M3 Surface(surfaceContainer/radiusM)：加载器图标 34dp
//     （ModLoaderIconHelper 检出；取不到 → surfaceVariant radiusS 容器 +
//     gamecontroller 兜底，ZL2VersionsViewController 卡内同款手法）+
//     版本名（titleMedium）/ 描述行（bodyMedium, onSurfaceVariant）+
//     标签行（MC版本 · 加载器，labelSmall alpha 0.7）+ 右侧「完成」文本钮。
//   · TabMenu = 竖排 NavigationRailItem 列（IntrinsicSize.Min，顶部起排）：
//     32dp 图标胶囊 + 4dp 间距 + labelMedium 标签；active = primaryContainer
//     胶囊 + onPrimaryContainer 图标 + primary 标签；inactive = 透明胶囊 +
//     onSurfaceVariant。division 分隔线（onSurface alpha 0.4）同位移植：
//     ZL2 在 ModsManager 与 ServerList 前（VersionSettingsScreen.kt L159-168）。
//   · 内容切换 = 子页懒建缓存 + addChild + 0.18s crossDissolve
//     （ZL2ShellViewController.m ame_attachChildIfNeeded/showPage 同手法）。
//
// 八子页（NormalNavKey.Versions.* → iOS）：概览/模组/存档/资源包/光影/
//   截图/服务器/配置（ZL2 的 ModifyVersion 编辑页语义折入概览页管理组，
//   见任务规格）。子页实现全量在 ZL2VersionPages.m。
//

#import "ZL2VersionDetailViewController.h"
#import "ZL2Theme.h"
#import "ZL2VersionPages.h"
#import "PLProfiles.h"
#import "ModLoaderIconHelper.h"
#import "CubicProfileArtwork.h"
#import "ModpackExportService.h"
#import "ModService.h"
#import "utils.h"   // localize()

#pragma mark - 常量

// 内容列边距/宽度（ZL2VersionsViewController 同款 999 等式宽度方案）
static const CGFloat ZL2V13PageMargin = 16.0;
static const CGFloat ZL2V13ContentMaxWidth = 720.0;
static const CGFloat ZL2V13RailWidth = 160.0;          // 任务规格：左轨 160pt（iPhone 同宽）
static const CGFloat ZL2V13RailItemSize = 56.0;        // M3 NavigationRailItem 高
static const CGFloat ZL2V13RailCapsuleSize = 32.0;     // 32pt 胶囊
static const CGFloat ZL2V13AnimateDuration = 0.18;     // 全域动画时长（ZL2Shell 同款）

static UIImage *ZL2V13SystemImage(NSString *name, NSString *fallback) {
    UIImage *image = [UIImage systemImageNamed:name];
    if (!image && fallback) image = [UIImage systemImageNamed:fallback];
    if (!image) image = [UIImage systemImageNamed:@"circle"];
    return image;
}

#pragma mark - 私有导航项（ZL2RailItem 视觉同款）

@interface ZL2VersionDetailNavItem : UIControl
@property (nonatomic, strong) UIView *iconBg;
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, assign) NSInteger pageIndex;
- (void)ameV13_setSelected:(BOOL)selected;
@end

@implementation ZL2VersionDetailNavItem

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return self;
    _iconBg = [[UIView alloc] init];
    _iconBg.translatesAutoresizingMaskIntoConstraints = NO;
    _iconBg.layer.cornerRadius = ZL2V13RailCapsuleSize / 2.0;  // 全圆胶囊
    _iconBg.layer.masksToBounds = YES;
    [self addSubview:_iconBg];

    _icon = [[UIImageView alloc] init];
    _icon.translatesAutoresizingMaskIntoConstraints = NO;
    _icon.contentMode = UIViewContentModeScaleAspectFit;
    _icon.userInteractionEnabled = NO;
    [_iconBg addSubview:_icon];

    _label = [[UILabel alloc] init];
    _label.translatesAutoresizingMaskIntoConstraints = NO;
    _label.font = [ZL2Theme fontLabelMedium];
    _label.textAlignment = NSTextAlignmentCenter;
    _label.userInteractionEnabled = NO;
    [self addSubview:_label];

    [NSLayoutConstraint activateConstraints:@[
        [_iconBg.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_iconBg.topAnchor constraintEqualToAnchor:self.topAnchor constant:4],
        [_iconBg.widthAnchor constraintEqualToConstant:ZL2V13RailCapsuleSize],
        [_iconBg.heightAnchor constraintEqualToConstant:ZL2V13RailCapsuleSize],
        [_icon.centerXAnchor constraintEqualToAnchor:_iconBg.centerXAnchor],
        [_icon.centerYAnchor constraintEqualToAnchor:_iconBg.centerYAnchor],
        [_icon.widthAnchor constraintEqualToConstant:20],
        [_icon.heightAnchor constraintEqualToConstant:20],
        [_label.topAnchor constraintEqualToAnchor:_iconBg.bottomAnchor constant:2],
        [_label.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_label.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:2],
        [_label.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-2],
        [_label.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-2],
    ]];
    return self;
}

- (void)ameV13_setSelected:(BOOL)selected {
    self.iconBg.backgroundColor = selected ? [ZL2Theme primaryContainer] : [UIColor clearColor];
    self.icon.tintColor = selected ? [ZL2Theme onPrimaryContainer] : [ZL2Theme onSurfaceVariant];
    self.label.textColor = selected ? [ZL2Theme primary] : [ZL2Theme onSurfaceVariant];
    self.accessibilityTraits = selected ? UIAccessibilityTraitSelected : UIAccessibilityTraitButton;
}

@end

#pragma mark - 容器

@interface ZL2VersionDetailViewController ()

// 头卡
@property (nonatomic, strong) UIView *headerCard;
@property (nonatomic, strong) UIView *iconBg;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *descLabel;
@property (nonatomic, strong) UILabel *tagLabel;

// 左轨 / 内容
@property (nonatomic, strong) UIStackView *railStack;
@property (nonatomic, strong) NSMutableArray<ZL2VersionDetailNavItem *> *railItems;
@property (nonatomic, strong) UIView *contentContainer;

// 状态
@property (nonatomic, copy) NSString *ameV13_profileName;
@property (nonatomic, assign) NSInteger ameV13_selectedIndex;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UIViewController *> *ameV13_childCache;

@end

@implementation ZL2VersionDetailViewController

- (instancetype)initWithProfileName:(NSString *)profileName {
    self = [super init];
    if (!self) return self;
    _ameV13_profileName = [profileName copy];
    _ameV13_selectedIndex = -1;
    _ameV13_childCache = [NSMutableDictionary dictionary];
    self.title = profileName;
    return self;
}

#pragma mark - 实例名→游戏目录解析链（工具方法，全部子页枚举走它）

/// ModService.m resolveAbsoluteGameDirForProfile:（L212-243）同契约移植：
///   ① profile[@"gameDir"] 缺失/空/"." → Task225 隔离嗅探
///      （+[ModService ame225_sniffedIsolationGameDirForProfile:]，公共类
///      方法，与启动链 JavaLauncher L2435 / ModService 三处同源规则）；
///      未命中 → POJAV_GAME_DIR（NSHomeDirectory 兜底）。
///   ② 显式绝对路径 → 原样。
///   ③ 显式相对路径 → POJAV_GAME_DIR 拼接（剥 "./" 前缀）。
/// POJAV_GAME_DIR 本身 = instances/<general.game_directory> 软链
/// （VersionManagerViewController switchGameDirTo: L1624-1641 建立），
/// 故此链与 JavaLauncher L2422-2426 的启动目录解析终点一致。
+ (NSString *)ameV13_resolvedGameDirForProfileName:(NSString *)profileName {
    NSDictionary *prof = PLProfiles.current.profiles[profileName];
    if (![prof isKindOfClass:[NSDictionary class]]) prof = @{};
    NSString *gameDir = prof[@"gameDir"];
    if (![gameDir isKindOfClass:[NSString class]] || gameDir.length == 0 || [gameDir isEqualToString:@"."]) {
        // Task225：无显式隔离 → 嗅探版本目录形状（auto 语义）
        NSString *sniffed = [ModService ame225_sniffedIsolationGameDirForProfile:prof];
        if ([sniffed isKindOfClass:[NSString class]] && sniffed.length > 0) return sniffed;
        const char *env = getenv("POJAV_GAME_DIR");
        return env ? [NSString stringWithUTF8String:env] : NSHomeDirectory();
    }
    if ([gameDir isAbsolutePath]) return gameDir;
    const char *env = getenv("POJAV_GAME_DIR");
    NSString *base = env ? [NSString stringWithUTF8String:env] : NSHomeDirectory();
    NSString *clean = [gameDir hasPrefix:@"./"] ? [gameDir substringFromIndex:2] : gameDir;
    return [base stringByAppendingPathComponent:clean];
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [ZL2Theme surface];

    // 概览页重命名后同步键名/标题/头卡（页面自更新自身，容器级身份由本通知收敛：
    // 缓存子页的 ameV13_profileName 一并改写，配置页 serverIp/完整设置入口不悬空）
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ameV13_profileRenamed:)
                                                 name:@"ZL2VersionDetailProfileRenamed"
                                               object:nil];

    [self ameV13_buildHeaderCard];
    [self ameV13_buildBody];
    [self ameV13_refreshHeader];
    [self ameV13_selectPage:1];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)ameV13_profileRenamed:(NSNotification *)note {
    NSString *newName = note.userInfo[@"newName"];
    if (![newName isKindOfClass:[NSString class]] || newName.length == 0) return;
    self.ameV13_profileName = newName;
    self.title = newName;
    [self.ameV13_childCache enumerateKeysAndObjectsUsingBlock:^(NSNumber *key, UIViewController *child, BOOL *stop) {
        if ([child isKindOfClass:[ZL2VersionPageBase class]]) {
            [(ZL2VersionPageBase *)child ameV13_updateProfileName:newName];
        }
    }];
    [self ameV13_refreshHeader];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 重命名/删除回写注册表后头卡随视图回归刷新（ZL2Versions reloadVersions 同口径）
    [PLProfiles updateCurrent];
    [self ameV13_refreshHeader];
}

#pragma mark - 头卡

- (void)ameV13_buildHeaderCard {
    _headerCard = [[UIView alloc] init];
    _headerCard.backgroundColor = [ZL2Theme surfaceContainer];
    _headerCard.layer.cornerRadius = [ZL2Theme radiusM];
    _headerCard.layer.masksToBounds = YES;
    _headerCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_headerCard];

    // 34pt 加载器图标（ZL2VersionsViewController 卡内同款：PNG 原色 /
    // SF 品牌色；取不到 → surfaceVariant radiusS 容器 + gamecontroller 兜底）
    _iconBg = [[UIView alloc] init];
    _iconBg.layer.cornerRadius = [ZL2Theme radiusS];
    _iconBg.layer.masksToBounds = YES;
    _iconBg.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:_iconBg];

    _iconView = [[UIImageView alloc] init];
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [_iconBg addSubview:_iconView];

    _nameLabel = [[UILabel alloc] init];
    _nameLabel.font = [ZL2Theme fontTitleMedium];
    _nameLabel.textColor = [ZL2Theme onSurface];
    _nameLabel.numberOfLines = 1;
    _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _descLabel = [[UILabel alloc] init];
    _descLabel.font = [ZL2Theme fontBodyMedium];
    _descLabel.textColor = [ZL2Theme onSurfaceVariant];
    _descLabel.numberOfLines = 1;
    _descLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _descLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _tagLabel = [[UILabel alloc] init];
    _tagLabel.font = [ZL2Theme fontLabelMedium];
    _tagLabel.textColor = [ZL2Theme onSurfaceVariant];
    _tagLabel.alpha = 0.7;
    _tagLabel.numberOfLines = 1;
    _tagLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _tagLabel.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[_nameLabel, _descLabel, _tagLabel]];
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.alignment = UIStackViewAlignmentLeading;
    textStack.spacing = 2;
    textStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerCard addSubview:textStack];

    // 「完成」（dismiss 语义：pop 优先，无 nav 时 dismiss 兜底）
    UIButton *doneButton = [UIButton buttonWithType:UIButtonTypeSystem];
    doneButton.tintColor = [ZL2Theme primary];
    doneButton.translatesAutoresizingMaskIntoConstraints = NO;
    doneButton.accessibilityLabel = NSLocalizedString(@"Profile menu", nil);
    [doneButton setImage:[UIImage systemImageNamed:@"ellipsis"] forState:UIControlStateNormal];
    doneButton.contentEdgeInsets = UIEdgeInsetsMake(8, 12, 8, 12);
    doneButton.showsMenuAsPrimaryAction = YES;
    __weak typeof(self) weakSelf = self;
    UIAction *folder = [UIAction actionWithTitle:NSLocalizedString(@"Open Folder", nil)
        image:[UIImage systemImageNamed:@"folder"] identifier:nil handler:^(__kindof UIAction *action) {
            ZL2VersionDetailViewController *owner = weakSelf;
            if (!owner) return;
            NSString *path = [ZL2VersionDetailViewController ameV13_resolvedGameDirForProfileName:owner.ameV13_profileName];
            [owner presentViewController:[FolderBrowserViewController wrappedControllerForPath:path] animated:YES completion:nil];
        }];
    UIAction *options = [UIAction actionWithTitle:NSLocalizedString(@"Profile Options", nil)
        image:[UIImage systemImageNamed:@"gearshape"] identifier:nil handler:^(__kindof UIAction *action) {
            [weakSelf ameV13_selectPage:7];
        }];
    UIAction *worlds = [UIAction actionWithTitle:NSLocalizedString(@"Worlds", nil)
        image:[UIImage systemImageNamed:@"globe"] identifier:nil handler:^(__kindof UIAction *action) {
            [weakSelf ameV13_selectPage:2];
        }];
    UIAction *logs = [UIAction actionWithTitle:NSLocalizedString(@"Logs", nil)
        image:[UIImage systemImageNamed:@"doc.text"] identifier:nil handler:^(__kindof UIAction *action) {
            ZL2VersionDetailViewController *owner = weakSelf;
            if (!owner) return;
            NSString *root = [ZL2VersionDetailViewController ameV13_resolvedGameDirForProfileName:owner.ameV13_profileName];
            [owner presentViewController:[FolderBrowserViewController wrappedControllerForPath:[root stringByAppendingPathComponent:@"logs"]] animated:YES completion:nil];
        }];
    UIAction *ai = [UIAction actionWithTitle:NSLocalizedString(@"Prisma AI", nil)
        image:[UIImage systemImageNamed:@"sparkles"] identifier:nil handler:^(__kindof UIAction *action) {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"ZL2ShellNavigate" object:nil userInfo:@{@"index": @6}];
        }];
    UIAction *overview = [UIAction actionWithTitle:NSLocalizedString(@"Overview", nil) image:nil identifier:nil handler:^(__kindof UIAction *action) {
        [weakSelf ameV13_selectPage:0];
    }];
    UIAction *servers = [UIAction actionWithTitle:NSLocalizedString(@"Servers", nil) image:nil identifier:nil handler:^(__kindof UIAction *action) {
        [weakSelf ameV13_selectPage:6];
    }];
    doneButton.menu = [UIMenu menuWithTitle:@"" children:@[folder, options, worlds, logs, overview, servers]];
    UIButton *back = [UIButton buttonWithType:UIButtonTypeSystem];
    [back setTitle:NSLocalizedString(@"‹ Profiles", nil) forState:UIControlStateNormal];
    back.tintColor = [ZL2Theme onPrimary];
    back.backgroundColor = [ZL2Theme primary];
    back.layer.cornerRadius = 7;
    back.contentEdgeInsets = UIEdgeInsetsMake(5, 10, 5, 10);
    back.translatesAutoresizingMaskIntoConstraints = NO;
    [back addTarget:self action:@selector(ameV13_finish) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:back];
    UIButton *assistant = [UIButton buttonWithType:UIButtonTypeSystem primaryAction:ai];
    [assistant setTitle:@"" forState:UIControlStateNormal];
    assistant.accessibilityLabel = ai.title;
    assistant.tintColor = [ZL2Theme primary];
    assistant.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:assistant];
    UIButton *play = [UIButton buttonWithType:UIButtonTypeSystem];
    play.accessibilityLabel = NSLocalizedString(@"Play", nil);
    [play setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal];
    play.backgroundColor = [ZL2Theme primary];
    play.tintColor = [ZL2Theme onPrimary];
    play.layer.cornerRadius = 8;
    play.translatesAutoresizingMaskIntoConstraints = NO;
    [play addTarget:self action:@selector(cubicPlay) forControlEvents:UIControlEventTouchUpInside];
    [_headerCard addSubview:play];
    [_headerCard addSubview:doneButton];

    [NSLayoutConstraint activateConstraints:@[
        [back.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:4],
        [back.leadingAnchor constraintEqualToAnchor:_headerCard.leadingAnchor],
        [assistant.centerYAnchor constraintEqualToAnchor:back.centerYAnchor],
        [assistant.trailingAnchor constraintEqualToAnchor:_headerCard.trailingAnchor],
        [_headerCard.topAnchor constraintEqualToAnchor:back.bottomAnchor constant:4],
        [_headerCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:ZL2V13PageMargin],
        [_headerCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-ZL2V13PageMargin],

        [_iconBg.leadingAnchor constraintEqualToAnchor:_headerCard.leadingAnchor constant:14],
        [_iconBg.centerYAnchor constraintEqualToAnchor:_headerCard.centerYAnchor],
        [_iconBg.widthAnchor constraintEqualToConstant:54],
        [_iconBg.heightAnchor constraintEqualToConstant:54],
        [_iconView.centerXAnchor constraintEqualToAnchor:_iconBg.centerXAnchor],
        [_iconView.centerYAnchor constraintEqualToAnchor:_iconBg.centerYAnchor],
        [_iconView.widthAnchor constraintEqualToAnchor:_iconBg.widthAnchor],
        [_iconView.heightAnchor constraintEqualToAnchor:_iconBg.heightAnchor],

        [textStack.leadingAnchor constraintEqualToAnchor:_iconBg.trailingAnchor constant:12],
        [_headerCard.heightAnchor constraintEqualToConstant:88],
        [textStack.centerYAnchor constraintEqualToAnchor:_headerCard.centerYAnchor],
        [textStack.bottomAnchor constraintLessThanOrEqualToAnchor:_headerCard.bottomAnchor constant:-12],
        [doneButton.leadingAnchor constraintGreaterThanOrEqualToAnchor:textStack.trailingAnchor constant:8],
        [doneButton.trailingAnchor constraintEqualToAnchor:play.leadingAnchor],
        [play.trailingAnchor constraintEqualToAnchor:_headerCard.trailingAnchor constant:-8],
        [play.centerYAnchor constraintEqualToAnchor:doneButton.centerYAnchor],
        [play.widthAnchor constraintEqualToConstant:36],
        [play.heightAnchor constraintEqualToConstant:36],
        [doneButton.centerYAnchor constraintEqualToAnchor:_headerCard.centerYAnchor],
    ]];
}

- (void)ameV13_refreshHeader {
    // 身份 = 注册表字典键（Task162 口径：name 字段与键可能分叉，键为准）
    NSMutableDictionary *profile = PLProfiles.current.profiles[self.ameV13_profileName];
    if (![profile isKindOfClass:[NSMutableDictionary class]]) profile = nil;

    NSString *displayName = nil;
    NSString *descText = nil;
    NSString *versionId = nil;
    if (profile) {
        displayName = [profile[@"name"] isKindOfClass:[NSString class]] && ((NSString *)profile[@"name"]).length > 0
            ? (NSString *)profile[@"name"] : self.ameV13_profileName;
        versionId = [profile[@"lastVersionId"] isKindOfClass:[NSString class]] ? (NSString *)profile[@"lastVersionId"] : nil;
        // 描述行：自定义摘要（概览页「编辑摘要」写入）优先，缺省回退最后游玩时间
        // （ZL2Versions 列表行同源格式：i18n_str_1069「最后游玩：%@」）
        NSString *summary = [profile[@"versionSummary"] isKindOfClass:[NSString class]] ? (NSString *)profile[@"versionSummary"] : nil;
        if (summary.length > 0) {
            descText = summary;
        } else {
            descText = [self ameV13_formatLastPlayed:profile[@"lastPlayed"]];
        }
    } else {
        displayName = self.ameV13_profileName;
        descText = @"";
    }

    NSString *loader = versionId.length > 0 ? [ModLoaderIconHelper detectLoaderFromVersionId:versionId] : nil;
    NSDictionary *parsed = versionId.length > 0 ? [ModpackExportService parseVersionId:versionId] : @{};
    NSString *mcVersion = [parsed[@"minecraft"] isKindOfClass:[NSString class]] ? (NSString *)parsed[@"minecraft"] : versionId;

    self.nameLabel.text = displayName;
    self.descLabel.text = descText.length > 0 ? descText : @" ";
    if (mcVersion.length > 0 && loader.length > 0) {
        self.tagLabel.text = [NSString stringWithFormat:@"MC %@ · %@", mcVersion, [ModLoaderIconHelper displayNameForLoader:loader]];
    } else if (mcVersion.length > 0) {
        self.tagLabel.text = [NSString stringWithFormat:@"MC %@", mcVersion];
    } else if (loader.length > 0) {
        self.tagLabel.text = [ModLoaderIconHelper displayNameForLoader:loader];
    } else {
        self.tagLabel.text = @" ";
    }

    self.iconView.image = CubicProfileArtwork(profile);
    self.iconView.contentMode = UIViewContentModeScaleAspectFill;
    self.iconBg.clipsToBounds = YES;
}

/// lastPlayed 时间戳 → 「最后游玩：xxx」（ZL2VersionsViewController 1:1）
- (NSString *)ameV13_formatLastPlayed:(id)lastPlayedRaw {
    if (!lastPlayedRaw) return @"";
    NSTimeInterval ts = 0;
    if ([lastPlayedRaw isKindOfClass:[NSNumber class]]) {
        ts = [(NSNumber *)lastPlayedRaw doubleValue];
    } else if ([lastPlayedRaw isKindOfClass:[NSString class]]) {
        ts = [(NSString *)lastPlayedRaw doubleValue];
    } else {
        return @"";
    }
    if (ts <= 0) return @"";
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:ts];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [NSLocale currentLocale];
    fmt.doesRelativeDateFormatting = YES;
    fmt.dateStyle = NSDateFormatterShortStyle;
    fmt.timeStyle = NSDateFormatterShortStyle;
    return [NSString stringWithFormat:localize(@"i18n_str_1069", nil), [fmt stringFromDate:date]];
}

#pragma mark - 左子导航轨 + 内容容器

- (void)ameV13_buildBody {
    UIScrollView *tabs = [[UIScrollView alloc] init];
    tabs.showsHorizontalScrollIndicator = NO;
    tabs.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:tabs];
    NSArray<NSString *> *titles = @[
        NSLocalizedString(@"Overview", nil), NSLocalizedString(@"Mods", nil),
        NSLocalizedString(@"Worlds", nil), NSLocalizedString(@"Resource Packs", nil),
        NSLocalizedString(@"Shaders", nil), NSLocalizedString(@"Screenshots", nil),
        NSLocalizedString(@"Servers", nil), NSLocalizedString(@"Profile Options", nil),
        NSLocalizedString(@"Data Packs", nil)
    ];
    _railItems = [NSMutableArray array];
    _railStack = [[UIStackView alloc] init];
    _railStack.spacing = 8;
    _railStack.translatesAutoresizingMaskIntoConstraints = NO;
    [tabs addSubview:_railStack];
    for (NSNumber *index in @[@1, @8, @3, @4]) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:titles[index.integerValue] forState:UIControlStateNormal];
        button.tintColor = [ZL2Theme primary];
        button.contentEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 8);
        button.tag = index.integerValue;
        [button addTarget:self action:@selector(cubicTabTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_railStack addArrangedSubview:button];
    }
    [NSLayoutConstraint activateConstraints:@[
        [tabs.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:8],
        [tabs.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-8],
        [tabs.topAnchor constraintEqualToAnchor:_headerCard.bottomAnchor constant:4],
        [tabs.heightAnchor constraintEqualToConstant:44],
        [_railStack.leadingAnchor constraintEqualToAnchor:tabs.contentLayoutGuide.leadingAnchor],
        [_railStack.trailingAnchor constraintEqualToAnchor:tabs.contentLayoutGuide.trailingAnchor],
        [_railStack.topAnchor constraintEqualToAnchor:tabs.contentLayoutGuide.topAnchor],
        [_railStack.bottomAnchor constraintEqualToAnchor:tabs.contentLayoutGuide.bottomAnchor],
        [_railStack.heightAnchor constraintEqualToAnchor:tabs.frameLayoutGuide.heightAnchor],
    ]];

    // 内容容器 = 轨右到页尾的整块填充；子页内部自持 999 等式宽度收敛
    //（ZL2VersionsViewController L211-226 同款，最大宽由子页自管）
    _contentContainer = [[UIView alloc] init];
    _contentContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _contentContainer.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_contentContainer];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_contentContainer.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:ZL2V13PageMargin],
        [_contentContainer.topAnchor constraintEqualToAnchor:tabs.bottomAnchor],
        [_contentContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-ZL2V13PageMargin],
        [_contentContainer.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
    ]];
}

#pragma mark - 子页切换（ZL2Shell 手法：懒建缓存 + addChild + crossDissolve）

- (void)cubicTabTapped:(UIButton *)sender {
    [self ameV13_selectPage:sender.tag];
}

- (UIViewController *)ameV13_childForIndex:(NSInteger)index {
    NSNumber *key = @(index);
    UIViewController *cached = self.ameV13_childCache[key];
    if (cached) return cached;

    UIViewController *vc = nil;
    NSString *profileName = self.ameV13_profileName;
    NSString *gameDir = [ZL2VersionDetailViewController ameV13_resolvedGameDirForProfileName:profileName];
    switch (index) {
        case 0: vc = [[ZL2VersionOverviewPage alloc]       initWithProfileName:profileName gameDir:gameDir]; break;
        case 1: vc = [[ZL2VersionModsPage alloc]           initWithProfileName:profileName gameDir:gameDir]; break;
        case 2: vc = [[ZL2VersionSavesPage alloc]          initWithProfileName:profileName gameDir:gameDir]; break;
        case 3: vc = [[ZL2VersionResourcePacksPage alloc]  initWithProfileName:profileName gameDir:gameDir]; break;
        case 4: vc = [[ZL2VersionShadersPage alloc]        initWithProfileName:profileName gameDir:gameDir]; break;
        case 5: vc = [[ZL2VersionScreenshotsPage alloc]    initWithProfileName:profileName gameDir:gameDir]; break;
        case 6: vc = [[ZL2VersionServersPage alloc]        initWithProfileName:profileName gameDir:gameDir]; break;
        case 7: vc = [[ZL2VersionConfigPage alloc]         initWithProfileName:profileName gameDir:gameDir]; break;
        case 8: {
            ZL2AssetSearchViewController *packs = [[ZL2AssetSearchViewController alloc]
                initWithType:ZL2AssetSearchTypeDataPack title:NSLocalizedString(@"Data Packs", nil)];
            packs.targetProfileName = profileName;
            vc = packs;
            break;
        }
        default: break;
    }
    if (!vc) return nil;
    self.ameV13_childCache[key] = vc;
    return vc;
}

- (void)ameV13_attachChildIfNeeded:(UIViewController *)child {
    if (child.parentViewController == self) return;
    [self addChildViewController:child];
    child.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentContainer addSubview:child.view];
    [NSLayoutConstraint activateConstraints:@[
        [child.view.leadingAnchor constraintEqualToAnchor:self.contentContainer.leadingAnchor],
        [child.view.trailingAnchor constraintEqualToAnchor:self.contentContainer.trailingAnchor],
        [child.view.topAnchor constraintEqualToAnchor:self.contentContainer.topAnchor],
        [child.view.bottomAnchor constraintEqualToAnchor:self.contentContainer.bottomAnchor],
    ]];
    [child didMoveToParentViewController:self];
}

- (void)ameV13_selectPage:(NSInteger)index {
    if (index < 0 || index >= 9) return;
    if (index == self.ameV13_selectedIndex) return;

    UIViewController *next = [self ameV13_childForIndex:index];
    if (!next) return;

    UIViewController *prev = nil;
    if (self.ameV13_selectedIndex >= 0) {
        prev = self.ameV13_childCache[@(self.ameV13_selectedIndex)];
    }

    [self ameV13_attachChildIfNeeded:next];

    void (^apply)(void) = ^{
        prev.view.hidden = YES;
        next.view.hidden = NO;
    };
    if (prev && prev.view.superview) {
        [UIView transitionWithView:self.contentContainer
                          duration:ZL2V13AnimateDuration
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:apply
                        completion:nil];
    } else {
        apply();
    }

    self.ameV13_selectedIndex = index;
    for (UIButton *tab in self.railStack.arrangedSubviews) {
        BOOL selected = tab.tag == index;
        tab.backgroundColor = selected ? [ZL2Theme primaryContainer] : UIColor.clearColor;
        tab.tintColor = selected ? [ZL2Theme onPrimaryContainer] : [ZL2Theme primary];
        tab.layer.cornerRadius = 8;
        tab.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
    }
}

#pragma mark - 完成

- (void)cubicPlay {
    if (self.playProfile) self.playProfile(self.ameV13_profileName);
}

- (void)ameV13_finish {
    if (self.navigationController && self.navigationController.viewControllers.count > 1) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

@end
