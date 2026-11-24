#import <Foundation/Foundation.h>
#import "PLProfiles.h"
#include <assert.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

// The profile class links against launcher services. Supply only its Foundation
// JSON file operations, localization and preference defaults for this executable.
id getPrefObject(NSString *key) { return nil; }
NSString *localize(NSString *key, NSString *comment) { return key; }
void customNSLog(const char *file, int line, const char *function, NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSLogv(format, args);
    va_end(args);
}
NSMutableDictionary *parseJSONFromFile(NSString *path) {
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&error];
    NSMutableDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error] : nil;
    return json ?: [@{@"NSErrorObject":error} mutableCopy];
}
NSError *saveJSONToFile(NSDictionary *dict, NSString *path) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:&error];
    if (data) [data writeToFile:path options:NSDataWritingAtomic error:&error];
    return error;
}

static void WriteMarker(NSString *path) {
    assert([NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
                                  withIntermediateDirectories:YES attributes:nil error:NULL]);
    assert([@"keep" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
}

static BOOL HasMarker(NSString *path) {
    return [[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL] isEqual:@"keep"];
}

int main(void) {
    @autoreleasepool {
        NSFileManager *files = NSFileManager.defaultManager;
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSString *game = [root stringByAppendingPathComponent:@"instances/default"];
        assert(setenv("POJAV_HOME", root.fileSystemRepresentation, 1) == 0);
        assert(setenv("POJAV_GAME_DIR", game.fileSystemRepresentation, 1) == 0);
        NSString *version = @"1.20.1-forge-47.4.28";
        NSString *runtime = [game stringByAppendingPathComponent:[NSString stringWithFormat:@"versions/%@/%@.json",version,version]];
        NSString *library = [game stringByAppendingPathComponent:@"libraries/forge.jar"];
        WriteMarker(runtime);
        WriteMarker(library);

        PLProfiles *store = PLProfiles.current;
        NSString *registry = store.profilePath;
        NSString *privateRoot = [game stringByAppendingPathComponent:@"profiles"];
        NSDictionary *(^entry)(NSString *) = ^NSDictionary *(NSString *name) {
            return @{@"name":name, @"type":@"custom", @"lastVersionId":version};
        };
        NSUInteger originalCount = store.profiles.count;
        NSError *error = nil;
        assert([store createProfile:entry(@"Alpha") withName:@"Alpha" error:&error] && !error);
        assert([store createProfile:entry(@"Beta") withName:@"Beta" error:&error] && !error);
        [PLProfiles updateCurrent];
        store = PLProfiles.current;
        assert(store.profiles.count == originalCount + 2 && [store.selectedProfileName isEqual:@"Beta"]);
        NSString *alpha = store.profiles[@"Alpha"][@"gameDir"];
        NSString *beta = store.profiles[@"Beta"][@"gameDir"];
        for (NSString *name in @[@"Alpha", @"Beta"]) {
            NSDictionary *saved = store.profiles[name];
            NSString *relative = saved[@"gameDir"];
            assert([saved[@"lastVersionId"] isEqual:version] && [relative.stringByDeletingLastPathComponent isEqual:@"profiles"]);
            assert([[NSUUID alloc] initWithUUIDString:relative.lastPathComponent]);
            BOOL directory = NO;
            assert([files fileExistsAtPath:[game stringByAppendingPathComponent:relative] isDirectory:&directory] && directory);
        }
        assert(![alpha isEqual:beta]);
        NSString *alphaSave = [[game stringByAppendingPathComponent:alpha] stringByAppendingPathComponent:@"saves/World/level.dat"];
        NSString *betaSave = [[game stringByAppendingPathComponent:beta] stringByAppendingPathComponent:@"saves/World/level.dat"];
        WriteMarker(alphaSave);
        WriteMarker(betaSave);

        NSData *previousRegistry = [NSData dataWithContentsOfFile:registry];
        NSSet *(^directories)(void) = ^NSSet *{
            return [NSSet setWithArray:[files contentsOfDirectoryAtPath:privateRoot error:NULL]];
        };
        NSSet *previousDirs = directories();
        assert(![store createProfile:entry(@"Alpha") withName:@"Alpha" error:&error] && error.code == NSFileWriteFileExistsError);
        assert([previousRegistry isEqual:[NSData dataWithContentsOfFile:registry]] && [previousDirs isEqual:directories()]);

        // A directory at the registry filename makes the real atomic file write fail
        // even when CI runs as a privileged user.
        NSString *backup = [registry stringByAppendingPathExtension:@"backup"];
        assert([files moveItemAtPath:registry toPath:backup error:NULL]);
        WriteMarker([registry stringByAppendingPathComponent:@"block-write"]);
        error = nil;
        assert(![store createProfile:entry(@"Failure") withName:@"Failure" error:&error] && error);
        assert(!store.profiles[@"Failure"] && [store.selectedProfileName isEqual:@"Beta"] && [previousDirs isEqual:directories()]);
        assert([files removeItemAtPath:registry error:NULL] && [files moveItemAtPath:backup toPath:registry error:NULL]);
        assert([previousRegistry isEqual:[NSData dataWithContentsOfFile:registry]]);

        error = nil;
        // Existing profiles may share or nest game directories. A private-looking
        // directory still belongs to them while another profile references it.
        store.profiles[@"Alias"] = [@{@"gameDir":[alpha stringByAppendingPathComponent:@"saves"]} mutableCopy];
        assert([store removePrivateGameDirectoryForProfileNamed:@"Alpha" error:&error] && !error && HasMarker(alphaSave));
        [store.profiles removeObjectForKey:@"Alias"];
        store.profiles[@"Legacy"] = [@{@"gameDir":[@"versions" stringByAppendingPathComponent:version]} mutableCopy];
        assert(![store removePrivateGameDirectoryForProfileNamed:@"Legacy" error:&error] && !error && HasMarker(runtime));
        assert([store removePrivateGameDirectoryForProfileNamed:@"Alpha" error:&error] && !error);
        assert(![files fileExistsAtPath:[game stringByAppendingPathComponent:alpha]]);
        assert(HasMarker(betaSave) && HasMarker(runtime) && HasMarker(library));
        assert([files removeItemAtPath:root error:NULL]);
        puts("Profile registry passed: persisted creation, shared runtime, duplicate, write rollback, and isolated deletion");
    }
    return 0;
}
