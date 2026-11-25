#include "PerformanceFrames.h"
#include <pthread.h>
#include <stdatomic.h>
#include <string.h>
#include <time.h>

// Regular launches skip timing, histogram updates and locking.
static atomic_bool enabled;
static atomic_uint_fast64_t benchmarkStart;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static uint64_t start, previous;
static uint64_t nextToken, previousToken;
static _Thread_local struct {
    uint64_t token, endNs, entryCpuNs;
    uint64_t prePresentUs, presentUs;
    bool hasEGL;
} localSwap;
static unsigned histogram[PerformanceSeconds * 1000 + 1];
static PerformanceSummary stats;
static const uint64_t second = 1000000000;

#ifndef PERFORMANCE_CLOCK
static uint64_t nowNs(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * 1000000000 + t.tv_nsec;
}
#define PERFORMANCE_CLOCK nowNs
#endif

#ifndef PERFORMANCE_THREAD_CLOCK
static uint64_t threadCpuNs(void) {
#ifdef CLOCK_THREAD_CPUTIME_ID
    struct timespec t;
    if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t) == 0)
        return (uint64_t)t.tv_sec * 1000000000 + t.tv_nsec;
#endif
    return 0;
}
#define PERFORMANCE_THREAD_CLOCK threadCpuNs
#endif

static void beginCapture(bool benchmark) {
    pthread_mutex_lock(&lock);
    memset(&stats, 0, sizeof(stats));
    memset(histogram, 0, sizeof(histogram));
    start = PERFORMANCE_CLOCK() + PerformanceLeadInSeconds * second;
    previous = previousToken = 0;
    stats.renderBenchmark = benchmark;
    atomic_store(&benchmarkStart, benchmark ? start : 0);
    atomic_store(&enabled, true);
    pthread_mutex_unlock(&lock);
}

void PerformanceBegin(void) {
    beginCapture(false);
}

void PerformanceBeginRenderBenchmark(void) {
    beginCapture(true);
}

uint64_t PerformanceBenchmarkWindow(void) {
    uint64_t window = atomic_load_explicit(&benchmarkStart, memory_order_acquire);
    if (!window) return 0;
    uint64_t t = PERFORMANCE_CLOCK();
    if (t < window) return 0;
    if (t - window < PerformanceSeconds * second) return window;
    atomic_compare_exchange_strong(&benchmarkStart, &window, 0);
    return 0;
}

void PerformanceBenchmarkCompleted(uint64_t window, bool previewSwapped) {
    if (!window) return;
    pthread_mutex_lock(&lock);
    if (window == PerformanceBenchmarkWindow()) {
        stats.gpuCompletedFrames++;
        if (previewSwapped) stats.previewSwaps++;
    }
    pthread_mutex_unlock(&lock);
}

void PerformanceBenchmarkUnavailable(uint64_t window) {
    if (!window) return;
    pthread_mutex_lock(&lock);
    if (window == atomic_load(&benchmarkStart)) {
        atomic_store(&benchmarkStart, 0);
        stats.benchmarkUnavailable = true;
    }
    pthread_mutex_unlock(&lock);
}

static bool inWindow(uint64_t t) {
    if (!atomic_load(&enabled) || t < start) return false;
    if (t - start < PerformanceSeconds * second) return true;
    // A stalled UI may miss the completion timer. Stop taking the lock on every
    // frame as soon as the render thread crosses the end of the capture.
    atomic_store(&enabled, false);
    return false;
}

// Keep the largest intervals, including unpaired ones. An interval across
// different render threads remains visible but has no swap-phase attribution.
static void rankInterval(PerformanceSlowFrame frame) {
    unsigned count = stats.slowFrameCount;
    if (count == PerformanceSlowFrameLimit && frame.intervalMs <= stats.slowFrames[count - 1].intervalMs) return;
    unsigned pos = count < PerformanceSlowFrameLimit ? count : count - 1;
    while (pos && frame.intervalMs > stats.slowFrames[pos - 1].intervalMs) {
        stats.slowFrames[pos] = stats.slowFrames[pos - 1];
        --pos;
    }
    stats.slowFrames[pos] = frame;
    if (count < PerformanceSlowFrameLimit) stats.slowFrameCount++;
}

uint64_t PerformanceFrame(enum PerformanceFrameSource source) {
    if (!atomic_load_explicit(&enabled, memory_order_relaxed)) return 0;
    uint64_t token = 0;
    pthread_mutex_lock(&lock);
    uint64_t t = PERFORMANCE_CLOCK();
    if (inWindow(t) && (!stats.source || stats.source == source)) {
        stats.source = source;
        uint64_t cpuNs = source == PerformanceSwap ? PERFORMANCE_THREAD_CLOCK() : 0;
        unsigned bucket = (unsigned)((t - start) / second);
        stats.counts[bucket]++;
        if (previous) {
            uint64_t delta = t - previous;
            unsigned msCeil = (unsigned)((delta + 999999) / 1000000);
            histogram[msCeil]++;
            if (msCeil > stats.maxIntervalMsCeil[bucket]) stats.maxIntervalMsCeil[bucket] = msCeil;
            stats.intervals++;
            stats.over50ms += delta > 50000000;
            stats.over100ms += delta > 100000000;
            double ms = delta / 1e6;
            if (ms > stats.longestMs) stats.longestMs = ms;
            PerformanceSlowFrame frame = {.endSeconds = (t - start) / 1e9, .intervalMs = ms};
            if (source == PerformanceSwap && previousToken && localSwap.token == previousToken &&
                localSwap.endNs >= previous && localSwap.endNs <= t) {
                frame.hasSwapPhases = true;
                frame.swapMs = (localSwap.endNs - previous) / 1e6;
                frame.outsideSwapMs = (t - localSwap.endNs) / 1e6;
                stats.phaseIntervalCount++;
                stats.swapTotalMs += frame.swapMs;
                stats.outsideSwapTotalMs += frame.outsideSwapMs;
                if (localSwap.hasEGL) {
                    frame.hasEGLPhases = true;
                    frame.prePresentMs = localSwap.prePresentUs / 1000.0;
                    frame.eglPresentMs = localSwap.presentUs / 1000.0;
                    stats.eglIntervalCount++;
                    stats.prePresentTotalMs += frame.prePresentMs;
                    stats.eglPresentTotalMs += frame.eglPresentMs;
                }
                if (localSwap.entryCpuNs && cpuNs >= localSwap.entryCpuNs) {
                    frame.hasThreadCPU = true;
                    frame.threadCpuMs = (cpuNs - localSwap.entryCpuNs) / 1e6;
                }
            }
            rankInterval(frame);
        }
        previous = t;
        if (source == PerformanceSwap) {
            token = ++nextToken;
            localSwap.token = token;
            localSwap.endNs = 0;
            localSwap.entryCpuNs = cpuNs;
            localSwap.hasEGL = false;
        }
        previousToken = token;
    }
    pthread_mutex_unlock(&lock);
    return token;
}

void PerformanceRecordEGLPhases(uint64_t prePresentUs, uint64_t presentUs) {
    // This hook runs inside the GL bridge on the same thread as the outer swap.
    if (!atomic_load_explicit(&enabled, memory_order_relaxed) || !localSwap.token || localSwap.endNs) return;
    localSwap.hasEGL = true;
    localSwap.prePresentUs = prePresentUs;
    localSwap.presentUs = presentUs;
}

void PerformanceEndSwap(uint64_t token) {
    if (token && localSwap.token == token && !localSwap.endNs)
        localSwap.endNs = PERFORMANCE_CLOCK();
}

void PerformanceOSMPhases(double finishUs, double readbackUs) {
    if (!atomic_load_explicit(&enabled, memory_order_relaxed)) return;
    pthread_mutex_lock(&lock);
    if (inWindow(PERFORMANCE_CLOCK())) {
        stats.osmSamples++;
        stats.finishMs += finishUs / 1000;
        stats.readbackMs += readbackUs / 1000;
    }
    pthread_mutex_unlock(&lock);
}

uint64_t PerformanceQueueStamp(void) {
    return atomic_load_explicit(&enabled, memory_order_relaxed) ? PERFORMANCE_CLOCK() : 0;
}

void PerformanceQueueDelivered(uint64_t stamp) {
    if (!stamp) return;
    pthread_mutex_lock(&lock);
    uint64_t t = PERFORMANCE_CLOCK();
    if (inWindow(stamp) && inWindow(t)) {
        stats.queueSamples++;
        stats.queueMs += (t - stamp) / 1e6;
    }
    pthread_mutex_unlock(&lock);
}

PerformanceSummary PerformanceSnapshot(bool stop) {
    pthread_mutex_lock(&lock);
    PerformanceSummary out = stats;
    uint64_t t = PERFORMANCE_CLOCK();
    out.elapsed = t > start ? (t - start) / 1e9 : 0;
    if (out.elapsed > PerformanceSeconds) out.elapsed = PerformanceSeconds;
    if (stop || out.elapsed >= PerformanceSeconds) {
        atomic_store(&benchmarkStart, 0);
        atomic_store(&enabled, false);
    }
    unsigned seen = 0, mid = (out.intervals + 1) / 2;
    unsigned high = (out.intervals * 95ULL + 99) / 100;
    unsigned tail = (out.intervals * 99ULL + 99) / 100;
    for (unsigned ms = 0; seen < tail; ms++) {
        unsigned before = seen;
        seen += histogram[ms];
        if (before < mid && seen >= mid) out.p50ms = ms;
        if (before < high && seen >= high) out.p95ms = ms;
        if (seen >= tail) out.p99ms = ms;
    }
    pthread_mutex_unlock(&lock);
    return out;
}
