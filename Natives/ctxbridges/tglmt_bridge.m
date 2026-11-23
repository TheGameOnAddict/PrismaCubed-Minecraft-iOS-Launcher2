#import "CubicRuntimeInfo.h"
// Uses Witch Launcher's TGLMT C ABI, pinned to Witch_launcher bd09e27c.
// The shipped renderer's MIT notice is in resources/licenses/TGLMT.txt.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import "SurfaceViewController.h"
#import "bridge_tbl.h"
#import "tglmt_bridge.h"
#import "utils.h"
#include <dlfcn.h>
#include <pthread.h>

static struct {
    void *(*create)(uint32_t, uint32_t, const char *, int);
    void (*destroy)(void *);
    int (*bind)(void *);
    void (*clear)(void);
    int (*present)(void *, void *);
    void (*interval)(int);
    void (*resize)(void *, uint32_t, uint32_t);
    int (*hasGPU)(void);
    const char *(*name)(void);
} api;

// The upstream library has a single GL context. Track its owning thread across
// detach/attach (including Forge's early window handoff).
static basic_render_window_t context;
static pthread_t owner;
static void *window;
static CGSize targetSize;
static BOOL presented, presentFailed;

bool tglmt_bridge_init(void) {
    static dispatch_once_t once;
    static bool ready;
    dispatch_once(&once, ^{
        NSString *path = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@RENDERER_NAME_TGLMT];
        void *library = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
        if (!library) {
            NSLog(@"[TGLMT] Library load failed: %s", dlerror());
            return;
        }
#define LOAD(field, symbol) api.field = dlsym(library, "TGLMT_" #symbol)
        LOAD(create, CreateWindow);
        LOAD(destroy, DestroyWindow);
        LOAD(bind, MakeCurrent);
        LOAD(clear, ClearCurrent);
        LOAD(present, SwapBuffers);
        LOAD(interval, SwapInterval);
        LOAD(resize, ResizeWindow);
        LOAD(hasGPU, HasRealGPU);
        LOAD(name, BackendName);
#undef LOAD
        ready = api.create && api.destroy && api.bind && api.clear && api.present &&
            api.interval && api.resize && api.hasGPU && api.name;
        if (!ready) NSLog(@"[TGLMT] Library is missing required window API symbols");
    });
    return ready;
}

static basic_render_window_t *createContext(basic_render_window_t *share) {
    @synchronized (SurfaceViewController.class) {
        if (share || window) {
            NSLog(@"[TGLMT] Game requested another context; this backend supports one window");
            return NULL;
        }
        CAMetalLayer *layer = (CAMetalLayer *)SurfaceViewController.surface.layer;
        if (![layer isKindOfClass:CAMetalLayer.class]) return NULL;
        layer.pixelFormat = MTLPixelFormatRGBA8Unorm;
        layer.framebufferOnly = NO;
        targetSize = layer.drawableSize;
        if (targetSize.width < 1 || targetSize.height < 1) {
            NSLog(@"[TGLMT] Surface has no drawable size");
            return NULL;
        }
        window = api.create(targetSize.width, targetSize.height, "apple", 1);
        if (!window) {
            NSLog(@"[TGLMT] Window creation failed");
            return NULL;
        }
        NSLog(@"[Renderer] TGLMT backend=%s realGPU=%d drawable=%.0fx%.0f",
              api.name(), api.hasGPU(), targetSize.width, targetSize.height);
        api.clear();
        if (!api.hasGPU()) {
            api.destroy(window);
            window = NULL;
            return NULL;
        }
        return &context;
    }
}

static void makeCurrent(basic_render_window_t *requested) {
    @synchronized (SurfaceViewController.class) {
        if (requested == NULL) {
            if (owner == pthread_self()) {
                api.clear();
                owner = NULL;
            }
            br_set_current(NULL);
        } else if (requested == &context && window && (!owner || owner == pthread_self()) && api.bind(window)) {
            owner = pthread_self();
            br_set_current(requested);
        } else {
            NSLog(@"[TGLMT] Could not bind the rendering context on this thread");
        }
    }
}

static void swapBuffers(void) {
    if (br_get_current() != &context) return;
    ame223_bg_park_wait("tglmt_present");
    CAMetalLayer *layer = (CAMetalLayer *)SurfaceViewController.surface.layer;
    if (![layer isKindOfClass:CAMetalLayer.class]) return;
    if (layer.pixelFormat != MTLPixelFormatRGBA8Unorm) layer.pixelFormat = MTLPixelFormatRGBA8Unorm;
    CGSize size = layer.drawableSize;
    if (size.width < 1 || size.height < 1) return;
    if (!CGSizeEqualToSize(size, targetSize)) {
        api.resize(window, size.width, size.height);
        targetSize = size;
    }
    if (api.present(window, (__bridge void *)layer)) {
        if (!presented) {
            [CubicRuntimeInfo observeNativeRenderer:"TGLMT"];
            NSLog(@"[Renderer] TGLMT first Metal present succeeded");
        }
        presented = YES;
        presentFailed = NO;
    } else if (!presentFailed) {
        NSLog(@"[Renderer] TGLMT Metal present failed at %.0fx%.0f", size.width, size.height);
        presentFailed = YES;
    }
}

static void swapInterval(int interval) {
    if (br_get_current() == &context) api.interval(interval);
}

static void terminate(void) {
    @synchronized (SurfaceViewController.class) {
        if (!window) return;
        if (owner && owner != pthread_self()) {
            NSLog(@"[TGLMT] Leaving render-thread context allocated until process exit");
            return;
        }
        api.clear();
        api.destroy(window);
        window = NULL;
        owner = NULL;
        br_set_current(NULL);
        ame_brLastCurrent = NULL;
        presented = presentFailed = NO;
    }
}

void set_tglmt_bridge_tbl(void) {
    br_init = tglmt_bridge_init;
    br_init_context = createContext;
    br_make_current = makeCurrent;
    br_swap_buffers = swapBuffers;
    br_swap_interval = swapInterval;
    br_terminate = terminate;
}
