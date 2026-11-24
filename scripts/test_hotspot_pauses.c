// cc -std=c11 -Wall -Wextra -Werror scripts/test_hotspot_pauses.c -o /tmp/test_hotspot_pauses
#include <assert.h>
#include <stdio.h>
#include "../Natives/HotSpotPause.h"

int main(int argc, char **argv) {
    HotSpotPause e;
    assert(parseHotSpotLine("[12345ms][gc       ] GC(18) Pause Young (Normal) (G1 Evacuation Pause) 32M->9M(64M) 14.375ms", &e));
    assert(e.kind == HotSpotGC && e.endEpochMs == 12345 && e.durationMs == 14.375);
    assert(parseHotSpotLine("[12345ms][gc] GC(2) Concurrent Mark Cycle 56.7ms", &e) && e.kind == HotSpotOther);
    assert(parseHotSpotLine("[12345ms][gc] GC(2) Pause Fake 99.7ms garbage", &e) && e.kind == HotSpotOther);
    assert(parseHotSpotLine("[12345ms][safepoint] Safepoint \"G1CollectForAllocation\", Reaching safepoint: 3000 ns, At safepoint: 8500000 ns, Leaving safepoint: 4000 ns, Total: 9000000 ns", &e));
    assert(e.kind == HotSpotSafepoint && e.durationMs == 9 && e.atSafepointMs == 8.5 && !e.threadInspection);
    assert(parseHotSpotLine("[12345ms][safepoint] Safepoint \"ThreadDump\", Total: 177000 ns", &e));
    assert(e.kind == HotSpotSafepoint && e.threadInspection);
    assert(parseHotSpotLine("[12345ms][safepoint] Safepoint \"ThreadDumpFoo\", Total: 180000 ns", &e));
    assert(e.kind == HotSpotSafepoint && !e.threadInspection);
    assert(parseHotSpotLine("[12345ms][safepoint] Safepoint \"Cleanup\", Total: ", &e) && e.kind == HotSpotOther);
    assert(!parseHotSpotLine("junk", &e));
    if (argc > 1) {
        FILE *f = fopen(argv[1], "r");
        assert(f);
        char line[1024];
        int gcs = 0, safepoints = 0, inspections = 0;
        while (fgets(line, sizeof(line), f)) {
            line[strcspn(line, "\n")] = 0;
            if (!parseHotSpotLine(line, &e)) continue;
            gcs += e.kind == HotSpotGC;
            safepoints += e.kind == HotSpotSafepoint;
            inspections += e.threadInspection;
        }
        fclose(f);
        assert(safepoints > 0);
        if (argc > 2) assert(inspections > 0);
        else assert(gcs > 0);
        printf("%d GC pauses, %d safepoints (%d thread inspections)\n", gcs, safepoints, inspections);
    }
}
