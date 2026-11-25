// cc -std=c11 -Wall -Wextra -Werror scripts/test_gameplay_presentation.c -o /tmp/gameplay-presentation
#include "../Natives/ctxbridges/GameplayPresentation.h"
#include <assert.h>
#include <stdio.h>

struct result { unsigned frames, submits, extra; };

// Simulate a FIFO surface which either returns at the next display tick or
// lets the render thread queue one image ahead. Use the real bridge policy.
static struct result run(unsigned hz, unsigned buildUs, unsigned fenceUs, bool queueAhead) {
    struct result counts = {0};
    GameplayPresentation state = {0};
    uint64_t now = 1000000, lastVisible = now, end = now + 1000000;
    uint64_t period = (1000000 + hz / 2) / hz;
    while (now < end) {
        now += buildUs;
        counts.frames++;
        if (GameplayCanRenderAhead(&state, 1, hz, now)) {
            uint64_t begin = now;
            now += fenceUs;
            if (GameplayCanHoldCompletedFrame(&state, begin, now)) {
                counts.extra++;
                continue;
            }
        }
        counts.submits++;
        uint64_t submit = now;
        uint64_t visible = 1000000 + ((now - 1000000) / period + 1) * period;
        if (visible < lastVisible + period) visible = lastVisible + period;
        lastVisible = visible;
        uint64_t release = queueAhead ? visible - period : visible;
        if (now < release) now = release;
        GameplayDidPresent(&state, submit, now);
    }
    assert(counts.frames == counts.submits + counts.extra);
    return counts;
}

int main(void) {
    for (int ahead = 0; ahead <= 1; ahead++) {
        for (unsigned hz = 60; hz <= 120; hz += 60) {
            struct result fast = run(hz, 1800, 200, ahead);
            assert(fast.submits >= hz - 1 && fast.submits <= hz + 2);
            assert(fast.frames > hz + 100);
            struct result slow = run(hz, 22000, 0, ahead);
            assert(slow.extra == 0 && slow.submits == slow.frames);
            struct result near = run(hz, (1000000 / hz) * 9 / 10, 0, ahead);
            assert(near.submits >= hz - 1);
        }
    }

    GameplayPresentation state = {0};
    assert(!GameplayCanRenderAhead(&state, 1, 120, 1000));
    GameplayDidPresent(&state, 1000, 1800);
    assert(GameplayCanRenderAhead(&state, 1, 120, 3300));
    assert(GameplayFenceBudgetNs(&state, 3300) > 0 && GameplayFenceBudgetNs(&state, 3300) < 8333000);
    assert(GameplayFenceBudgetNs(&state, state.nextPresentUs) == 0);
    state.retryAfterUs = 4000;
    assert(!GameplayCanRenderAhead(&state, 1, 120, 3300));
    // A fence that uses up the available headroom must immediately present.
    assert(!GameplayCanHoldCompletedFrame(&state, 3300, 9300));
    GameplayDidPresent(&state, 9300, 16000);
    // Changing mode/display or resuming foreground always presents the first frame.
    assert(!GameplayCanRenderAhead(&state, 2, 60, 16500));
    GameplayDidPresent(&state, 16500, 16700);
    // A long world-generation hitch never produces a burst of catch-up swaps.
    assert(!GameplayCanRenderAhead(&state, 2, 60, 500000));
    GameplayDidPresent(&state, 500000, 500200);
    assert(state.nextPresentUs > 500000 && state.nextPresentUs <= 516667);
    puts("PASS: 60/120 Hz FIFO cadence, fast/slow workloads, late fences, resume, and hitches");
}
