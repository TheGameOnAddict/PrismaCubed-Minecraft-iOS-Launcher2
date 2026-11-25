#pragma once

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    void *(*fence)(unsigned condition, unsigned flags);
    unsigned (*wait)(void *sync, unsigned flags, uint64_t timeoutNs);
    void (*destroy)(void *sync);
} RenderBenchmarkSync;

typedef struct {
    uint64_t window;
    uint64_t lastPreviewUs;
} RenderBenchmarkPreview;

static inline bool RenderBenchmarkPreviewDue(RenderBenchmarkPreview *preview, uint64_t window, uint64_t nowUs) {
    if (preview->window != window) {
        preview->window = window;
        preview->lastPreviewUs = 0;
    }
    return !preview->lastPreviewUs || nowUs - preview->lastPreviewUs >= 33334;
}

// The pinned Magma DirectVulkan path flushes recorded draws to a VkFence.
// Its glFinish export is a stub. Use a bounded wait for this frame's own fence.
typedef enum { RenderFenceFailed, RenderFencePending, RenderFenceComplete } RenderFenceResult;

static inline RenderFenceResult RenderWaitForFrame(const RenderBenchmarkSync *sync, uint64_t timeoutNs) {
    void *fence = sync->fence(0x9117 /* GL_SYNC_GPU_COMMANDS_COMPLETE */, 0);
    if (!fence) return RenderFenceFailed;
    unsigned result = sync->wait(fence, 1 /* GL_SYNC_FLUSH_COMMANDS_BIT */, timeoutNs);
    sync->destroy(fence);
    if (result == 0x911A /* GL_ALREADY_SIGNALED */ || result == 0x911C /* GL_CONDITION_SATISFIED */)
        return RenderFenceComplete;
    return result == 0x911B /* GL_TIMEOUT_EXPIRED */ ? RenderFencePending : RenderFenceFailed;
}

static inline bool RenderBenchmarkWaitForFrame(const RenderBenchmarkSync *sync) {
    return RenderWaitForFrame(sync, 250000000) == RenderFenceComplete;
}
