// cc -std=c11 -Wall -Wextra -Werror scripts/test_render_benchmark.c -o /tmp/render-benchmark
#include "../Natives/ctxbridges/RenderBenchmark.h"
#include <assert.h>

static unsigned waits, destroys, waitResult;
static bool failCreate;
static int fenceHandle;

static void *fence(unsigned condition, unsigned flags) {
    assert(condition == 0x9117 && !flags);
    return failCreate ? 0 : &fenceHandle;
}

static unsigned waitForGPU(void *handle, unsigned flags, uint64_t timeout) {
    assert(handle == &fenceHandle && flags == 1 && timeout > 0 && timeout <= 250000000);
    waits++;
    return waitResult;
}

static void destroy(void *handle) {
    assert(handle == &fenceHandle);
    destroys++;
}

int main(void) {
    RenderBenchmarkSync api = {fence, waitForGPU, destroy};
    waitResult = 0x911A;
    assert(RenderBenchmarkWaitForFrame(&api));
    waitResult = 0x911C;
    assert(RenderBenchmarkWaitForFrame(&api));
    waitResult = 0x911B; // GL_TIMEOUT_EXPIRED
    assert(!RenderBenchmarkWaitForFrame(&api));
    waitResult = 0x911D; // GL_WAIT_FAILED
    assert(!RenderBenchmarkWaitForFrame(&api));
    failCreate = true;
    assert(!RenderBenchmarkWaitForFrame(&api));
    assert(waits == 4 && destroys == 4);

    RenderBenchmarkPreview preview = {0};
    assert(RenderBenchmarkPreviewDue(&preview, 1, 1000000));
    preview.lastPreviewUs = 1001000;
    assert(!RenderBenchmarkPreviewDue(&preview, 1, 1001000 + 33333));
    assert(RenderBenchmarkPreviewDue(&preview, 1, 1001000 + 33334));
    assert(RenderBenchmarkPreviewDue(&preview, 2, 1001001));
    return 0;
}
