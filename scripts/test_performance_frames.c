// Compile with cc -std=c11 -pthread scripts/test_performance_frames.c
#include <assert.h>
#include <stdint.h>
static uint64_t clockNs;
static unsigned clockReads;
static uint64_t testClock(void) { ++clockReads; return clockNs; }
#define PERFORMANCE_CLOCK testClock
static uint64_t mockCpuNs;
#define PERFORMANCE_THREAD_CLOCK() mockCpuNs
#include "../Natives/PerformanceFrames.c"

static uint64_t enterSwap(void) {
    return PerformanceFrame(PerformanceSwap);
}

static void *foreignSwap(void *ignored) {
    (void)ignored;
    PerformanceEndSwap(previousToken); // No token from this thread.
    uint64_t token = enterSwap();
    assert(token);
    clockNs += 1000000;
    PerformanceEndSwap(token);
    return NULL;
}

static void testPairedIntervals(void) {
    PerformanceBegin();
    clockNs += PerformanceLeadInSeconds * second;
    mockCpuNs = 1000000;
    uint64_t token = enterSwap();
    assert(token);
    PerformanceRecordEGLPhases(1500, 18000);
    clockNs += 22000000;
    PerformanceEndSwap(token);
    clockNs += 8000000;
    mockCpuNs += 4000000;
    token = enterSwap();
    PerformanceSummary s = PerformanceSnapshot(false);
    assert(s.phaseIntervalCount == 1 && s.eglIntervalCount == 1 && s.slowFrameCount == 1);
    PerformanceSlowFrame f = s.slowFrames[0];
    assert(f.endSeconds == .03 && f.intervalMs == 30 && f.swapMs == 22 && f.outsideSwapMs == 8);
    assert(f.hasSwapPhases && f.hasEGLPhases && f.prePresentMs == 1.5 && f.eglPresentMs == 18);
    assert(f.hasThreadCPU && f.threadCpuMs == 4);

    clockNs += 2000000;
    PerformanceEndSwap(token);
    clockNs += 38000000;
    pthread_t worker;
    assert(!pthread_create(&worker, NULL, foreignSwap, NULL));
    assert(!pthread_join(worker, NULL));
    clockNs += 50000000;
    token = enterSwap();
    s = PerformanceSnapshot(false);
    assert(s.slowFrames[0].intervalMs == 51 && !s.slowFrames[0].hasSwapPhases);
    assert(s.slowFrames[1].intervalMs == 40 && !s.slowFrames[1].hasThreadCPU);
    assert(s.slowFrames[2].hasEGLPhases && s.phaseIntervalCount == 1);
    for (int i = 1; i <= 30; ++i) {
        PerformanceEndSwap(token);
        clockNs += i * 1000000;
        token = enterSwap();
    }
    s = PerformanceSnapshot(true);
    assert(s.intervals == 33 && s.phaseIntervalCount == 31 && s.eglIntervalCount == 1);
    assert(s.swapTotalMs == 22 && s.outsideSwapTotalMs == 473);
    assert(s.prePresentTotalMs == 1.5 && s.eglPresentTotalMs == 18);
    assert(s.slowFrameCount == PerformanceSlowFrameLimit && s.slowFrames[3].intervalMs == 30);
    assert(!s.slowFrames[3].hasEGLPhases);
    for (unsigned i = 1; i < s.slowFrameCount; ++i)
        assert(s.slowFrames[i - 1].intervalMs >= s.slowFrames[i].intervalMs);
    PerformanceBegin();
    clockNs += PerformanceLeadInSeconds * second;
    uint64_t fresh = enterSwap();
    PerformanceEndSwap(token); // Old completion cannot populate the new capture.
    clockNs += 9000000;
    assert(fresh && fresh != token);
    enterSwap();
    s = PerformanceSnapshot(true);
    assert(s.intervals == 1 && s.phaseIntervalCount == 0 && !s.slowFrames[0].hasSwapPhases);
}

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
    assert(s.p50ms == 16 && s.p95ms == 16 && s.p99ms == 200 && s.longestMs == 200);
    assert(s.over50ms == 1 && s.over100ms == 1);
    assert(s.maxIntervalMsCeil[0] == 200 && s.maxIntervalMsCeil[1] == 0);
    assert(s.osmSamples == 1 && s.finishMs == 2 && s.readbackMs == .5);
    assert(s.queueSamples == 1 && s.queueMs == 4);
    clockNs = 4000000001;
    PerformanceFrame(PerformanceSwap);
    assert(PerformanceSnapshot(false).maxIntervalMsCeil[1] == 497);
    clockNs = 63000000000;
    PerformanceFrame(PerformanceSwap);
    assert(PerformanceQueueStamp() == 0); // No UI timer needed to end sampling.
    unsigned stoppedReads = clockReads;
    PerformanceOSMPhases(2, 1);
    PerformanceFrame(PerformanceSwap);
    assert(clockReads == stoppedReads);
    s = PerformanceSnapshot(false);
    assert(s.elapsed == 60 && s.intervals == 21 && PerformanceQueueStamp() == 0);
    PerformanceBegin();
    clockNs += 3000000000;
    PerformanceQueueDelivered(stamp);
    PerformanceFrame(PerformanceDrawable);
    s = PerformanceSnapshot(true);
    assert(!s.intervals && !s.queueSamples && s.source == PerformanceDrawable);
    assert(PerformanceQueueStamp() == 0);
    testPairedIntervals();
    return 0;
}
