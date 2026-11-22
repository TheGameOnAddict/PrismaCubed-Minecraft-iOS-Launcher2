#import <Foundation/Foundation.h>
#include <errno.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

// An imported profile may point at the instance itself or its isolated version directory.
static inline NSString *ModpackInstanceID(NSString *gameDir, NSString *instancesDir) {
    if (![gameDir isKindOfClass:NSString.class] || !gameDir.isAbsolutePath || !instancesDir.length) return nil;
    NSString *base = [instancesDir.stringByResolvingSymlinksInPath stringByAppendingString:@"/"];
    NSString *path = gameDir.stringByResolvingSymlinksInPath;
    if (![path hasPrefix:base]) return nil;
    NSArray<NSString *> *parts = [[path substringFromIndex:base.length] pathComponents];
    if (parts.count != 1 && !(parts.count == 3 && [parts[1] isEqual:@"versions"])) return nil;
    NSString *folder = parts.firstObject;
    NSRange separator = [folder rangeOfString:@"_"];
    if (separator.location == NSNotFound) return nil;
    NSString *uuid = [folder substringFromIndex:NSMaxRange(separator)];
    return [[NSUUID alloc] initWithUUIDString:uuid] ? folder : nil;
}

static inline BOOL ModpackIsGeneratedFolder(NSString *folder) {
    if (![folder hasPrefix:@"curseforge_"] && ![folder hasPrefix:@"modrinth_"]) return NO;
    NSString *uuid = [folder substringFromIndex:NSMaxRange([folder rangeOfString:@"_"])];
    return [[NSUUID alloc] initWithUUIDString:uuid] != nil;
}

// Reconciliation in older builds created these bare custom records for import working directories.
static inline BOOL ModpackIsDirectoryCard(NSString *key, NSDictionary *profile, NSString *instances) {
    if (!ModpackIsGeneratedFolder(key) || ![profile isKindOfClass:NSDictionary.class] || ![profile[@"type"] isEqual:@"custom"] || ![key isEqual:profile[@"name"]]) return NO;
    NSString *dir = profile[@"gameDir"];
    if (![dir isKindOfClass:NSString.class] ||
        ![ModpackInstanceID(dir, instances) isEqual:key]) return NO;
    NSSet *fields = [NSSet setWithArray:@[@"name", @"gameDir", @"type", @"created", @"lastVersionId", @"lastPlayed"]];
    return [[NSSet setWithArray:profile.allKeys] isSubsetOfSet:fields];
}

// CurseForge exports inactive mod JARs with required=false. Keep them available to the profile toggle.
static inline NSString *ModpackInstalledFileName(NSString *name, NSString *category, id required) {
    if ([category isEqual:@"mods"] && [name.pathExtension.lowercaseString isEqual:@"jar"] &&
        [required isKindOfClass:NSNumber.class] && ![required boolValue]) {
        return [name stringByAppendingPathExtension:@"disabled"];
    }
    return name;
}

// Resolve the existing ancestor before appending a missing suffix. Foundation can
// return the original spelling for a missing leaf under an iOS container alias.
static inline NSString *ModpackResolvedPath(NSString *path, NSError **error) {
    if (!path.isAbsolutePath) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{NSFilePathErrorKey:path ?: @""}];
        return nil;
    }
    struct stat entry;
    if (lstat(path.fileSystemRepresentation, &entry) == -1 && errno == ENOENT) {
        NSString *parent = ModpackResolvedPath(path.stringByDeletingLastPathComponent, error);
        return [parent stringByAppendingPathComponent:path.lastPathComponent];
    }
    char *resolved = realpath(path.fileSystemRepresentation, NULL);
    if (!resolved) {
        int code = errno;
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:@{NSFilePathErrorKey:path}];
        return nil;
    }
    NSString *result = [NSFileManager.defaultManager stringWithFileSystemRepresentation:resolved length:strlen(resolved)];
    free(resolved);
    return result;
}

// The installer writes libraries and assets beside its versions directory. A pack also
// has a private copy of the version JSON for its content folder.
static inline NSString *ModpackInstalledRuntime(NSString *home, NSString *owner, NSString *preferred, NSString *version) {
    if (!version.length || ![version isEqual:version.lastPathComponent] || !home.length) return nil;
    NSMutableArray *candidates = [NSMutableArray array];
    if ([owner isKindOfClass:NSString.class] && owner.length && !owner.isAbsolutePath &&
        ![owner.pathComponents containsObject:@".."]) [candidates addObject:[home stringByAppendingPathComponent:owner]];
    [candidates addObject:[home stringByAppendingPathComponent:@"Library/Application Support/minecraft"]];
    if (preferred.length && [preferred isEqual:preferred.lastPathComponent]) {
        [candidates addObject:[[home stringByAppendingPathComponent:@"instances"] stringByAppendingPathComponent:preferred]];
    }
    [candidates addObject:[home stringByAppendingPathComponent:@"shared_core"]];
    NSString *json = [NSString stringWithFormat:@"versions/%@/%@.json", version, version];
    for (NSString *path in candidates) {
        BOOL directory = NO;
        if ([NSFileManager.defaultManager fileExistsAtPath:[path stringByAppendingPathComponent:json] isDirectory:&directory] && !directory)
            return ModpackResolvedPath(path, NULL);
    }
    return nil;
}

static inline BOOL ModpackForgeError(NSError **error, NSString *path, NSString *reason) {
    if (error) *error = [NSError errorWithDomain:@"ModpackImportError" code:4010 userInfo:@{
        NSFilePathErrorKey:path, NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Forge library %@ — %@ (%@)", path.lastPathComponent, reason, path]}];
    return NO;
}

// A plain install verifies in place. A pack gets its own copy in its staged launch root.
static inline BOOL ModpackPrepareForgeJar(NSString *libraries, NSString *instance, NSString *relative, NSError **error) {
    if (!relative.length || relative.isAbsolutePath || [relative.pathComponents containsObject:@".."])
        return ModpackForgeError(error, relative ?: @"", @"invalid library path");

    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *sourceRoot = ModpackResolvedPath(libraries, error);
    NSString *packRoot = ModpackResolvedPath(instance, error);
    if (!sourceRoot || !packRoot) return NO;
    NSString *source = ModpackResolvedPath([sourceRoot stringByAppendingPathComponent:relative], error);
    NSString *target = ModpackResolvedPath([[packRoot stringByAppendingPathComponent:@"libraries"] stringByAppendingPathComponent:relative], error);
    if (!source || !target) return NO;
    if (![source hasPrefix:[sourceRoot stringByAppendingString:@"/"]])
        return ModpackForgeError(error, source, @"source resolves outside the installer library folder");
    BOOL sameFile = [source isEqualToString:target];
    if (!sameFile && ![target hasPrefix:[packRoot stringByAppendingString:@"/"]])
        return ModpackForgeError(error, target, @"destination resolves outside the selected profile");

    struct stat info;
    if (stat(source.fileSystemRepresentation, &info) == -1)
        return ModpackForgeError(error, source, [NSString stringWithFormat:@"cannot read processor output (%s)", strerror(errno)]);
    if (!S_ISREG(info.st_mode)) return ModpackForgeError(error, source, @"processor output is not a regular file");
    NSFileHandle *file = [NSFileHandle fileHandleForReadingFromURL:[NSURL fileURLWithPath:source] error:error];
    if (!file) return NO;
    NSData *magic = [file readDataOfLength:4];
    [file closeFile];
    if (![magic isEqual:[NSData dataWithBytes:"PK\003\004" length:4]])
        return ModpackForgeError(error, source, [NSString stringWithFormat:@"invalid JAR header %@ in %lld bytes", magic, (long long)info.st_size]);
    if (sameFile || ([fm fileExistsAtPath:target] && [fm contentsEqualAtPath:source andPath:target])) return YES;
    NSString *parent = target.stringByDeletingLastPathComponent;
    if (![fm createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    // Publish a complete copy in one rename, including when repairing a stale staged copy.
    NSString *temporary = [parent stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    if (![fm copyItemAtPath:source toPath:temporary error:error]) return NO;
    if (rename(temporary.fileSystemRepresentation, target.fileSystemRepresentation) == 0) return YES;
    int code = errno;
    [fm removeItemAtPath:temporary error:nil];
    return ModpackForgeError(error, target, [NSString stringWithFormat:@"could not publish the library (%s)", strerror(code)]);
}
