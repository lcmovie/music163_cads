#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define NC_VERSION @"2.0.0"
#define NC_TARGET @"com.netease.cloudmusic"

#define NC_REPOSITORY @"https://github.com/lcmovie/music163_cads"

NSArray<NSString *> *NCModuleKeys(void);
NSArray<NSString *> *NCModuleTitles(void);
BOOL NCRead(NSString *key);
void NCWrite(NSString *key, BOOL value);
BOOL NCEnabled(NSString *key);
void NCLog(NSString *event, NSDictionary *fields);
void NCSetStatus(NSString *module, NSString *status);
NSString *NCStatus(NSString *module);
void NCRecordHook(NSString *module);
NSUInteger NCHookCount(NSString *module);
void NCInstallHomePromotionHooks(void);

BOOL NCSignature(Method method, const char *returns, NSArray<NSString *> *arguments);
BOOL NCOwnMethod(Class cls, SEL selector);
BOOL NCHasHook(Class cls, SEL selector);
BOOL NCReplace(Class cls, SEL selector, IMP original, IMP replacement, BOOL allowInherited);
void NCInstallAdHooks(void);
void NCPrepareLaunchHooks(void);
void NCReportLaunchHooks(void);
void NCRefreshLaunchState(void);
void NCRefreshAdViews(void);
void NCInstallSettings(void);
void NCInstallSettingsDiscovery(void);
void NCInstallMenuLayoutHooks(void);
void NCInstallMountBatchHook(void);
void NCSynchronizeSettingsAtMount(void);
BOOL NCPlaceMenuRow(UIViewController *controller, id target, SEL action);
void NCHideMenuRow(UIViewController *controller);
BOOL NCIsSettingsController(UIViewController *controller);
BOOL NCEnsureSettingsEntry(UIViewController *controller);
void NCHideSettingsEntry(UIViewController *controller);

void NCCheckForUpdates(BOOL interactive, UIViewController *presenter);
NSString *NCVersionRowTitle(void);
BOOL NCUpdateAvailable(void);
extern NSString *const NCUpdateStateChangedNotification;

@interface NCShieldPanel : UIViewController
@property(nonatomic, weak) UIViewController *sourceSettingsController;
@property(nonatomic) BOOL usesAppNavigation;
@end
