// Run on macOS with clang -fobjc-arc -framework Foundation -framework CoreFoundation -I Natives
// scripts/test_hitch_report.m Natives/CubicHitchReport.m -o /tmp/test_hitch_report
#import "CubicHitchReport.h"
#import <assert.h>

int main(void) {
    @autoreleasepool {
        NSArray *intervals = @[
            @{@"endSeconds":@1, @"intervalMs":@60, @"swapMs":@42,
              @"outsideSwapMs":@18, @"threadCpuMs":@9, @"eglPresentMs":@39},
            @{@"endSeconds":@2, @"intervalMs":@20}
        ];
        NSDictionary *report = @{@"captureWindowStartEpochMs":@100000,
            @"frameTiming":@{@"slowestIntervals":intervals, @"measuredSeconds":@2, @"averageFPS":@119.45}};
        NSDictionary *java = @{@"captureStartEpochMs":@100000, @"status":@"completed", @"samples":@[
            @{@"atMs":@100971, @"probeMs":@2, @"work":@[@"worker/chunk-generation", @"worker/chunk-generation",
                                                      @"render/entity-rendering", @"private-canary"]},
            @{@"atMs":@100940, @"probeMs":@5, @"work":@[@"worker/lighting"]},
            @{@"atMs":@101104, @"probeMs":@1, @"work":@[@"map-worker/map-work"]},
            @{@"atMs":@102003, @"probeMs":@1, @"work":@[@"worker/chunk-io"]}
        ]};
        NSDictionary *pauses = @{@"coversWindowStart":@YES, @"eventsTruncated":@NO, @"events":@[
            @{@"kind":@"gc", @"startMs":@933, @"endMs":@950},
            @{@"kind":@"safepoint", @"startMs":@936, @"endMs":@951},
            @{@"kind":@"safepoint", @"threadInspection":@YES, @"startMs":@1985, @"endMs":@1987}
        ]};
        NSDictionary *a = CubicHitchAnalysis(report, java, pauses);
        assert([a[@"jvmPauseLogStatus"] isEqual:@"recorded"]);
        assert([a[@"intervalsWithJVMPauseOverlap"] isEqual:@1]);
        assert([a[@"intervalsWithThreadInspection"] isEqual:@1]);
        assert([a[@"windowRoundCountByJavaWork"][@"worker/chunk-generation"] isEqual:@1]);
        assert([a[@"windowRoundCountByJavaWork"][@"worker/lighting"] isEqual:@1]);
        assert([a[@"windowRoundCountByJavaWork"][@"map-worker/map-work"] isEqual:@1]);
        assert(!a[@"windowRoundCountByJavaWork"][@"worker/chunk-io"]);
        assert([a[@"javaSampleRoundsInFile"] isEqual:@3]);
        assert([a[@"javaProbeMaxMsCeil"] isEqual:@5]);
        assert([a[@"intervals"][0][@"largestJVMPauseOverlapMsByKind"][@"gc"] isEqual:@10]);
        assert([a[@"intervals"][0][@"largestJVMPauseOverlapMsByKind"][@"safepoint"] isEqual:@11]);
        assert([a[@"intervals"][0][@"javaRoundsInside"] isEqual:@1]);
        assert([a[@"intervals"][0][@"javaRoundsCrossingBoundary"] isEqual:@1]);
        assert(!a[@"intervals"][0][@"observedJavaWork"][@"worker/lighting"]);
        assert([a[@"intervals"][0][@"observedJavaWork"][@"render/entity-rendering"] isEqual:@1]);
        assert([a[@"intervals"][1][@"javaRoundsInside"] isEqual:@0]);
        NSString *summary = CubicHitchSummary(a);
        assert([summary containsString:@"worker/chunk-generation"]);
        assert([summary containsString:@"Thread-inspection safepoints"]);
        assert(![a.description containsString:@"private-canary"]);
        assert(![summary containsString:@"private-canary"]);

        NSDictionary *detailed = @{
            @"captureStartEpochMs":@100000, @"status":@"completed", @"samples":@[
                @{@"atMs":@100950, @"probeMs":@1, @"work":@[@"render/graphics-draw", @"c2me-worker/chunk-generation"]},
                @{@"atMs":@100970, @"probeMs":@1, @"work":@[@"render/graphics-draw", @"c2me-storage/chunk-io"]},
                @{@"atMs":@101300, @"probeMs":@1, @"work":@[@"render/graphics-buffer-upload"]},
                @{@"atMs":@101350, @"probeMs":@1, @"work":@[@"render/graphics-texture-upload"]},
                @{@"atMs":@101400, @"probeMs":@1, @"work":@[@"render/graphics-shader"]},
                @{@"atMs":@101450, @"probeMs":@1, @"work":@[@"render/graphics-sync"]},
                @{@"atMs":@101500, @"probeMs":@1, @"work":@[@"render/graphics-blit", @"c2me-storage/private-canary"]}
            ]};
        a = CubicHitchAnalysis(report, detailed, nil);
        NSDictionary *duringFrame = a[@"intervals"][0][@"observedJavaWork"];
        assert([duringFrame[@"render/graphics-draw"] isEqual:@2]);
        assert([duringFrame[@"c2me-worker/chunk-generation"] isEqual:@1]);
        assert([duringFrame[@"c2me-storage/chunk-io"] isEqual:@1]);
        assert([a[@"windowRoundCountByJavaWork"] count] == 8);
        summary = CubicHitchSummary(a);
        assert([summary containsString:@"Java observations by number of rounds\n    render/graphics-draw (2)"]);
        assert(![summary containsString:@"private-canary"]);

        NSMutableDictionary *other = [java mutableCopy];
        other[@"captureStartEpochMs"] = @99999;
        a = CubicHitchAnalysis(report, other, nil);
        assert([a[@"javaSampleStatus"] isEqual:@"unavailable"]);
        assert([a[@"intervalsWithJavaSamples"] isEqual:@0]);
        assert([a[@"jvmPauseLogStatus"] isEqual:@"unavailable"]);
        assert(!CubicHitchAnalysis(@{@"frameTiming":NSNull.null},nil,nil));

        NSDictionary *edited = @{@"intervals":@[NSNull.null, @{@"intervalMs":@20, @"endSeconds":@2,
            @"observedJavaWork":NSNull.null, @"largestJVMPauseOverlapMsByKind":@[]}],
            @"windowRoundCountByJavaWork":@{@"render/other":NSNull.null, @"arbitrary":@42},
            @"javaSampleRoundsInFile":NSNull.null, @"p99IntervalMsCeil":@[], @"jvmPauseLogStatus":@{},
            @"intervalsWithJVMPauseOverlap":@"private-canary"};
        assert(![CubicHitchSummary(edited) containsString:@"private-canary"]);
        assert(![CubicHitchSummary(edited) containsString:@"arbitrary"]);
    }
    return 0;
}
