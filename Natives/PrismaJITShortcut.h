#import <UIKit/UIKit.h>

static inline NSURL *PrismaJITShortcutSetupURL(void) {
    return [NSURL URLWithString:@"https://github.com/TheGameOnAddict/PrismaCubed-Minecraft-iOS-Launcher2/blob/feature/prisma-beta-english-forge/docs/prismacubed-cellular-jit.md"];
}

@interface PrismaJITShortcut : NSObject
+ (void)prepareWithCompletion:(void (^)(BOOL ready))completion;
+ (void)restoreWithCompletion:(void (^)(void))completion;
+ (void)recoverOnFirstActivation;
+ (void)handleCallbackURL:(NSURL *)url;
@end
