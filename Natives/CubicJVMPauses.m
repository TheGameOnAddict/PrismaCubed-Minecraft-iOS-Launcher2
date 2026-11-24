#import "CubicJVMPauses.h"
#import "HotSpotPause.h"
#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>

static NSURL *pauseFile(NSURL *report) {
    NSString *key = report.lastPathComponent.stringByDeletingPathExtension;
    if (!key || [key rangeOfString:@"^Prisma-[0-9]{13}-[0-9A-Fa-f]{8}$" options:NSRegularExpressionSearch].location == NSNotFound)
        return nil;
    NSURL *cache = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *folder = [cache URLByAppendingPathComponent:@"Prisma JVM timing" isDirectory:YES];
    return [folder URLByAppendingPathComponent:[key stringByAppendingPathExtension:@"log"]];
}

NSString *CubicPrepareJVMPauseArgument(NSURL *report) {
    NSURL *url = pauseFile(report);
    if (!url || [url.path rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@":%\""]].location != NSNotFound) return nil;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *folder = url.URLByDeletingLastPathComponent;
    if (![fm createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil]) return nil;
    int fd = open(url.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (fd < 0) return nil;
    close(fd);

    // A completed report persists its parsed events. Preserve the current test
    // across relaunches, then bound disk use when a different test is launched.
    for (NSURL *old in [fm contentsOfDirectoryAtURL:folder includingPropertiesForKeys:nil options:0 error:nil]) {
        NSString *name = old.lastPathComponent;
        if (![name isEqualToString:url.lastPathComponent] &&
            [name rangeOfString:@"^Prisma-[0-9]{13}-[0-9A-Fa-f]{8}\\.log(\\.0)?$"
                        options:NSRegularExpressionSearch].location != NSNotFound)
            [fm removeItemAtURL:old error:nil];
    }
    return [NSString stringWithFormat:@"-Xlog:gc,safepoint:file=%@:timemillis,tags:filecount=1,filesize=256k", url.path];
}

NSDictionary *CubicReadJVMPauses(NSURL *report, double start, double seconds) {
    NSURL *url = pauseFile(report);
    if (!url || !isfinite(start) || !isfinite(seconds) || start <= 0 || seconds <= 0) return nil;
    // Hold an open descriptor for each generation during the read. Rotation
    // renames the active file to .0; inode equality below suppresses duplicates.
    int current = open(url.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
    int previous = open([url.path stringByAppendingString:@".0"].fileSystemRepresentation,
                        O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
    int generations[] = { previous, current };
    ino_t prior = 0;
    double earliest = INFINITY;
    NSUInteger gc = 0, safepoints = 0, inspections = 0;
    NSMutableArray *events = [NSMutableArray array];
    for (unsigned i = 0; i < 2; ++i) {
        int fd = generations[i];
        if (fd < 0) continue;
        struct stat st;
        if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_ino == prior || st.st_size > 512*1024) {
            close(fd); continue;
        }
        prior = st.st_ino;
        FILE *stream = fdopen(fd, "r");
        if (!stream) { close(fd); continue; }
        // Only read the snapshotted length. Never chase a running VM's log.
        off_t remaining = st.st_size;
        char line[1024];
        while (remaining > 0 && fgets(line, (int)MIN((off_t)sizeof(line), remaining+1), stream)) {
            size_t n = strlen(line);
            if (!n) break;
            remaining -= n;
            if (line[n-1] != '\n') continue;
            line[n-1] = '\0';
            HotSpotPause event;
            if (!parseHotSpotLine(line, &event)) continue;
            earliest = fmin(earliest, event.endEpochMs);
            if (event.kind == HotSpotOther) continue;
            double end = event.endEpochMs - start;
            double begin = end - event.durationMs;
            if (end < 0 || begin > seconds*1000) continue;
            BOOL isGC = event.kind == HotSpotGC;
            if (isGC) ++gc; else ++safepoints;
            NSMutableDictionary *item = [@{@"kind":isGC ? @"gc" : @"safepoint", @"startMs":@(begin),
                @"endMs":@(end), @"durationMs":@(event.durationMs)} mutableCopy];
            if (!isGC) item[@"threadInspection"] = @(event.threadInspection);
            if (event.threadInspection) ++inspections;
            if (event.atSafepointMs >= 0) item[@"atSafepointMs"] = @(event.atSafepointMs);
            [events addObject:item];
        }
        fclose(stream);
    }
    if (!isfinite(earliest)) return nil;
    // A minute at 20 thread snapshots/s can itself generate ~1200 inspection
    // events. Keep those alongside real pauses on an ordinary full capture.
    const NSUInteger limit = 2048;
    BOOL truncated = events.count > limit;
    if (truncated) {
        [events sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"durationMs" ascending:NO]]];
        [events removeObjectsInRange:NSMakeRange(limit, events.count-limit)];
    }
    [events sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"startMs" ascending:YES]]];
    return @{@"coversWindowStart":@(earliest <= start), @"eventsTruncated":@(truncated),
        @"gcPauseCount":@(gc), @"safepointCount":@(safepoints), @"threadInspectionCount":@(inspections), @"events":events};
}
