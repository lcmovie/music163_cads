#import "NCAdShield.h"
#import <UserNotifications/UserNotifications.h>
#include <stdlib.h>

@interface NCAdViewState : NSObject
@property(nonatomic, copy) NSString *module;
@property(nonatomic) BOOL previousHidden;
@property(nonatomic) BOOL applied;
@property(nonatomic, copy) void (^replay)(void);
@end
@implementation NCAdViewState
@end

static char viewStateKey;
static NSHashTable<UIView *> *observedViews;

static NCAdViewState *NCViewState(UIView *view, NSString *module) {
    NCAdViewState *state = objc_getAssociatedObject(view, &viewStateKey);
    if (!state) {
        state = [NCAdViewState new];
        state.module = module;
        objc_setAssociatedObject(view, &viewStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!observedViews) observedViews = [NSHashTable weakObjectsHashTable];
        [observedViews addObject:view];
    }
    return state;
}

static void NCHideAdView(UIView *view, NCAdViewState *state) {
    if (!state.applied) { state.previousHidden = view.hidden; state.applied = YES; }
    view.hidden = YES;
}

void NCRefreshAdViews(void) {
    NSCAssert([NSThread isMainThread], @"Refresh views on main queue");
    for (UIView *view in observedViews.allObjects) {
        NCAdViewState *state = objc_getAssociatedObject(view, &viewStateKey);
        if (NCEnabled(state.module)) {
            if (!state.applied && [state.module isEqualToString:@"feed"]) {
                SEL pause = NSSelectorFromString(@"pause");
                Method method = class_getInstanceMethod([view class], pause);
                if (NCSignature(method, "v", @[]))
                    ((void (*)(id, SEL))method_getImplementation(method))(view, pause);
            }
            NCHideAdView(view, state);
        } else if (state.applied) {
            view.hidden = state.previousHidden;
            state.applied = NO;
            void (^replay)(void) = state.replay;
            state.replay = nil;
            if (replay) replay();
        }
    }
}

static void NCCommit(Class cls, SEL sel, Method method, IMP replacement, NSString *module) {
    if (NCReplace(cls, sel, method_getImplementation(method), replacement, NO)) {
        NCRecordHook(module);
        NCLog(@"hook_installed", @{@"module":module, @"class":NSStringFromClass(cls),
                                   @"selector":NSStringFromSelector(sel),
                                   @"types":@(method_getTypeEncoding(method))});
    } else {
        imp_removeBlock(replacement);
    }
}

// A distinct closure captures the original IMP for each class/selector pair.
// No guessed argument lists, global original pointer, model validity or tracking hooks.
static BOOL NCInstallVoid(Class cls, NSString *name, NSString *module) {
    SEL sel = NSSelectorFromString(name);
    if (!cls || NCHasHook(cls, sel) || !NCOwnMethod(cls, sel)) return NO;
    Method method = class_getInstanceMethod(cls, sel);
    IMP original = method_getImplementation(method);
    IMP replacement = NULL;
    if (NCSignature(method, "v", @[])) {
        replacement = imp_implementationWithBlock(^(id object) {
            if (!NCEnabled(module)) ((void (*)(id, SEL))original)(object, sel);
        });
    } else if (NCSignature(method, "v", @[@"@"])) {
        replacement = imp_implementationWithBlock(^(id object, id argument) {
            BOOL enabled = NCEnabled(module);
            if (([name isEqualToString:@"setAd:"] || [name isEqualToString:@"setAdvertisement:"]) &&
                [object isKindOfClass:[UIView class]]) {
                if (![NSThread isMainThread]) {
                    ((void (*)(id, SEL, id))original)(object, sel, argument);
                    return;
                }
                UIView *view = object;
                NCAdViewState *state = NCViewState(view, module);
                if (enabled) {
                    __weak UIView *weakView = view;
                    state.replay = ^{
                        UIView *strongView = weakView;
                        if (strongView) ((void (*)(id, SEL, id))original)(strongView, sel, argument);
                    };
                    NCHideAdView(view, state);
                    return;
                }
                state.replay = nil;
                if (state.applied) { view.hidden = state.previousHidden; state.applied = NO; }
            }
            if (!enabled) ((void (*)(id, SEL, id))original)(object, sel, argument);
        });
    } else if (NCSignature(method, "v", @[@"@", @"@"])) {
        replacement = imp_implementationWithBlock(^(id object, id first, id second) {
            if (!NCEnabled(module)) ((void (*)(id, SEL, id, id))original)(object, sel, first, second);
        });
    }
    if (!replacement) {
        NCLog(@"signature_skipped", @{@"module":module, @"class":NSStringFromClass(cls),
                                      @"selector":name, @"types":@(method_getTypeEncoding(method))});
        return NO;
    }
    NCCommit(cls, sel, method, replacement, module);
    return NCHasHook(cls, sel);
}

static void NCInstallBoolean(Class cls, NSString *name, NSString *module, BOOL blockedValue) {
    SEL sel = NSSelectorFromString(name);
    if (!cls || NCHasHook(cls, sel) || !NCOwnMethod(cls, sel)) return;
    Method method = class_getInstanceMethod(cls, sel);
    if (!NCSignature(method, "Bc", @[])) return;
    IMP original = method_getImplementation(method);
    IMP replacement = imp_implementationWithBlock(^BOOL(id object) {
        return NCEnabled(module) ? blockedValue : ((BOOL (*)(id, SEL))original)(object, sel);
    });
    NCCommit(cls, sel, method, replacement, module);
}

static void NCInstallPush(void) {
    Class cls = [UNUserNotificationCenter class];
    SEL sel = @selector(requestAuthorizationWithOptions:completionHandler:);
    if (NCHasHook(cls, sel)) return;
    Method method = class_getInstanceMethod(cls, sel);
    if (!NCOwnMethod(cls, sel) || !NCSignature(method, "v", @[@"Q", @"@?"])) return;
    IMP original = method_getImplementation(method);
    IMP replacement = imp_implementationWithBlock(^(id object, UNAuthorizationOptions options, void (^handler)(BOOL, NSError *)) {
        if (NCEnabled(@"push")) {
            if (handler) dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{ handler(NO, nil); });
        } else {
            ((void (*)(id, SEL, UNAuthorizationOptions, void (^)(BOOL, NSError *)))original)(object, sel, options, handler);
        }
    });
    NCCommit(cls, sel, method, replacement, @"push");
}

static void NCInstallViewGroup(NSString *module, NSArray<NSString *> *names) {
    for (NSString *name in names) NCInstallVoid(NSClassFromString(name), @"setAd:", module);
}

// Dedicated ad views can be Swift classes without any ObjC show/setAd method.
// Add an override on that class only; never modify UIView's implementation.
static void NCInstallAdViewLifecycle(Class cls, NSString *module) {
    if (!cls || ![cls isSubclassOfClass:[UIView class]]) return;
    for (NSString *name in @[@"didMoveToWindow", @"layoutSubviews"]) {
        SEL sel = NSSelectorFromString(name);
        if (NCHasHook(cls, sel)) continue;
        Method method = class_getInstanceMethod(cls, sel);
        if (!NCSignature(method, "v", @[])) continue;
        IMP original = method_getImplementation(method);
        IMP replacement = imp_implementationWithBlock(^(UIView *view) {
            ((void (*)(id, SEL))original)(view, sel);
            if (![NSThread isMainThread]) return;
            NCAdViewState *state = NCViewState(view, module);
            if (NCEnabled(module)) NCHideAdView(view, state);
            else if (state.applied) { view.hidden = state.previousHidden; state.applied = NO; }
        });
        if (NCReplace(cls, sel, original, replacement, YES)) {
            NCRecordHook(module);
            NCLog(@"ad_view_lifecycle", @{@"class":NSStringFromClass(cls), @"selector":name, @"module":module});
        } else imp_removeBlock(replacement);
    }
}

static void NCInstallAdvertisementView(NSString *name, NSString *module) {
    Class cls = NSClassFromString(name);
    NCInstallVoid(cls, @"setAdvertisement:", module);
    NCInstallAdViewLifecycle(cls, module);
}

static void NCInstallFeedPlayer(void) {
    Class cls = NSClassFromString(@"NMSquareAdvertisementCell");
    SEL sel = NSSelectorFromString(@"setPlayer:autoPlayWhenReady:");
    Method method = class_getInstanceMethod(cls, sel);
    if (!cls || NCHasHook(cls, sel) || !NCOwnMethod(cls, sel) || !NCSignature(method, "v", @[@"@", @"B"])) return;
    IMP original = method_getImplementation(method);
    IMP replacement = imp_implementationWithBlock(^(id object, id player, BOOL autoplay) {
        if (NCEnabled(@"feed")) return;
        ((void (*)(id, SEL, id, BOOL))original)(object, sel, player, autoplay);
    });
    NCCommit(cls, sel, method, replacement, @"feed");
    NCInstallVoid(cls, @"setPlayer:", @"feed");
    NCInstallVoid(cls, @"play", @"feed");
}

void NCInstallAdHooks(void) {
    NCPrepareLaunchHooks();
    NCReportLaunchHooks();
    NCInstallHomePromotionHooks();
    NCInstallViewGroup(@"banner", @[@"NMAdvertisementGXCardView", @"NMAdvertisementGXCardViewCell",
                                  @"NMAdvertisementAdHeaderView", @"NMAdvertisementBtView"]);
    NCInstallViewGroup(@"feed", @[@"NMSquareAdvertisementCell"]);
    NCInstallAdvertisementView(@"NMSquareAdvertisementCell", @"feed");
    NCInstallFeedPlayer();
    NCInstallViewGroup(@"search", @[@"NMSearchAdvertisementCell", @"NMSearchHomeAdCollectionViewCell", @"RNSearchAdView"]);
    NCInstallViewGroup(@"comment", @[@"NMAdvertisementCommentCell"]);
    for (NSString *name in @[@"NMSearchAdvertisementCell", @"NMSearchHomeAdCollectionViewCell"])
        NCInstallAdvertisementView(name, @"search");
    NCInstallAdvertisementView(@"NMAdvertisementCommentCell", @"comment");
    NCInstallViewGroup(@"podcast", @[@"NMRCTPodcastAdView", @"NMRCTVoiceAdView"]);
    NCInstallVoid(NSClassFromString(@"NMRNSongShareAdViewManager"), @"requestAd:contentView:", @"share");
    NCInstallVoid(NSClassFromString(@"NMAdvertisementAdIncentiveManager"), @"showIncentiveAdWithUrl:", @"incentive");
    NCInstallViewGroup(@"incentive", @[@"NMAdIncentiveTopHintView", @"NMAdIncentiveBottomHintView"]);
    NCInstallPush();
    // This configuration belongs to the gift-panel promotion banner, not to ordinary gifts.
    NCInstallBoolean(NSClassFromString(@"NMLGiftPanelBannerConfig"), @"isValid", @"live", NO);
    for (NSString *name in @[@"NMSettingTabViewController", @"NMPrivacySettingViewController"])
        NCInstallBoolean(NSClassFromString(name), @"hasRequestNotificationPermission", @"push", YES);

    NSArray *guides = @[@"NMGeneralPromotionPopupManager", @"NMPushGuideHintView", @"PushPopGuideView", @"OpenPushGuideAlert",
                       @"NMAdLaxinGuidePopupView", @"NMAdMiniBarGuideView", @"NMAdMiniBarGuideManager",
                       @"NMAppGuideView", @"NMBubbleGuideView", @"NMAppAnimatedGuideView"];
    for (NSString *name in guides) {
        Class cls = NSClassFromString(name);
        for (NSString *selector in @[@"showPopup", @"showPopup:", @"show", @"showInViewController:", @"show:"]) {
            if (NCInstallVoid(cls, selector, @"guide")) break;
            if (NCInstallVoid(object_getClass(cls), selector, @"guide")) break;
        }
    }

    // Swift exposure is unknown: enumerate only the named ad component and require a real ObjC method.
    static BOOL loggedLive;
    unsigned count = 0;
    Class *classes = objc_copyClassList(&count);
    for (unsigned i = 0; i < count; i++) {
        Class cls = classes[i];
        NSString *name = NSStringFromClass(cls);
        if ([name hasSuffix:@"NMLGiftBannerContentView"] || [name hasSuffix:@"NMLLiveGiftAdHintView"])
            NCInstallAdViewLifecycle(cls, @"live");
        if (![name hasSuffix:@"NMLGiftAdvertisementPlugin"]) continue;
        if (!loggedLive) {
            unsigned methodsCount = 0;
            Method *methods = class_copyMethodList(cls, &methodsCount);
            NSMutableArray *summary = [NSMutableArray array];
            for (unsigned j = 0; j < MIN(methodsCount, 64u); j++) {
                [summary addObject:@{@"selector":NSStringFromSelector(method_getName(methods[j])),
                                     @"types":@(method_getTypeEncoding(methods[j]))}];
            }
            free(methods);
            NCLog(@"live_component_methods", @{@"class":name, @"methods":summary});
            loggedLive = YES;
        }
        for (NSString *selector in @[@"showAdvertisement", @"showAd", @"show", @"showInView:"])
            if (NCInstallVoid(cls, selector, @"live")) break;
    }
    free(classes);
}
