#import "NCAdShield.h"
#import <objc/message.h>

// Append to the same pending RN mounting batch. didPerformMounting itself runs on
// the UIManager queue in this RN version, so it is not a place to mutate UIKit.
void NCInstallMountBatchHook(void) {
    Class cls = NSClassFromString(@"RCTUIManager");
    SEL flush = NSSelectorFromString(@"flushUIBlocksWithCompletion:");
    SEL add = NSSelectorFromString(@"addUIBlock:");
    if (!cls || NCHasHook(cls, flush)) return;
    Ivar pending = class_getInstanceVariable(cls, "_pendingUIBlocks");
    const char *ivarType = pending ? ivar_getTypeEncoding(pending) : NULL;
    Method method = class_getInstanceMethod(cls, flush);
    if (!ivarType || ivarType[0] != '@' || !NCOwnMethod(cls, flush) ||
        !NCSignature(method, "v", @[@"@?"]) ||
        !NCSignature(class_getInstanceMethod(cls, add), "v", @[@"@?"])) return;
    IMP original = method_getImplementation(method);
    IMP replacement = imp_implementationWithBlock(^(id manager, void (^completion)(void)) {
        // The flush method is confined to the source App's UIManager queue.
        id blocks = object_getIvar(manager, pending);
        if ([blocks isKindOfClass:[NSArray class]] && [(NSArray *)blocks count] > 0) {
            void (^menuBlock)(id, NSDictionary *) = ^(id mountedManager, NSDictionary *registry) {
                NCSynchronizeSettingsAtMount(); // Inline on the same main-thread mounting batch.
            };
            ((void (*)(id, SEL, id))objc_msgSend)(manager, add, menuBlock);
        }
        ((void (*)(id, SEL, void (^)(void)))original)(manager, flush, completion);
    });
    if (!NCReplace(cls, flush, original, replacement, NO)) imp_removeBlock(replacement);
    else NCLog(@"settings_mount_batch_hook", @{@"same_batch":@YES});
}
