#import "NCAdShield.h"
#include <stdlib.h>
#include <string.h>

static NSMutableSet<NSString *> *installed;

static NSString *NCHookKey(Class cls, SEL selector) {
    return [NSString stringWithFormat:@"%p/%@", cls, NSStringFromSelector(selector)];
}

BOOL NCHasHook(Class cls, SEL selector) { return [installed containsObject:NCHookKey(cls, selector)]; }

BOOL NCOwnMethod(Class cls, SEL selector) {
    unsigned count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    BOOL found = NO;
    for (unsigned i = 0; i < count; i++) {
        if (sel_isEqual(method_getName(methods[i]), selector)) { found = YES; break; }
    }
    free(methods);
    return found;
}

static const char *NCUnqualified(const char *type) {
    while (*type && strchr("rnNoORV", *type)) type++;
    return type;
}

BOOL NCSignature(Method method, const char *returns, NSArray<NSString *> *arguments) {
    if (!method || method_getNumberOfArguments(method) != arguments.count + 2) return NO;
    char type[256] = {0};
    method_getReturnType(method, type, sizeof(type));
    const char *result = NCUnqualified(type);
    if (!*result || !strchr(returns, *result)) return NO;
    for (NSUInteger i = 0; i < arguments.count; i++) {
        memset(type, 0, sizeof(type));
        method_getArgumentType(method, (unsigned)i + 2, type, sizeof(type));
        const char *actual = NCUnqualified(type);
        const char *expected = arguments[i].UTF8String;
        if (strcmp(expected, "@") == 0) {
            if (*actual != '@' || actual[1] == '?') return NO;
        } else if (strcmp(expected, "B") == 0) {
            if (*actual != 'B' && *actual != 'c') return NO;
        } else if (strcmp(actual, expected) != 0) {
            return NO;
        }
    }
    return YES;
}

BOOL NCReplace(Class cls, SEL selector, IMP original, IMP replacement, BOOL allowInherited) {
    NSCAssert([NSThread isMainThread], @"Install hooks only on the main queue");
    if (!cls || !original || !replacement || NCHasHook(cls, selector)) return NO;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getImplementation(method) != original) return NO;
    BOOL owned = NCOwnMethod(cls, selector);
    if (!owned && !allowInherited) return NO;
    if (owned) {
        method_setImplementation(method, replacement);
    } else if (!class_addMethod(cls, selector, replacement, method_getTypeEncoding(method))) {
        return NO;
    }
    if (!installed) installed = [NSMutableSet set];
    [installed addObject:NCHookKey(cls, selector)];
    return YES;
}
