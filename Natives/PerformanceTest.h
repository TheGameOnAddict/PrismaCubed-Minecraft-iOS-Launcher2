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
@property(nonatomic, readonly) BOOL showsRenderBenchmark;
@property(nonatomic, readonly) NSString *renderBenchmarkMenuTitle;
@property(nonatomic, readonly, nullable) NSString *renderBenchmarkResult;
- (void)showRenderBenchmarkFrom:(UIViewController *)controller;
- (void)shareFrom:(UIViewController *)controller;
- (BOOL)tickWidth:(int)width height:(int)height memoryMiB:(double)memory
        renderFPS:(NSInteger)renderFPS presentedPerSecond:(NSInteger)presented;
- (void)interrupt;
@end
