#import "NCAdShield.h"
#import "NCMenuGeometry.h"
#import "NCNativeStyle.h"
#import <objc/message.h>
#include <math.h>
#include <string.h>

@interface NCNativeMenuButton : UIButton
@property(nonatomic, strong) UIImageView *arrow;
@property(nonatomic) CGFloat titleInset;
@end
@implementation NCNativeMenuButton
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [self setTitle:@"music163_cads" forState:UIControlStateNormal];
        self.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        self.titleInset = 16;
        self.arrow = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
        self.arrow.contentMode = UIViewContentModeScaleAspectFit;
        self.arrow.tintColor = [UIColor tertiaryLabelColor];
        [self addSubview:self.arrow];
        self.accessibilityLabel = @"music163_cads 广告屏蔽设置";
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.titleLabel.frame = CGRectMake(self.titleInset, 0, MAX(0, self.bounds.size.width - self.titleInset - 38), self.bounds.size.height);
    self.arrow.frame = CGRectMake(self.bounds.size.width - 24, (self.bounds.size.height - 18) / 2, 12, 18);
}
@end

@interface NCMenuRowState : NSObject
@property(nonatomic, weak) UIViewController *owner;
@property(nonatomic, weak) UIView *wrapper;
@property(nonatomic, weak) UIScrollView *scroll;
@property(nonatomic, weak) UIView *content;
@property(nonatomic, weak) UIView *card;
@property(nonatomic, weak) UIView *label;
@property(nonatomic, strong) NCNativeMenuButton *button;
@property(nonatomic) CGFloat shift;
@property(nonatomic) BOOL active;
@property(nonatomic) BOOL busy;
@end
@implementation NCMenuRowState
@end

static char menuOwnerKey, menuWrapperKey, menuContentKey;
static BOOL layoutHooksReady;

static void NCPrepareRowForWrapper(UIView *wrapper) {
    static BOOL preparing;
    if (preparing || ![NSThread isMainThread] || objc_getAssociatedObject(wrapper, &menuWrapperKey)) return;
    preparing = YES;
    @try {
        UIResponder *responder = wrapper;
        for (NSUInteger i = 0; responder && i < 32; i++, responder = responder.nextResponder) {
            if ([responder isKindOfClass:[UIViewController class]] &&
                NCEnsureSettingsEntry((UIViewController *)responder)) break;
        }
    } @finally { preparing = NO; }
}

static id NCReadObjectGetter(id object, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    Method method = class_getInstanceMethod([object class], sel);
    if (!NCSignature(method, "@", @[])) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, sel);
}

static NSAttributedString *NCTextStorage(UIView *view) {
    if (![NSStringFromClass([view class]) hasPrefix:@"RCTText"]) return nil;
    Ivar ivar = class_getInstanceVariable([view class], "_textStorage");
    if (!ivar || ivar_getTypeEncoding(ivar)[0] != '@') return nil;
    id value = object_getIvar(view, ivar);
    return [value isKindOfClass:[NSAttributedString class]] ? value : nil;
}

static NSString *NCStaticText(UIView *view) {
    if ([view isKindOfClass:[UILabel class]]) return [(UILabel *)view text];
    if ([NSStringFromClass([view class]) hasPrefix:@"RCTText"])
        return view.accessibilityLabel ?: NCTextStorage(view).string;
    return nil;
}

static UIView *NCAccountLabel(UIView *root) {
    NSMutableArray *pending = [NSMutableArray arrayWithObject:root];
    NSUInteger scanned = 0;
    while (pending.count && scanned++ < 2400) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        if (view.hidden || view.alpha < 0.01) continue;
        if ([NCStaticText(view) isEqualToString:@"账号与安全"]) return view;
        [pending addObjectsFromArray:view.subviews];
    }
    return nil;
}

static CGFloat NCCornerRadius(UIView *view) {
    SEL sel = NSSelectorFromString(@"borderRadius");
    Method method = class_getInstanceMethod([view class], sel);
    if (NCSignature(method, "d", @[])) {
        double radius = ((double (*)(id, SEL))objc_msgSend)(view, sel);
        if (radius >= 0 && radius <= 32) return radius;
    }
    return view.layer.cornerRadius;
}

static UIView *NCAccountCard(UIView *label, UIView *content, UIScrollView *scroll) {
    UIView *best = nil;
    CGFloat score = -CGFLOAT_MAX;
    for (UIView *v = label.superview; v && v != content; v = v.superview) {
        CGFloat h = v.bounds.size.height, w = v.bounds.size.width;
        if (h < 32 || h > 96 || w < scroll.bounds.size.width * 0.7) continue;
        CGFloat alpha = v.backgroundColor ? CGColorGetAlpha(v.backgroundColor.CGColor) : 0;
        CGFloat candidate = (alpha > 0.01 ? 100 : 0) + (NCCornerRadius(v) > 0 ? 30 : 0) +
                            (w < scroll.bounds.size.width - 8 ? 10 : 0) - fabs(h - 48) / 10;
        if (candidate > score) { best = v; score = candidate; }
    }
    return best;
}

static void NCStyleMenu(NCMenuRowState *state) {
    UIView *card = state.card, *label = state.label;
    NCNativeMenuButton *button = state.button;
    NSAttributedString *storage = NCTextStorage(label);
    NSDictionary *attributes = storage.length ? [storage attributesAtIndex:0 effectiveRange:NULL] : @{};
    UIFont *font = attributes[NSFontAttributeName];
    UIColor *color = attributes[NSForegroundColorAttributeName];
    if ([label isKindOfClass:[UILabel class]]) { font = [(UILabel *)label font]; color = [(UILabel *)label textColor]; }
    button.titleLabel.font = font ?: [UIFont systemFontOfSize:17];
    [button setTitleColor:color ?: [UIColor labelColor] forState:UIControlStateNormal];
    button.backgroundColor = card.backgroundColor ?: [UIColor secondarySystemGroupedBackgroundColor];
    button.layer.cornerRadius = MAX(0, NCCornerRadius(card));
    button.layer.masksToBounds = YES;
    CGRect labelRect = [label convertRect:label.bounds toView:card];
    button.titleInset = labelRect.origin.x >= 8 && labelRect.origin.x <= 36 ? labelRect.origin.x : 16;
    NSMutableArray *pending = [NSMutableArray arrayWithObject:card];
    while (pending.count) {
        UIView *v = pending.lastObject;
        [pending removeLastObject];
        if ([v isKindOfClass:[UIImageView class]] && v.bounds.size.width <= 26 && v.bounds.size.height <= 30) {
            CGRect imageRect = [v convertRect:v.bounds toView:card];
            UIImage *image = [(UIImageView *)v image];
            if (image && imageRect.origin.x > card.bounds.size.width * 0.75) {
                button.arrow.image = image;
                button.arrow.tintColor = v.tintColor;
                break;
            }
        }
        [pending addObjectsFromArray:v.subviews];
    }
}


static NSDictionary *NCNativeTextAttributes(UIView *view) {
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        return @{NSFontAttributeName:label.font, NSForegroundColorAttributeName:label.textColor ?: [UIColor labelColor]};
    }
    NSAttributedString *text = NCTextStorage(view);
    return text.length ? [text attributesAtIndex:0 effectiveRange:NULL] : @{};
}

NCNativeStyle *NCCaptureNativeStyle(UIViewController *owner) {
    NCNativeStyle *style = [NCNativeStyle new];
    if (!owner.isViewLoaded) return style;
    NCMenuRowState *state = objc_getAssociatedObject(owner, &menuOwnerKey);
    UIView *card = state.card, *label = state.label;
    if (!card || !label) return style;
    NSDictionary *attributes = NCNativeTextAttributes(label);
    UIFont *font = attributes[NSFontAttributeName];
    UIColor *color = attributes[NSForegroundColorAttributeName];
    if ([font isKindOfClass:[UIFont class]]) style.rowFont = font;
    if ([color isKindOfClass:[UIColor class]]) style.textColor = color;
    style.titleColor = style.textColor;
    style.secondaryFont = [UIFont systemFontOfSize:MAX(11, style.rowFont.pointSize - 3)];
    if (card.backgroundColor && CGColorGetAlpha(card.backgroundColor.CGColor) > 0.9) style.cardColor = card.backgroundColor;
    for (UIView *v = state.content; v; v = v.superview) {
        if (v.backgroundColor && CGColorGetAlpha(v.backgroundColor.CGColor) > 0.9) { style.pageColor = v.backgroundColor; break; }
        if (v == owner.view) break;
    }
    if (card.bounds.size.height >= 32 && card.bounds.size.height <= 96) style.rowHeight = card.bounds.size.height;
    CGRect cardRect = [card convertRect:card.bounds toView:owner.view];
    if (cardRect.origin.x >= 8 && cardRect.origin.x <= 48) style.cardInset = cardRect.origin.x;
    CGRect labelRect = [label convertRect:label.bounds toView:card];
    if (labelRect.origin.x >= 8 && labelRect.origin.x <= 36) style.textInset = labelRect.origin.x;
    style.trailingInset = style.textInset;
    style.cornerRadius = MAX(0, NCCornerRadius(card));
    style.rowArrow = state.button.arrow.image;
    style.arrowColor = state.button.arrow.tintColor ?: style.arrowColor;

    NSMutableArray *pending = [NSMutableArray arrayWithObject:owner.view];
    NSMutableArray *visible = [NSMutableArray array];
    UIView *title = nil;
    for (NSUInteger scanned = 0; pending.count && scanned < 2400; scanned++) {
        UIView *v = pending.lastObject;
        [pending removeLastObject];
        if (v.hidden || v.alpha < 0.01) continue;
        [visible addObject:v];
        NSString *text = NCStaticText(v);
        if ([text isEqualToString:@"设置"]) title = v;
        if ([text isEqualToString:@"播放与下载"]) {
            for (UIView *group = v.superview; group && group != owner.view; group = group.superview) {
                if (group.bounds.size.width < card.bounds.size.width * 0.9 || group.bounds.size.height < style.rowHeight*1.5) continue;
                if (!group.backgroundColor || CGColorGetAlpha(group.backgroundColor.CGColor) < 0.9) continue;
                CGRect groupRect = [group convertRect:group.bounds toView:owner.view];
                CGFloat gap = groupRect.origin.y - CGRectGetMaxY(cardRect);
                if (gap >= 8 && gap <= 32) style.groupGap = gap;
                break;
            }
        }
        if ([text isEqualToString:@"未开启"]) {
            UIColor *secondary = NCNativeTextAttributes(v)[NSForegroundColorAttributeName];
            if ([secondary isKindOfClass:[UIColor class]]) style.secondaryColor = secondary;
            UIFont *valueFont = NCNativeTextAttributes(v)[NSFontAttributeName];
            if ([valueFont isKindOfClass:[UIFont class]]) style.valueFont = valueFont;
        }
        [pending addObjectsFromArray:v.subviews];
    }
    if (title) {
        UIFont *titleFont = NCNativeTextAttributes(title)[NSFontAttributeName];
        if ([titleFont isKindOfClass:[UIFont class]]) style.titleFont = titleFont;
        UIColor *titleColor = NCNativeTextAttributes(title)[NSForegroundColorAttributeName];
        if ([titleColor isKindOfClass:[UIColor class]]) style.titleColor = titleColor;
        UIView *navigation = nil;
        for (UIView *v = title.superview; v && v != owner.view; v = v.superview) {
            if (v.bounds.size.width >= owner.view.bounds.size.width * 0.7 &&
                v.bounds.size.height >= 32 && v.bounds.size.height <= 64) { navigation = v; break; }
        }
        if (navigation) {
            style.navigationHeight = navigation.bounds.size.height;
            CGRect headerRect = [navigation convertRect:navigation.bounds toView:owner.view];
            // Use the injected row's original top position, before the account row's shift.
            CGFloat rowTop = [state.button convertRect:state.button.bounds toView:owner.view].origin.y;
            CGFloat gap = rowTop - CGRectGetMaxY(headerRect);
            if (gap >= 0 && gap <= 24) style.topGap = gap;
        }
        CGRect titleRect = [title convertRect:title.bounds toView:owner.view];
        UIView *back = nil;
        CGFloat score = -CGFLOAT_MAX;
        for (UIView *v in visible) {
            CGRect r = [v convertRect:v.bounds toView:owner.view];
            if (r.origin.x < 4 || r.origin.x > 44 || r.size.width < 8 || r.size.width > 32 ||
                r.size.height < 10 || r.size.height > 32 || fabs(CGRectGetMidY(r)-CGRectGetMidY(titleRect)) > 10) continue;
            NSString *className = NSStringFromClass([v class]);
            BOOL image = [v isKindOfClass:[UIImageView class]] && [(UIImageView *)v image];
            BOOL vector = [className containsString:@"SVG"] || [className containsString:@"Svg"];
            if (!image && !vector) continue;
            CGFloat candidate = (image ? 100 : 50) - fabs(r.size.width-24);
            if (candidate > score) { score = candidate; back = v; }
        }
        if (back) {
            CGRect r = [back convertRect:back.bounds toView:owner.view];
            style.backLeading = r.origin.x; style.backSize = r.size;
            UIGraphicsBeginImageContextWithOptions(back.bounds.size, NO, 0);
            CGContextRef context = UIGraphicsGetCurrentContext();
            if (context) [back.layer renderInContext:context];
            style.backImage = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
        }
    }
    NCLog(@"native_panel_style", @{@"row_height":@(style.rowHeight), @"font_size":@(style.rowFont.pointSize),
                                   @"card_inset":@(style.cardInset), @"text_inset":@(style.textInset),
                                   @"navigation_height":@(style.navigationHeight)});
    return style;
}

static void NCLayoutMenu(NCMenuRowState *state) {
    if (!state.active || state.busy || !state.content || !state.scroll || !state.owner) return;
    if (!NCIsSettingsController(state.owner)) { NCHideMenuRow(state.owner); return; }
    UIView *content = state.content;
    if (!CGAffineTransformIsIdentity(content.transform) &&
        !CGAffineTransformEqualToTransform(content.transform, CGAffineTransformMakeTranslation(0, state.shift))) {
        state.button.hidden = YES;
        return;
    }
    if (state.card && [state.card isDescendantOfView:content]) {
        CGRect cardFrame = [state.card convertRect:state.card.bounds toView:state.scroll];
        NCMenuGeometry geometry;
        CGFloat previousShift = content.transform.ty;
        if (!NCMenuGeometryCompute(cardFrame.origin.y, previousShift, cardFrame.size.height, 16,
                                   content.bounds.size.height, &geometry)) return;
        state.busy = YES;
        [UIView performWithoutAnimation:^{
            state.shift = geometry.shift;
            content.transform = CGAffineTransformMakeTranslation(0, state.shift);
            CGRect frame = cardFrame;
            frame.origin.y = geometry.rowY;
            state.button.frame = frame;
            NCStyleMenu(state);
            [state.button setNeedsLayout];
        }];
        state.busy = NO;
    }
    state.button.hidden = NO;
    [state.scroll bringSubviewToFront:state.button];
}

void NCHideMenuRow(UIViewController *controller) {
    NCMenuRowState *state = objc_getAssociatedObject(controller, &menuOwnerKey);
    if (!state || !state.active) return;
    state.active = NO;
    if (CGAffineTransformEqualToTransform(state.content.transform, CGAffineTransformMakeTranslation(0, state.shift)))
        state.content.transform = CGAffineTransformIdentity;
    state.button.hidden = YES;
    state.shift = 0;
    id wrapper = state.wrapper;
    SEL update = NSSelectorFromString(@"updateContentSizeIfNeeded");
    if (NCSignature(class_getInstanceMethod([wrapper class], update), "v", @[]))
        ((void (*)(id, SEL))objc_msgSend)(wrapper, update);
}

BOOL NCPlaceMenuRow(UIViewController *controller, id target, SEL action) {
    if (!layoutHooksReady) return NO;
    NCMenuRowState *state = objc_getAssociatedObject(controller, &menuOwnerKey);
    if (state.content && state.scroll && state.content.superview == state.scroll) {
        if (!state.card || ![state.card isDescendantOfView:state.content]) {
            UIView *label = NCAccountLabel(controller.view);
            UIView *card = label ? NCAccountCard(label, state.content, state.scroll) : nil;
            if (card) { state.card = card; state.label = label; }
        }
        state.active = YES;
        NCLayoutMenu(state);
        return state.shift > 0;
    }
    UIView *label = NCAccountLabel(controller.view);
    if (!label) return NO;
    UIScrollView *scroll = nil;
    for (UIView *v = label.superview; v && v != controller.view; v = v.superview)
        if ([v isKindOfClass:[UIScrollView class]]) { scroll = (UIScrollView *)v; break; }
    if (!scroll) return NO;
    UIView *wrapper = scroll.superview;
    Class rct = NSClassFromString(@"RCTScrollView");
    if (!rct || ![wrapper isKindOfClass:rct]) return NO;
    id contentObject = NCReadObjectGetter(wrapper, @"contentView");
    if (![contentObject isKindOfClass:[UIView class]]) return NO;
    UIView *content = contentObject;
    if (content.superview != scroll || ![label isDescendantOfView:content] ||
        !CGAffineTransformIsIdentity(content.transform)) return NO;
    UIView *card = NCAccountCard(label, content, scroll);
    if (!card) return NO;
    // This mechanism moves the list body only. Refuse a structure containing an unrelated header above it.
    CGRect logicalCard = [card convertRect:card.bounds toView:content];
    if (logicalCard.origin.y < -1 || logicalCard.origin.y > card.bounds.size.height) return NO;
    state = [NCMenuRowState new];
    state.owner = controller; state.wrapper = wrapper; state.content = content;
    state.scroll = scroll; state.card = card; state.label = label;
    state.button = [[NCNativeMenuButton alloc] initWithFrame:CGRectZero];
    [state.button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    state.active = YES;
    objc_setAssociatedObject(controller, &menuOwnerKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(wrapper, &menuWrapperKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(content, &menuContentKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [scroll addSubview:state.button];
    NCLayoutMenu(state);
    SEL update = NSSelectorFromString(@"updateContentSizeIfNeeded");
    ((void (*)(id, SEL))objc_msgSend)(wrapper, update);
    CGRect actual = [card convertRect:card.bounds toView:scroll];
    NCLog(@"settings_native_row", @{@"class":NSStringFromClass([controller class]),
                                    @"height":@(state.button.bounds.size.height), @"shift":@(state.shift),
                                    @"gap_to_account":@(actual.origin.y - CGRectGetMaxY(state.button.frame))});
    NCSetStatus(@"settings", @"菜单已插入账号与安全上方");
    return state.shift > 0;
}

void NCInstallMenuLayoutHooks(void) {
    Class cls = NSClassFromString(@"RCTScrollView");
    SEL sizeSelector = NSSelectorFromString(@"contentSize");
    Method sizeMethod = class_getInstanceMethod(cls, sizeSelector);
    char returnType[128] = {0};
    if (sizeMethod) method_getReturnType(sizeMethod, returnType, sizeof(returnType));
    if (!cls || !sizeMethod || strcmp(returnType, "{CGSize=dd}") || method_getNumberOfArguments(sizeMethod) != 2) return;
    if (!NCHasHook(cls, sizeSelector)) {
        IMP original = method_getImplementation(sizeMethod);
        IMP replacement = imp_implementationWithBlock(^CGSize(id wrapper) {
            CGSize size = ((CGSize (*)(id, SEL))original)(wrapper, sizeSelector);
            NCMenuRowState *state = objc_getAssociatedObject(wrapper, &menuWrapperKey);
            if (state.active) size.height += state.shift;
            return size;
        });
        if (!NCReplace(cls, sizeSelector, original, replacement, NO)) { imp_removeBlock(replacement); return; }
    }
    for (NSString *name in @[@"layoutSubviews", @"updateContentSizeIfNeeded"]) {
        SEL sel = NSSelectorFromString(name);
        Method method = class_getInstanceMethod(cls, sel);
        if (NCHasHook(cls, sel)) continue;
        if (!NCOwnMethod(cls, sel) || !NCSignature(method, "v", @[])) return;
        IMP original = method_getImplementation(method);
        IMP replacement = imp_implementationWithBlock(^(id wrapper) {
            NCPrepareRowForWrapper(wrapper);
            NCMenuRowState *state = objc_getAssociatedObject(wrapper, &menuWrapperKey);
            if (state.active) NCLayoutMenu(state);
            ((void (*)(id, SEL))original)(wrapper, sel);
            NCPrepareRowForWrapper(wrapper);
            state = objc_getAssociatedObject(wrapper, &menuWrapperKey);
            if (state.active) NCLayoutMenu(state);
        });
        if (!NCReplace(cls, sel, original, replacement, NO)) { imp_removeBlock(replacement); return; }
    }
    layoutHooksReady = YES;
}
