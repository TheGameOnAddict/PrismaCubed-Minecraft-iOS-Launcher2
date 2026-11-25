"""Exercise the render gate with real pthreads and count foreground lock calls."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "Natives/utils.m").read_text()
# Compile the production functions on CI and Linux. The gate's only Apple API is NSLog.
source = source[source.index("static pthread_mutex_t ame223_park_mutex"):
                source.index("\n}", source.index("void ame223_bg_park_wait")) + 2]

hooks = r"""
#include <assert.h>
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdbool.h>
typedef bool BOOL;
#define NO false
#define YES true
#define NSLog(...)

static atomic_uint locks, waiting, returned;
static _Thread_local bool observedWait;

static int countedLock(pthread_mutex_t *mutex) {
    atomic_fetch_add(&locks, 1);
    return pthread_mutex_lock(mutex);
}

static int countedWait(pthread_cond_t *cond, pthread_mutex_t *mutex) {
    if (!observedWait) {
        observedWait = true;
        atomic_fetch_add(&waiting, 1);
    }
    return pthread_cond_wait(cond, mutex);
}

#define pthread_mutex_lock countedLock
#define pthread_cond_wait countedWait
"""

test = r"""
static void *render(void *unused) {
    ame223_bg_park_wait("test");
    atomic_fetch_add(&returned, 1);
    return NULL;
}

int main(void) {
    for (int round = 0; round < 32; round++) {
        unsigned before = atomic_load(&locks);
        for (int frame = 0; frame < 120; frame++) ame223_bg_park_wait("foreground");
        assert(atomic_load(&locks) == before);
        ame223_bg_park_begin();
        ame223_bg_park_begin();
        pthread_t threads[2];
        atomic_store(&waiting, 0);
        atomic_store(&returned, 0);
        for (int i = 0; i < 2; i++) assert(!pthread_create(&threads[i], NULL, render, NULL));
        while (atomic_load(&waiting) < 2) sched_yield();
        assert(atomic_load(&returned) == 0);
        ame223_bg_park_end();
        ame223_bg_park_end();
        for (int i = 0; i < 2; i++) assert(!pthread_join(threads[i], NULL));
        assert(atomic_load(&returned) == 2);
    }
    return 0;
}
"""

with tempfile.TemporaryDirectory() as tmp:
    executable = Path(tmp) / "test"
    subprocess.run([os.environ.get("CC", "cc"), "-x", "c", "-std=c11", "-O2", "-pthread",
                    "-o", str(executable), "-"], input=hooks + source + test, text=True, check=True)
    subprocess.run([str(executable)], check=True, timeout=15)
print("Foreground presents took no gate locks. Both render threads resumed in all 32 cycles.")
