#import "ModpackLayout.h"
#include <assert.h>

int main(void) {
    @autoreleasepool {
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *instances = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSString *folder = @"curseforge_45307D42-B213-4497-A9EF-F8B82CF40182";
        NSString *live = [instances stringByAppendingPathComponent:folder];
        NSString *content = [live stringByAppendingPathComponent:@"versions/1.20.1-forge-47.4.28-pack"];
        assert([fm createDirectoryAtPath:content withIntermediateDirectories:YES attributes:nil error:NULL]);
        assert([ModpackInstanceID(live, instances) isEqual:folder]);
        assert([ModpackInstanceID(content, instances) isEqual:folder]);
        assert(!ModpackInstanceID([content stringByAppendingPathComponent:@"mods"], instances));
        assert(!ModpackInstanceID([live stringByAppendingString:@"-backup-12345"], instances));

        NSString *installer = [instances stringByAppendingPathComponent:@"default"];
        NSString *libraries = [installer stringByAppendingPathComponent:@"libraries"];
        NSString *stage = [instances stringByAppendingPathComponent:@".stage"];
        assert([fm createDirectoryAtPath:stage withIntermediateDirectories:YES attributes:nil error:NULL]);
        NSArray *products = @[
            @"net/minecraft/client/1.20.1-20230612.114412/client-1.20.1-20230612.114412-srg.jar",
            @"net/minecraft/client/1.20.1-20230612.114412/client-1.20.1-20230612.114412-extra.jar",
            @"net/minecraftforge/forge/1.20.1-47.4.28/forge-1.20.1-47.4.28-client.jar"
        ];
        NSData *header = [NSData dataWithBytes:"PK\003\004" length:4];
        for (NSString *product in products) {
            NSError *error = nil;
            assert(!ModpackPrepareForgeJar(libraries, stage, product, &error) && error);
            NSString *source = [libraries stringByAppendingPathComponent:product];
            assert([fm createDirectoryAtPath:source.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL]);
            assert([NSData.data writeToFile:source atomically:YES]);
            assert(!ModpackPrepareForgeJar(libraries, stage, product, NULL));
            assert([header writeToFile:source atomically:YES]);
            assert(ModpackPrepareForgeJar(libraries, installer, product, NULL));
            assert(ModpackPrepareForgeJar(libraries, stage, product, NULL));
            assert(ModpackPrepareForgeJar(libraries, stage, product, NULL));
        }
        assert(!ModpackPrepareForgeJar(libraries, stage, @"../elsewhere", NULL));
        assert([fm moveItemAtPath:live toPath:[live stringByAppendingString:@"-backup-12345"] error:NULL]);
        assert([fm moveItemAtPath:stage toPath:live error:NULL]);
        for (NSString *product in products) {
            NSString *installed = [[live stringByAppendingPathComponent:@"libraries"] stringByAppendingPathComponent:product];
            assert([[NSData dataWithContentsOfFile:installed] isEqual:header]);
        }
        assert([fm removeItemAtPath:instances error:NULL]);
    }
    return 0;
}
