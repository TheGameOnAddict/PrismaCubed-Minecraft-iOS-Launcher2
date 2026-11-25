#pragma once

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    uint64_t policy;
    uint64_t nextPresentUs;
    uint64_t previousReturnUs;
    uint64_t expectedBuildUs;
    uint64_t expectedFenceUs;
    uint64_t retryAfterUs;
    uint64_t periodUs;
} GameplayPresentation;

// An unexpectedly slow frame should immediately get a real swap. Let a run
// of cheaper frames gradually re-establish spare time for rendering ahead.
static inline uint64_t GameplayFrameEstimate(uint64_t previous, uint64_t sample) {
    return sample >= previous ? sample : (3 * previous + sample) / 4;
}

static inline bool GameplayHasTimeForAnotherFrame(const GameplayPresentation *state, uint64_t nowUs) {
    if (nowUs >= state->nextPresentUs) return false;
    uint64_t remaining = state->nextPresentUs - nowUs;
    return remaining > state->expectedBuildUs + state->expectedFenceUs + state->periodUs / 8;
}

static inline bool GameplayCanRenderAhead(GameplayPresentation *state, uint64_t policy, unsigned hz, uint64_t entryUs) {
    if (policy != state->policy) {
        *state = (GameplayPresentation){.policy = policy, .periodUs = (1000000u + hz / 2) / hz};
    }
    if (!state->previousReturnUs || !state->nextPresentUs) return false;
    uint64_t build = entryUs - state->previousReturnUs;
    if (build > state->periodUs * 2) build = state->periodUs * 2;
    state->expectedBuildUs = GameplayFrameEstimate(state->expectedBuildUs, build);
    // Include the cost of completing this frame AND constructing its replacement.
    return entryUs >= state->retryAfterUs && GameplayHasTimeForAnotherFrame(state, entryUs + state->expectedFenceUs);
}

// Limit the GPU wait to the remaining headroom. If the GPU is busy, fall back
// to pipelined presentation for a quarter second before trying again.
static inline uint64_t GameplayFenceBudgetNs(const GameplayPresentation *state, uint64_t nowUs) {
    if (nowUs >= state->nextPresentUs) return 0;
    uint64_t spare = state->nextPresentUs - nowUs;
    uint64_t reserve = state->expectedBuildUs + state->periodUs / 8;
    if (spare <= reserve) return 0;
    uint64_t budget = spare - reserve;
    return (budget < state->periodUs ? budget : state->periodUs) * 1000;
}

static inline bool GameplayCanHoldCompletedFrame(GameplayPresentation *state, uint64_t beganUs, uint64_t completedUs) {
    uint64_t cost = completedUs - beganUs;
    if (cost > state->periodUs) cost = state->periodUs;
    state->expectedFenceUs = GameplayFrameEstimate(state->expectedFenceUs, cost);
    if (!GameplayHasTimeForAnotherFrame(state, completedUs)) return false;
    state->previousReturnUs = completedUs;
    return true;
}

static inline void GameplayDidPresent(GameplayPresentation *state, uint64_t submitUs, uint64_t returnedUs) {
    // The next slot is relative to the previous submission schedule. Starting
    // a fresh interval AFTER a FIFO acquire returns can halve the visible rate.
    if (!state->nextPresentUs) {
        // The first real swap may already have waited an entire vblank. Use its
        // return as our initial display-phase estimate, then advance absolute slots.
        state->nextPresentUs = returnedUs + state->periodUs;
    } else if (state->nextPresentUs <= submitUs) {
        uint64_t elapsed = submitUs - state->nextPresentUs;
        state->nextPresentUs += (1 + elapsed / state->periodUs) * state->periodUs;
    } else {
        state->nextPresentUs += state->periodUs;
    }
    state->previousReturnUs = returnedUs;
    // Recover from an isolated expensive fence even when following swaps took
    // the ordinary GPU-pipelined route and offered no newer fence measurement.
    state->expectedFenceUs -= (state->expectedFenceUs + 15) / 16;
}
