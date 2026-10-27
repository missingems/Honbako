#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>
#import <os/log.h>
#import "HBJavaExtensionExecutor.h"

static NSURL *Documents(void) {
    return [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
}
static void SaveText(NSString *name, NSString *text) {
    [text writeToURL:[Documents() URLByAppendingPathComponent:name] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
static void SaveJSON(NSString *name, id object) {
    [[NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:nil]
        writeToURL:[Documents() URLByAppendingPathComponent:name] atomically:YES];
}
static NSDictionary *Object(NSString *json) {
    id value = json ? [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}
static NSString *JSON(id object) {
    return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:object options:0 error:nil] encoding:NSUTF8StringEncoding];
}
static NSString *SHA256(NSData *data) {
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, bytes);
    NSMutableString *result = [NSMutableString new];
    for (NSUInteger i = 0; i < sizeof(bytes); i++) [result appendFormat:@"%02x", bytes[i]];
    return result;
}

@interface ProbeSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) UILabel *status;
@property(nonatomic, strong) NSDate *started;
@property(nonatomic, copy) NSString *core;
@property(nonatomic, strong) NSDictionary *proof;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *checks;
@property(nonatomic) BOOL finished;
@end

@implementation ProbeSceneDelegate
- (void)sceneDidDisconnect:(UIScene *)scene { UIApplication.sharedApplication.idleTimerDisabled = NO; }
- (void)sceneWillResignActive:(UIScene *)scene { UIApplication.sharedApplication.idleTimerDisabled = NO; }
- (void)sceneDidBecomeActive:(UIScene *)scene { UIApplication.sharedApplication.idleTimerDisabled = !self.finished; }
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    [NSFileManager.defaultManager createDirectoryAtURL:Documents() withIntermediateDirectories:YES attributes:nil error:nil];
    for (NSString *name in @[@"runtime-core-result.txt", @"runtime-result.txt", @"extension-proof.json", @"native-executor-result.json"]) {
        [NSFileManager.defaultManager removeItemAtURL:[Documents() URLByAppendingPathComponent:name] error:nil];
    }
    self.started = NSDate.date;
    self.checks = [NSMutableArray new];
    SaveJSON(@"runtime-start.json", @{@"startedAt": [[NSISO8601DateFormatter new] stringFromDate:self.started],
        @"mode": @"persistent-native-executor", @"build": [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @""});
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    UIViewController *controller = [UIViewController new];
    controller.view.backgroundColor = UIColor.systemBackgroundColor;
    self.status = [UILabel new];
    self.status.numberOfLines = 0;
    self.status.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.status.adjustsFontForContentSizeCategory = YES;
    self.status.textColor = UIColor.labelColor;
    self.status.text = @"Checking the Java extension engine…";
    self.status.translatesAutoresizingMaskIntoConstraints = NO;
    [controller.view addSubview:self.status];
    [NSLayoutConstraint activateConstraints:@[
        [self.status.leadingAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.leadingAnchor constant:24],
        [self.status.trailingAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.trailingAnchor constant:-24],
        [self.status.centerYAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.centerYAnchor]
    ]];
    self.window.rootViewController = controller;
    [self.window makeKeyAndVisible];
    UIApplication.sharedApplication.idleTimerDisabled = YES;
    [HBJavaExtensionExecutor.sharedExecutor runBundledProofWithCompletion:^(NSString *core, NSString *proof, NSError *error) {
        self.core = core ?: @"Core diagnostic did not finish.";
        SaveText(@"runtime-core-result.txt", self.core);
        if (proof) SaveText(@"extension-proof.json", proof);
        self.proof = Object(proof);
        if (error || ![self.proof[@"ok"] boolValue] || ![self.proof[@"fixtureRetained"] boolValue]) {
            [self finish:error.localizedDescription ?: self.proof[@"error"] ?: @"The retained extension fixture was unavailable."];
            return;
        }
        [self checkImage:0];
    }];
}

- (NSDictionary *)baseRequest {
    return @{@"extensionPath": [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"tachiyomi-all.komga-v1.6.74.jar"],
             @"sourceId": self.proof[@"sourceIds"][0],
             @"preferences": @{@"Address": self.proof[@"fixtureBaseURL"]}};
}

- (void)checkImage:(NSUInteger)index {
    NSArray *operations = self.proof[@"operations"];
    NSDictionary *pages = nil;
    NSDictionary *search = nil;
    for (NSDictionary *operation in operations) {
        if ([operation[@"operation"] isEqual:@"pages"]) pages = operation[@"response"][@"result"];
        if (!search && [operation[@"operation"] isEqual:@"search"]) search = operation[@"response"][@"result"];
    }
    NSArray *pageRecords = pages[@"pages"];
    if (pageRecords.count != 3 || [self.proof[@"pageSha256"] count] != 3) {
        [self finish:@"Unexpected original-content page list."];
        return;
    }
    NSMutableDictionary *request = [self.baseRequest mutableCopy];
    NSString *expected;
    if (index < 3) {
        request[@"operation"] = @"image";
        request[@"page"] = pageRecords[index];
        expected = self.proof[@"pageSha256"][index];
    } else if (index == 3) {
        request[@"operation"] = @"cover";
        request[@"url"] = search[@"entries"][0][@"cover"];
        NSData *original = [NSData dataWithContentsOfFile:[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"fixture/cover.png"]];
        if (!original) { [self finish:@"Original cover fixture missing."]; return; }
        expected = SHA256(original);
    } else { [self checkReuse:0]; return; }
    [HBJavaExtensionExecutor.sharedExecutor imageJSON:JSON(request) completion:^(HBJavaImagePayload *payload, NSError *error) {
        BOOL passed = payload && payload.data.length > 0 && [SHA256(payload.data) isEqual:expected]
            && [payload.sha256 isEqual:expected] && [payload.mediaType hasPrefix:@"image/"];
        [self.checks addObject:@{@"kind": index < 3 ? @"page-bytes" : @"cover-bytes", @"position": @(index),
            @"bytes": @(payload.data.length), @"sha256": payload ? SHA256(payload.data) : @"", @"passed": @(passed)}];
        if (error || !passed) [self finish:error.localizedDescription ?: @"The native image bytes did not match the original artwork."];
        else [self checkImage:index + 1];
    }];
}

- (void)checkReuse:(NSUInteger)index {
    if (index == 2) { [self finish:nil]; return; }
    NSMutableDictionary *request = [self.baseRequest mutableCopy];
    request[@"operation"] = @"discover";
    [HBJavaExtensionExecutor.sharedExecutor executeJSON:JSON(request) completion:^(NSString *json, NSError *error) {
        NSDictionary *response = Object(json);
        BOOL passed = [response[@"ok"] boolValue]
            && [response[@"result"][@"package"] isEqual:@"eu.kanade.tachiyomi.extension.all.komga"];
        [self.checks addObject:@{@"kind": @"worker-reuse", @"position": @(index), @"passed": @(passed)}];
        if (error || !passed) [self finish:error.localizedDescription ?: @"A repeated request failed."];
        else [self checkReuse:index + 1];
    }];
}

- (void)finish:(NSString *)failure {
    [HBJavaExtensionExecutor.sharedExecutor endBundledProofWithCompletion:^(NSError *cleanupError) {
        self.finished = YES;
        UIApplication.sharedApplication.idleTimerDisabled = NO;
        NSString *error = failure ?: cleanupError.localizedDescription;
        BOOL passed = !error && self.checks.count == 6;
        SaveJSON(@"native-executor-result.json", @{@"ok": @(passed), @"checks": self.checks,
            @"elapsedSeconds": @(-self.started.timeIntervalSinceNow), @"fixtureClosed": @(!cleanupError),
            @"autoLockRestored": @(!UIApplication.sharedApplication.idleTimerDisabled), @"error": error ?: @""});
        NSString *result = [self.core stringByAppendingFormat:@"\n\n%@", passed
            ? @"Komga 1.6.74: Passed\nSearch, Chapters, Pages: Passed\nNative Image and Cover Bytes: Passed\nRepeated Requests: Passed\nFixture Cleanup: Passed"
            : [@"Extension Check Failed\n" stringByAppendingString:error ?: @"Incomplete diagnostic."]];
        SaveText(@"runtime-result.txt", result);
        self.status.text = result;
        os_log(OS_LOG_DEFAULT, "Honbako persistent runtime check: %{public}@", result);
    }];
}
@end

@interface ProbeDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation ProbeDelegate
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Runtime Probe" sessionRole:session.role];
    configuration.delegateClass = ProbeSceneDelegate.class;
    return configuration;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(ProbeDelegate.class)); }
}
