#import "NCAdShield.h"
#include <dlfcn.h>

static void NCScan(void) {
    @try {
        NCInstallAdHooks();
        NCInstallSettings();
        NSMutableDictionary *counts = [NSMutableDictionary dictionary];
        for (NSString *key in NCModuleKeys()) counts[key] = @(NCHookCount(key));
        NCLog(@"scan_complete", counts);
    } @catch (NSException *exception) {
        // This protects ObjC exceptions only, never claims to catch memory corruption.
        NCLog(@"install_exception", @{@"name":exception.name ?: @"unknown"});
    }
}

static void NCStart(void) {
    @autoreleasepool {
        NSString *bundleID = [NSBundle mainBundle].bundleIdentifier ?: @"unknown";
        BOOL canonicalBundle = [bundleID isEqualToString:NC_TARGET];
        BOOL targetExecutable = [[[NSProcessInfo processInfo] processName] isEqualToString:@"neteasemusic"];
        if (!canonicalBundle && !targetExecutable) return;
        NSDictionary *info = [NSBundle mainBundle].infoDictionary;
        NSString *appVersion = info[@"CFBundleShortVersionString"] ?: @"unknown";
        NSString *build = info[@"CFBundleVersion"] ?: @"unknown";
        Dl_info image = {0};
        dladdr((const void *)&NCStart, &image);
        NSString *filename = image.dli_fname ? [@(image.dli_fname) lastPathComponent] : @"unknown";
        NCLog(@"loaded", @{@"app_version":appVersion, @"app_build":build,
                          @"image":filename, @"os":[UIDevice currentDevice].systemVersion,
                          @"bundle_id":bundleID});
        // Settings remain reachable if the host metadata differs.
        NCSetStatus(@"app", [NSString stringWithFormat:@"云音乐 %@ (%@)", appVersion, build]);
        NCInstallSettings();
        if (!canonicalBundle || ![appVersion isEqualToString:@"9.6.09"] || ![build isEqualToString:@"7516"]) {
            NCSetStatus(@"app", [NSString stringWithFormat:@"当前 %@ (%@)：仅设置可用，广告适配未启用", appVersion, build]);
            NCLog(@"unsupported_app_metadata", @{@"canonical_bundle":@(canonicalBundle)});
            return;
        }
        NCScan();
        NCRefreshLaunchState();
        // Retry a bounded number of times for classes from delayed-loaded frameworks.
        for (NSNumber *delay in @[@2, @10, @30]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay.longLongValue * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ NCScan(); });
        }
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            NCRefreshLaunchState();
            static NSUInteger retries;
            if (retries++ < 3) NCScan();
        }];
    }
}

static void NCStartOnMain(void *context) { NCStart(); }

__attribute__((constructor))
static void NCEntry(void) {
    // Minimal fixed C IMP hooks are installed before the first main-queue turn.
    // No ObjC messaging, blocks, preferences, UI, or singleton creation here.
    NCPrepareLaunchHooks();
    dispatch_async_f(dispatch_get_main_queue(), NULL, NCStartOnMain);
}
