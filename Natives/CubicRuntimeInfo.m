#import "CubicRuntimeInfo.h"
#import "CubicDiagnostics.h"
#import "utils.h"

@implementation CubicRuntimeInfo
static NSString *observedName, *observedLibrary, *observedSource, *observedDriver;
static NSString *libraryName(void) {
    const char *value = getenv("AMETHYST_RENDERER");
    return value ? [NSString stringWithUTF8String:value].lastPathComponent : nil;
}

+ (void)reset {
    @synchronized (self) { observedName = observedSource = observedLibrary = observedDriver = nil; }
}

+ (void)record:(NSString *)driver source:(NSString *)source {
    if (!driver.length) return;
    NSDictionary *names = @{@"Magma":@"Magma", @"zink":@"Zink", @"MobileGlues":@"MobileGlues",
        @"MobileGL Core":@"MobileGL", @"llvmpipe":@"llvmpipe", @"virgl":@"VirGL",
        @"Metallum":@"Metallum", @"Mithril":@"Mithril", @"TGLMT":@"TGLMT", @"ANGLE":@"ANGLE"};
    NSString *name = nil;
    for (NSString *token in @[@"Magma",@"zink",@"MobileGlues",@"llvmpipe",@"virgl",@"Metallum",@"Mithril",@"TGLMT",@"MobileGL Core",@"ANGLE"]) {
        if ([driver rangeOfString:token options:NSCaseInsensitiveSearch].location != NSNotFound) {
            name = names[token];
            break;
        }
    }
    NSString *library = libraryName() ?: @"";
    if (!name && [driver isEqualToString:@"Vulkan"]) name = @"Vulkan";
    if (!name) {
        // GL info can be an arbitrary vendor/version tuple. Use the renderer
        // field from GL_RENDERER directly, but never guess from a vendor tuple.
        if ([source isEqualToString:@"gameInfo"]) return;
        name = driver.length <= 30 ? driver : [[driver substringToIndex:29] stringByAppendingString:@"…"];
    }
    @synchronized (self) {
        // A helper context can bind after Minecraft has identified its render
        // backend. Keep the game's answer until a new library or game report.
        if ([source isEqualToString:@"context"] && [observedLibrary isEqualToString:library] &&
            [observedSource hasPrefix:@"game"]) return;
        if ([source isEqualToString:@"gameInfo"] && [observedLibrary isEqualToString:library] &&
            [observedSource isEqualToString:@"game"]) return;
        if ([observedName isEqual:name] && [observedLibrary isEqual:library] &&
            [observedSource isEqual:source] && [observedDriver isEqual:driver]) return;
        observedName = [name copy];
        observedLibrary = library;
        observedSource = source;
        observedDriver = [driver substringToIndex:MIN(driver.length, 240)];
        [CubicDiagnostics updateLaunchDetails:@{@"renderer":@{@"name":observedName,
            @"library":observedLibrary, @"source":observedSource}}];
    }
}

+ (void)observeNativeRenderer:(const char *)value {
    if (value && *value) [self record:[NSString stringWithUTF8String:value] source:@"context"];
}

+ (void)observeGameLine:(NSString *)line {
    if ([line hasSuffix:@"[PrismaCubic] Vulkan window surface ready"]) {
        [self record:@"Vulkan" source:@"context"];
        return;
    }
    NSRange info = [line rangeOfString:@"/INFO]: "];
    if (info.location == NSNotFound) return;
    NSRange body = NSMakeRange(NSMaxRange(info), line.length-NSMaxRange(info));
    for (NSString *marker in @[@"OpenGL Renderer: ", @"GL info: ", @"Using graphics backend Vulkan", @"Using graphics backend Metal", @"Metal device: "]) {
        if ([line rangeOfString:marker options:NSAnchoredSearch range:body].location == NSNotFound) continue;
        if ([marker hasSuffix:@"Vulkan"]) [self record:@"Vulkan" source:@"game"];
        else if ([marker isEqualToString:@"Metal device: "] || [marker hasSuffix:@"Metal"])
            [self record:@"Metallum" source:@"game"];
        else [self record:[line substringFromIndex:body.location+marker.length]
                   source:[marker hasPrefix:@"GL info"] ? @"gameInfo" : @"game"];
        return;
    }
}

+ (NSDictionary *)renderer {
    NSString *library = libraryName() ?: @"";
    @synchronized (self) {
        if (observedName && [observedLibrary isEqualToString:library])
            return @{@"name":observedName, @"source":observedSource, @"driver":observedDriver, @"library":library};
    }
    static NSDictionary *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ names = @{@ RENDERER_NAME_MOBILEGL:@"MobileGL", @ RENDERER_NAME_MOBILEGL_GLES:@"MobileGL GLES",
        @ RENDERER_NAME_MOBILEGLUES:@"MobileGlues", @ RENDERER_NAME_VK_ZINK:@"Zink", @ RENDERER_NAME_VIRGL:@"VirGL",
        @ RENDERER_NAME_VULKAN:@"MoltenVK", @ RENDERER_NAME_METAL:@"Metallum", @ RENDERER_NAME_MITHRIL:@"Mithril",
        @ RENDERER_NAME_TGLMT:@"TGLMT", @ RENDERER_NAME_MTL_ANGLE:@"TinyGL4ANGLE", @ RENDERER_NAME_GL4ESZL2:@"GL4ES",
        @ RENDERER_NAME_NGGL4ES:@"NG-GL4ES", @ RENDERER_NAME_LTW:@"LTW", @ RENDERER_NAME_VGPU:@"vGPU"}; });
    return @{@"name":names[library] ?: (library.length ? library : @"…"), @"source":@"selection", @"library":library};
}

+ (NSString *)javaVersionAtHome:(NSString *)home {
    NSString *release = [NSString stringWithContentsOfFile:[home stringByAppendingPathComponent:@"release"]
                                                 encoding:NSUTF8StringEncoding error:nil];
    for (NSString *line in [release componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"JAVA_VERSION=\""]) {
            NSString *value = [[line substringFromIndex:14] componentsSeparatedByString:@"\""].firstObject;
            if (value.length) return value;
        }
    }
    return nil;
}
@end
