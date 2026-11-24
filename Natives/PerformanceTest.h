#import <UIKit/UIKit.h>

@interface PerformanceTest : NSObject
+ (void)showForProfile:(NSString *)name version:(NSString *)version gameDirectory:(NSString *)directory
                  from:(UIViewController *)controller launch:(void (^)(void))launch;
+ (NSDictionary *)sceneForDirectory:(NSString *)directory since:(NSDate *)date;
+ (nullable NSURL *)latestReportForProfile:(NSString *)profile;
+ (nullable NSURL *)activeReportURL;
+ (nullable NSURL *)activeCaptureMarkerURL;
+ (NSDictionary *)reportWithHitchEvidence:(NSDictionary *)report atURL:(NSURL *)url;
+ (void)claimLaunchRequestForProfile:(NSString *)profile;
+ (instancetype)takeForGame:(NSString *)profile;
@property(nonatomic, readonly) BOOL recording;
- (void)recordLaunchOptions:(NSDictionary *)options;
- (void)recordDisplayCadence:(NSDictionary *)sample forPhase:(NSString *)phase;
- (void)firstFrameObserved;
- (BOOL)beginCapture;
- (void)shareFrom:(UIViewController *)controller;
- (BOOL)tickWidth:(int)width height:(int)height memoryMiB:(double)memory;
- (void)interrupt;
@end
