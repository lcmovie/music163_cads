#import "NCAdShield.h"
#import "NCVersionCompare.h"
#include <string.h>

NSString *const NCUpdateStateChangedNotification = @"music163_cads.update.changed";
static NSString *const remoteTagKey = @"music163_cads.v2.update.remoteTag";
static NSString *const checkedKey = @"music163_cads.v2.update.checkedAt";

@interface NCReleaseChecker : NSObject
@property(nonatomic) BOOL checking;
@property(nonatomic) NSTimeInterval lastAttempt;
@property(nonatomic) NSTimeInterval lastSuccess;
@property(nonatomic, copy) NSString *remoteTag;
@property(nonatomic, copy) NSString *failure;
@property(nonatomic, weak) UIViewController *presenter;
- (void)check:(BOOL)interactive presenter:(UIViewController *)presenter;
@end

static BOOL NCTagValid(NSString *tag) {
    if (![tag isKindOfClass:[NSString class]] || !tag.length || tag.length > 128) return NO;
    const char *utf8 = tag.UTF8String;
    int comparison = 0;
    return utf8 && strlen(utf8) == [tag lengthOfBytesUsingEncoding:NSUTF8StringEncoding] &&
           NCCompareVersions(NC_VERSION.UTF8String, utf8, &comparison);
}
static NSURL *NCReleaseURL(NSString *tag) {
    NSURLComponents *parts = [NSURLComponents componentsWithString:NC_REPOSITORY];
    parts.path = [parts.path stringByAppendingFormat:@"/releases/tag/%@", tag];
    return parts.URL;
}
static NCReleaseChecker *NCChecker(void) {
    static NCReleaseChecker *checker;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        checker = [NCReleaseChecker new];
        NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:remoteTagKey];
        if (NCTagValid(saved)) checker.remoteTag = saved;
        checker.lastSuccess = [[NSUserDefaults standardUserDefaults] doubleForKey:checkedKey];
    });
    return checker;
}
BOOL NCUpdateAvailable(void) {
    NSString *tag = NCChecker().remoteTag;
    int comparison = 0;
    return NCTagValid(tag) && NCCompareVersions(NC_VERSION.UTF8String, tag.UTF8String, &comparison) && comparison < 0;
}
NSString *NCVersionRowTitle(void) {
    if (NCUpdateAvailable()) return @"插件版本 · 有新版本";
    return NCChecker().checking ? @"插件版本 · 检查中" : @"插件版本";
}
void NCCheckForUpdates(BOOL interactive, UIViewController *presenter) {
    NSCAssert([NSThread isMainThread], @"Updates use main queue state");
    [NCChecker() check:interactive presenter:presenter];
}

@implementation NCReleaseChecker
- (void)changed {
    [[NSNotificationCenter defaultCenter] postNotificationName:NCUpdateStateChangedNotification object:nil];
}
- (void)showResult {
    UIViewController *presenter = self.presenter;
    self.presenter = nil;
    if (!presenter.isViewLoaded || !presenter.view.window || presenter.presentedViewController) return;
    NSString *title, *message;
    if (self.failure) { title = @"检查失败"; message = self.failure; }
    else if (!self.remoteTag) {
        title = @"暂无发行版";
        message = [NSString stringWithFormat:@"仓库尚未发布发行版。\n本机版本：%@", NC_VERSION];
    } else {
        int comparison = 0;
        if (!NCCompareVersions(NC_VERSION.UTF8String, self.remoteTag.UTF8String, &comparison)) return;
        title = comparison < 0 ? @"发现新版本" : (comparison == 0 ? @"版本一致" : @"本机版本较新");
        message = [NSString stringWithFormat:@"本机版本：%@\n仓库版本：%@", NC_VERSION, self.remoteTag];
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    if (!self.failure && self.remoteTag) {
        NSURL *url = NCReleaseURL(self.remoteTag);
        [alert addAction:[UIAlertAction actionWithTitle:@"查看发行版" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}
- (void)completeWithTag:(NSString *)tag failure:(NSString *)failure {
    self.checking = NO;
    self.failure = failure;
    if (!failure) {
        self.remoteTag = tag;
        self.lastSuccess = [NSDate date].timeIntervalSince1970;
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if (tag) [defaults setObject:tag forKey:remoteTagKey]; else [defaults removeObjectForKey:remoteTagKey];
        [defaults setDouble:self.lastSuccess forKey:checkedKey];
    }
    [self changed];
    [self showResult]; // Only a manual tap supplies a presenter.
}
- (void)check:(BOOL)interactive presenter:(UIViewController *)presenter {
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if (interactive) self.presenter = presenter;
    if (self.checking) return; // A manual tap joins the existing check.
    if (!interactive && ((self.lastSuccess > 0 && now >= self.lastSuccess && now - self.lastSuccess < 15 * 60) ||
                         (self.lastAttempt > 0 && now >= self.lastAttempt && now - self.lastAttempt < 15 * 60))) return;
    self.lastAttempt = now;
    self.checking = YES;
    self.failure = nil;
    [self changed];
    // No App credentials, cookies, device identifiers or authorization token.
    NSURLComponents *parts = [NSURLComponents componentsWithString:NC_REPOSITORY];
    NSURL *endpoint = [NSURL URLWithString:[NSString stringWithFormat:@"https://api.github.com/repos%@/releases?per_page=100", parts.path]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:endpoint cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:12];
    request.HTTPShouldHandleCookies = NO;
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:[@"music163_cads/" stringByAppendingString:NC_VERSION] forHTTPHeaderField:@"User-Agent"];
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.HTTPCookieStorage = nil;
    config.URLCache = nil;
    config.HTTPShouldSetCookies = NO;
    config.timeoutIntervalForResource = 20;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *failure = nil, *best = nil;
        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        if (error) failure = @"暂时无法连接 GitHub，请稍后重试。";
        else if (status == 403 || status == 429) failure = @"GitHub 暂时限制请求，请稍后重试。";
        else if (status != 200) failure = @"无法读取仓库发行版，请稍后重试。";
        else if (!data || data.length > 2 * 1024 * 1024) failure = @"发行版数据异常，请稍后重试。";
        else {
            id releases = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            if (![releases isKindOfClass:[NSArray class]]) failure = @"发行版数据格式异常。";
            else {
                BOOL hasPublishedRelease = NO;
                for (id entry in (NSArray *)releases) {
                    if (![entry isKindOfClass:[NSDictionary class]]) continue;
                    id draft = entry[@"draft"];
                    if (![draft isKindOfClass:[NSNumber class]] || [draft boolValue]) continue;
                    hasPublishedRelease = YES;
                    NSString *tag = entry[@"tag_name"];
                    if (!NCTagValid(tag)) continue;
                    int comparison = 0;
                    if (!best || (NCCompareVersions(best.UTF8String, tag.UTF8String, &comparison) && comparison < 0)) best = tag;
                }
                if (hasPublishedRelease && !best) failure = @"仓库发行版的版本号无法识别。";
                // SemVer includes published test/prerelease tags, so test.10 follows test.9.
            }
        }
        [session finishTasksAndInvalidate];
        dispatch_async(dispatch_get_main_queue(), ^{ [self completeWithTag:best failure:failure]; });
    }];
    [task resume];
}
@end
