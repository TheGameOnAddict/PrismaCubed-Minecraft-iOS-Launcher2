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
    [files removeItemAtURL:root error:nil];
    writeFixture(@"ok", [docs URLByAppendingPathComponent:@"fixture-diagnostics.done"], now);
}
