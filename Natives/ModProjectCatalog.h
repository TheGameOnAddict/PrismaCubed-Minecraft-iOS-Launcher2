#import <Foundation/Foundation.h>
#import "ModVersion.h"

typedef void (^ModFilesCompletion)(NSArray<ModVersion *> *files, NSError *error);

@interface ModProjectCatalog : NSObject
+ (void)filesForID:(NSString *)projectID source:(NSInteger)source completion:(ModFilesCompletion)completion;
+ (void)findProject:(NSString *)title type:(NSString *)type source:(NSInteger)source completion:(void (^)(NSString *, NSError *))completion;
+ (ModVersion *)latestFile:(NSArray<ModVersion *> *)files minecraft:(NSString *)minecraft loader:(NSString *)loader;
+ (void)quickFileForID:(NSString *)projectID title:(NSString *)title source:(NSInteger)source minecraft:(NSString *)minecraft loader:(NSString *)loader completion:(void (^)(ModVersion *, NSError *))completion;
@end
