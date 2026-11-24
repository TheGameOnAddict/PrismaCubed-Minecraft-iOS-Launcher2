// Exercises the same archive exporter used by the profile and crash sheets.
// Real crash files, accounts, and game saves are never used in simulator tests.
#import "CubicDiagnostics.h"

static void writeFixture(NSString *text, NSURL *url, NSDate *time) {
    NSCAssert([text writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil], @"Could not write fixture %@",url.lastPathComponent);
    NSCAssert([NSFileManager.defaultManager setAttributes:@{NSFileModificationDate:time} ofItemAtPath:url.path error:nil],
              @"Could not stamp fixture %@",url.lastPathComponent);
}

void CubicRunDiagnosticsFixture(void) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSURL *root = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSURL *game = [root URLByAppendingPathComponent:@"instances/example"];
    NSURL *logs = [game URLByAppendingPathComponent:@"logs"];
    NSCAssert([files createDirectoryAtURL:logs withIntermediateDirectories:YES attributes:nil error:nil], @"Could not create fixture");
    NSURL *docs = [files URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSDate *now = NSDate.date;
    NSDateFormatter *format = [NSDateFormatter new];
    format.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    format.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *stamp = [format stringFromDate:now];
    NSString *report = [NSString stringWithFormat:@"=== ame273 crash report ===\ntime: %@\nexit_code: 6\ncategory: jvm_fatal\nheadline: Problematic frame in libMobileGL.dylib\ndetail_begin\nAn error report file with more information is saved as:\nhs_err_pid10981.log\ndetail_end\n", stamp];
    NSString *hotspot = @"# A fatal error has been detected by the Java Runtime Environment:\n# SIGSEGV (0xb) at pc=0x1234, pid=10981, tid=7\n# Problematic frame:\n# C  [libMobileGL.dylib+0x77cd74]\nNative frames: (J=compiled Java code, j=interpreted)\nC  [libMobileGL.dylib+0x77cd74]\n\nCommand Line: --accessToken secret-test\nRegisters:\nX1=raw-register-fixture\nEnvironment Variables:\nCANARY_ENV=private-fixture-value\n";
    NSURL *hs = [root URLByAppendingPathComponent:@"hs_err_pid10981.log"];
    NSURL *extra = [root URLByAppendingPathComponent:@"hs_err_pid99999.log"];
    NSURL *metrics = [root URLByAppendingPathComponent:@"test.json"];
    writeFixture(@"renderDistance:8\nunknown-setting:setting-canary\n",[game URLByAppendingPathComponent:@"options.txt"],now);
    NSURL *outside = [root URLByAppendingPathComponent:@"external-config"];
    NSCAssert([files createDirectoryAtURL:outside withIntermediateDirectories:NO attributes:nil error:nil], @"Could not create canary directory");
    writeFixture(@"shaderPack=shader-canary.zip\n",[outside URLByAppendingPathComponent:@"oculus.properties"],now);
    NSCAssert([files createSymbolicLinkAtURL:[game URLByAppendingPathComponent:@"config"] withDestinationURL:outside error:nil], @"Could not link canary config");
    writeFixture(hotspot,hs,now);
    writeFixture(@"Unreferenced JVM dump\n",extra,now);
    writeFixture(@"{\"schema\":1,\"profile\":\"example\",\"status\":\"complete\"}",metrics,now);
    writeFixture(@"[Render thread/INFO]: OpenGL Renderer: zink Vulkan 1.4\n[CHAT] private-test\n",[logs URLByAppendingPathComponent:@"latest.log"],now);
    writeFixture(@"Newly restarted launcher without game logs.\n",[root URLByAppendingPathComponent:@"latestlog.txt"],now);
    writeFixture(@"[Init] hs_err_pid10981.log\n--accessToken secret-test\n",[root URLByAppendingPathComponent:@"latestlog.old.txt"],now);
    writeFixture(@"world contents must never be included",[game URLByAppendingPathComponent:@"level.dat"],now);
    writeFixture(report,[root URLByAppendingPathComponent:@"ame273_crash_report.last.txt"],now);
    for (NSString *name in @[@"matched", @"profile", @"stale"]) {
        if ([name isEqual:@"stale"]) {
            writeFixture(hotspot,hs,[now dateByAddingTimeInterval:-86400]);
            writeFixture(@"{\"schema\":1,\"profile\":\"other-profile\"}",metrics,now);
        }
        NSError *error = nil;
        NSURL *zip = [CubicDiagnostics archiveForProfile:@"example" directory:game.path crashReport:([name isEqual:@"profile"] ? nil : report)
            documents:root performanceReport:metrics error:&error];
        NSCAssert(zip && [zip.pathExtension isEqual:@"zip"], @"Could not create %@ diagnostics ZIP: %@",name,error);
        NSURL *dest = [docs URLByAppendingPathComponent:[NSString stringWithFormat:@"fixture-%@.zip",name]];
        NSCAssert([files copyItemAtURL:zip toURL:dest error:&error], @"Could not retrieve fixture ZIP: %@",error);
    }
    // An early Java exit can happen before Minecraft creates logs/latest.log.
    // The launcher restarts and the fatal trace accumulates other launches.
    [files removeItemAtURL:[logs URLByAppendingPathComponent:@"latest.log"] error:nil];
    NSString *run = NSUUID.UUID.UUIDString;
    NSURL *sessions = [root URLByAppendingPathComponent:@"Diagnostics/.sessions"];
    NSCAssert([files createDirectoryAtURL:sessions withIntermediateDirectories:YES attributes:nil error:nil], @"Could not create sessions directory");
    NSDictionary *session = @{@"id":run, @"profile":@"example", @"pid":@12260,
                              @"directory":@"instances/example", @"start":@([now timeIntervalSince1970]-15)};
    NSData *json = [NSJSONSerialization dataWithJSONObject:session options:0 error:nil];
    NSCAssert([json writeToURL:[sessions URLByAppendingPathComponent:@"session.json"] atomically:YES], @"Could not create session fixture");
    NSDate *traceTime = [now dateByAddingTimeInterval:-1];
    format.dateFormat = @"MMdd-HHmmss";
    NSString *snapshot = [NSString stringWithFormat:@"latestlog.selfexit-%@.txt",[format stringFromDate:traceTime]];
    format.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    NSString *(^header)(NSDate *) = ^(NSDate *time) {
        return [NSString stringWithFormat:@"===== [Amethyst fatal trace] %@ =====",[format stringFromDate:time]];
    };
    NSString *traceHeader = header(traceTime);
    NSString *trace = [NSString stringWithFormat:@"%@\nreason: exit(0) called\nprevious-run-canary\n%@\nreason: exit(1) called\nmatching-trace\n%@\nreason: exit(0) called\nfollowing-run-canary\n",
                       header([now dateByAddingTimeInterval:-80]),traceHeader,header([now dateByAddingTimeInterval:0.8])];
    NSString *headline = @"Caused by: joptsimple.ValueConversionException: Directory does not exist";
    NSString *javaExit = [NSString stringWithFormat:@"=== ame273 crash report ===\ntime: %@\nexit_code: 1\ncategory: java_exception\nheadline: %@\ndetail_begin\n[Task261] selfexit snapshot saved: %@ (54886B) -- silent-exit log preserved against rotation\n%@\nreason: exit(1) called\ndetail_end\n",
                          stamp,headline,snapshot,traceHeader];
    writeFixture([NSString stringWithFormat:@"[PrismaDiagnostics] run=%@\nmatching-launcher-snapshot\n",run],[root URLByAppendingPathComponent:snapshot],traceTime);
    writeFixture([NSString stringWithFormat:@"Restart after failure: %@\nwrong-restart-log\n",headline],[root URLByAppendingPathComponent:@"latestlog.txt"],now);
    writeFixture(trace,[root URLByAppendingPathComponent:@"fatal_trace.txt"],now);
    writeFixture(hotspot,[root URLByAppendingPathComponent:@"hs_err_pid12260.log"],now);
    writeFixture(javaExit,[root URLByAppendingPathComponent:@"ame273_crash_report.last.txt"],now);
    for (NSString *name in @[@"early", @"early-profile"]) {
        NSError *error = nil;
        NSURL *zip = [CubicDiagnostics archiveForProfile:@"example" directory:game.path crashReport:([name isEqual:@"early"] ? javaExit : nil)
            documents:root performanceReport:metrics error:&error];
        NSCAssert(zip, @"Could not create early exit ZIP: %@",error);
        NSURL *dest = [docs URLByAppendingPathComponent:[NSString stringWithFormat:@"fixture-%@.zip",name]];
        NSCAssert([files copyItemAtURL:zip toURL:dest error:&error], @"Could not retrieve early exit ZIP: %@",error);
    }
    // MobileGL reuses one file across all profiles. Run across midnight, then
    // overwrite it from another profile and finally restore a stale copy.
    [files removeItemAtURL:[root URLByAppendingPathComponent:@"ame273_crash_report.last.txt"] error:nil];
    [files removeItemAtURL:[sessions URLByAppendingPathComponent:@"session.json"] error:nil];
    format.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSDate *start = [format dateFromString:@"2026-01-18 23:59:57"];
    NSDate *end = [start dateByAddingTimeInterval:15];
    NSDictionary *mobileSession = @{@"id":run, @"profile":@"example", @"pid":@11111, @"directory":@"instances/example",
        @"renderer":@{@"library":@"libMobileGL.dylib"}, @"start":@(start.timeIntervalSince1970)};
    NSData *mobileData = [NSJSONSerialization dataWithJSONObject:mobileSession options:0 error:nil];
    NSCAssert([mobileData writeToURL:[sessions URLByAppendingPathComponent:@"session.json"] atomically:YES], @"Could not write renderer session");
    NSURL *mobileFile = [root URLByAppendingPathComponent:@"mobilegl.log"];
    NSMutableString *driver = [NSMutableString stringWithString:@"[00:00:01] [macOS UnknownThread/INFO]: Initializing MobileGL...\n[00:00:01] [macOS UnknownThread/INFO]: Renderer Name: Magma\n[00:00:01] [macOS UnknownThread/INFO]: --accessToken renderer-canary\n"];
    for (NSUInteger i = 0; i < 7000; i++) {
        [driver appendFormat:@"[00:00:%02lu] [macOS UnknownThread/FATAL]: Vulkan error VK_ERROR_DEVICE_LOST (-4)\n"
                              @"[00:00:%02lu] [macOS UnknownThread/FATAL]: Present, vkQueuePresentKHR\n",
                              (unsigned long)(i%10+2),(unsigned long)(i%10+2)];
    }
    [driver appendString:@"[00:00:12] [macOS UnknownThread/FATAL]: final fence operation\n"];
    writeFixture(driver,mobileFile,end);
    NSURL *otherFile = [sessions URLByAppendingPathComponent:@"other.json"];
    for (NSString *name in @[@"mobilegl", @"mobilegl-other-run", @"mobilegl-stale"]) {
        if ([name isEqual:@"mobilegl-other-run"]) {
            NSDictionary *other = @{@"id":NSUUID.UUID.UUIDString, @"profile":@"other", @"pid":@22222,
                @"start":@([end timeIntervalSince1970]-2)};
            NSCAssert([[NSJSONSerialization dataWithJSONObject:other options:0 error:nil] writeToURL:otherFile atomically:YES], @"Could not create other profile");
        } else if ([name isEqual:@"mobilegl-stale"]) {
            [files removeItemAtURL:otherFile error:nil];
            writeFixture(@"[23:55:00] [macOS UnknownThread/INFO]: Initializing MobileGL...\nold renderer output\n",mobileFile,end);
        }
        NSError *error = nil;
        NSURL *zip = [CubicDiagnostics archiveForProfile:@"example" directory:game.path crashReport:nil documents:root performanceReport:metrics error:&error];
        NSCAssert(zip, @"Could not create renderer ZIP: %@",error);
        NSURL *destination = [docs URLByAppendingPathComponent:[NSString stringWithFormat:@"fixture-%@.zip",name]];
        NSCAssert([files copyItemAtURL:zip toURL:destination error:&error], @"Could not retrieve renderer fixture: %@",error);
    }
    [files removeItemAtURL:root error:nil];
    writeFixture(@"ok", [docs URLByAppendingPathComponent:@"fixture-diagnostics.done"], now);
}
