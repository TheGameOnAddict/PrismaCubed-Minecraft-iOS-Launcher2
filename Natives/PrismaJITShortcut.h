#import <UIKit/UIKit.h>

@interface PrismaJITShortcut : NSObject
+ (void)prepareWithCompletion:(void (^)(BOOL ready))completion;
+ (void)restoreWithCompletion:(void (^)(void))completion;
+ (void)recoverOnFirstActivation;
+ (void)handleCallbackURL:(NSURL *)url;
@end
