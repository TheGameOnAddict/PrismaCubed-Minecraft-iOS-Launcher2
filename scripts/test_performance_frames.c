// Compile with cc -std=c11 -pthread scripts/test_performance_frames.c
#include <assert.h>
#include <stdint.h>
static uint64_t clockNs;
static unsigned clockReads;
static uint64_t testClock(void) { ++clockReads; return clockNs; }
#define PERFORMANCE_CLOCK testClock
#include "../Natives/PerformanceFrames.c"

int main(void) {
    PerformanceBegin();
    PerformanceFrame(PerformanceSwap);
    clockNs = 3000000000;
    PerformanceFrame(PerformanceSwap);
    for (int i = 0; i < 19; i++) {
        clockNs += 16000000;
        PerformanceFrame(PerformanceDrawable);
        PerformanceFrame(PerformanceSwap);
    }
    clockNs += 200000000;
    PerformanceFrame(PerformanceSwap);
    uint64_t stamp = PerformanceQueueStamp();
    clockNs += 4000000;
    PerformanceQueueDelivered(stamp);
    PerformanceOSMPhases(2000, 500);
    PerformanceSummary s = PerformanceSnapshot(false);
    assert(s.counts[0] == 21 && s.intervals == 20);
    assert(s.p50ms == 16 && s.p95ms == 16 && s.longestMs == 200);
    assert(s.over50ms == 1 && s.over100ms == 1);
    assert(s.osmSamples == 1 && s.finishMs == 2 && s.readbackMs == .5);
    assert(s.queueSamples == 1 && s.queueMs == 4);
    clockNs = 63000000000;
    PerformanceFrame(PerformanceSwap);
    assert(PerformanceQueueStamp() == 0); // No UI timer needed to end sampling.
    unsigned stoppedReads = clockReads;
    PerformanceOSMPhases(2, 1);
    PerformanceFrame(PerformanceSwap);
    assert(clockReads == stoppedReads);
    s = PerformanceSnapshot(false);
    assert(s.elapsed == 60 && s.intervals == 20 && PerformanceQueueStamp() == 0);
    PerformanceBegin();
    clockNs += 3000000000;
    PerformanceQueueDelivered(stamp);
    PerformanceFrame(PerformanceDrawable);
    s = PerformanceSnapshot(true);
    assert(!s.intervals && !s.queueSamples && s.source == PerformanceDrawable);
    assert(PerformanceQueueStamp() == 0);
    return 0;
}
