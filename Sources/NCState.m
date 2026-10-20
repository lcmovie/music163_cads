#import "NCAdShield.h"

static NSMutableDictionary<NSString *, NSString *> *statuses;
static NSMutableDictionary<NSString *, NSNumber *> *hookCounts;

NSArray<NSString *> *NCModuleKeys(void) {
    return @[@"launch", @"banner", @"feed", @"search", @"comment", @"podcast",
             @"share", @"live", @"incentive", @"push", @"guide"];
}

NSArray<NSString *> *NCModuleTitles(void) {
    return @[@"开屏广告", @"首页横幅广告", @"信息流插入广告", @"搜索页广告", @"评论区广告",
             @"播客／语音广告", @"分享面板广告", @"直播礼物墙广告", @"激励视频（全部拦截）",
             @"屏蔽推送权限弹窗", @"屏蔽运营／引导弹窗"];
}

static NSString *NCKey(NSString *key) {
    return [@"music163_cads.v2." stringByAppendingString:key];
}

BOOL NCRead(NSString *key) { return [[NSUserDefaults standardUserDefaults] boolForKey:NCKey(key)]; }
void NCWrite(NSString *key, BOOL value) {
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:NCKey(key)];
    NCRefreshAdViews();
    NCRefreshLaunchState();
}
BOOL NCEnabled(NSString *key) {
    return NCRead(key) && ([@[@"push", @"guide"] containsObject:key] || NCRead(@"master"));
}

void NCLog(NSString *event, NSDictionary *fields) {
    // Public builds neither persist nor emit runtime collection records.
}

void NCSetStatus(NSString *module, NSString *status) {
    NSCAssert([NSThread isMainThread], @"Status updates use the main queue");
    if (!statuses) statuses = [NSMutableDictionary dictionary];
    statuses[module] = status;
}
NSString *NCStatus(NSString *module) { return statuses[module] ?: @"尚未匹配可用入口"; }
void NCRecordHook(NSString *module) {
    if (!hookCounts) hookCounts = [NSMutableDictionary dictionary];
    hookCounts[module] = @([hookCounts[module] unsignedIntegerValue] + 1);
    NCSetStatus(module, [NSString stringWithFormat:@"匹配 %lu 个入口，效果待实测", (unsigned long)[hookCounts[module] unsignedIntegerValue]]);
}
NSUInteger NCHookCount(NSString *module) { return [hookCounts[module] unsignedIntegerValue]; }
