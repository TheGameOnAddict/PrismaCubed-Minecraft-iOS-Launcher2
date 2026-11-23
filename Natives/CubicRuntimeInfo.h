#import <Foundation/Foundation.h>

@interface CubicRuntimeInfo : NSObject
+ (void)reset;
+ (void)observeNativeRenderer:(const char *)value;
+ (void)observeGameLine:(NSString *)line;
+ (NSDictionary *)renderer;
+ (NSString *)javaVersionAtHome:(NSString *)home;
@end
