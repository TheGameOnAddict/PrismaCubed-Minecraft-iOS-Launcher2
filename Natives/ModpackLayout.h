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
    NSRange separator = [folder rangeOfString:@"_"];
    if (!folder.length || separator.location == NSNotFound) return NO;
    NSString *kind = [folder substringToIndex:separator.location];
    if (![@[@"curseforge", @"modrinth", @"mcbbs", @"mmc", @"plainzip"] containsObject:kind]) return NO;
    return [[NSUUID alloc] initWithUUIDString:[folder substringFromIndex:NSMaxRange(separator)]] != nil;
}

// Return only the importer's own ID or ID/versions/version. Legacy records
// may use either spelling of the iOS data container path.
static inline NSString *ModpackContentRelativePath(NSString *gameDir, NSString *instances) {
    if (![gameDir isKindOfClass:NSString.class] || !instances.isAbsolutePath) return nil;
    NSString *relative = nil;
    NSString *base = [instances stringByAppendingString:@"/"];
    if ([gameDir hasPrefix:base]) {
        relative = [gameDir substringFromIndex:base.length];
    } else if ([gameDir hasPrefix:@"instances/"]) {
        relative = [gameDir substringFromIndex:@"instances/".length];
    } else {
        NSString *path = [gameDir hasPrefix:@"/private/var/"] ? [gameDir substringFromIndex:8] : gameDir;
        NSString *prefix = @"/var/mobile/Containers/Data/Application/";
        if (![path hasPrefix:prefix]) return nil;
        NSArray *parts = [[path substringFromIndex:prefix.length] componentsSeparatedByString:@"/"];
        if (parts.count < 4 || ![[NSUUID alloc] initWithUUIDString:parts[0]] ||
            ![parts[1] isEqual:@"Documents"] || ![parts[2] isEqual:@"instances"]) return nil;
        relative = [[parts subarrayWithRange:NSMakeRange(3, parts.count-3)] componentsJoinedByString:@"/"];
    }
    NSArray *parts = [relative componentsSeparatedByString:@"/"];
    if (parts.count != 1 && !(parts.count == 3 && [parts[1] isEqual:@"versions"] &&
        [parts[2] length] && ![parts[2] hasPrefix:@"."])) return nil;
    return ModpackIsGeneratedFolder(parts.firstObject) ? relative : nil;
}

static inline NSString *ModpackProfileGameDir(NSDictionary *profile, NSString *instances, BOOL portable) {
    NSString *path = profile[@"gameDir"];
    if (![profile[@"type"] isEqual:@"modpack"]) return path;
    NSString *relative = ModpackContentRelativePath(path, instances);
    if (!relative) return path;
    return [(portable ? @"instances" : instances) stringByAppendingPathComponent:relative];
}

// Each managed component must be a real directory. Duplicate-card repair and
// ordinary browsing must not create a missing root or follow it out of instances.
static inline BOOL ModpackProfileContentUnavailable(NSDictionary *profile, NSString *instances) {
    if (![profile[@"type"] isEqual:@"modpack"]) return NO;
    NSString *relative = ModpackContentRelativePath(profile[@"gameDir"], instances);
    if (!relative) return NO;
    NSString *path = instances;
    struct stat entry;
    for (NSString *component in relative.pathComponents) {
        path = [path stringByAppendingPathComponent:component];
        if (lstat(path.fileSystemRepresentation, &entry) || !S_ISDIR(entry.st_mode)) return YES;
    }
    return NO;
}

// The registry in memory always has absolute paths. Serialize a separate copy
// with Documents-relative paths so iOS can relocate the app container.
static inline void ModpackTranslateProfileDirectories(NSDictionary *registry, NSString *instances, BOOL portable) {
    NSMutableDictionary *profiles = registry[@"profiles"];
    if (![profiles isKindOfClass:NSMutableDictionary.class]) return;
    for (NSString *key in profiles.allKeys) {
        NSDictionary *profile = profiles[key];
        if (![profile isKindOfClass:NSDictionary.class]) continue;
        NSString *dir = ModpackProfileGameDir(profile, instances, portable);
        if (!dir || [dir isEqual:profile[@"gameDir"]]) continue;
        NSMutableDictionary *updated = profile.mutableCopy;
        updated[@"gameDir"] = dir;
        profiles[key] = updated;
    }
}

// Reconciliation in older builds created these bare custom records for import working directories.
static inline BOOL ModpackIsDirectoryCard(NSString *key, NSDictionary *profile, NSString *instances) {
    if (!ModpackIsGeneratedFolder(key) || ![profile isKindOfClass:NSDictionary.class] || ![profile[@"type"] isEqual:@"custom"] || ![key isEqual:profile[@"name"]]) return NO;
    NSString *dir = profile[@"gameDir"];
    NSString *relative = ModpackContentRelativePath(dir, instances);
    if (![relative.pathComponents.firstObject isEqual:key]) return NO;
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

// A verified installation is reusable only for this version and these exact files.
static inline BOOL ModpackCanReuseForge(NSString *root, NSString *version, NSString *(^digest)(NSString *)) {
    if (!root.length || !version.length || ![version isEqual:version.lastPathComponent]) return NO;
    NSString *directory = [NSString stringWithFormat:@"versions/%@", version];
    NSString *manifest = [NSString stringWithFormat:@"%@/%@.json", directory, version];
    NSString *receipt = [[root stringByAppendingPathComponent:directory] stringByAppendingPathComponent:@".prismacubic-forge.plist"];
    NSDictionary *files = [NSDictionary dictionaryWithContentsOfFile:receipt];
    if (files.count < 2 || !files[manifest]) return NO;
    for (NSString *relative in files) {
        if (![relative isKindOfClass:NSString.class] || [relative.pathComponents containsObject:@".."] ||
            !([relative isEqual:manifest] || [relative hasPrefix:@"libraries/"])) return NO;
        NSString *expected = files[relative];
        if (![expected isKindOfClass:NSString.class] || expected.length != 40 ||
            ![expected isEqual:digest([root stringByAppendingPathComponent:relative])]) return NO;
    }
    return YES;
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
