#import "NCAdShield.h"
#import "NCHomePolicy.h"
#import <objc/message.h>
#include <stdatomic.h>

// The recommendation page's filter is called before component construction for
// cache, network, and single-block rebuilds. Returning YES uses the App's own
// skip path; response arrays, pagination, caches, and template files stay intact.
static id NCHomeObject(id object, NSString *name) {
    if (!object) return nil;
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod([object class], selector);
    if (!NCSignature(method, "@", @[])) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static BOOL NCHomeMusicNode(NSDictionary *node) {
    id type = node[@"resourceType"];
    return [type isKindOfClass:[NSString class]] && NCHomeMusicResource([type UTF8String]);
}

static unsigned NCHomeEvidence(id value, NSUInteger depth, NSUInteger *remaining) {
    if (!value || depth > 12 || !*remaining) return 0;
    --*remaining;
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSDictionary *node = value;
        // Never inspect song/playlist metadata, even when it mentions a campaign.
        if (NCHomeMusicNode(node)) return 0;
        unsigned reason = 0;
        NSArray *fields = @[@"title", @"text", @"subTitle", @"subtitle", @"showTitle", @"label", @"tagText", @"name",
                            @"adTag", @"adTagText", @"adLabel", @"resourceType", @"creativeType"];
        for (NSString *field in fields) {
            id text = node[field];
            if ([text isKindOfClass:[NSString class]] && [text length] <= 512)
                reason |= NCHomeTextEvidence(field.UTF8String, [text UTF8String]);
        }
        if (reason) return reason;
        // Template text, CSS, lyrics, and URLs are not runtime ad evidence.
        NSSet *skip = [NSSet setWithArray:@[@"crossPlatformConfig", @"dslContent", @"dslMap", @"rnContent", @"nativeContent",
                       @"databinding", @"css", @"json", @"lyrics", @"lyric", @"comments", @"log", @"logMap"]];
        for (id key in node) {
            if (![key isKindOfClass:[NSString class]] || [skip containsObject:key]) continue;
            id child = node[key];
            if ([child isKindOfClass:[NSDictionary class]] || [child isKindOfClass:[NSArray class]]) {
                reason |= NCHomeEvidence(child, depth + 1, remaining);
            } else if ([child isKindOfClass:[NSString class]] &&
                       [@[@"dslData", @"rnData", @"nativeData"] containsObject:key] && [child length] <= 128 * 1024) {
                NSData *json = [child dataUsingEncoding:NSUTF8StringEncoding];
                if (json) reason |= NCHomeEvidence([NSJSONSerialization JSONObjectWithData:json options:0 error:NULL], depth + 1, remaining);
            }
            if (reason || !*remaining) break;
        }
        return reason;
    }
    if ([value isKindOfClass:[NSArray class]]) {
        for (id child in (NSArray *)value) {
            unsigned reason = NCHomeEvidence(child, depth + 1, remaining);
            if (reason) return reason;
            if (!*remaining) break;
        }
    }
    return 0;
}

static unsigned NCHomeBuilderEvidence(id builder) {
    NSUInteger remaining = 512;
    id model = NCHomeObject(builder, @"model");
    id origin = NCHomeObject(model, @"originData");
    unsigned reason = NCHomeEvidence(origin, 0, &remaining);
    if (!reason) reason = NCHomeEvidence(NCHomeObject(builder, @"data"), 0, &remaining);
    return reason;
}

void NCInstallHomePromotionHooks(void) {
    Class cls = NSClassFromString(@"NMRcmdHomeViewController");
    SEL selector = NSSelectorFromString(@"mixedLayoutViewController:filterComponentWithBuilder:");
    if (!cls || NCHasHook(cls, selector) || !NCOwnMethod(cls, selector)) return;
    Method method = class_getInstanceMethod(cls, selector);
    if (!NCSignature(method, "B", @[@"@", @"@"])) return;
    IMP original = method_getImplementation(method);
    IMP replacement = imp_implementationWithBlock(^BOOL(id page, id layout, id builder) {
        BOOL nativeDecision = ((BOOL (*)(id, SEL, id, id))original)(page, selector, layout, builder);
        BOOL enabled = NCEnabled(@"banner");
        if (nativeDecision || !enabled) {
            return nativeDecision;
        }
        unsigned reason = 0;
        @try {
            reason = NCHomeBuilderEvidence(builder);
        } @catch (NSException *exception) {
            NCLog(@"home_promotion_read_failed", @{@"name":exception.name ?: @"unknown"});
            return nativeDecision;
        }
        if (!reason) return nativeDecision;
        static atomic_uint reports;
        if (atomic_fetch_add_explicit(&reports, 1, memory_order_relaxed) < 64) {
            SEL fromCache = NSSelectorFromString(@"fromCache");
            Method getter = class_getInstanceMethod([builder class], fromCache);
            BOOL cached = NCSignature(getter, "B", @[]) && ((BOOL (*)(id, SEL))objc_msgSend)(builder, fromCache);
            NCLog(@"home_promotion_filtered", @{@"reason":@(reason), @"from_cache":@(cached)});
        }
        return YES;
    });
    if (NCReplace(cls, selector, original, replacement, NO)) {
        NCRecordHook(@"banner");
        NCLog(@"hook_installed", @{@"module":@"banner", @"class":NSStringFromClass(cls),
                                   @"selector":NSStringFromSelector(selector), @"types":@(method_getTypeEncoding(method))});
    } else imp_removeBlock(replacement);
}
