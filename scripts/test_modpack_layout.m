#import "ModpackLayout.h"
#include <assert.h>

int main(void) {
    @autoreleasepool {
        NSString *mod = @"oculus-mc1.20.1-1.8.0.jar";
        assert([ModpackInstalledFileName(mod, @"mods", @NO) isEqual:[mod stringByAppendingPathExtension:@"disabled"]]);
        assert([ModpackInstalledFileName(mod, @"mods", @YES) isEqual:mod]);
        assert([ModpackInstalledFileName(mod, @"mods", nil) isEqual:mod]);
        assert([ModpackInstalledFileName(@"shaders.zip", @"shaderpacks", @NO) isEqual:@"shaders.zip"]);

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

        NSString *oldBase = @"/private/var/mobile/Containers/Data/Application/2B43FB61-E3B9-4EC8-AEBF-A03D4E324F62/Documents/instances";
        NSString *old = [oldBase stringByAppendingPathComponent:folder];
        NSString *oldNested = [old stringByAppendingPathComponent:@"versions/1.20.1-forge-47.4.28-pack"];
        NSString *portable = [@"instances" stringByAppendingPathComponent:folder];
        NSString *customDir = [@"/other/Documents/instances" stringByAppendingPathComponent:folder];
        NSDictionary *source = @{@"selectedProfile":@"THE GANG", @"profiles":@{
            @"THE GANG":@{@"type":@"modpack", @"gameDir":old, @"lastVersionId":@"forge"},
            @"Nested":@{@"type":@"modpack", @"gameDir":oldNested},
            @"Outside":@{@"type":@"modpack", @"gameDir":customDir},
            @"Custom":@{@"type":@"custom", @"gameDir":old}}};
        NSMutableDictionary *(^roundTrip)(NSDictionary *) = ^NSMutableDictionary *(NSDictionary *registry) {
            NSData *json = [NSJSONSerialization dataWithJSONObject:registry options:0 error:NULL];
            return [NSJSONSerialization JSONObjectWithData:json options:NSJSONReadingMutableContainers error:NULL];
        };
        NSMutableDictionary *loaded = roundTrip(source);
        ModpackTranslateProfileDirectories(loaded, instances, NO);
        assert([loaded[@"profiles"][@"THE GANG"][@"gameDir"] isEqual:live]);
        assert([loaded[@"profiles"][@"Nested"][@"gameDir"] isEqual:content]);
        assert([loaded[@"profiles"][@"Outside"][@"gameDir"] isEqual:customDir]);
        assert([loaded[@"profiles"][@"Custom"][@"gameDir"] isEqual:old]);
        assert(!ModpackProfileContentUnavailable(loaded[@"profiles"][@"THE GANG"], instances));
        NSMutableDictionary *disk = roundTrip(loaded);
        ModpackTranslateProfileDirectories(disk, instances, YES);
        assert([disk[@"profiles"][@"THE GANG"][@"gameDir"] isEqual:portable]);
        assert([disk[@"profiles"][@"Nested"][@"gameDir"] hasPrefix:[portable stringByAppendingString:@"/versions/"]]);
        assert([loaded[@"profiles"][@"THE GANG"][@"gameDir"] isEqual:live]);
        NSString *newBase = [instances stringByAppendingPathComponent:@"newContainer"];
        NSMutableDictionary *restored = roundTrip(disk);
        ModpackTranslateProfileDirectories(restored, newBase, NO);
        assert([restored[@"profiles"][@"THE GANG"][@"gameDir"] isEqual:[newBase stringByAppendingPathComponent:folder]]);
        assert(ModpackProfileContentUnavailable(restored[@"profiles"][@"THE GANG"], newBase));
        assert(![fm fileExistsAtPath:newBase]);
        assert(!ModpackContentRelativePath([old stringByAppendingString:@"/versions/.."], instances));
        assert(!ModpackContentRelativePath([old stringByAppendingString:@"-backup"], instances));
        assert([ModpackContentRelativePath([old substringFromIndex:8], instances) isEqual:folder]);
        assert([fm createDirectoryAtPath:newBase withIntermediateDirectories:YES attributes:nil error:NULL]);
        assert([fm createSymbolicLinkAtPath:[newBase stringByAppendingPathComponent:folder] withDestinationPath:live error:NULL]);
        assert(ModpackProfileContentUnavailable(restored[@"profiles"][@"THE GANG"], newBase));

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
        NSDictionary *card = @{@"name":folder, @"gameDir":live, @"type":@"custom"};
        assert(ModpackIsDirectoryCard(folder, card, instances));
        NSString *oldFolder = [@"/var/mobile/Containers/Data/Application/A0123456-ABCD-1234-BEEF-0123456789AB/Documents/instances" stringByAppendingPathComponent:folder];
        assert(ModpackIsDirectoryCard(folder, @{@"name":folder, @"gameDir":oldFolder, @"type":@"custom"}, instances));
        assert(ModpackIsGeneratedFolder(@"mmc_45307D42-B213-4497-A9EF-F8B82CF40182"));
        assert(!ModpackIsGeneratedFolder(@"my_45307D42-B213-4497-A9EF-F8B82CF40182"));
        assert(!ModpackIsDirectoryCard(@"THE GANG", card, instances));
        NSMutableDictionary *configured = card.mutableCopy;
        configured[@"gameDir"] = content;
        assert(ModpackIsDirectoryCard(folder, configured, instances));
        configured[@"icon"] = @"custom";
        assert(!ModpackIsDirectoryCard(folder, configured, instances));
        NSString *vid = content.lastPathComponent;
        NSString *manifest = [NSString stringWithFormat:@"versions/%@/%@.json", vid, vid];
        NSString *mainJSON = [installer stringByAppendingPathComponent:manifest];
        assert([fm createDirectoryAtPath:mainJSON.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL]);
        assert([NSData.data writeToFile:mainJSON atomically:YES]);
        assert([NSData.data writeToFile:[live stringByAppendingPathComponent:manifest] atomically:YES]);
        assert([ModpackInstalledRuntime(instances, @"default", nil, vid) isEqual:ModpackResolvedPath(installer, NULL)]);
        assert(!ModpackInstalledRuntime(instances, @"../default", nil, vid));
        NSString *home = [instances stringByAppendingPathComponent:@"legacy-home"];
        NSString *stable = [home stringByAppendingPathComponent:@"Library/Application Support/minecraft"];
        assert([fm createDirectoryAtPath:stable.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL]);
        assert([fm createSymbolicLinkAtPath:stable withDestinationPath:installer error:NULL]);
        assert([ModpackInstalledRuntime(home, nil, @"default", vid) isEqual:ModpackResolvedPath(installer, NULL)]);
        NSString *runtimeJSON = [NSString stringWithFormat:@"versions/%@/%@.json", vid, vid];
        NSString *runtimeLibrary = [@"libraries" stringByAppendingPathComponent:products.firstObject];
        NSString *receiptPath = [mainJSON.stringByDeletingLastPathComponent stringByAppendingPathComponent:@".prismacubic-forge.plist"];
        NSString *expected = @"0123456789012345678901234567890123456789";
        NSString *(^fixtureDigest)(NSString *) = ^NSString *(NSString *file) {
            NSData *data = [NSData dataWithContentsOfFile:file];
            return (data && (data.length == 0 || [data isEqual:header])) ? expected : nil;
        };
        assert(!ModpackCanReuseForge(installer, vid, fixtureDigest));
        NSDictionary *receipt = @{runtimeJSON:expected, runtimeLibrary:expected};
        assert([receipt writeToFile:receiptPath atomically:YES]);
        assert(ModpackCanReuseForge(installer, vid, fixtureDigest));
        assert(!ModpackCanReuseForge(installer, @"1.20.1-forge-47.4.29", fixtureDigest));
        NSString *jar = [installer stringByAppendingPathComponent:runtimeLibrary];
        assert([[@"broken" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:jar atomically:YES]);
        assert(!ModpackCanReuseForge(installer, vid, fixtureDigest));
        assert([fm removeItemAtPath:jar error:NULL]);
        assert(!ModpackCanReuseForge(installer, vid, fixtureDigest));
        assert([header writeToFile:jar atomically:YES]);
        // A new profile reached through an alias has no libraries/net/... descendants yet.
        NSString *alias = [instances stringByAppendingPathComponent:@"game-dir"];
        assert([fm createSymbolicLinkAtPath:alias withDestinationPath:installer error:NULL]);
        NSString *sourceAlias = [alias stringByAppendingPathComponent:@"libraries"];
        NSString *newPack = [instances stringByAppendingPathComponent:@"new-pack"];
        assert([fm createDirectoryAtPath:newPack withIntermediateDirectories:YES attributes:nil error:NULL]);
        NSString *packAlias = [instances stringByAppendingPathComponent:@"pack-alias"];
        assert([fm createSymbolicLinkAtPath:packAlias withDestinationPath:newPack error:NULL]);
        NSString *product = products.firstObject;
        NSString *target = [[newPack stringByAppendingPathComponent:@"libraries"] stringByAppendingPathComponent:product];
        assert([ModpackResolvedPath([[packAlias stringByAppendingPathComponent:@"libraries"] stringByAppendingPathComponent:product], NULL)
            isEqual:[ModpackResolvedPath(newPack, NULL) stringByAppendingPathComponent:[@"libraries" stringByAppendingPathComponent:product]]]);
        assert(ModpackPrepareForgeJar(sourceAlias, packAlias, product, NULL));
        assert([NSData.data writeToFile:target atomically:YES]);
        assert(ModpackPrepareForgeJar(sourceAlias, packAlias, product, NULL));
        assert([[NSData dataWithContentsOfFile:target] isEqual:header]);
        NSString *sharedPack = [instances stringByAppendingPathComponent:@"shared-pack"];
        assert([fm createDirectoryAtPath:sharedPack withIntermediateDirectories:YES attributes:nil error:NULL]);
        NSString *sharedLibraries = [sharedPack stringByAppendingPathComponent:@"libraries"];
        assert([fm createSymbolicLinkAtPath:sharedLibraries withDestinationPath:libraries error:NULL]);
        assert(ModpackPrepareForgeJar(sourceAlias, sharedPack, product, NULL));
        assert([fm removeItemAtPath:sharedLibraries error:NULL]);
        assert([fm createSymbolicLinkAtPath:sharedLibraries withDestinationPath:newPack error:NULL]);
        assert(!ModpackPrepareForgeJar(sourceAlias, sharedPack, product, NULL));
        assert(![fm fileExistsAtPath:[newPack stringByAppendingPathComponent:product]]);
        NSError *missing = nil;
        assert(!ModpackPrepareForgeJar(sourceAlias, packAlias, @"net/minecraft/missing.jar", &missing));
        assert([missing.localizedDescription containsString:@"cannot read processor output"] && missing.userInfo[NSFilePathErrorKey]);
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
