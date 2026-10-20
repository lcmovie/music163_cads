#import "NCAdShield.h"
#import "NCNativeStyle.h"
#import "NCPanelCell.h"
#import <objc/message.h>
#include <math.h>

static CGSize NCSourceSwitchSize(void) {
    Class cls = NSClassFromString(@"NMSettingSwitchCell");
    SEL width = NSSelectorFromString(@"defaultSwitchWidthForSettingCell");
    SEL height = NSSelectorFromString(@"defaultSwitchHeightForSettingCell");
    if (NCSignature(class_getClassMethod(cls, width), "d", @[]) &&
        NCSignature(class_getClassMethod(cls, height), "d", @[])) {
        double w = ((double (*)(id, SEL))objc_msgSend)(cls, width);
        double h = ((double (*)(id, SEL))objc_msgSend)(cls, height);
        if (w >= 30 && w <= 64 && h >= 18 && h <= 40) return CGSizeMake(w, h);
    }
    return CGSizeMake(51, 31); // Source sample's verified native settings dimensions.
}

@interface NCSettingsAttachment : NSObject
@property(nonatomic, weak) UIViewController *owner;
@property(nonatomic, weak) NCShieldPanel *openedPanel;
- (void)openPanel;
@end

@implementation NCSettingsAttachment
- (void)openPanel {
    UIViewController *owner = self.owner;
    if (!owner.view.window || owner.presentedViewController || self.openedPanel.parentViewController ||
        [owner.navigationController.topViewController isKindOfClass:[NCShieldPanel class]]) return;
    NCShieldPanel *panel = [NCShieldPanel new];
    panel.sourceSettingsController = owner;
    panel.hidesBottomBarWhenPushed = YES;
    self.openedPanel = panel;
    UINavigationController *navigation = owner.navigationController;
    SEL push = NSSelectorFromString(@"nm_pushViewController:animated:");
    id route = owner;
    if (!NCSignature(class_getInstanceMethod([route class], push), "v", @[@"@", @"B"])) route = navigation;
    if (NCSignature(class_getInstanceMethod([route class], push), "v", @[@"@", @"B"])) {
        panel.usesAppNavigation = YES;
        ((void (*)(id, SEL, id, BOOL))objc_msgSend)(route, push, panel, YES);
    } else if (navigation) [navigation pushViewController:panel animated:YES];
    else {
        panel.modalPresentationStyle = UIModalPresentationFullScreen;
        panel.transitioningDelegate = (id<UIViewControllerTransitioningDelegate>)panel;
        [owner presentViewController:panel animated:YES completion:nil];
    }
}
@end

static char attachmentKey;

@interface NCShieldPanel () <UITableViewDataSource, UITableViewDelegate, UIViewControllerTransitioningDelegate>
@property(nonatomic, strong) id updateObserver;
@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, strong) UIView *nativeHeader;
@property(nonatomic, strong) UILabel *nativeTitle;
@property(nonatomic, strong) UIButton *backButton;
@property(nonatomic, strong) UIImageView *backIcon;
@property(nonatomic, strong) NCNativeStyle *nativeStyle;
@property(nonatomic, strong) UIPercentDrivenInteractiveTransition *fallbackInteraction;
@property(nonatomic) BOOL changedNavigationBar;
@end

BOOL NCEnsureSettingsEntry(UIViewController *vc) {
    if (!vc.isViewLoaded || !NCIsSettingsController(vc)) return NO;
    NCSettingsAttachment *attachment = objc_getAssociatedObject(vc, &attachmentKey);
    if (!attachment) {
        attachment = [NCSettingsAttachment new];
        attachment.owner = vc;
        objc_setAssociatedObject(vc, &attachmentKey, attachment, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    __block BOOL placed = NO;
    [UIView performWithoutAnimation:^{ placed = NCPlaceMenuRow(vc, attachment, @selector(openPanel)); }];
    return placed;
}

void NCHideSettingsEntry(UIViewController *vc) {
    NCHideMenuRow(vc);
}

static BOOL NCHookSettingsLifecycle(Class cls, NSString *name, BOOL hasArgument) {
    SEL sel = NSSelectorFromString(name);
    if (NCHasHook(cls, sel)) return YES;
    Method method = class_getInstanceMethod(cls, sel);
    if (!NCSignature(method, "v", hasArgument ? @[@"B"] : @[])) return NO;
    IMP original = method_getImplementation(method);
    IMP replacement;
    if (hasArgument) {
        replacement = imp_implementationWithBlock(^(UIViewController *vc, BOOL animated) {
            ((void (*)(id, SEL, BOOL))original)(vc, sel, animated);
            NCEnsureSettingsEntry(vc);
        });
    } else {
        replacement = imp_implementationWithBlock(^(UIViewController *vc) {
            ((void (*)(id, SEL))original)(vc, sel);
            NCEnsureSettingsEntry(vc);
        });
    }
    if (NCReplace(cls, sel, original, replacement, YES)) return YES;
    imp_removeBlock(replacement);
    return NO;
}

void NCInstallSettings(void) {
    NCInstallMenuLayoutHooks();
    NCInstallMountBatchHook();
    NCInstallSettingsDiscovery();
    // The supplied binary uses a generic RN page container. moduleName filters to rn-setting.
    // SettingTab controllers also host rn-sidebar and are not sufficient evidence of a settings page.
    for (NSString *name in @[@"NMRCTPageViewController"]) {
        Class cls = NSClassFromString(name);
        if (!cls || ![cls isSubclassOfClass:[UIViewController class]]) continue;
        BOOL willAppear = NCHookSettingsLifecycle(cls, @"viewWillAppear:", YES);
        BOOL appeared = NCHookSettingsLifecycle(cls, @"viewDidAppear:", YES);
        BOOL layout = NCHookSettingsLifecycle(cls, @"viewDidLayoutSubviews", NO);
        static NSMutableSet *logged;
        if (!logged) logged = [NSMutableSet set];
        if (![logged containsObject:name]) {
            NCLog(@"settings_lifecycle_hooks", @{@"class":name, @"will_appear":@(willAppear), @"appear":@(appeared), @"layout":@(layout)});
            [logged addObject:name];
        }
    }
}

@interface NCPanelTransition : NSObject <UIViewControllerAnimatedTransitioning>
@property(nonatomic) BOOL presenting;
@end
@implementation NCPanelTransition
- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)context { return 0.3; }
- (void)animateTransition:(id<UIViewControllerContextTransitioning>)context {
    UIView *from = [context viewForKey:UITransitionContextFromViewKey];
    UIView *to = [context viewForKey:UITransitionContextToViewKey];
    UIView *container = context.containerView;
    if (!from || !to) { [context completeTransition:NO]; return; }
    CGFloat width = container.bounds.size.width;
    if (self.presenting) {
        to.frame = container.bounds;
        [container addSubview:to];
        to.transform = CGAffineTransformMakeTranslation(width, 0);
    } else [container insertSubview:to belowSubview:from];
    [UIView animateWithDuration:[self transitionDuration:context] animations:^{
        if (self.presenting) to.transform = CGAffineTransformIdentity;
        else from.transform = CGAffineTransformMakeTranslation(width, 0);
    } completion:^(BOOL finished) {
        BOOL cancelled = context.transitionWasCancelled;
        from.transform = CGAffineTransformIdentity;
        to.transform = CGAffineTransformIdentity;
        [context completeTransition:!cancelled];
    }];
}
@end

static NSString *const masterSubtitle = @"默认关闭，开启总开关后，分模块按开关生效。";

static NCNativeToggle *NCNativeSwitch(NCNativeStyle *style) {
    Class sourceClass = NSClassFromString(@"NMShakeFeedbackSevenSwitch");
    BOOL native = sourceClass && [sourceClass isSubclassOfClass:[UIControl class]] &&
        NCSignature(class_getInstanceMethod(sourceClass, @selector(isOn)), "B", @[]) &&
        NCSignature(class_getInstanceMethod(sourceClass, @selector(setOn:)), "v", @[@"B"]) &&
        NCSignature(class_getInstanceMethod(sourceClass, @selector(onTintColor)), "@", @[]) &&
        NCSignature(class_getInstanceMethod(sourceClass, @selector(setOnTintColor:)), "v", @[@"@"]);
    NCNativeToggle *toggle = native ? (NCNativeToggle *)[[sourceClass alloc] initWithFrame:CGRectMake(0,0,style.switchSize.width,style.switchSize.height)] : (NCNativeToggle *)[UISwitch new];
    toggle.onTintColor = style.switchColor;
    for (NSArray *pair in @[@[@"setOnTintColorKey:", @"NMSettingSwitchCellSwitchColorKey"],
                            @[@"setThumbTintColorKey:", @"NMSettingSwitchCellSwitchThumbTintColorKey"]]) {
        SEL selector = NSSelectorFromString(pair[0]);
        if (NCSignature(class_getInstanceMethod([toggle class], selector), "v", @[@"@"]))
            ((void (*)(id, SEL, id))objc_msgSend)(toggle, selector, pair[1]);
    }
    SEL skin = NSSelectorFromString(@"setSettingSwitchChangeSkin");
    if (NCSignature(class_getInstanceMethod([toggle class], skin), "v", @[]))
        ((void (*)(id, SEL))objc_msgSend)(toggle, skin);
    if (toggle.onTintColor) style.switchColor = toggle.onTintColor;
    return toggle;
}

@implementation NCShieldPanel
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"music163_cads";
    self.nativeStyle = [NCNativeStyle new];
    self.edgesForExtendedLayout = UIRectEdgeAll;
    self.nativeHeader = [UIView new];
    self.nativeTitle = [UILabel new];
    self.nativeTitle.text = self.title;
    self.nativeTitle.textAlignment = NSTextAlignmentCenter;
    self.backButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.backButton.accessibilityLabel = @"返回";
    [self.backButton addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
    self.backIcon = [UIImageView new]; self.backIcon.contentMode = UIViewContentModeScaleAspectFit;
    [self.backButton addSubview:self.backIcon];
    [self.nativeHeader addSubview:self.nativeTitle];
    [self.nativeHeader addSubview:self.backButton];
    [self.view addSubview:self.nativeHeader];
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    self.tableView.dataSource = self; self.tableView.delegate = self;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.tableView.estimatedRowHeight = 0;
    [self.view addSubview:self.tableView];
    [self refreshNativeStyle];
    __weak NCShieldPanel *weakSelf = self;
    self.updateObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NCUpdateStateChangedNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        [weakSelf.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:3]] withRowAnimation:UITableViewRowAnimationNone];
    }];
    if (!self.navigationController && !self.usesAppNavigation) {
        UIScreenEdgePanGestureRecognizer *edge = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(fallbackBackPan:)];
        edge.edges = UIRectEdgeLeft;
        [self.view addGestureRecognizer:edge];
    }
}
- (void)refreshNativeStyle {
    self.nativeStyle = NCCaptureNativeStyle(self.sourceSettingsController);
    self.nativeStyle.switchSize = NCSourceSwitchSize();
    self.view.backgroundColor = self.nativeStyle.pageColor;
    self.nativeHeader.backgroundColor = self.nativeStyle.pageColor;
    self.tableView.backgroundColor = self.nativeStyle.pageColor;
    self.tableView.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,self.nativeStyle.topGap)];
    self.nativeTitle.font = self.nativeStyle.titleFont;
    self.nativeTitle.textColor = self.nativeStyle.titleColor;
    self.backIcon.image = self.nativeStyle.backImage ?: [UIImage systemImageNamed:@"chevron.left"];
    self.backIcon.tintColor = self.nativeStyle.textColor;
    self.tableView.indicatorStyle = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ?
        UIScrollViewIndicatorStyleWhite : UIScrollViewIndicatorStyleBlack;
    [self.tableView reloadData];
    [self.view setNeedsLayout];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    UINavigationController *nav = self.navigationController;
    if (nav && !nav.navigationBarHidden) {
        self.changedNavigationBar = YES;
        [nav setNavigationBarHidden:YES animated:NO];
    }
    [self refreshNativeStyle];
    NCCheckForUpdates(NO, self);
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    BOOL leaving = self.isMovingFromParentViewController || self.isBeingDismissed;
    for (UIViewController *parent = self.parentViewController; parent && !leaving; parent = parent.parentViewController)
        leaving = parent.isMovingFromParentViewController || parent.isBeingDismissed;
    if (leaving && self.changedNavigationBar) {
        [self.navigationController setNavigationBarHidden:NO animated:animated];
        self.changedNavigationBar = NO;
    }
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIEdgeInsets safe = self.view.safeAreaInsets;
    CGFloat width = self.view.bounds.size.width;
    CGFloat navHeight = self.nativeStyle.navigationHeight;
    self.nativeHeader.frame = CGRectMake(safe.left, safe.top, width-safe.left-safe.right, navHeight);
    self.nativeTitle.frame = CGRectMake(64,0,MAX(0,self.nativeHeader.bounds.size.width-128),navHeight);
    self.backButton.frame = CGRectMake(0,0,64,navHeight);
    self.backIcon.frame = CGRectMake(self.nativeStyle.backLeading,(navHeight-self.nativeStyle.backSize.height)/2,
                                    self.nativeStyle.backSize.width,self.nativeStyle.backSize.height);
    CGFloat top = CGRectGetMaxY(self.nativeHeader.frame);
    CGFloat previousWidth = self.tableView.bounds.size.width;
    self.tableView.frame = CGRectMake(0,top,width,MAX(0,self.view.bounds.size.height-top));
    self.tableView.contentInset = UIEdgeInsetsMake(0,0,safe.bottom+self.nativeStyle.groupGap,0);
    self.tableView.scrollIndicatorInsets = UIEdgeInsetsMake(0,0,safe.bottom,0);
    if (fabs(previousWidth-width)>0.5) [self.tableView reloadData];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (self.isViewLoaded && [self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous]) [self refreshNativeStyle];
}
- (UIStatusBarStyle)preferredStatusBarStyle { return self.sourceSettingsController ? self.sourceSettingsController.preferredStatusBarStyle : UIStatusBarStyleDefault; }
- (BOOL)prefersStatusBarHidden { return self.sourceSettingsController.prefersStatusBarHidden; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return self.sourceSettingsController ? self.sourceSettingsController.supportedInterfaceOrientations : UIInterfaceOrientationMaskAllButUpsideDown;
}
- (BOOL)shouldAutorotate { return self.sourceSettingsController ? self.sourceSettingsController.shouldAutorotate : YES; }
- (BOOL)isNavigationBarVisible { return NO; }
- (void)dealloc {
    if (self.updateObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.updateObserver];
}
- (void)closePanel {
    UINavigationController *navigation = self.navigationController;
    SEL pop = NSSelectorFromString(@"nm_popViewController:");
    if (self.usesAppNavigation && NCSignature(class_getInstanceMethod([self class], pop), "v", @[@"B"]))
        ((void (*)(id,SEL,BOOL))objc_msgSend)(self,pop,YES);
    else if (navigation.viewControllers.count > 1) [navigation popViewControllerAnimated:YES];
    else [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)fallbackBackPan:(UIScreenEdgePanGestureRecognizer *)gesture {
    CGFloat progress = MAX(0,MIN(1,[gesture translationInView:self.view].x/MAX(1,self.view.bounds.size.width)));
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.fallbackInteraction = [UIPercentDrivenInteractiveTransition new];
        [self dismissViewControllerAnimated:YES completion:nil];
    } else if (gesture.state == UIGestureRecognizerStateChanged) [self.fallbackInteraction updateInteractiveTransition:progress];
    else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        if (gesture.state != UIGestureRecognizerStateCancelled && (progress>0.3 || [gesture velocityInView:self.view].x>500))
            [self.fallbackInteraction finishInteractiveTransition];
        else [self.fallbackInteraction cancelInteractiveTransition];
        self.fallbackInteraction = nil;
    }
}
- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented presentingController:(UIViewController *)presenting sourceController:(UIViewController *)source {
    NCPanelTransition *transition = [NCPanelTransition new]; transition.presenting = YES; return transition;
}
- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed {
    return [NCPanelTransition new];
}
- (id<UIViewControllerInteractiveTransitioning>)interactionControllerForDismissal:(id<UIViewControllerAnimatedTransitioning>)animator { return self.fallbackInteraction; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 1 : (section == 1 ? 9 : 2);
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)ip {
    return [NCPanelCell heightForStyle:self.nativeStyle width:tableView.bounds.size.width subtitle:ip.section == 0 ? masterSubtitle : nil];
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return section == 0 ? 0.01 : self.nativeStyle.groupGap + self.nativeStyle.valueFont.lineHeight + 10;
}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (!section) return nil;
    CGFloat height = [self tableView:tableView heightForHeaderInSection:section];
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0,0,tableView.bounds.size.width,height)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(self.nativeStyle.cardInset+self.nativeStyle.textInset,
          self.nativeStyle.groupGap,tableView.bounds.size.width-64,self.nativeStyle.valueFont.lineHeight)];
    label.text = @[@"",@"广告模块",@"系统弹窗",@"关于"][section];
    label.font = self.nativeStyle.valueFont; label.textColor = self.nativeStyle.secondaryColor;
    [view addSubview:label]; return view;
}
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section { return 0.01; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    NCPanelCell *cell = [[NCPanelCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.nativeStyle = self.nativeStyle;
    NSInteger count = [self tableView:tableView numberOfRowsInSection:ip.section];
    cell.roundedCorners = (ip.row == 0 ? kCALayerMinXMinYCorner|kCALayerMaxXMinYCorner : 0) |
                          (ip.row == count-1 ? kCALayerMinXMaxYCorner|kCALayerMaxXMaxYCorner : 0);
    if (ip.section == 3) {
        cell.mainLabel.text = ip.row == 0 ? NCVersionRowTitle() : @"仓库地址";
        cell.valueLabel.text = ip.row == 0 ? NC_VERSION : nil;
        cell.emphasizesTitle = ip.row == 0 && NCUpdateAvailable();
        cell.showsArrow = YES;
        return cell;
    }
    NSInteger index = ip.section == 1 ? ip.row : ip.row + 9;
    NSString *key = ip.section == 0 ? @"master" : NCModuleKeys()[index];
    cell.mainLabel.text = ip.section == 0 ? @"去广告总开关" : NCModuleTitles()[index];
    cell.subtitleLabel.text = ip.section == 0 ? masterSubtitle : nil;
    NCNativeToggle *toggle = NCNativeSwitch(self.nativeStyle);
    toggle.accessibilityIdentifier = key;
    toggle.accessibilityLabel = cell.mainLabel.text;
    toggle.on = NCRead(key);
    toggle.enabled = ip.section == 0 || (NCHookCount(key) > 0 && (ip.section == 2 || NCRead(@"master")));
    [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    cell.toggle = toggle;
    return cell;
}
- (void)toggleChanged:(NCNativeToggle *)toggle {
    NCWrite(toggle.accessibilityIdentifier, toggle.isOn);
    if ([toggle.accessibilityIdentifier isEqualToString:@"master"]) {
        NSMutableArray *rows = [NSMutableArray array];
        for (NSInteger row = 0; row < 9; row++) [rows addObject:[NSIndexPath indexPathForRow:row inSection:1]];
        [self.tableView reloadRowsAtIndexPaths:rows withRowAnimation:UITableViewRowAnimationNone];
    }
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tableView deselectRowAtIndexPath:ip animated:YES];
    if (ip.section != 3) return;
    if (ip.row == 0) { NCCheckForUpdates(YES, self); return; }
    NSURL *url = [NSURL URLWithString:NC_REPOSITORY];
    if (url && [url.scheme isEqualToString:@"https"] && [url.host isEqualToString:@"github.com"]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"仓库尚未配置" message:@"提供仓库地址后再接入更新检查。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}
@end
