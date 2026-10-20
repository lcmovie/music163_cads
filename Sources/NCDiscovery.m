#import "NCAdShield.h"
#import <objc/message.h>

static NSHashTable<UIViewController *> *recognizedSettings;
static NSHashTable<UIViewController *> *activeEntries;

// Inspect only exact, static settings labels. Never copy arbitrary page text to diagnostics.
static NSSet<NSString *> *NCSettingsLabels(UIView *root) {
    NSArray *expected = @[@"账号与安全", @"播放与下载", @"音质", @"通用", @"通知",
                         @"隐私与权限", @"存储空间", @"未成年人模式", @"关于"];
    NSMutableSet *found = [NSMutableSet set];
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:root];
    NSUInteger inspected = 0;
    while (pending.count && inspected++ < 1600) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        if (view.hidden || view.alpha < 0.01) continue;
        NSString *label = nil;
        if ([view isKindOfClass:[UILabel class]]) label = [(UILabel *)view text];
        else if ([NSStringFromClass([view class]) hasPrefix:@"RCTText"]) label = view.accessibilityLabel;
        if (label) {
            NSString *text = [label stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (text && [expected containsObject:text]) [found addObject:text];
        }
        [pending addObjectsFromArray:view.subviews];
    }
    return found;
}

static BOOL NCSettingsTitle(UIViewController *vc) {
    NSArray *titles = @[@"设置", @"Settings"];
    if ((vc.title && [titles containsObject:vc.title]) ||
        (vc.navigationItem.title && [titles containsObject:vc.navigationItem.title])) return YES;
    UIView *titleView = vc.navigationItem.titleView;
    return [titleView isKindOfClass:[UILabel class]] && [titles containsObject:([(UILabel *)titleView text] ?: @"")];
}

// 1 = rn-setting, -1 = another known RN module, 0 = no usable module metadata.
static NSInteger NCReactSettingsMatch(UIViewController *vc) {
    Class base = NSClassFromString(@"NEReactViewController");
    if (!base || ![vc isKindOfClass:base]) return 0;
    SEL selector = NSSelectorFromString(@"moduleName");
    Method getter = class_getInstanceMethod([vc class], selector);
    if (!NCSignature(getter, "@", @[])) return 0;
    @try {
        id value = ((id (*)(id, SEL))objc_msgSend)(vc, selector);
        if (![value isKindOfClass:[NSString class]] || ![(NSString *)value length]) return 0;
        return [@[@"rn-setting", @"rn-setting@index"] containsObject:value] ? 1 : -1;
    } @catch (__unused NSException *exception) { return 0; }
}

BOOL NCIsSettingsController(UIViewController *vc) {
    if (!vc) return NO;
    NSInteger rn = NCReactSettingsMatch(vc);
    if (rn) return rn == 1;
    BOOL title = NCSettingsTitle(vc);
    Class reactBase = NSClassFromString(@"NEReactViewController");
    BOOL hint = title || [[NSStringFromClass([vc class]) lowercaseString] containsString:@"setting"] ||
                (reactBase && [vc isKindOfClass:reactBase]);
    if (!hint) return NO;
    if (title && [recognizedSettings containsObject:vc]) return YES;
    NSSet *labels = NCSettingsLabels(vc.view);
    BOOL account = [labels containsObject:@"账号与安全"];
    NSUInteger other = labels.count - (account ? 1 : 0);
    return (title && other >= 2) || (account && other >= 3);
}

static UIViewController *NCFindVisibleSettings(UIViewController *vc, NSUInteger depth, NSMutableArray *probes) {
    if (!vc || depth > 16) return nil;
    if (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed)
        return NCFindVisibleSettings(vc.presentedViewController, depth + 1, probes);
    if ([vc isKindOfClass:[UINavigationController class]])
        return NCFindVisibleSettings([(UINavigationController *)vc visibleViewController], depth + 1, probes);
    if ([vc isKindOfClass:[UITabBarController class]])
        return NCFindVisibleSettings([(UITabBarController *)vc selectedViewController], depth + 1, probes);
    if (!vc.isViewLoaded || !vc.view.window || vc.view.hidden || vc.view.alpha < 0.01) return nil;
    if ([vc isKindOfClass:[NCShieldPanel class]]) return nil;
    CGRect rect = [vc.view convertRect:vc.view.bounds toView:vc.view.window];
    if (CGRectIsEmpty(CGRectIntersection(rect, vc.view.window.bounds))) return nil;

    NSString *className = NSStringFromClass([vc class]);
    NSInteger rn = NCReactSettingsMatch(vc);
    if (rn == 1) {
        [recognizedSettings addObject:vc];
        if (probes.count < 12) [probes addObject:@{@"class":className, @"rn_settings_module":@YES}];
        return vc;
    }
    BOOL title = NCSettingsTitle(vc);
    // Do not scan arbitrary content pages. The generic fallback needs a settings title/class hint.
    Class reactBase = NSClassFromString(@"NEReactViewController");
    BOOL settingsHint = title || [[className lowercaseString] containsString:@"setting"] ||
                        (rn == 0 && reactBase && [vc isKindOfClass:reactBase]);
    NSSet *labels = settingsHint ? NCSettingsLabels(vc.view) : [NSSet set];
    BOOL account = [labels containsObject:@"账号与安全"];
    NSUInteger other = labels.count - (account ? 1 : 0);
    BOOL remembered = [recognizedSettings containsObject:vc] && title;
    BOOL match = rn != -1 && (remembered || (title && other >= 2) || (account && other >= 3));
    if (probes.count < 12) [probes addObject:@{@"class":className, @"settings_title":@(title),
                                             @"account_anchor":@(account), @"other_anchors":@(other),
                                             @"other_rn_module":@(rn == -1)}];
    // Prefer a matching visible child to its container to avoid adding controls to an entire app shell.
    for (UIViewController *child in vc.childViewControllers) {
        UIViewController *candidate = NCFindVisibleSettings(child, depth + 1, probes);
        if (candidate) return candidate;
    }
    if (match) { [recognizedSettings addObject:vc]; return vc; }
    return nil;
}

static NSArray<UIWindow *> *NCForegroundWindows(void) {
    NSMutableArray *windows = [NSMutableArray array];
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive)
            [windows addObjectsFromArray:[(UIWindowScene *)scene windows]];
    }
    if (!windows.count) [windows addObjectsFromArray:[UIApplication sharedApplication].windows];
    return windows;
}

static void NCDiscoverSettings(void) {
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return;
    @try {
        NSMutableArray<UIViewController *> *current = [NSMutableArray array];
        NSMutableArray *probes = [NSMutableArray array];
        for (UIWindow *window in NCForegroundWindows()) {
            if (window.hidden || window.alpha < 0.01 || window.windowLevel != UIWindowLevelNormal) continue;
            UIViewController *vc = NCFindVisibleSettings(window.rootViewController, 0, probes);
            if (vc && NCEnsureSettingsEntry(vc)) [current addObject:vc];
        }
        // Covering a settings page with the plugin panel is not a change of RN module.
        // Keep its row and geometry mounted so returning cannot show an unshifted list first.
        for (UIViewController *old in activeEntries.allObjects) {
            if ([current containsObject:old]) continue;
            if (NCIsSettingsController(old)) [current addObject:old];
            else NCHideSettingsEntry(old);
        }
        [activeEntries removeAllObjects];
        for (UIViewController *vc in current) [activeEntries addObject:vc];

        NSMutableString *fingerprint = [NSMutableString string];
        for (NSDictionary *probe in probes)
            [fingerprint appendFormat:@"%@/%@/%@/%@;", probe[@"class"], probe[@"settings_title"], probe[@"account_anchor"], probe[@"other_anchors"]];
        static NSString *lastFingerprint;
        if (![lastFingerprint isEqualToString:fingerprint]) {
            NCLog(@"visible_settings_probe", @{@"candidates":probes, @"matched":@(current.count)});
            lastFingerprint = [fingerprint copy];
        }
    } @catch (NSException *exception) {
        static BOOL logged;
        if (!logged) { NCLog(@"settings_discovery_exception", @{@"name":exception.name ?: @"unknown"}); logged = YES; }
    }
}

void NCSynchronizeSettingsAtMount(void) {
    if (![NSThread isMainThread]) return;
    [UIView performWithoutAnimation:^{ NCDiscoverSettings(); }];
}

void NCInstallSettingsDiscovery(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        recognizedSettings = [NSHashTable weakObjectsHashTable];
        activeEntries = [NSHashTable weakObjectsHashTable];
        NCSetStatus(@"settings", @"等待进入设置页面");
        for (NSString *event in @[UIApplicationDidBecomeActiveNotification, UIWindowDidBecomeVisibleNotification]) {
            [[NSNotificationCenter defaultCenter] addObserverForName:event object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
                NCDiscoverSettings();
            }];
        }
        NCLog(@"settings_discovery_started", @{
            @"rn_page_class_available":@(NSClassFromString(@"NMRCTPageViewController") != Nil),
            @"rn_base_class_available":@(NSClassFromString(@"NEReactViewController") != Nil)
        });
    });
    NCDiscoverSettings();
}
