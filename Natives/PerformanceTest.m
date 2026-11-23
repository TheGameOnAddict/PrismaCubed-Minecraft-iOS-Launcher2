#import "PerformanceTest.h"
#import "PerformanceFrames.h"
#import "CubicRuntimeInfo.h"
#import "PLProfiles.h"
#import <CommonCrypto/CommonDigest.h>
#import <sys/utsname.h>
#if __has_include("config.h")
#import "config.h"
#endif

static PerformanceTest *requested, *launching;
static dispatch_queue_t reportQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("prisma.performance.reports", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

static NSURL *profileFolder(NSString *name) {
    NSData *data = [name dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *key = [NSMutableString string];
    for (NSUInteger i = 0; i < 8; i++) [key appendFormat:@"%02x", digest[i]];
    NSURL *docs = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    return [[docs URLByAppendingPathComponent:@"Performance Tests"] URLByAppendingPathComponent:key];
}

static void alert(UIViewController *vc, NSString *message) {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Performance Test",nil) message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil) style:UIAlertActionStyleDefault handler:nil]];
    [vc presentViewController:a animated:YES completion:nil];
}

static void shareReport(NSURL *url, UIViewController *controller) {
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    share.popoverPresentationController.sourceView = controller.view;
    share.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(controller.view.bounds), CGRectGetMidY(controller.view.bounds), 1, 1);
    [controller presentViewController:share animated:YES completion:nil];
}

// Read only small, allowlisted configuration values. Never export the full config or log.
static NSDictionary *settings(NSString *directory, NSString *file, NSString *separator, NSArray *keys) {
    NSURL *url = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:file]];
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingFromURL:url error:nil];
    NSData *data = [fh readDataUpToLength:131072 error:nil];
    [fh closeAndReturnError:nil];
    NSString *text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    [text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        NSRange split = [line rangeOfString:separator];
        if (split.location == NSNotFound) return;
        NSString *key = [line substringToIndex:split.location];
        if (![keys containsObject:key]) return;
        NSString *value = [line substringFromIndex:NSMaxRange(split)];
        if (value.length < 160) values[key] = value.lastPathComponent ?: @"";
    }];
    return values;
}

static NSDictionary *sceneContext(NSString *directory, NSDate *launchDate) {
    NSMutableDictionary *context = [NSMutableDictionary dictionary];
    context[@"options"] = settings(directory, @"options.txt", @":", @[@"renderDistance",@"simulationDistance",@"maxFps",@"enableVsync",@"graphicsMode",@"entityDistanceScaling",@"biomeBlendRadius",@"mipmapLevels"]);
    for (NSString *file in @[@"oculus.properties", @"iris.properties"]) {
        NSDictionary *shader = settings(directory, [@"config" stringByAppendingPathComponent:file], @"=", @[@"enableShaders",@"shaderPack"]);
        if (shader.count) context[file] = shader;
    }
    NSArray *files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:[directory stringByAppendingPathComponent:@"mods"] error:nil];
    if (files) context[@"enabledModFiles"] = [[files filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *name, NSDictionary *bindings) {
        return [name.pathExtension.lowercaseString isEqual:@"jar"];
    }]] sortedArrayUsingSelector:@selector(compare:)];

    NSString *path = [directory stringByAppendingPathComponent:@"logs/latest.log"];
    NSDate *modified = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil].fileModificationDate;
    if (modified && [modified compare:launchDate] != NSOrderedAscending) {
        NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
        NSData *data = [fh readDataUpToLength:2*1024*1024 error:nil];
        [fh closeAndReturnError:nil];
        // A bounded prefix can end mid-character. Latin-1 preserves ASCII renderer markers.
        NSString *text = data ? [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] : nil;
        [text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
            if ([line containsString:@"/INFO]: OpenGL Renderer:"] || [line containsString:@"/INFO]: GL info:"]) {
                for (NSString *backend in @[@"Magma",@"zink",@"MobileGlues",@"ANGLE",@"llvmpipe",@"virgl"]) {
                    if ([line localizedCaseInsensitiveContainsString:backend]) { context[@"reportedGLBackend"] = backend; break; }
                }
            }
            if ([line hasSuffix:@"/INFO]: Shaders are disabled"]) context[@"shadersReportedEnabled"] = @NO;
        }];
    }
    return context;
}

@interface PerformanceTest ()
@property(nonatomic, copy) NSString *profile, *gameDirectory;
@property(nonatomic) NSURL *url;
@property(nonatomic) NSDate *created;
@property(nonatomic) NSTimeInterval launchUptime;
@property(nonatomic) NSMutableDictionary *report;
@property(nonatomic) NSMutableArray *samples;
@property(nonatomic) BOOL recording;
@property(nonatomic) NSInteger checkpoint;
@property(nonatomic) NSDictionary *context;
@end

@implementation PerformanceTest

- (NSDictionary *)snapshot {
    NSMutableDictionary *copy = [self.report mutableCopy];
    copy[@"samples"] = [self.samples copy];
    copy[@"lastCheckpointUTC"] = [NSISO8601DateFormatter.new stringFromDate:NSDate.date];
    if (self.context) copy[@"scene"] = self.context;
    return copy;
}

- (void)save {
    NSDictionary *renderer = [CubicRuntimeInfo renderer];
    self.report[@"renderer"] = renderer;
    self.report[@"rendererLibrary"] = [renderer[@"library"] length] ? renderer[@"library"] : nil;
    NSDictionary *snapshot = [self snapshot];
    NSURL *url = self.url;
    dispatch_async(reportQueue(), ^{
        NSError *error;
        NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:NSJSONWritingPrettyPrinted error:&error];
        if (![data writeToURL:url options:NSDataWritingAtomic error:&error]) NSLog(@"[PerformanceTest] checkpoint failed (%ld)", (long)error.code);
    });
}

+ (void)showForProfile:(NSString *)name version:(NSString *)version gameDirectory:(NSString *)directory
                  from:(UIViewController *)controller launch:(void (^)(void))launch {
    NSURL *folder = profileFolder(name);
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Performance Test",nil)
        message:NSLocalizedString(@"Launch, enter your test scene, then open the in-game gear and tap Record 60 Seconds. Return here to share the report.",nil) preferredStyle:UIAlertControllerStyleAlert];
    [sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Test Launch",nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        PerformanceTest *test = [self new];
        test.profile = name;
        test.gameDirectory = directory;
        test.created = NSDate.date;
        test.launchUptime = NSProcessInfo.processInfo.systemUptime;
        NSString *identifier = [NSString stringWithFormat:@"Prisma-%013lld-%@.json", (long long)(test.created.timeIntervalSince1970*1000), [NSUUID.UUID.UUIDString substringToIndex:8]];
        test.url = [folder URLByAppendingPathComponent:identifier];
        struct utsname info;
        uname(&info);
        test.report = [@{@"schema":@1, @"profile":name, @"versionId":version ?: @"", @"device":[NSString stringWithUTF8String:info.machine],
            @"os":UIDevice.currentDevice.systemVersion, @"launchUTC":[NSISO8601DateFormatter.new stringFromDate:test.created],
            @"status":@"launch_requested", @"durationTargetSeconds":@(PerformanceSeconds)} mutableCopy];
#ifdef CONFIG_COMMIT
        test.report[@"launcherCommit"] = @CONFIG_COMMIT;
#endif
        test.samples = [NSMutableArray array];
        NSError *error;
        if (![NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:&error] ||
            ![[NSJSONSerialization dataWithJSONObject:[test snapshot] options:NSJSONWritingPrettyPrinted error:&error] writeToURL:test.url options:NSDataWritingAtomic error:&error]) {
            alert(controller,error.localizedDescription); return;
        }
        requested = test;
        launch();
        requested = nil;
    }]];
    NSURL *latest = [[[NSFileManager.defaultManager contentsOfDirectoryAtURL:folder includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSURL *url, NSDictionary *bindings) {
        return [url.pathExtension isEqual:@"json"] && [url.lastPathComponent hasPrefix:@"Prisma-"];
    }]] sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) { return [b.lastPathComponent compare:a.lastPathComponent]; }].firstObject;
    if (latest) [sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Share Latest Report",nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        shareReport(latest, controller);
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel",nil) style:UIAlertActionStyleCancel handler:nil]];
    [controller presentViewController:sheet animated:YES completion:nil];
}

+ (void)claimLaunchRequestForProfile:(NSString *)profile {
    launching = [requested.profile isEqual:profile] ? requested : nil;
    requested = nil;
}

+ (instancetype)takeForGame:(NSString *)profile {
    PerformanceTest *test = [launching.profile isEqual:profile] ? launching : nil;
    launching = nil;
    if (test) {
        test.report[@"status"] = @"waiting_for_scene";
        test.report[@"profileName"] = PLProfiles.current.selectedProfile[@"name"] ?: profile;
        test.report[@"configuredRenderer"] = [PLProfiles resolveKeyForCurrentProfile:@"renderer"] ?: @"auto";
        test.report[@"gameSurfaceAfterSeconds"] = @(NSProcessInfo.processInfo.systemUptime - test.launchUptime);
        [test save];
    }
    return test;
}

- (void)recordLaunchOptions:(NSDictionary *)options {
    if (!options.count) return;
    self.report[@"launchOptions"] = [options copy];
    [self save];
}

- (void)firstFrameObserved {
    if (self.report[@"firstFrameObservedAfterSeconds"]) return;
    self.report[@"firstFrameObservedAfterSeconds"] = @(NSProcessInfo.processInfo.systemUptime - self.launchUptime);
    [self save];
}

- (BOOL)beginCapture {
    if (self.recording || self.report[@"frameTiming"]) return NO;
    self.report[@"status"] = @"recording_partial";
    self.report[@"captureRequestedUTC"] = [NSISO8601DateFormatter.new stringFromDate:NSDate.date];
    self.checkpoint = -1;
    self.recording = YES;
    dispatch_async(reportQueue(), ^{
        NSDictionary *scene = sceneContext(self.gameDirectory, self.created);
        dispatch_async(dispatch_get_main_queue(), ^{ self.context = scene; [self save]; });
    });
    PerformanceBegin();
    [self save];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(background:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    return YES;
}

- (void)background:(NSNotification *)note { [self interrupt]; }

- (BOOL)updateSummary:(PerformanceSummary)s stopped:(BOOL)stopped {
    NSMutableArray *counts = [NSMutableArray array];
    unsigned frames = 0;
    for (unsigned i=0; i < ceil(s.elapsed) && i < PerformanceSeconds; i++) {
        [counts addObject:@(s.counts[i])];
        frames += s.counts[i];
    }
    NSMutableDictionary *timing = [@{@"measuredSeconds":@(s.elapsed), @"framesPerBucket1s":counts,
        @"frameEvents":@(frames), @"intervalCount":@(s.intervals), @"intervalsOver50ms":@(s.over50ms), @"intervalsOver100ms":@(s.over100ms),
        @"eventSource":s.source == PerformanceSwap ? @"GL swap entry" : s.source == PerformanceDrawable ? @"drawable acquisition" : @"none"} mutableCopy];
    if (s.elapsed > 0) timing[@"averageFPS"] = @(frames/s.elapsed);
    if (s.intervals) {
        timing[@"p50IntervalMsCeil"] = @(s.p50ms); timing[@"p95IntervalMsCeil"] = @(s.p95ms); timing[@"maxIntervalMs"] = @(s.longestMs);
    }
    if (s.osmSamples) timing[@"osmPhases"] = @{@"samples":@(s.osmSamples), @"meanFinishMs":@(s.finishMs/s.osmSamples), @"meanReadbackPhaseMs":@(s.readbackMs/s.osmSamples)};
    if (s.queueSamples) timing[@"osmMainQueue"] = @{@"samples":@(s.queueSamples), @"meanWaitMs":@(s.queueMs/s.queueSamples)};
    self.report[@"frameTiming"] = timing;
    BOOL finished = s.elapsed >= PerformanceSeconds;
    if (finished || stopped) {
        self.recording = NO;
        self.report[@"status"] = finished ? @"completed" : @"interrupted";
        [NSNotificationCenter.defaultCenter removeObserver:self];
    }
    [self save];
    return finished;
}

- (BOOL)tickWidth:(int)width height:(int)height memoryMiB:(double)memory {
    if (!self.recording) {
        // A test can crash while loading or exploring, before Record is tapped.
        // Persist the first confirmed renderer and any later fallback in that window.
        if ([self.report[@"status"] isEqual:@"waiting_for_scene"]) {
            NSDictionary *renderer = [CubicRuntimeInfo renderer];
            if (![renderer isEqual:self.report[@"renderer"]]) [self save];
        }
        return NO;
    }
    PerformanceSummary s = PerformanceSnapshot(false);
    if (s.elapsed <= 0) return NO;
    NSArray *thermal = @[@"nominal",@"fair",@"serious",@"critical"];
    NSUInteger state = NSProcessInfo.processInfo.thermalState;
    [self.samples addObject:@{@"elapsedSeconds":@(s.elapsed), @"width":@(width), @"height":@(height),
        @"footprintMiB":@(memory), @"thermal":state < thermal.count ? thermal[state] : @"unknown",
        @"lowPower":@(NSProcessInfo.processInfo.lowPowerModeEnabled)}];
    NSInteger checkpoint = (NSInteger)s.elapsed / 5;
    if (checkpoint == self.checkpoint && s.elapsed < PerformanceSeconds) return NO;
    self.checkpoint = checkpoint;
    return [self updateSummary:s stopped:NO];
}

- (void)shareFrom:(UIViewController *)controller {
    if (self.recording) {
        alert(controller, NSLocalizedString(@"The capture is running. Share after the 60 seconds finish.", nil));
        return;
    }
    // Wait for earlier checkpoints before the activity receives the URL.
    dispatch_async(reportQueue(), ^{
        dispatch_async(dispatch_get_main_queue(), ^{ shareReport(self.url, controller); });
    });
}

- (void)interrupt {
    if (self.recording) [self updateSummary:PerformanceSnapshot(true) stopped:YES];
}

@end
