#pragma once
#include <stdbool.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

enum { PerformanceSeconds = 60 };
enum PerformanceFrameSource { PerformanceSwap = 1, PerformanceDrawable };
typedef struct {
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
void PerformanceFrame(enum PerformanceFrameSource source);
void PerformanceOSMPhases(double finishUs, double readbackUs);
uint64_t PerformanceQueueStamp(void);
void PerformanceQueueDelivered(uint64_t stamp);
PerformanceSummary PerformanceSnapshot(bool stop);
#ifdef __cplusplus
}
#endif
