#include "PerformanceFrames.h"
#include <pthread.h>
#include <stdatomic.h>
#include <string.h>
#include <time.h>

// Regular launches skip timing, histogram updates and locking.
static atomic_bool enabled;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static uint64_t start, previous;
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

void PerformanceBegin(void) {
    pthread_mutex_lock(&lock);
    memset(&stats, 0, sizeof(stats));
    memset(histogram, 0, sizeof(histogram));
    start = PERFORMANCE_CLOCK() + 3 * second;
    previous = 0;
    atomic_store(&enabled, true);
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

void PerformanceFrame(enum PerformanceFrameSource source) {
    if (!atomic_load_explicit(&enabled, memory_order_relaxed)) return;
    pthread_mutex_lock(&lock);
    uint64_t t = PERFORMANCE_CLOCK();
    if (inWindow(t) && (!stats.source || stats.source == source)) {
        stats.source = source;
        stats.counts[(t - start) / second]++;
        if (previous) {
            uint64_t delta = t - previous;
            histogram[(delta + 999999) / 1000000]++;
            stats.intervals++;
            stats.over50ms += delta > 50000000;
            stats.over100ms += delta > 100000000;
            double ms = delta / 1e6;
            if (ms > stats.longestMs) stats.longestMs = ms;
        }
        previous = t;
    }
    pthread_mutex_unlock(&lock);
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
    if (stop || out.elapsed >= PerformanceSeconds) atomic_store(&enabled, false);
    unsigned seen = 0, mid = (out.intervals + 1) / 2, high = (out.intervals * 95 + 99) / 100;
    for (unsigned ms = 0; seen < high; ms++) {
        unsigned before = seen;
        seen += histogram[ms];
        if (before < mid && seen >= mid) out.p50ms = ms;
        if (seen >= high) out.p95ms = ms;
    }
    pthread_mutex_unlock(&lock);
    return out;
}
