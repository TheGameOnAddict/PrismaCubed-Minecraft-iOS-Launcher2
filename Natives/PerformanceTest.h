#import <UIKit/UIKit.h>

@interface PerformanceTest : NSObject
+ (void)showForProfile:(NSString *)name version:(NSString *)version gameDirectory:(NSString *)directory
                  from:(UIViewController *)controller launch:(void (^)(void))launch;
+ (void)claimLaunchRequestForProfile:(NSString *)profile;
+ (instancetype)takeForGame:(NSString *)profile;
@property(nonatomic, readonly) BOOL recording;
- (void)recordLaunchOptions:(NSDictionary *)options;
- (void)firstFrameObserved;
- (BOOL)beginCapture;
- (void)shareFrom:(UIViewController *)controller;
- (BOOL)tickWidth:(int)width height:(int)height memoryMiB:(double)memory;
- (void)interrupt;
@end
