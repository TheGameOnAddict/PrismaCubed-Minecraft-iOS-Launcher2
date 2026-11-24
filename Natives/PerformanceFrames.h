#pragma once
#include <stdbool.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

enum { PerformanceLeadInSeconds = 3, PerformanceSeconds = 60, PerformanceSlowFrameLimit = 16 };
enum PerformanceFrameSource { PerformanceSwap = 1, PerformanceDrawable };
typedef struct {
    double endSeconds, intervalMs;
    bool hasSwapPhases, hasEGLPhases, hasThreadCPU;
    double swapMs, outsideSwapMs, prePresentMs, eglPresentMs, threadCpuMs;
} PerformanceSlowFrame;

typedef struct {
    unsigned slowFrameCount, phaseIntervalCount, eglIntervalCount;
    PerformanceSlowFrame slowFrames[PerformanceSlowFrameLimit];
    double swapTotalMs, outsideSwapTotalMs, prePresentTotalMs, eglPresentTotalMs;
    unsigned counts[PerformanceSeconds];
    unsigned intervals, over50ms, over100ms;
    unsigned p50ms, p95ms, p99ms;
    unsigned maxIntervalMsCeil[PerformanceSeconds];
    double longestMs, elapsed;
    enum PerformanceFrameSource source;
    unsigned osmSamples, queueSamples;
    double finishMs, readbackMs, queueMs;
} PerformanceSummary;

void PerformanceBegin(void);
// Returns a per-call token for an accepted GL swap entry, or zero otherwise.
uint64_t PerformanceFrame(enum PerformanceFrameSource source);
void PerformanceEndSwap(uint64_t token);
void PerformanceRecordEGLPhases(uint64_t prePresentUs, uint64_t presentUs);
void PerformanceOSMPhases(double finishUs, double readbackUs);
uint64_t PerformanceQueueStamp(void);
void PerformanceQueueDelivered(uint64_t stamp);
PerformanceSummary PerformanceSnapshot(bool stop);
#ifdef __cplusplus
}
#endif
