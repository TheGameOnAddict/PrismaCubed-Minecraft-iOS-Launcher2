#import "ModProjectCatalog.h"
#import "installer/modpack/CurseForgeAPI.h"
#import "installer/modpack/ModrinthAPI.h"

@implementation ModProjectCatalog

+ (void)filesForID:(NSString *)projectID source:(NSInteger)source completion:(ModFilesCompletion)completion {
    if (source != 2) {
        [[ModrinthAPI sharedInstance] getVersionsForModWithID:projectID completion:completion];
        return;
    }
    // The default CurseForge page can contain only newer Minecraft releases.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CurseForgeAPI *api = [CurseForgeAPI sharedInstance];
        NSString *path = [NSString stringWithFormat:@"mods/%@/files", projectID];
        NSMutableArray *files = [NSMutableArray array];
        NSUInteger offset = 0;
        for (;;) {
            NSDictionary *response = [api getEndpoint:path params:@{@"index":@(offset), @"pageSize":@50}];
            NSArray *page = [response isKindOfClass:NSDictionary.class] ? response[@"data"] : nil;
            if (![page isKindOfClass:NSArray.class]) {
                completion(nil, [NSError errorWithDomain:@"ModProjectCatalog" code:NSURLErrorBadServerResponse userInfo:nil]);
                return;
            }
            for (NSDictionary *entry in page) {
                if (![entry isKindOfClass:NSDictionary.class] || [entry[@"isServerPack"] boolValue]) continue;
                ModVersion *file = [[ModVersion alloc] initWithDictionary:entry];
                if (file) [files addObject:file];
            }
            offset += page.count;
            NSDictionary *pagination = response[@"pagination"];
            if (!page.count || ![pagination isKindOfClass:NSDictionary.class] ||
                offset >= [pagination[@"totalCount"] unsignedIntegerValue] ||
                [pagination[@"index"] unsignedIntegerValue] != offset - page.count) break;
        }
        completion(files, nil);
    });
}

static NSString *UniqueTitleMatch(NSArray *results, NSString *title) {
    NSString *match = nil;
    for (NSDictionary *hit in results) {
        if (![hit isKindOfClass:NSDictionary.class] || ![hit[@"title"] isKindOfClass:NSString.class] ||
            [hit[@"title"] caseInsensitiveCompare:title] != NSOrderedSame) continue;
        NSString *candidate = [hit[@"id"] description];
        if (!candidate.length) continue;
        if (match && ![match isEqual:candidate]) return nil;
        match = candidate;
    }
    return match;
}

+ (void)findProject:(NSString *)title type:(NSString *)type source:(NSInteger)source completion:(void (^)(NSString *, NSError *))completion {
    NSDictionary *query = @{@"name":title ?: @"", @"projectType":type ?: @"mod", @"limit":@20};
    void (^found)(NSArray *, NSError *) = ^(NSArray *results, NSError *error) {
        completion(UniqueTitleMatch(results, title), error);
    };
    if (source != 2) {
        [[ModrinthAPI sharedInstance] searchModWithFilters:query completion:found];
        return;
    }
    // CurseForge can rank recently updated add-ons ahead of the exact project (e.g. Sodium).
    NSMutableDictionary *popular = [query mutableCopy];
    popular[@"sort"] = @"downloads";
    [[CurseForgeAPI sharedInstance] searchModWithFilters:popular completion:^(NSArray *results, NSError *error) {
        NSString *match = UniqueTitleMatch(results, title);
        if (match || error) { completion(match, error); return; }
        [[CurseForgeAPI sharedInstance] searchModWithFilters:query completion:found];
    }];
}

+ (ModVersion *)latestFile:(NSArray<ModVersion *> *)files minecraft:(NSString *)minecraft loader:(NSString *)loader {
    if (!minecraft.length || !loader.length) return nil;
    NSISO8601DateFormatter *plain = [[NSISO8601DateFormatter alloc] init];
    NSISO8601DateFormatter *fractional = [[NSISO8601DateFormatter alloc] init];
    fractional.formatOptions |= NSISO8601DateFormatWithFractionalSeconds;
    ModVersion *latest = nil;
    NSDate *latestDate = nil;
    for (ModVersion *file in files) {
        if (![file.gameVersions containsObject:minecraft] || ![file.loaders containsObject:loader.lowercaseString]) continue;
        NSString *link = file.primaryFile[@"url"];
        if (![link isKindOfClass:NSString.class] || ![NSURL URLWithString:link].host.length) continue;
        NSDate *date = [fractional dateFromString:file.datePublished ?: @""] ?: [plain dateFromString:file.datePublished ?: @""];
        if (!latest || (date && (!latestDate || [date compare:latestDate] == NSOrderedDescending))) {
            latest = file;
            latestDate = date;
        }
    }
    return latest;
}

+ (void)quickFileForID:(NSString *)projectID title:(NSString *)title source:(NSInteger)source minecraft:(NSString *)minecraft loader:(NSString *)loader completion:(void (^)(ModVersion *, NSError *))completion {
    if (!minecraft.length || !loader.length) { completion(nil, nil); return; }
    NSInteger otherSource = source == 2 ? 1 : 2;
    dispatch_group_t group = dispatch_group_create();
    __block NSArray *original, *other;
    __block NSError *originalError, *otherError;
    dispatch_group_enter(group);
    [self filesForID:projectID source:source completion:^(NSArray *files, NSError *error) {
        original = files;
        originalError = error;
        dispatch_group_leave(group);
    }];
    dispatch_group_enter(group);
    [self findProject:title type:@"mod" source:otherSource completion:^(NSString *match, NSError *error) {
        if (!match) { otherError = error; dispatch_group_leave(group); return; }
        [self filesForID:match source:otherSource completion:^(NSArray *files, NSError *failure) {
            other = files;
            otherError = failure;
            dispatch_group_leave(group);
        }];
    }];
    dispatch_group_notify(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Equal names alone cannot establish that two publishers distribute the same mod.
        NSMutableSet *hashes = [NSMutableSet set];
        for (ModVersion *file in original) {
            NSString *hash = file.primaryFile[@"hashes"][@"sha1"];
            if (hash.length) [hashes addObject:hash.lowercaseString];
        }
        NSArray *candidates = original;
        for (ModVersion *file in other) {
            NSString *hash = file.primaryFile[@"hashes"][@"sha1"];
            if (hash.length && [hashes containsObject:hash.lowercaseString]) {
                candidates = [original arrayByAddingObjectsFromArray:other];
                break;
            }
        }
        ModVersion *best = [self latestFile:candidates minecraft:minecraft loader:loader];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(best, best ? nil : (originalError ?: otherError)); });
    });
}
@end
