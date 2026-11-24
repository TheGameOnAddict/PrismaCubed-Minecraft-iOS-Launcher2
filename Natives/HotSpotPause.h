// HotSpot unified logging configured with timemillis,tags decorators.
// Accept only durations and numeric time. Never forward freeform VM text.
#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

typedef enum { HotSpotOther, HotSpotGC, HotSpotSafepoint } HotSpotPauseKind;

typedef struct {
    int64_t endEpochMs;
    HotSpotPauseKind kind;
    double durationMs;
    double atSafepointMs;
    bool threadInspection;
} HotSpotPause;

static inline bool parseHotSpotLine(const char *line, HotSpotPause *event) {
    long long stamp;
    char tag[24] = {0};
    int used = 0;
    if (sscanf(line, "[%lldms][%23[^]]] %n", &stamp, tag, &used) != 2 || !used || stamp <= 0) return false;
    char *padding = strchr(tag, ' ');
    if (padding) *padding = '\0';
    const char *message = line + used;
    *event = (HotSpotPause){ .endEpochMs = stamp, .atSafepointMs = -1 };
    if (strcmp(tag, "gc") == 0) {
        // Concurrent GC cycle durations are not stop-the-world GC pauses.
        if (strncmp(message, "GC(", 3) || !strstr(message, ") Pause ")) return true;
        const char *duration = strrchr(message, ' ');
        double ms;
        int end = 0;
        if (duration && sscanf(duration, " %lfms%n", &ms, &end) == 1 && end && !duration[end] &&
            isfinite(ms) && ms >= 0) {
            event->kind = HotSpotGC;
            event->durationMs = ms;
        }
    } else if (strcmp(tag, "safepoint") == 0 && !strncmp(message, "Safepoint ", 10)) {
        const char *total = strstr(message, "Total: ");
        const char *at = strstr(message, "At safepoint: ");
        long long nanos = -1;
        int end = 0;
        if (total && sscanf(total, "Total: %lld ns%n", &nanos, &end) == 1 && end && !total[end] && nanos >= 0) {
            event->kind = HotSpotSafepoint;
            // ThreadMXBean can cause ThreadDump during a sample. Other stack-dump
            // operations may be initiated by mods or the VM. Match the complete
            // quoted HotSpot operation name, never arbitrary reason text.
            const char *operation = message + strlen("Safepoint ");
            static const char *const inspections[] = {
                "\"ThreadDump\",", "\"PrintThreads\",", "\"GetAllStackTraces\",", "\"GetThreadListStackTraces\","
            };
            for (size_t i = 0; i < sizeof(inspections) / sizeof(inspections[0]); ++i) {
                if (!strncmp(operation, inspections[i], strlen(inspections[i]))) {
                    event->threadInspection = true;
                    break;
                }
            }
            event->durationMs = nanos / 1e6;
            end = 0;
            if (at && sscanf(at, "At safepoint: %lld ns%n", &nanos, &end) == 1 && end && nanos >= 0)
                event->atSafepointMs = nanos / 1e6;
        }
    }
    return true;
}
