#import "NCAdShield.h"
#import <objc/message.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <stdlib.h>
#include <string.h>

// Exact source-image UUID gate: early installation does not message NSBundle/NSUserDefaults.
static BOOL NCSourceImageMatches(void) {
    static const unsigned char expected[16] = {0xea,0x88,0xec,0x63,0xa3,0x29,0x3f,0xc6,0x8c,0xb5,0xb0,0x75,0x50,0x74,0x28,0xc2};
    const struct mach_header_64 *header = (const void *)_dyld_get_image_header(0);
    if (!header || header->magic != MH_MAGIC_64 || header->ncmds > 512 || header->sizeofcmds > 65536) return NO;
    const unsigned char *p = (const void *)(header + 1), *end = p + header->sizeofcmds;
    for (uint32_t i = 0; i < header->ncmds; i++) {
        if ((size_t)(end - p) < sizeof(struct load_command)) return NO;
        const struct load_command *command = (const void *)p;
        if (command->cmdsize < sizeof(*command) || command->cmdsize > (size_t)(end - p)) return NO;
        if (command->cmd == LC_UUID && command->cmdsize == sizeof(struct uuid_command))
            return memcmp(((const struct uuid_command *)command)->uuid, expected, 16) == 0;
        p += command->cmdsize;
    }
    return NO;
}

typedef struct {
    const char *className, *selectorName, *types;
    IMP replacement, original;
    BOOL installed, reported;
} NCLaunchHook;
static char finishingKey;
static BOOL cacheCleared;
static NSUInteger blockedCalls;

static id NCLaunchObject(id object, const char *name) {
    SEL sel = sel_registerName(name);
    Method method = class_getInstanceMethod(object_getClass(object), sel);
    if (!NCSignature(method, "@", @[])) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, sel);
}
static void NCLaunchVoid(id object, const char *name) {
    SEL sel = sel_registerName(name);
    Method method = class_getInstanceMethod(object_getClass(object), sel);
    if (NCSignature(method, "v", @[])) ((void (*)(id, SEL))objc_msgSend)(object, sel);
}
static void NCLaunchBool(id object, const char *name, BOOL value) {
    SEL sel = sel_registerName(name);
    Method method = class_getInstanceMethod(object_getClass(object), sel);
    if (NCSignature(method, "v", @[@"B"])) ((void (*)(id, SEL, BOOL))objc_msgSend)(object, sel, value);
}
static id NCLaunchManager(void) {
    return NCLaunchObject(NSClassFromString(@"NMLaunchAdViewManager"), "sharedManager");
}

// Called only from a real App method / main-queue work, never from the initializer.
static void NCClearLaunchMetadata(void) {
    if (cacheCleared) return;
    id manager = NCLaunchObject(NSClassFromString(@"NMAdvertisementManager"), "defaultManager");
    if (!manager) return;
    SEL reset = sel_registerName("resetCachedStartupAdvertisement");
    SEL clear = sel_registerName("deleteLauchCache");
    if (!NCSignature(class_getInstanceMethod(object_getClass(manager), reset), "v", @[]) ||
        !NCSignature(class_getInstanceMethod(object_getClass(manager), clear), "v", @[])) return;
    cacheCleared = YES; // Set first, because App callbacks may reenter.
    ((void (*)(id, SEL))objc_msgSend)(manager, reset);
    ((void (*)(id, SEL))objc_msgSend)(manager, clear);
    NCLog(@"launch_cache_metadata_reset", @{@"scope":@"startup_metadata_only"});
}

static void NCFinishLaunch(id manager) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (NCEnabled(@"launch")) NCFinishLaunch(manager); });
        return;
    }
    if (!manager || [objc_getAssociatedObject(manager, &finishingKey) boolValue]) return;
    SEL completion = sel_registerName("adCompletionType:loadMainScreenEnable:");
    Method method = class_getInstanceMethod(object_getClass(manager), completion);
    if (!NCSignature(method, "v", @[@"q", @"B"])) return;
    objc_setAssociatedObject(manager, &finishingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        NCLaunchVoid(manager, "cancelADDataTimer");
        NCLaunchVoid(manager, "stopTimer");
        NCLaunchBool(manager, "setLoadingAd:", NO);
        NCLaunchVoid(manager, "markFakeLaunchViewEnd");
        // 2 is the source App's failure completion, with its own once-only callback guard.
        // Completing the load path is necessary; returning from show alone can leave a placeholder.
        ((void (*)(id, SEL, NSInteger, BOOL))objc_msgSend)(manager, completion, 2, YES);
        id container = NCLaunchObject(manager, "launchAdViewContoller");
        if (container) NCLaunchBool(manager, "dismiss:", NO);
        NCLaunchBool(manager, "setShowing:", NO);
        NCClearLaunchMetadata();
        if (blockedCalls++ < 12) NCLog(@"launch_blocked_and_completed", @{@"cached_materials_also_blocked":@YES});
    } @finally {
        objc_setAssociatedObject(manager, &finishingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static BOOL NCBlockLaunch(void) { return NCEnabled(@"launch"); }
static void NCCold(id, SEL);
static void NCWarm(id, SEL);
static void NCShow(id, SEL);
static void NCCacheShow(id, SEL);
static void NCControllerShow(id, SEL);
static void NCContainerShow(id, SEL);
static id NCCacheAd(id, SEL, NSInteger, BOOL);
static id NCStartupAd(id, SEL, BOOL);
static id NCStartupAd2(id, SEL, BOOL);
static id NCStartupAd3(id, SEL, BOOL);
static id NCStartupAd4(id, SEL, BOOL);
static id NCStartupAdLegacy(id, SEL, BOOL);
static void NCVideoPlay(id, SEL);

enum { Cold, Warm, Show, CacheShow, ControllerShow, ContainerShow, CacheAd,
       StartupAd, StartupAd2, StartupAd3, StartupAd4, StartupAdLegacy, VideoPlay };
static NCLaunchHook launchHooks[] = {
    {"NMLaunchAdViewManager","loadCurrentAdWhenStartup","v16@0:8",(IMP)NCCold,0,0,0},
    {"NMLaunchAdViewManager","loadCurrentAdWhenBecomeActive","v16@0:8",(IMP)NCWarm,0,0,0},
    {"NMLaunchAdViewManager","_doShowAd","v16@0:8",(IMP)NCShow,0,0,0},
    {"NMLaunchAdViewManager","showCacheAdIfNeedWhenCurrentAdShowFailed","v16@0:8",(IMP)NCCacheShow,0,0,0},
    {"NMLaunchAdViewController","show","v16@0:8",(IMP)NCControllerShow,0,0,0},
    {"NMLaunchAdContainerView","show","v16@0:8",(IMP)NCContainerShow,0,0,0},
    {"NMAdvertisementManager","advertisementForPosition:needDownloaded:","@28@0:8q16B24",(IMP)NCCacheAd,0,0,0},
    {"NMAdvertisementManager","properAdV2ForStartupNeedDownloaded:","@20@0:8B16",(IMP)NCStartupAd,0,0,0},
    {"NMAdvertisementManager","_properAdV2ForStartupNeedDownloaded:","@20@0:8B16",(IMP)NCStartupAd2,0,0,0},
    {"NMAdvertisementManager","_properAdV3ForStartupNeedDownloaded:","@20@0:8B16",(IMP)NCStartupAd3,0,0,0},
    {"NMAdvertisementManager","_properAdV4ForStartupNeedDownloaded:","@20@0:8B16",(IMP)NCStartupAd4,0,0,0},
    {"NMAdvertisementManager","_properAdForStartupNeedDownloaded:","@20@0:8B16",(IMP)NCStartupAdLegacy,0,0,0},
    {"NMLaunchAdVideoPlayer","playIfReady","v16@0:8",(IMP)NCVideoPlay,0,0,0},
};
#define NC_MANAGER_WRAPPER(function, index) \
static void function(id object, SEL sel) { \
    @autoreleasepool { \
        if (NCBlockLaunch()) { NCFinishLaunch(object); return; } \
        ((void (*)(id, SEL))launchHooks[index].original)(object, sel); \
    } \
}
NC_MANAGER_WRAPPER(NCCold, Cold)
NC_MANAGER_WRAPPER(NCWarm, Warm)
NC_MANAGER_WRAPPER(NCShow, Show)
NC_MANAGER_WRAPPER(NCCacheShow, CacheShow)

#define NC_CONTAINER_WRAPPER(function, index) \
static void function(id object, SEL sel) { \
    @autoreleasepool { \
        if (NCBlockLaunch()) { NCFinishLaunch(NCLaunchManager()); return; } \
        ((void (*)(id, SEL))launchHooks[index].original)(object, sel); \
    } \
}
NC_CONTAINER_WRAPPER(NCControllerShow, ControllerShow)
NC_CONTAINER_WRAPPER(NCContainerShow, ContainerShow)

static id NCCacheAd(id object, SEL sel, NSInteger position, BOOL downloaded) {
    // The source fallback passes position=1; other placements retain their own module controls.
    if (position == 1 && NCBlockLaunch()) return nil;
    return ((id (*)(id, SEL, NSInteger, BOOL))launchHooks[CacheAd].original)(object, sel, position, downloaded);
}
#define NC_STARTUP_WRAPPER(function, index) \
static id function(id object, SEL sel, BOOL downloaded) { \
    if (NCBlockLaunch()) return nil; \
    return ((id (*)(id, SEL, BOOL))launchHooks[index].original)(object, sel, downloaded); \
}
NC_STARTUP_WRAPPER(NCStartupAd, StartupAd)
NC_STARTUP_WRAPPER(NCStartupAd2, StartupAd2)
NC_STARTUP_WRAPPER(NCStartupAd3, StartupAd3)
NC_STARTUP_WRAPPER(NCStartupAd4, StartupAd4)
NC_STARTUP_WRAPPER(NCStartupAdLegacy, StartupAdLegacy)

static void NCVideoPlay(id object, SEL sel) {
    if (NCBlockLaunch()) {
        NCLaunchVoid(object, "stopPlayVideo");
        return;
    }
    ((void (*)(id, SEL))launchHooks[VideoPlay].original)(object, sel);
}

void NCPrepareLaunchHooks(void) {
    // C runtime calls only. No Objective-C messages or heap-backed ObjC registries.
    if (!NCSourceImageMatches()) return;
    for (size_t i = 0; i < sizeof(launchHooks)/sizeof(launchHooks[0]); i++) {
        NCLaunchHook *hook = &launchHooks[i];
        if (hook->installed) continue;
        Class cls = objc_getClass(hook->className);
        if (!cls) continue;
        SEL sel = sel_registerName(hook->selectorName);
        unsigned count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        Method method = NULL;
        for (unsigned j = 0; j < count; j++) if (method_getName(methods[j]) == sel) { method = methods[j]; break; }
        if (method && strcmp(method_getTypeEncoding(method), hook->types) == 0) {
            hook->original = method_getImplementation(method);
            if (hook->original && hook->original != hook->replacement) {
                method_setImplementation(method, hook->replacement);
                hook->installed = YES;
            }
        }
        free(methods);
    }
}
void NCReportLaunchHooks(void) {
    for (size_t i = 0; i < sizeof(launchHooks)/sizeof(launchHooks[0]); i++) {
        NCLaunchHook *hook = &launchHooks[i];
        if (!hook->installed || hook->reported) continue;
        hook->reported = YES;
        NCRecordHook(@"launch");
        NCLog(@"launch_hook_installed", @{@"class":@(hook->className), @"selector":@(hook->selectorName)});
    }
}
void NCRefreshLaunchState(void) {
    if (!NCSourceImageMatches()) return;
    if (!NCBlockLaunch()) { cacheCleared = NO; return; }
    NCClearLaunchMetadata();
    id manager = NCLaunchManager();
    SEL showing = sel_registerName("isShowing");
    Method method = class_getInstanceMethod(object_getClass(manager), showing);
    if (NCSignature(method, "B", @[]) && ((BOOL (*)(id,SEL))objc_msgSend)(manager, showing))
        NCFinishLaunch(manager); // Catch injection after an already displayed cached ad.
}
