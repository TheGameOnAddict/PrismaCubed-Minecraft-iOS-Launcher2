#import "CubicHitchReport.h"
#import "PerformanceFrames.h"
#import <math.h>
#import <CoreFoundation/CoreFoundation.h>

static NSDictionary *dictionary(id value) {
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static NSArray *boundedArray(id value, NSUInteger limit) {
    return [value isKindOfClass:NSArray.class] && [value count] <= limit ? value : nil;
}

static NSNumber *number(id value, double minimum, double maximum) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return nil;
    double n = [value doubleValue];
    return isfinite(n) && n >= minimum && n <= maximum ? value : nil;
}

static NSSet *workLabels(void) {
    static NSSet *labels;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableSet *set = [NSMutableSet set];
        NSArray *categories = @[@"lighting", @"chunk-generation", @"chunk-meshing", @"chunk-loading",
            @"chunk-io", @"entity-rendering", @"entity-ticking", @"map-work", @"graphics-present",
            @"graphics-driver", @"graphics-draw", @"graphics-buffer-upload", @"graphics-texture-upload",
            @"graphics-shader", @"graphics-sync", @"graphics-blit", @"other", @"waiting"];
        for (NSString *role in @[@"render", @"server", @"worker", @"map-worker", @"c2me-worker", @"c2me-storage"])
            for (NSString *category in categories)
                [set addObject:[NSString stringWithFormat:@"%@/%@", role, category]];
        labels = [set copy];
    });
    return labels;
}

static void increment(NSMutableDictionary *counts, NSString *key) {
    counts[key] = @([counts[key] unsignedIntegerValue] + 1);
}

NSDictionary *CubicHitchAnalysis(NSDictionary *report, NSDictionary *javaSamples, NSDictionary *jvmPauses) {
    NSDictionary *timing = dictionary(dictionary(report)[@"frameTiming"]);
    NSArray *ranked = boundedArray(timing[@"slowestIntervals"], PerformanceSlowFrameLimit);
    if (!ranked) return nil;
    NSNumber *epoch = number(report[@"captureWindowStartEpochMs"], 1, 1e14);
    javaSamples = dictionary(javaSamples);
    jvmPauses = dictionary(jvmPauses);
    NSNumber *javaEpoch = number(javaSamples[@"captureStartEpochMs"], 1, 1e14);
    NSArray *samples = (epoch && javaEpoch && [epoch isEqualToNumber:javaEpoch])
        ? boundedArray(javaSamples[@"samples"], 1200) : nil;
    NSArray *pauses = boundedArray(jvmPauses[@"events"], 4096);
    NSMutableArray *intervals = [NSMutableArray array];
    NSMutableDictionary *workCounts = [NSMutableDictionary dictionary];
    NSUInteger sampledFrames = 0, pausedFrames = 0, inspectionFrames = 0;
    double totalSwapMs = 0, totalOutsideMs = 0;
    NSUInteger pairedFrames = 0;

    NSMutableArray *timeline = [NSMutableArray array];
    NSMutableDictionary *windowCounts = [NSMutableDictionary dictionary];
    NSUInteger labeledRounds = 0;
    double probeTotalMs = 0, probeMaxMs = 0;
    NSNumber *elapsed = number(timing[@"measuredSeconds"], 0, PerformanceSeconds);
    double windowMs = (elapsed ? elapsed.doubleValue : PerformanceSeconds) * 1000;
    for (id raw in samples) {
        NSDictionary *sample = dictionary(raw);
        NSNumber *at = number(sample[@"atMs"], epoch.doubleValue, epoch.doubleValue + windowMs);
        NSNumber *probe = number(sample[@"probeMs"], 0, PerformanceSeconds * 1000);
        NSArray *labels = boundedArray(sample[@"work"], 16);
        if (!at || !probe || !labels) continue;
        NSMutableOrderedSet *seen = [NSMutableOrderedSet orderedSet];
        for (id label in labels) {
            if ([label isKindOfClass:NSString.class] && [label length] < 64 && [workLabels() containsObject:label])
                [seen addObject:label];
        }
        for (NSString *label in seen) increment(windowCounts, label);
        if (seen.count) labeledRounds++;
        probeTotalMs += probe.doubleValue;
        probeMaxMs = MAX(probeMaxMs, probe.doubleValue);
        [timeline addObject:@{@"atMs":@(at.doubleValue - epoch.doubleValue), @"probeMs":probe, @"work":seen.array}];
    }
    for (id object in ranked) {
        NSDictionary *frame = dictionary(object);
        NSNumber *end = number(frame[@"endSeconds"], 0, PerformanceSeconds);
        NSNumber *length = number(frame[@"intervalMs"], 0.000001, PerformanceSeconds * 1000);
        if (!end || !length) continue;
        double endMs = end.doubleValue * 1000, startMs = endMs - length.doubleValue;
        if (startMs < -0.01) continue;
        NSMutableDictionary *entry = [@{@"endSeconds":end, @"intervalMs":length} mutableCopy];
        for (NSString *key in @[@"swapMs", @"outsideSwapMs", @"prePresentMs", @"eglPresentMs", @"threadCpuMs"]) {
            NSNumber *phase = number(frame[key], 0, length.doubleValue + 1.0);
            if (phase) entry[key] = phase;
        }
        if (entry[@"swapMs"] && entry[@"outsideSwapMs"]) {
            pairedFrames++;
            totalSwapMs += [entry[@"swapMs"] doubleValue];
            totalOutsideMs += [entry[@"outsideSwapMs"] doubleValue];
        }

        NSUInteger inside = 0, boundary = 0;
        NSMutableDictionary *work = [NSMutableDictionary dictionary];
        for (NSDictionary *sample in timeline) {
            double t = [sample[@"atMs"] doubleValue];
            NSNumber *probe = sample[@"probeMs"];
            // The JVM reads several threads per round. The midpoint and wall clock are rounded
            // to milliseconds. Attribute a category only when the whole observation fits.
            double uncertainty = probe.doubleValue / 2.0 + 1.0;
            if (t + uncertainty <= startMs || t - uncertainty >= endMs) continue;
            if (t - uncertainty < startMs || t + uncertainty > endMs) {
                boundary++;
                continue;
            }
            inside++;
            for (NSString *label in sample[@"work"]) increment(work, label);
        }
        if (inside) sampledFrames++;
        for (NSString *label in work) increment(workCounts, label);
        entry[@"javaRoundsInside"] = @(inside);
        entry[@"javaRoundsCrossingBoundary"] = @(boundary);
        entry[@"observedJavaWork"] = work;

        NSMutableDictionary *overlaps = [NSMutableDictionary dictionary];
        for (id raw in pauses) {
            NSDictionary *pause = dictionary(raw);
            NSString *kind = pause[@"kind"];
            if (![@[@"gc", @"safepoint"] containsObject:kind ?: @""]) continue;
            NSNumber *from = number(pause[@"startMs"], -86400000, PerformanceSeconds * 1000);
            NSNumber *until = number(pause[@"endMs"], 0, 86400000);
            if (!from || !until) continue;
            double overlap = MIN(until.doubleValue, endMs) - MAX(from.doubleValue, startMs);
            if (overlap <= 0) continue;
            // A GC pause can also appear as a safepoint. Keep each kind separate.
            if ([kind isEqual:@"safepoint"] && [pause[@"threadInspection"] isEqual:@YES]) kind = @"thread inspection";
            overlaps[kind] = @(MAX([overlaps[kind] doubleValue], overlap));
        }
        if (overlaps[@"gc"] || overlaps[@"safepoint"]) pausedFrames++;
        if (overlaps[@"thread inspection"]) inspectionFrames++;
        entry[@"largestJVMPauseOverlapMsByKind"] = overlaps;
        [intervals addObject:entry];
    }

    BOOL coversStart = [jvmPauses[@"coversWindowStart"] isEqual:@YES];
    BOOL truncated = [jvmPauses[@"eventsTruncated"] isEqual:@YES];
    NSString *pauseStatus = !pauses ? @"unavailable" : truncated ? @"truncated" : coversStart ? @"recorded" : @"partial";
    NSMutableDictionary *result = [@{@"intervals":intervals, @"intervalsWithJavaSamples":@(sampledFrames),
        @"intervalsWithJVMPauseOverlap":@(pausedFrames), @"intervalsWithThreadInspection":@(inspectionFrames), @"intervalCountByJavaWork":workCounts,
        @"javaRounds":timeline, @"windowRoundCountByJavaWork":windowCounts, @"javaLabeledRounds":@(labeledRounds),
        @"javaProbeTotalMsCeil":@(probeTotalMs), @"javaProbeMaxMsCeil":@(probeMaxMs),
        @"javaSampleRoundsInFile":@(timeline.count), @"jvmPauseLogStatus":pauseStatus,
        @"pairedIntervals":@(pairedFrames), @"swapMsAcrossPairedIntervals":@(totalSwapMs),
        @"outsideSwapMsAcrossPairedIntervals":@(totalOutsideMs)} mutableCopy];
    NSString *status = javaSamples[@"status"];
    result[@"javaSampleStatus"] = samples && [@[@"completed", @"recording", @"interrupted", @"unavailable"] containsObject:status ?: @""]
        ? status : @"unavailable";
    for (NSString *key in @[@"averageFPS",@"p99IntervalMsCeil"]) {
        NSNumber *value = number(timing[key], 0, 100000);
        if (value) result[key] = value;
    }
    return result;
}

static NSString *statusString(id value, NSArray *allowed) {
    return [allowed containsObject:value ?: @""] ? value : @"unavailable";
}

static NSArray<NSString *> *observedWork(id rawCounts, NSUInteger limit) {
    NSDictionary *counts = dictionary(rawCounts);
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    for (NSString *label in workLabels()) {
        if (number(counts[label], 1, limit)) [labels addObject:label];
    }
    [labels sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSComparisonResult result = [counts[b] compare:counts[a]];
        return result == NSOrderedSame ? [a compare:b] : result;
    }];
    NSMutableArray *formatted = [NSMutableArray array];
    for (NSString *label in labels) [formatted addObject:[NSString stringWithFormat:@"%@ (%@)", label, counts[label]]];
    return formatted;
}

NSString *CubicHitchSummary(NSDictionary *analysis) {
    analysis = dictionary(analysis);
    NSArray *rows = boundedArray(analysis[@"intervals"], PerformanceSlowFrameLimit);
    if (!rows) return @"Frame interval data is unavailable.\n";
    NSMutableString *text = [NSMutableString stringWithString:@"Frame timing\n"];
    NSNumber *average = number(analysis[@"averageFPS"], 0, 100000);
    NSNumber *p99 = number(analysis[@"p99IntervalMsCeil"], 0, PerformanceSeconds * 1000);
    if (average) [text appendFormat:@"Average FPS %.1f\n", average.doubleValue];
    if (p99) [text appendFormat:@"99th-percentile frame interval at most %.0f ms\n", p99.doubleValue];

    [text appendFormat:@"\n%lu longest frame intervals\n", (unsigned long)rows.count];
    NSNumber *paired = number(analysis[@"pairedIntervals"], 1, rows.count);
    NSNumber *swapTotal = number(analysis[@"swapMsAcrossPairedIntervals"], 0, PerformanceSeconds * 1000);
    NSNumber *outsideTotal = number(analysis[@"outsideSwapMsAcrossPairedIntervals"], 0, PerformanceSeconds * 1000);
    if (paired && swapTotal && outsideTotal) {
        [text appendFormat:@"Across %@ timed intervals, %.1f ms fell inside the launcher swap call and %.1f ms between calls.\n",
            paired, swapTotal.doubleValue, outsideTotal.doubleValue];
    }
    NSString *javaStatus = statusString(analysis[@"javaSampleStatus"], @[@"completed", @"recording", @"interrupted"]);
    NSNumber *rounds = number(analysis[@"javaSampleRoundsInFile"], 0, 1200) ?: @0;
    NSNumber *matched = number(analysis[@"intervalsWithJavaSamples"], 0, rows.count) ?: @0;
    [text appendFormat:@"Java sampling %@. %@ rounds in the capture window. %@ of these %lu intervals contained a complete sampling round.\n",
        javaStatus, rounds, matched, (unsigned long)rows.count];
    NSArray *work = observedWork(analysis[@"windowRoundCountByJavaWork"], rounds.unsignedIntegerValue);
    if (work.count)
        [text appendFormat:@"Java observations across the full capture, counted once per label per round\n%@\n", [work componentsJoinedByString:@", "]];
    NSString *pauseStatus = statusString(analysis[@"jvmPauseLogStatus"], @[@"recorded", @"partial", @"truncated"]);
    NSNumber *pauseFrames = number(analysis[@"intervalsWithJVMPauseOverlap"], 0, rows.count) ?: @0;
    [text appendFormat:@"JVM pause log %@. %@ ranked intervals overlapped a recorded GC pause or other non-inspection safepoint.\n", pauseStatus, pauseFrames];

    NSNumber *inspections = number(analysis[@"intervalsWithThreadInspection"], 1, rows.count);
    if (inspections) [text appendFormat:@"Thread-inspection safepoints overlapped %@ intervals and may include sampler overhead.\n", inspections];

    for (id raw in rows) {
        NSDictionary *row = dictionary(raw);
        NSNumber *end = number(row[@"endSeconds"], 0, PerformanceSeconds);
        NSNumber *len = number(row[@"intervalMs"], 0, PerformanceSeconds * 1000);
        if (!end || !len) continue;
        [text appendFormat:@"\n%7.3f s   %5.1f ms", end.doubleValue, len.doubleValue];
        NSNumber *swap = number(row[@"swapMs"], 0, len.doubleValue + 1);
        NSNumber *outside = number(row[@"outsideSwapMs"], 0, len.doubleValue + 1);
        NSNumber *egl = number(row[@"eglPresentMs"], 0, len.doubleValue + 1);
        NSNumber *cpu = number(row[@"threadCpuMs"], 0, len.doubleValue + 1);
        if (swap && outside) [text appendFormat:@"   swap %.1f ms   between swaps %.1f ms", swap.doubleValue, outside.doubleValue];
        if (egl) [text appendFormat:@"   EGL swap %.1f ms", egl.doubleValue];
        if (cpu) [text appendFormat:@"   render-thread CPU %.1f ms", cpu.doubleValue];
        [text appendString:@"\n"];
        NSArray *labels = observedWork(row[@"observedJavaWork"], 1200);
        if (labels.count) {
            [text appendFormat:@"  Java observations by number of rounds\n    %@\n", [labels componentsJoinedByString:@", "]];
        } else if (!number(row[@"javaRoundsInside"], 1, 1200)) {
            [text appendString:@"  No complete Java sample in this interval.\n"];
        }
        NSDictionary *overlaps = dictionary(row[@"largestJVMPauseOverlapMsByKind"]);
        for (NSString *kind in @[@"gc", @"safepoint", @"thread inspection"]) {
            NSNumber *ms = number(overlaps[kind], 0, len.doubleValue + 1);
            if (ms) [text appendFormat:@"  %@ overlap %.1f ms\n", kind, ms.doubleValue];
        }
    }
    [text appendString:@"\nJava labels describe sampled work grouped by thread role. Background work can run alongside a slow frame. "
        @"Short jobs can fall between samples, and samples that cross a frame boundary are omitted from its labels. "
        @"EGL swap includes submission and waiting. GPU execution time is unavailable here. "
        @"Render-thread CPU overlaps the wall-clock phases. GC and safepoint events can cover the same pause.\n"];
    return text;
}
