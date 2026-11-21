#import "PrismaJITShortcut.h"
#import "StikDebugEngine.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import <netinet/in.h>

static NSString *const PendingRestoreKey = @"PrismaCubedJITPendingRestore";
static NSString *callbackToken;
static void (^shortcutCompletion)(BOOL, NSString *);
static BOOL preparing;

@implementation PrismaJITShortcut

+ (void)finish:(BOOL)success result:(NSString *)result token:(NSString *)token {
    if (![callbackToken isEqualToString:token]) return;
    void (^completion)(BOOL, NSString *) = shortcutCompletion;
    shortcutCompletion = nil;
    callbackToken = nil;
    if (completion) completion(success, result);
}

+ (void)runCommand:(NSString *)command completion:(void (^)(BOOL, NSString *))completion {
    if (shortcutCompletion) {
        completion(NO, nil);
        return;
    }

    NSString *token = NSUUID.UUID.UUIDString;
    callbackToken = token;
    shortcutCompletion = [completion copy];
    NSString *callbackBase = [NSString stringWithFormat:@"prismacubed-jit://shortcut/%@/", token];
    NSURLComponents *url = [NSURLComponents componentsWithString:@"shortcuts://x-callback-url/run-shortcut"];
    url.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"name" value:@"PrismaCubed JIT"],
        [NSURLQueryItem queryItemWithName:@"input" value:@"text"],
        [NSURLQueryItem queryItemWithName:@"text" value:command],
        [NSURLQueryItem queryItemWithName:@"x-success" value:[callbackBase stringByAppendingString:@"success"]],
        [NSURLQueryItem queryItemWithName:@"x-error" value:[callbackBase stringByAppendingString:@"error"]],
        [NSURLQueryItem queryItemWithName:@"x-cancel" value:[callbackBase stringByAppendingString:@"cancel"]],
    ];
    [UIApplication.sharedApplication openURL:url.URL options:@{} completionHandler:^(BOOL opened) {
        if (!opened) [self finish:NO result:nil token:token];
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 45 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self finish:NO result:nil token:token];
    });
}

+ (void)handleCallbackURL:(NSURL *)url {
    if (![url.scheme isEqualToString:@"prismacubed-jit"] || ![url.host isEqualToString:@"shortcut"]) return;
    NSArray<NSString *> *path = url.pathComponents;
    if (path.count != 3) return;
    BOOL success = [path[2] isEqualToString:@"success"];
    NSString *result = nil;
    for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems) {
        if ([item.name isEqualToString:success ? @"result" : @"errorMessage"]) {
            result = item.value;
            break;
        }
    }
    if (!success) NSLog(@"[Cellular JIT] Shortcut callback: %@ (%@)", path[2], result ?: @"");
    [self finish:success result:result token:path[1]];
}

+ (BOOL)usesCellular {
    struct sockaddr_in address = { .sin_len = sizeof(address), .sin_family = AF_INET };
    SCNetworkReachabilityRef route = SCNetworkReachabilityCreateWithAddress(NULL, (const struct sockaddr *)&address);
    if (!route) return NO;
    SCNetworkReachabilityFlags flags = 0;
    BOOL gotFlags = SCNetworkReachabilityGetFlags(route, &flags);
    CFRelease(route);
    return gotFlags && (flags & kSCNetworkReachabilityFlagsIsWWAN);
}

+ (void)waitForVPNUntil:(NSTimeInterval)deadline completion:(void (^)(BOOL))completion {
    [StikDebugEngine.sharedEngine checkLocalDevVPNWithCompletion:^(BOOL connected) {
        if (connected || NSProcessInfo.processInfo.systemUptime >= deadline) {
            completion(connected);
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
            [self waitForVPNUntil:deadline completion:completion];
        });
    }];
}

+ (void)prepareWithCompletion:(void (^)(BOOL))completion {
    if (preparing || shortcutCompletion) {
        completion(NO);
        return;
    }
    preparing = YES;
    [StikDebugEngine.sharedEngine checkLocalDevVPNWithCompletion:^(BOOL connected) {
        if (connected) {
            preparing = NO;
            completion(YES);
            return;
        }
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        if ([defaults stringForKey:PendingRestoreKey]) {
            preparing = NO;
            completion(NO);
            return;
        }
        BOOL cellular = [self usesCellular];
        NSString *done = cellular ? @"done cellular" : @"done";
        [defaults setObject:done forKey:PendingRestoreKey];
        [self runCommand:cellular ? @"start cellular" : @"start" completion:^(BOOL success, NSString *result) {
            if (!success) {
                preparing = NO;
                completion(NO);
                return;
            }
            NSString *vpnAction = @{
                @"none": @" vpn-off", @"other": @" vpn-restore", @"local": @""
            }[[result stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @""];
            if (!vpnAction) {
                preparing = NO;
                completion(NO);
                return;
            }
            [defaults setObject:[done stringByAppendingString:vpnAction] forKey:PendingRestoreKey];
            [self waitForVPNUntil:NSProcessInfo.processInfo.systemUptime + 15 completion:^(BOOL ready) {
                preparing = NO;
                completion(ready);
            }];
        }];
    }];
}

+ (void)restoreWithCompletion:(void (^)(void))completion {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *pending = [defaults stringForKey:PendingRestoreKey];
    if (!pending || preparing || shortcutCompletion) {
        if (completion) completion();
        return;
    }
    [self runCommand:pending completion:^(BOOL success, NSString *result) {
        if (success) {
            [defaults removeObjectForKey:PendingRestoreKey];
        } else {
            NSLog(@"[Cellular JIT] Network restore did not finish; will retry on the next launch");
        }
        if (completion) completion();
    }];
}

+ (void)recoverOnFirstActivation {
    static BOOL ran;
    if (ran) return;
    ran = YES;
    if (@available(iOS 27.0, *)) [self restoreWithCompletion:nil];
}

@end
