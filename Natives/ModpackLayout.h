#import <Foundation/Foundation.h>

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

// A plain install verifies in place. A pack gets its own copy in its staged launch root.
static inline BOOL ModpackPrepareForgeJar(NSString *libraries, NSString *instance, NSString *relative, NSError **error) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *source = [libraries stringByAppendingPathComponent:relative];
    NSString *packLibraries = [instance stringByAppendingPathComponent:@"libraries"];
    NSString *target = [packLibraries stringByAppendingPathComponent:relative];
    BOOL sameFile = [source.stringByResolvingSymlinksInPath isEqual:target.stringByResolvingSymlinksInPath];
    BOOL safe = !relative.isAbsolutePath && ![relative.pathComponents containsObject:@".."] &&
        [source.stringByResolvingSymlinksInPath hasPrefix:[libraries.stringByResolvingSymlinksInPath stringByAppendingString:@"/"]] &&
        (sameFile || [target.stringByResolvingSymlinksInPath hasPrefix:[instance.stringByResolvingSymlinksInPath stringByAppendingString:@"/"]]);
    BOOL directory = NO;
    BOOL regular = safe && [fm fileExistsAtPath:source isDirectory:&directory] && !directory;
    NSFileHandle *file = regular ? [NSFileHandle fileHandleForReadingAtPath:source] : nil;
    NSData *magic = [file readDataOfLength:4];
    [file closeFile];
    if (![magic isEqual:[NSData dataWithBytes:"PK\003\004" length:4]]) {
        if (error) *error = [NSError errorWithDomain:@"ModpackImportError" code:4010 userInfo:@{
            NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Forge could not verify the generated client library %@.", relative.lastPathComponent]}];
        return NO;
    }
    if (sameFile) return YES;
    if ([fm fileExistsAtPath:target] && [fm contentsEqualAtPath:source andPath:target]) return YES;
    if (![fm createDirectoryAtPath:target.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    return [fm copyItemAtPath:source toPath:target error:error];
}
