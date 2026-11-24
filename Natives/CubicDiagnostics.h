#import <UIKit/UIKit.h>

@interface CubicDiagnostics : NSObject
+ (void)markLaunchForProfile:(NSString *)profile directory:(NSString *)directory version:(NSString *)version;
+ (void)updateLaunchDetails:(NSDictionary *)details;
+ (void)shareForProfile:(NSString *)profile directory:(NSString *)directory
            crashReport:(NSString *)content from:(UIViewController *)presenter;
// File collection and compression run on a background queue. The returned archive
// is also accessible in Files > PrismaCubic > Diagnostics.
+ (NSURL *)archiveForProfile:(NSString *)profile directory:(NSString *)directory crashReport:(NSString *)content
                  documents:(NSURL *)documents performanceReport:(NSURL *)performance error:(NSError **)error;
@end
