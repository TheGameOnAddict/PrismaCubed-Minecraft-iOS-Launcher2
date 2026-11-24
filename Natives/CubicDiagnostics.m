#import "CubicDiagnostics.h"
#import "CubicDiagnosticText.h"
#import "PerformanceTest.h"
#import <unistd.h>
#import <sys/utsname.h>
#if __has_include("config.h")
#import "config.h"
#endif

static NSFileManager *files(void) { return NSFileManager.defaultManager; }
static NSURL *documentsURL(void) { return [files() URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject; }
static NSURL *child(NSURL *parent, NSString *name) { return [parent URLByAppendingPathComponent:name]; }
static NSURL *exports(NSURL *docs) { return child(docs, @"Diagnostics"); }
static BOOL regular(NSURL *file) {
    return file && [[files() attributesOfItemAtPath:file.path error:nil].fileType isEqual:NSFileTypeRegular];
}
static NSDate *modified(NSURL *file) {
    return [files() attributesOfItemAtPath:file.path error:nil].fileModificationDate;
}

// Clip on line boundaries, keeping a header and a tail for large launcher logs.
static NSData *logBytes(NSURL *url, NSUInteger limit, BOOL prefixOnly) {
    if (!regular(url)) return nil;
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:url error:nil];
    unsigned long long length = 0;
    if (![handle seekToEndReturningOffset:&length error:nil] || ![handle seekToOffset:0 error:nil]) return nil;
    if (prefixOnly || length <= limit) return [handle readDataUpToLength:limit error:nil];
    NSMutableData *data = [[handle readDataUpToLength:limit/4 error:nil] mutableCopy];
    NSData *newline = [@"\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange end = [data rangeOfData:newline options:NSDataSearchBackwards range:NSMakeRange(0,data.length)];
    data.length = end.location == NSNotFound ? 0 : NSMaxRange(end);
    [data appendData:[@"[... middle omitted for export ...]\n" dataUsingEncoding:NSUTF8StringEncoding]];
    if (![handle seekToOffset:length-limit*3/4 error:nil]) return data;
    NSData *tail = [handle readDataUpToLength:limit*3/4 error:nil];
    NSRange start = [tail rangeOfData:newline options:0 range:NSMakeRange(0,tail.length)];
    if (tail && start.location != NSNotFound)
        [data appendData:[tail subdataWithRange:NSMakeRange(NSMaxRange(start),tail.length-NSMaxRange(start))]];
    return data;
}
static NSString *logString(NSData *bytes) {
    if (!bytes.length) return nil;
    return [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding] ?:
           [[NSString alloc] initWithData:bytes encoding:NSISOLatin1StringEncoding];
}
static NSString *match(NSString *text, NSString *pattern) {
    if (!text.length) return nil;
    NSRange range = [text rangeOfString:pattern options:NSRegularExpressionSearch];
    return range.location == NSNotFound ? nil : [text substringWithRange:range];
}
static NSDate *reportDate(NSString *content) {
    NSString *stamp = match(content, @"(?m)(?<=^time: )\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}");
    if (!stamp) return nil;
    NSDateFormatter *format = [NSDateFormatter new];
    format.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    format.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    return [format dateFromString:stamp];
}
static BOOL nearDate(NSDate *a, NSDate *b) { return a && b && fabs([a timeIntervalSinceDate:b]) <= 120; }
// PatchSVC records the exact basename after it copies latestlog.txt. Restrict
// the name to the snapshot format before resolving it under Documents.
static NSURL *exitSnapshot(NSString *crash, NSURL *docs, NSDate *when) {
    NSString *name = match(crash, @"(?<=\\[Task261\\] selfexit snapshot saved: )latestlog\\.selfexit-[0-9]{4}-[0-9]{6}\\.txt(?= \\()");
    if (!name) return nil;
    NSURL *file = child(docs,name);
    return regular(file) && nearDate(when,modified(file)) ? file : nil;
}
static NSString *snapshotRun(NSURL *snapshot) {
    return match(logString(logBytes(snapshot,3*1024*1024,NO)), @"(?<=\\[PrismaDiagnostics\\] run=)[0-9A-Fa-f-]{36}\\b");
}
static NSDictionary *loadJSON(NSURL *file) {
    NSData *data = logBytes(file, 65536, YES);
    id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [obj isKindOfClass:NSDictionary.class] ? obj : nil;
}
static NSArray<NSURL *> *newestMatching(NSURL *folder, NSPredicate *predicate, NSUInteger count) {
    NSArray *urls = [files() contentsOfDirectoryAtURL:folder includingPropertiesForKeys:@[NSURLContentModificationDateKey]
                                                options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    NSMutableArray *selected = [NSMutableArray array];
    for (NSURL *url in urls)
        if ([predicate evaluateWithObject:url.lastPathComponent] && regular(url)) [selected addObject:url];
    [selected sortUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) { return [modified(b) compare:modified(a)]; }];
    return [selected subarrayWithRange:NSMakeRange(0,MIN(count,selected.count))];
}
static NSString *canonical(NSURL *file) { return file.URLByResolvingSymlinksInPath.URLByStandardizingPath.path; }
static BOOL within(NSURL *file, NSURL *parent) {
    return file && parent && [canonical(file) hasPrefix:[canonical(parent) stringByAppendingString:@"/"]];
}
// Pre-index builds have no launch marker. Only infer a profile directory when
// exactly one known Minecraft log finished close to the displayed crash.
static NSURL *legacyCrashDirectory(NSURL *docs, NSDate *when) {
    NSURL *instances = child(docs,@"instances");
    NSArray *roots = [files() contentsOfDirectoryAtURL:instances includingPropertiesForKeys:nil
                                                options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    NSMutableSet<NSString *> *matches = [NSMutableSet set];
    for (NSURL *root in roots) {
        if (!within(root,instances)) continue;
        NSMutableArray *dirs = [NSMutableArray arrayWithObject:root];
        NSURL *versions = child(root,@"versions");
        NSArray *children = [files() contentsOfDirectoryAtURL:versions includingPropertiesForKeys:nil
                                                       options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
        for (NSURL *version in children) {
            [dirs addObject:version];
            [dirs addObject:child(version,@"game")];
        }
        for (NSURL *dir in dirs) {
            NSURL *log = child(dir,@"logs/latest.log");
            if (within(log,instances) && regular(log) && nearDate(when,modified(log))) [matches addObject:canonical(dir)];
            if (matches.count > 1) return nil;
        }
    }
    return matches.count == 1 ? [NSURL fileURLWithPath:matches.anyObject] : nil;
}
static NSString *fatalSection(NSString *text, NSDate *date, NSString *crash) {
    if (!date || !text.length) return nil;
    NSString *prefix = @"===== [Amethyst fatal trace] ";
    NSString *stampPattern = @"^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3} =====(?=\\r?\\n)";
    NSDateFormatter *format = [NSDateFormatter new];
    format.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    format.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    NSString *identified = nil, *fallback = nil;
    NSUInteger exactCount = 0, nearbyCount = 0;
    NSArray *sections = [text componentsSeparatedByString:prefix];
    for (NSUInteger i = 1; i < sections.count; i++) {
        NSString *section = sections[i];
        NSString *stamp = match(section, stampPattern);
        if (!stamp) continue;
        NSDate *traceDate = [format dateFromString:[stamp substringToIndex:23]];
        if (!traceDate || !nearDate(traceDate,date)) continue;
        NSString *header = [prefix stringByAppendingString:stamp];
        if ([crash containsString:header]) {
            identified = section;
            exactCount++;
        }
        NSTimeInterval offset = [traceDate timeIntervalSinceDate:date];
        if (offset >= -2 && offset < 1) {
            fallback = section;
            nearbyCount++;
        }
    }
    NSString *selected = exactCount == 1 ? identified : nil;
    if (!exactCount && ![crash containsString:prefix] && nearbyCount == 1) selected = fallback;
    if (!selected) return nil;
    // logBytes joins a bounded head and tail. If a section straddles that gap,
    // its tail could belong to a different trace whose header was clipped.
    NSRange gap = [selected rangeOfString:@"[... middle omitted for export ...]"];
    if (gap.location != NSNotFound) selected = [selected substringToIndex:NSMaxRange(gap)];
    return [prefix stringByAppendingString:selected];
}

static NSURL *activeSessionURL;
static NSMutableDictionary *activeSession;
static dispatch_queue_t sessionWrites(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("prisma.diagnostics.sessions",DISPATCH_QUEUE_SERIAL); });
    return queue;
}

@implementation CubicDiagnostics
+ (void)updateLaunchDetails:(NSDictionary *)details {
    dispatch_async(sessionWrites(), ^{
        if (!activeSessionURL) return;
        [activeSession addEntriesFromDictionary:details];
        NSData *json = [NSJSONSerialization dataWithJSONObject:activeSession options:0 error:nil];
        [json writeToURL:activeSessionURL options:NSDataWritingAtomic error:nil];
    });
}
+ (void)markLaunchForProfile:(NSString *)profile directory:(NSString *)directory version:(NSString *)version {
    if (!profile.length || !directory.length) return;
    NSURL *docs = documentsURL(), *root = child(exports(docs), @".sessions");
    NSURL *game = [NSURL fileURLWithPath:directory];
    NSString *relative = within(game,docs) ? [canonical(game) substringFromIndex:canonical(docs).length+1] : @"";
    NSString *run = NSUUID.UUID.UUIDString;
    NSDictionary *session = @{@"id":run, @"profile":profile, @"directory":relative, @"version":version ?: @"",
        @"pid":@(getpid()), @"start":@(NSDate.date.timeIntervalSince1970)};
    if ([files() createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil]) {
        dispatch_sync(sessionWrites(), ^{
            activeSession = [session mutableCopy];
            activeSessionURL = child(root,[run stringByAppendingPathExtension:@"json"]);
            NSData *json = [NSJSONSerialization dataWithJSONObject:session options:0 error:nil];
            [json writeToURL:activeSessionURL options:NSDataWritingAtomic error:nil];
        });
        NSArray *recent = newestMatching(root,[NSPredicate predicateWithFormat:@"SELF ENDSWITH %@",@".json"],NSUIntegerMax);
        for (NSUInteger i = 128; i < recent.count; i++) [files() removeItemAtURL:recent[i] error:nil];
    }
    NSLog(@"[PrismaDiagnostics] run=%@", run);
}

+ (NSURL *)archiveForProfile:(NSString *)profile directory:(NSString *)directory crashReport:(NSString *)content
                  documents:(NSURL *)docs performanceReport:(NSURL *)performance error:(NSError **)error {
    NSURL *out = exports(docs);
    if (![files() createDirectoryAtURL:out withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    NSString *uuid = NSUUID.UUID.UUIDString;
    NSURL *stage = child([NSURL fileURLWithPath:NSTemporaryDirectory()],uuid);
    if (![files() createDirectoryAtURL:stage withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    @try {
        NSMutableArray *included = [NSMutableArray array], *missing = [NSMutableArray array];
        __block NSError *writeError;
        void (^add)(NSString *,NSData *) = ^(NSString *name, NSData *data) {
            if (!data.length) { [missing addObject:name]; return; }
            if (!writeError && [data writeToURL:child(stage,name) options:NSDataWritingAtomic error:&writeError])
                [included addObject:name];
        };
        NSURL *game = directory.length ? [NSURL fileURLWithPath:directory] : nil;
        NSArray *reports = newestMatching(docs,[NSPredicate predicateWithFormat:
            @"SELF MATCHES %@", @"ame273_crash_report(\\.last|\\.seen-[0-9]+)?\\.txt"],10);
        NSString *crash = content, *association = content.length ? @"displayed crash report" : nil;
        NSDate *when = reportDate(crash);
        NSURL *root = child(out,@".sessions");
        NSArray *sessions = newestMatching(root,[NSPredicate predicateWithFormat:@"SELF ENDSWITH %@",@".json"],128);
        NSDictionary *session = nil;
        NSString *explicitPID = match(crash,@"(?<=hs_err_pid)[0-9]+(?=\\.log)");
        NSString *explicitRun = snapshotRun(exitSnapshot(crash,docs,when));
        for (NSURL *file in sessions) {
            NSDictionary *s = loadJSON(file);
            if (![s[@"id"] isKindOfClass:NSString.class] || ![s[@"pid"] isKindOfClass:NSNumber.class] ||
                ![s[@"start"] isKindOfClass:NSNumber.class] || ![s[@"profile"] isKindOfClass:NSString.class]) continue;
            if (explicitRun && ![s[@"id"] isEqual:explicitRun]) continue;
            if (profile.length && ![s[@"profile"] isEqual:profile]) continue;
            if (!profile.length && (!when || (!explicitRun.length && !explicitPID.length))) continue;
            if (explicitPID.length && ![[s[@"pid"] stringValue] isEqual:explicitPID]) continue;
            if (when && [s[@"start"] doubleValue] > when.timeIntervalSince1970+1) continue;
            session = s;
            break;
        }
        if (session && !game && [session[@"directory"] length]) {
            NSURL *candidate = child(docs,session[@"directory"]);
            if (within(candidate,docs)) game = candidate;
        }
        if (!game && !session && content.length && when) game = legacyCrashDirectory(docs,when);
        NSURL *gameLog = game ? child(game,@"logs/latest.log") : nil;
        if (gameLog && !within(gameLog,game)) gameLog = nil;
        NSDate *gameDate = gameLog && regular(gameLog) ? modified(gameLog) : nil;
        NSString *pid = [session[@"pid"] stringValue];
        if (!crash.length) {
            for (NSURL *file in reports) {
                NSString *candidate = logString(logBytes(file,131072,YES));
                NSDate *date = reportDate(candidate) ?: modified(file);
                NSString *filePID = match(candidate,@"(?<=hs_err_pid)[0-9]+(?=\\.log)");
                if (pid && date.timeIntervalSince1970+1 < [session[@"start"] doubleValue]) continue;
                if (pid && filePID && ![filePID isEqual:pid]) continue;
                BOOL matchedPID = pid && [filePID isEqual:pid];
                NSString *run = session ? snapshotRun(exitSnapshot(candidate,docs,date)) : nil;
                if (run && ![session[@"id"] isEqual:run]) continue;
                if (!run && !matchedPID && !nearDate(gameDate,date)) continue;
                crash = candidate; when = date;
                association = run ? @"launcher snapshot run ID" : (matchedPID ? @"launch process ID" : @"game log and crash timestamps");
                break;
            }
        }
        if (gameLog && ((!session && content.length && !nearDate(when,gameDate)) ||
            (session && gameDate.timeIntervalSince1970+1 < [session[@"start"] doubleValue]) ||
            (content.length && when && [gameDate timeIntervalSinceDate:when]>120))) gameLog = nil;
        add(@"game-latest.log", CubicRedactedDiagnosticData(logBytes(gameLog,2*1024*1024,NO)));
        if (game && [files() fileExistsAtPath:game.path]) {
            NSDictionary *scene = [PerformanceTest sceneForDirectory:game.path since:gameDate ?: NSDate.date];
            add(@"profile.json",[NSJSONSerialization dataWithJSONObject:scene options:NSJSONWritingPrettyPrinted error:nil]);
            NSArray *javaReports = newestMatching(child(game,@"crash-reports"),
                [NSPredicate predicateWithFormat:@"SELF LIKE %@",@"crash-*.txt"],1);
            NSURL *javaReport = javaReports.firstObject;
            if (javaReport && within(javaReport,game) && nearDate(modified(javaReport),when ?: gameDate))
                add(@"minecraft-crash.txt",CubicRedactedDiagnosticData(logBytes(javaReport,512*1024,NO)));
        }
        add(@"crash-report.txt", CubicRedactedDiagnosticData([crash dataUsingEncoding:NSUTF8StringEncoding]));
        NSString *hs = match(crash,@"\\bhs_err_pid[0-9]+\\.log\\b");
        BOOL nativeFailure = [match(crash,@"(?m)(?<=^category: )[^\\r\\n]+") isEqual:@"jvm_fatal"];
        if (!hs && pid && (nativeFailure || !crash.length)) hs = [NSString stringWithFormat:@"hs_err_pid%@.log",pid];
        NSURL *jvm = hs ? child(docs,hs) : nil;
        BOOL jvmMatches = jvm && regular(jvm) && (when ? nearDate(when,modified(jvm)) :
            session && modified(jvm).timeIntervalSince1970 >= [session[@"start"] doubleValue]-1);
        if (hs || nativeFailure) add(hs ?: @"JVM crash log",jvmMatches ? CubicRedactedHotSpotData(logBytes(jvm,1024*1024,YES)) : nil);
        if (!when && jvmMatches) when = modified(jvm);
        NSString *trace = when ? fatalSection(logString(logBytes(child(docs,@"fatal_trace.txt"),262144,NO)),when,crash) : nil;
        add(@"fatal-trace.txt",CubicRedactedDiagnosticData([trace dataUsingEncoding:NSUTF8StringEncoding]));

        NSMutableArray *candidates = [NSMutableArray arrayWithArray:@[child(docs,@"latestlog.txt"),
            child(docs,@"latestlog.old.txt"),child(docs,@"latestlog.crash.txt")]];
        [candidates addObjectsFromArray:newestMatching(docs,[NSPredicate predicateWithFormat:@"SELF LIKE %@",@"latestlog.selfexit-*.txt"],5)];
        NSString *headline = match(crash,@"(?m)(?<=^headline: ).{12,}");
        NSString *crashMarker = hs ?: headline;
        NSData *launcher = logBytes(exitSnapshot(crash,docs,when),3*1024*1024,NO);
        for (NSURL *file in candidates) {
            if (launcher.length) break;
            if (!regular(file)) continue;
            NSData *bytes = logBytes(file,3*1024*1024,NO);
            NSString *text = logString(bytes);
            if (!text.length) continue;
            NSString *runMarker = session ? [@"[PrismaDiagnostics] run=" stringByAppendingString:session[@"id"]] : nil;
            BOOL tagged = runMarker && [text containsString:runMarker];
            BOOL matchedCrash = when && nearDate(when,modified(file)) && crashMarker.length && [text containsString:crashMarker];
            BOOL matchedProfile = !session && game && gameDate && nearDate(gameDate,modified(file)) &&
                ([text containsString:game.path] || [text containsString:canonical(game)]);
            if (tagged || matchedCrash || matchedProfile) { launcher = bytes; break; }
        }
        add(@"launcher.log", CubicRedactedDiagnosticData(launcher));
        if (!performance && [session[@"profile"] length]) performance = [PerformanceTest latestReportForProfile:session[@"profile"]];
        NSData *measurements = logBytes(performance,1024*1024,YES);
        id run = measurements ? [NSJSONSerialization JSONObjectWithData:measurements options:0 error:nil] : nil;
        if (![run isKindOfClass:NSDictionary.class] || (profile && ![run[@"profile"] isEqual:profile])) measurements = nil;
        // Test reports are structured, generated from an allowlist, and explicitly
        // identified as the latest test, which can precede the latest game launch.
        add(@"performance.json", measurements);
        struct utsname hw; uname(&hw);
        NSMutableDictionary *manifest = [@{@"schema":@1, @"exportedUTC":[NSISO8601DateFormatter.new stringFromDate:NSDate.date],
            @"hardware":[NSString stringWithUTF8String:hw.machine], @"system":UIDevice.currentDevice.systemVersion,
            @"included":included,@"unavailable":missing,@"profile":profile ?: session[@"profile"] ?: NSNull.null,
            @"version":session[@"version"] ?: NSNull.null,@"crashMatch":association ?: NSNull.null,
            @"performanceScope":@"Latest recorded test for this profile", @"textLogs":@"Filtered, size-limited excerpts"} mutableCopy];
#ifdef CONFIG_COMMIT
        manifest[@"exporterBuild"] = @CONFIG_COMMIT;
#endif
        if (session[@"launchOptions"]) manifest[@"launchOptions"] = session[@"launchOptions"];
        if (session[@"renderer"]) manifest[@"renderer"] = session[@"renderer"];
        NSData *metadata = [NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:error];
        if (writeError) { if (error) *error = writeError; return nil; }
        if (!metadata || ![metadata writeToURL:child(stage,@"manifest.json") options:NSDataWritingAtomic error:error]) return nil;
        NSString *stamp = [[NSISO8601DateFormatter.new stringFromDate:NSDate.date] stringByReplacingOccurrencesOfString:@":" withString:@"-"];
        NSURL *dest = child(out,[NSString stringWithFormat:@"Prisma-Diagnostics-%@-%@.zip",stamp,[uuid substringToIndex:8]]);
        __block BOOL copied = NO;
        __block NSError *copyError;
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        [coordinator coordinateReadingItemAtURL:stage options:NSFileCoordinatorReadingForUploading error:error
            byAccessor:^(NSURL *zip) { copied = [files() copyItemAtURL:zip toURL:dest error:&copyError]; }];
        if (!copied && copyError && error) *error = copyError;
        return copied ? dest : nil;
    } @finally {
        [files() removeItemAtURL:stage error:nil];
    }
}

+ (void)shareForProfile:(NSString *)profile directory:(NSString *)directory
            crashReport:(NSString *)content from:(UIViewController *)presenter {
    if (!presenter.view.window) return;
    UIAlertController *status = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Preparing diagnostics…", nil)
        message:NSLocalizedString(@"A copy is saved in Files under PrismaCubic → Diagnostics.",nil)
        preferredStyle:UIAlertControllerStyleAlert];
    [presenter presentViewController:status animated:YES completion:^{
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
            NSError *error = nil;
            NSURL *archive = [self archiveForProfile:profile directory:directory crashReport:content
                documents:documentsURL() performanceReport:[PerformanceTest latestReportForProfile:profile] error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                [status dismissViewControllerAnimated:YES completion:^{
                    if (!presenter.view.window) return;
                    if (!archive) {
                        UIAlertController *failure = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Export failed",nil)
                            message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                        [failure addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK",nil)
                            style:UIAlertActionStyleDefault handler:nil]];
                        [presenter presentViewController:failure animated:YES completion:nil];
                        return;
                    }
                    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[archive] applicationActivities:nil];
                    share.popoverPresentationController.sourceView = presenter.view;
                    share.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds),
                        CGRectGetMidY(presenter.view.bounds),1,1);
                    [presenter presentViewController:share animated:YES completion:nil];
                }];
            });
        });
    }];
}
@end
