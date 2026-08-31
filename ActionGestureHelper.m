#import "ActionGestureHelper.h"

#import <CoreMotion/CoreMotion.h>
#import <UIKit/UIKit.h>
#import <notify.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdarg.h>
#import <stdio.h>
#import <unistd.h>
#if __has_include(<roothide.h>)
#import <roothide.h>
#else
static inline NSString *jbroot(NSString *path) {
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"]) {
        return [@"/var/jb" stringByAppendingString:path];
    }
    return path;
}
#endif

NSString *const AGGestureSingle = @"single";
NSString *const AGGestureDouble = @"double";
NSString *const AGGestureLong = @"long";

NSString *const AGDirectionFaceUp = @"faceUp";
NSString *const AGDirectionFaceDown = @"faceDown";
NSString *const AGDirectionPortrait = @"portrait";
NSString *const AGDirectionPortraitUpsideDown = @"portraitUpsideDown";
NSString *const AGDirectionLandscapeLeft = @"landscapeLeft";
NSString *const AGDirectionLandscapeRight = @"landscapeRight";

NSString *const AGCustomActionNative = @"native";
NSString *const AGCustomActionWechatScan = @"wechat.scan";
NSString *const AGCustomActionWechatPayCode = @"wechat.paycode";
NSString *const AGCustomActionAlipayScan = @"alipay.scan";
NSString *const AGCustomActionAlipayPayCode = @"alipay.paycode";

void AGWriteLog(NSString *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    if (!message) return;

    NSString *line = [message stringByAppendingString:@"\n"];
    @synchronized (ActionGestureHelper.class) {
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        for (NSString *path in @[
            @"/tmp/ActionGesture.runtime.log",
            @"/var/tmp/com.huami.actiongesture.runtime.log",
            @"/var/mobile/Library/Preferences/com.huami.actiongesture.runtime.log"
        ]) {
            FILE *file = fopen(path.fileSystemRepresentation, "ab");
            if (!file) continue;
            fwrite(data.bytes, 1, data.length, file);
            fflush(file);
            fclose(file);
        }
    }
    NSLog(@"%@", message);
}

static void AGLogRuntimeMethods(Class cls) {
    for (Class current = cls; current && current != NSObject.class;
         current = class_getSuperclass(current)) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(current, &count);
        AGWriteLog(@"[ActionGesture] runtime methods %@ count=%u",
              NSStringFromClass(current), count);
        for (unsigned int index = 0; index < count; index++) {
            SEL selector = method_getName(methods[index]);
            NSString *selectorName = NSStringFromSelector(selector);
            if ([selectorName rangeOfString:@"action" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [selectorName rangeOfString:@"button" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [selectorName rangeOfString:@"execute" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [selectorName rangeOfString:@"perform" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [selectorName rangeOfString:@"activate" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [selectorName rangeOfString:@"invoke" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [selectorName rangeOfString:@"trigger" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                AGWriteLog(@"[ActionGesture] runtime selector %@ args=%u",
                      selectorName, method_getNumberOfArguments(methods[index]));
            }
        }
        free(methods);
    }
}

typedef void (*AGButtonEventIMP)(SBRingerHardwareButton *,
                                 SEL,
                                 id<AGHardwareButtonEvent>);

@interface AGGestureConfiguration : NSObject

@property (nonatomic) BOOL hasSection;
@property (nonatomic) BOOL hasArchive;
@property (nonatomic, copy, nullable) NSString *sectionIdentifier;
@property (nonatomic, copy, nullable) NSData *configuredActionArchive;

@end

@implementation AGGestureConfiguration
@end

@interface ActionGestureHelper ()

@property (nonatomic, readwrite) NSBundle *settingsBundle;
@property (nonatomic) AGButtonEventIMP originalButtonDown;
@property (nonatomic) AGButtonEventIMP originalButtonLongPress;
@property (nonatomic) AGButtonEventIMP originalButtonUp;
@property (nonatomic) NSMutableDictionary<NSString *, NSDictionary *> *
    systemActionCache;
@property (nonatomic) BOOL snapshotScheduled;
@property (nonatomic, copy, nullable) NSString *pendingSnapshotGesture;
@property (nonatomic, copy, nullable) NSString *pendingSnapshotDirection;
@property (nonatomic) CMMotionManager *motionManager;
@property (nonatomic, copy, nullable) NSString *sampledDirection;
@property (nonatomic) int directionNotificationToken;
@property (nonatomic) BOOL suppressSystemActionSnapshots;

- (NSString *)customActionStorageKeyForGesture:(NSString *)gesture
                                      direction:(nullable NSString *)direction;

- (id)preferenceValueForKey:(NSString *)key;
- (void)setPreferenceValue:(nullable id)value forKey:(NSString *)key;
- (NSString *)storageKeyForGesture:(NSString *)gesture
                         direction:(nullable NSString *)direction
                            suffix:(NSString *)suffix;
- (AGGestureConfiguration *)configurationForGesture:(NSString *)gesture
                                           direction:
                                               (nullable NSString *)direction
                                         synchronize:(BOOL)synchronize;
- (void)storeConfiguration:(AGGestureConfiguration *)configuration
                forGesture:(NSString *)gesture
                 direction:(nullable NSString *)direction
               synchronize:(BOOL)synchronize;
- (AGGestureConfiguration *)currentNativeConfiguration;
- (void)initializeDirectionalConfigurations;
- (void)migrateDirectionalFallbackModelIfNeeded;
- (void)removeConfigurationForGesture:(NSString *)gesture
                            direction:(NSString *)direction
                          synchronize:(BOOL)synchronize;
- (BOOL)configuration:(AGGestureConfiguration *)configuration
    isEqualToConfiguration:(AGGestureConfiguration *)otherConfiguration;
- (AGGestureConfiguration *)effectiveConfigurationForGesture:
                                (NSString *)gesture
                                                   direction:
                                                       (nullable NSString *)
                                                           direction
                                           resolvedDirection:
                                               (NSString *_Nullable *_Nullable)
                                                   resolvedDirection
                                                 synchronize:(BOOL)synchronize;
- (void)reloadDirectionMode;
- (NSTimeInterval)fallbackReloadDelay;
- (BOOL)applyConfiguration:(AGGestureConfiguration *)configuration;
- (nullable NSString *)finishDirectionSampling;
- (nullable NSString *)directionForGravity:(CMAcceleration)gravity;
- (NSString *)assignmentIdentifierForGesture:(NSString *)gesture
                                    direction:(nullable NSString *)direction;

@end

@implementation ActionGestureHelper

+ (void)load {
    // +load is intentionally used in addition to the C constructor.  It is
    // invoked by Objective-C image loading even when RootHide defers the
    // tweak's constructor callbacks.
    [self ag_bootstrapRuntime];
}

+ (void)ag_bootstrapRuntime {
    @autoreleasepool {
        AGWriteLog(@"[ActionGesture] ObjC +load bootstrap process=%d", getpid());
        for (NSUInteger attempt = 0; attempt <= 20; attempt++) {
            NSTimeInterval delay = 0.25 * attempt;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                          (int64_t)(delay * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (!AGInstallDirectHooks()) {
                    if (attempt == 20) {
                        AGWriteLog(@"[ActionGesture] ObjC bootstrap failed after retries");
                    }
                }
            });
        }
    }
}

+ (instancetype)sharedHelper {
    static ActionGestureHelper *helper;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        helper = [[self alloc] init];
    });
    return helper;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _currentGesture = AGGestureSingle;
        _currentDirection = AGDirectionFaceUp;
        _systemActionCache = [NSMutableDictionary dictionaryWithCapacity:18];
        _settingsBundle =
            [NSBundle bundleWithPath:
                @"/System/Library/PreferenceBundles/ActionButtonSettings.bundle"];
    }
    return self;
}

- (id)preferenceValueForKey:(NSString *)key {
    return CFBridgingRelease(
        CFPreferencesCopyAppValue(
            (__bridge CFStringRef)key,
            CFSTR("com.huami.actiongesture")));
}

- (void)setPreferenceValue:(id)value forKey:(NSString *)key {
    CFPreferencesSetAppValue(
        (__bridge CFStringRef)key,
        (__bridge CFPropertyListRef)value,
        CFSTR("com.huami.actiongesture"));
}

- (NSString *)storageKeyForGesture:(NSString *)gesture
                         direction:(NSString *)direction
                            suffix:(NSString *)suffix {
    if (direction) {
        return [NSString stringWithFormat:
            @"native.%@.%@.%@", gesture, direction, suffix];
    }
    return [NSString stringWithFormat:@"native.%@.%@", gesture, suffix];
}

- (NSUserDefaults *)springBoardDefaults {
    return [[NSUserDefaults alloc] initWithSuiteName:@"com.apple.springboard"];
}

- (BOOL)isKnownGesture:(NSString *)gesture {
    return [gesture isEqualToString:AGGestureSingle] ||
           [gesture isEqualToString:AGGestureDouble] ||
           [gesture isEqualToString:AGGestureLong];
}

- (NSArray<NSString *> *)directions {
    return @[
        AGDirectionPortrait,
        AGDirectionFaceUp,
        AGDirectionFaceDown,
        AGDirectionPortraitUpsideDown,
        AGDirectionLandscapeLeft,
        AGDirectionLandscapeRight
    ];
}

- (BOOL)isKnownDirection:(NSString *)direction {
    return [[self directions] containsObject:direction];
}

- (NSString *)activeEditorDirection {
    return self.directionModeEnabled ? self.currentDirection : nil;
}

- (void)loadEditorState {
    CFPreferencesAppSynchronize(CFSTR("com.huami.actiongesture"));
    NSString *gesture = [self preferenceValueForKey:@"editorGesture"];
    NSString *direction = [self preferenceValueForKey:@"editorDirection"];
    self.currentGesture =
        [self isKnownGesture:gesture] ? gesture : AGGestureSingle;
    self.currentDirection =
        [self isKnownDirection:direction] ? direction : AGDirectionFaceUp;
    self.directionModeEnabled =
        [[self preferenceValueForKey:@"directionModeEnabled"] boolValue];
    [self migrateDirectionalFallbackModelIfNeeded];
    if (self.directionModeEnabled) {
        [self initializeDirectionalConfigurations];
    }
}

- (void)saveCurrentGesture:(NSString *)gesture {
    if (![self isKnownGesture:gesture]) return;
    self.currentGesture = gesture;
    [self setPreferenceValue:gesture forKey:@"editorGesture"];
    CFPreferencesAppSynchronize(CFSTR("com.huami.actiongesture"));
}

- (void)saveCurrentDirection:(NSString *)direction {
    if (![self isKnownDirection:direction]) return;
    self.currentDirection = direction;
    [self setPreferenceValue:direction forKey:@"editorDirection"];
    CFPreferencesAppSynchronize(CFSTR("com.huami.actiongesture"));
}

- (void)saveDirectionModeEnabled:(BOOL)enabled {
    if (enabled && !self.directionModeEnabled) {
        [self migrateDirectionalFallbackModelIfNeeded];
        [self initializeDirectionalConfigurations];
    }
    self.directionModeEnabled = enabled;
    [self setPreferenceValue:@(enabled) forKey:@"directionModeEnabled"];
    CFPreferencesAppSynchronize(CFSTR("com.huami.actiongesture"));
    notify_post("com.huami.actiongesture.direction-mode-changed");
}

- (NSString *)customActionStorageKeyForGesture:(NSString *)gesture
                                      direction:(NSString *)direction {
    return direction
        ? [NSString stringWithFormat:@"customAction.%@.%@", gesture, direction]
        : [NSString stringWithFormat:@"customAction.%@.default", gesture];
}

- (NSString *)customActionForGesture:(NSString *)gesture
                           direction:(NSString *)direction {
    if (![self isKnownGesture:gesture] ||
        (direction && ![self isKnownDirection:direction])) {
        return AGCustomActionNative;
    }
    CFPreferencesAppSynchronize(CFSTR("com.huami.actiongesture"));
    id value = [self preferenceValueForKey:
        [self customActionStorageKeyForGesture:gesture direction:direction]];
    return [value isKindOfClass:NSString.class] ? value : AGCustomActionNative;
}

- (void)saveCustomAction:(NSString *)action
               forGesture:(NSString *)gesture
                direction:(NSString *)direction {
    NSArray *knownActions = @[ AGCustomActionNative, AGCustomActionWechatScan,
                               AGCustomActionWechatPayCode,
                               AGCustomActionAlipayScan,
                               AGCustomActionAlipayPayCode ];
    if (![knownActions containsObject:action] ||
        ![self isKnownGesture:gesture] ||
        (direction && ![self isKnownDirection:direction])) {
        return;
    }
    [self setPreferenceValue:action
                      forKey:[self customActionStorageKeyForGesture:gesture
                                                               direction:direction]];
    CFPreferencesAppSynchronize(CFSTR("com.huami.actiongesture"));
}

- (NSString *)titleForCustomAction:(NSString *)action {
    NSDictionary *titles = @{
        AGCustomActionNative: @"系统动作",
        AGCustomActionWechatScan: @"微信扫一扫",
        AGCustomActionWechatPayCode: @"微信付款码",
        AGCustomActionAlipayScan: @"支付宝扫一扫",
        AGCustomActionAlipayPayCode: @"支付宝付款码"
    };
    return titles[action] ?: titles[AGCustomActionNative];
}

- (BOOL)executeCustomAction:(NSString *)action {
    NSDictionary *urlCandidates = @{
        AGCustomActionWechatScan: @[ @"weixin://scanqrcode",
                                     @"weixin://dl/scan" ],
        AGCustomActionWechatPayCode: @[ @"weixin://widget/pay",
                                       @"weixin://pay" ],
        AGCustomActionAlipayScan:
            @[ @"alipays://platformapi/startapp?saId=10000007",
               @"alipayqr://platformapi/startapp?saId=10000007" ],
        AGCustomActionAlipayPayCode:
            @[ @"alipays://platformapi/startapp?saId=20000056",
               @"alipayqr://platformapi/startapp?saId=20000056" ]
    };
    NSDictionary *bundleIDs = @{
        AGCustomActionWechatScan: @"com.tencent.xin",
        AGCustomActionWechatPayCode: @"com.tencent.xin",
        AGCustomActionAlipayScan: @"com.eg.android.AlipayGphone",
        AGCustomActionAlipayPayCode: @"com.eg.android.AlipayGphone"
    };
    NSArray<NSString *> *candidates = urlCandidates[action];
    if (!candidates.count) return NO;
    Class workspaceClass = objc_getClass("LSApplicationWorkspace");
    SEL defaultWorkspaceSEL = sel_registerName("defaultWorkspace");
    SEL establishConnectionSEL = sel_registerName("establishConnection");
    SEL openSensitiveURLErrorSEL =
        sel_registerName("openSensitiveURL:withOptions:error:");
    SEL openSensitiveURLSEL =
        sel_registerName("openSensitiveURL:withOptions:");
    SEL openURLErrorSEL = sel_registerName("openURL:withOptions:error:");
    SEL openURLWithOptionsSEL = sel_registerName("openURL:withOptions:");
    SEL openURLSEL = sel_registerName("openURL:");
    SEL openBundleSEL = sel_registerName("openApplicationWithBundleID:");
    id workspace = nil;
    if (workspaceClass && [workspaceClass respondsToSelector:defaultWorkspaceSEL]) {
        id (*getWorkspace)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
        workspace = getWorkspace((id)workspaceClass, defaultWorkspaceSEL);
    }

    UIApplication *application = UIApplication.sharedApplication;
    SEL applicationOpenURLSEL = @selector(openURL:options:completionHandler:);

    // Do not make a synchronous LaunchServices IPC call on SpringBoard's
    // button-event thread.  floating-view can synchronously observe the same
    // activation request, which otherwise deadlocks SpringBoard and appears
    // as a frozen screen.  Dispatch the request off the main thread and
    // consume the button event immediately.
    if (workspace) {
        NSString *candidate = candidates.firstObject;
        NSURL *url = [NSURL URLWithString:candidate];
        if (url) {
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                if ([workspace respondsToSelector:establishConnectionSEL]) {
                    void (*establishConnection)(id, SEL) =
                        (void (*)(id, SEL))objc_msgSend;
                    establishConnection(workspace, establishConnectionSEL);
                    AGWriteLog(@"[ActionGesture] LSApplicationWorkspace connection established (background)");
                }
                NSError *error = nil;
                BOOL opened = NO;
                if ([workspace respondsToSelector:openSensitiveURLErrorSEL]) {
                    BOOL (*openSensitiveURL)(id, SEL, NSURL *, NSDictionary *, NSError **) =
                        (BOOL (*)(id, SEL, NSURL *, NSDictionary *, NSError **))objc_msgSend;
                    opened = openSensitiveURL(workspace, openSensitiveURLErrorSEL, url, nil, &error);
                }
                if (!opened && [workspace respondsToSelector:openSensitiveURLSEL]) {
                    BOOL (*openSensitiveURL)(id, SEL, NSURL *, NSDictionary *) =
                        (BOOL (*)(id, SEL, NSURL *, NSDictionary *))objc_msgSend;
                    opened = openSensitiveURL(workspace, openSensitiveURLSEL, url, nil);
                }
                if (!opened && [workspace respondsToSelector:openURLErrorSEL]) {
                    error = nil;
                    BOOL (*openURLWithOptions)(id, SEL, NSURL *, NSDictionary *, NSError **) =
                        (BOOL (*)(id, SEL, NSURL *, NSDictionary *, NSError **))objc_msgSend;
                    opened = openURLWithOptions(workspace, openURLErrorSEL, url, nil, &error);
                }
                if (!opened && [workspace respondsToSelector:openURLWithOptionsSEL]) {
                    BOOL (*openURLWithOptions)(id, SEL, NSURL *, NSDictionary *) =
                        (BOOL (*)(id, SEL, NSURL *, NSDictionary *))objc_msgSend;
                    opened = openURLWithOptions(workspace, openURLWithOptionsSEL, url, nil);
                }
                if (!opened && [workspace respondsToSelector:openURLSEL]) {
                    BOOL (*openURL)(id, SEL, NSURL *) =
                        (BOOL (*)(id, SEL, NSURL *))objc_msgSend;
                    opened = openURL(workspace, openURLSEL, url);
                }
                AGWriteLog(@"[ActionGesture] background LaunchServices URL %@ accepted=%@ error=%@",
                      candidate, opened ? @"YES" : @"NO", error);
            });
            return YES;
        }
    }

    for (NSString *candidate in candidates) {
        NSURL *url = [NSURL URLWithString:candidate];
        if (!url) continue;

        // UIApplication is the public iOS 17 launch path.  The completion
        // handler supplies the real acceptance result; on failure we still
        // let the private workspace fallback try the same URL.
        // In SpringBoard, prefer LaunchServices.  UIApplication may report
        // success while a presentation helper (such as floating-view) owns
        // the scene; LaunchServices asks SpringBoard to activate the target
        // application normally and therefore keeps the launch full-screen.
        if (!workspace && application && [application respondsToSelector:applicationOpenURLSEL]) {
            void (^completion)(BOOL) = ^(BOOL success) {
                AGWriteLog(@"[ActionGesture] UIApplication URL %@ accepted=%@",
                      candidate, success ? @"YES" : @"NO");
                if (!success && workspace) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if ([workspace respondsToSelector:openSensitiveURLErrorSEL]) {
                            NSError *fallbackError = nil;
                            BOOL (*openSensitiveURL)(id, SEL, NSURL *, NSDictionary *, NSError **) =
                                (BOOL (*)(id, SEL, NSURL *, NSDictionary *, NSError **))objc_msgSend;
                            BOOL fallbackOpened = openSensitiveURL(workspace,
                                                                   openSensitiveURLErrorSEL,
                                                                   url, nil,
                                                                   &fallbackError);
                            AGWriteLog(@"[ActionGesture] workspace fallback URL %@ accepted=%@ error=%@",
                                  candidate, fallbackOpened ? @"YES" : @"NO", fallbackError);
                        }
                    });
                }
            };
            void (*openApplicationURL)(id, SEL, NSURL *, NSDictionary *, void (^)(BOOL)) =
                (void (*)(id, SEL, NSURL *, NSDictionary *, void (^)(BOOL)))objc_msgSend;
            openApplicationURL(application, applicationOpenURLSEL, url, nil, completion);
            return YES;
        }

        if (workspace) continue;
    }

    // UIApplication fallback for environments where LaunchServices is not
    // exposed by the injected SpringBoard process.
    if (application && [application respondsToSelector:applicationOpenURLSEL]) {
        for (NSString *candidate in candidates) {
            NSURL *url = [NSURL URLWithString:candidate];
            if (!url) continue;
            __block BOOL accepted = NO;
            void (^completion)(BOOL) = ^(BOOL success) {
                accepted = success;
                AGWriteLog(@"[ActionGesture] UIApplication fallback URL %@ accepted=%@",
                      candidate, success ? @"YES" : @"NO");
            };
            void (*openApplicationURL)(id, SEL, NSURL *, NSDictionary *, void (^)(BOOL)) =
                (void (*)(id, SEL, NSURL *, NSDictionary *, void (^)(BOOL)))objc_msgSend;
            openApplicationURL(application, applicationOpenURLSEL, url, nil, completion);
            if (accepted) return YES;
        }
    }
    if (workspace && [workspace respondsToSelector:openBundleSEL]) {
        NSString *bundleID = bundleIDs[action];
        if (bundleID.length) {
            void (*openBundle)(id, SEL, NSString *) =
                (void (*)(id, SEL, NSString *))objc_msgSend;
            openBundle(workspace, openBundleSEL, bundleID);
            AGWriteLog(@"[ActionGesture] custom action %@ URL failed; opened %@ home",
                  action, bundleID);
            return YES;
        }
    }
    AGWriteLog(@"[ActionGesture] custom action %@ could not launch any target", action);
    return YES;
}

- (BOOL)shouldTriggerSingleActionImmediately {
    if (self.directionModeEnabled) return NO;

    AGGestureConfiguration *singleConfiguration =
        [self effectiveConfigurationForGesture:AGGestureSingle
                                     direction:nil
                             resolvedDirection:nil
                                   synchronize:YES];
    NSString *singleAction =
        [self customActionForGesture:AGGestureSingle direction:nil];
    if (!singleConfiguration || singleConfiguration.hasArchive ||
        [singleAction isEqualToString:AGCustomActionNative]) {
        return NO;
    }

    // Immediate single delivery is safe only when double/long have no native
    // action and no custom action that would otherwise be stolen by ButtonDown.
    for (NSString *gesture in @[ AGGestureDouble, AGGestureLong ]) {
        AGGestureConfiguration *configuration =
            [self effectiveConfigurationForGesture:gesture
                                         direction:nil
                                 resolvedDirection:nil
                                       synchronize:NO];
        NSString *action = [self customActionForGesture:gesture direction:nil];
        if ((configuration && configuration.hasArchive) ||
            ![action isEqualToString:AGCustomActionNative]) {
            return NO;
        }
    }
    return YES;
}

- (NSTimeInterval)fallbackReloadDelay {
    CFPreferencesAppSynchronize(CFSTR("com.huami.actiongesture"));
    id value = [self preferenceValueForKey:@"fallbackReloadDelayMs"];
    double milliseconds =
        [value isKindOfClass:NSNumber.class] ? [value doubleValue] : 80.0;
    if (milliseconds < 0) milliseconds = 0;
    if (milliseconds > 500) milliseconds = 500;
    return milliseconds / 1000.0;
}
- (AGGestureConfiguration *)configurationForGesture:(NSString *)gesture
                                           direction:(NSString *)direction
                                         synchronize:(BOOL)synchronize {
    if (![self isKnownGesture:gesture] ||
        (direction && ![self isKnownDirection:direction])) {
        return nil;
    }
    if (synchronize) {
        CFPreferencesAppSynchronize(CFSTR("com.huami.actiongesture"));
    }

    if (![[self preferenceValueForKey:
            [self storageKeyForGesture:gesture
                             direction:direction
                                suffix:@"initialized"]]
            boolValue]) {
        return nil;
    }

    AGGestureConfiguration *configuration = [AGGestureConfiguration new];
    configuration.hasSection =
        [[self preferenceValueForKey:
            [self storageKeyForGesture:gesture
                             direction:direction
                                suffix:@"hasSection"]]
            boolValue];
    configuration.hasArchive =
        [[self preferenceValueForKey:
            [self storageKeyForGesture:gesture
                             direction:direction
                                suffix:@"hasArchive"]]
            boolValue];

    id sectionIdentifier =
        [self preferenceValueForKey:
            [self storageKeyForGesture:gesture
                             direction:direction
                                suffix:@"section"]];
    id configuredActionArchive =
        [self preferenceValueForKey:
            [self storageKeyForGesture:gesture
                             direction:direction
                                suffix:@"archive"]];
    if ([sectionIdentifier isKindOfClass:NSString.class]) {
        configuration.sectionIdentifier = sectionIdentifier;
    }
    if ([configuredActionArchive isKindOfClass:NSData.class]) {
        configuration.configuredActionArchive = configuredActionArchive;
    }
    return configuration;
}

- (BOOL)hasStoredConfigurationForGesture:(NSString *)gesture
                               direction:(NSString *)direction {
    return [self configurationForGesture:gesture
                               direction:direction
                             synchronize:YES] != nil;
}

- (AGGestureConfiguration *)currentNativeConfiguration {
    NSUserDefaults *defaults = [self springBoardDefaults];
    NSString *sectionIdentifier =
        [defaults objectForKey:@"SBSystemActionSelectedSectionIdentifier"];
    NSData *configuredActionArchive =
        [defaults objectForKey:@"SBSystemActionConfiguredActionArchive"];

    AGGestureConfiguration *configuration = [AGGestureConfiguration new];
    configuration.hasSection =
        [sectionIdentifier isKindOfClass:NSString.class];
    configuration.hasArchive =
        [configuredActionArchive isKindOfClass:NSData.class];
    configuration.sectionIdentifier =
        configuration.hasSection ? sectionIdentifier : nil;
    configuration.configuredActionArchive =
        configuration.hasArchive ? configuredActionArchive : nil;
    return configuration;
}

- (void)storeConfiguration:(AGGestureConfiguration *)configuration
                forGesture:(NSString *)gesture
                 direction:(NSString *)direction
               synchronize:(BOOL)synchronize {
    if (!configuration ||
        ![self isKnownGesture:gesture] ||
        (direction && ![self isKnownDirection:direction])) {
        return;
    }
    [self setPreferenceValue:@YES
                      forKey:[self storageKeyForGesture:gesture
                                             direction:direction
                                                suffix:@"initialized"]];
    [self setPreferenceValue:@(configuration.hasSection)
                      forKey:[self storageKeyForGesture:gesture
                                             direction:direction
                                                suffix:@"hasSection"]];
    [self setPreferenceValue:@(configuration.hasArchive)
                      forKey:[self storageKeyForGesture:gesture
                                             direction:direction
                                                suffix:@"hasArchive"]];
    [self setPreferenceValue:configuration.hasSection
                                 ? configuration.sectionIdentifier
                                 : nil
                      forKey:[self storageKeyForGesture:gesture
                                             direction:direction
                                                suffix:@"section"]];
    [self setPreferenceValue:configuration.hasArchive
                                 ? configuration.configuredActionArchive
                                 : nil
                      forKey:[self storageKeyForGesture:gesture
                                             direction:direction
                                                suffix:@"archive"]];
    if (synchronize) {
        CFPreferencesAppSynchronize(CFSTR("com.huami.actiongesture"));
    }
}

- (void)snapshotNativeConfigurationForGesture:(NSString *)gesture
                                     direction:(NSString *)direction {
    [self storeConfiguration:[self currentNativeConfiguration]
                  forGesture:gesture
                   direction:direction
                 synchronize:YES];
}

- (void)initializeDirectionalConfigurations {
    CFPreferencesAppSynchronize(CFSTR("com.huami.actiongesture"));
    for (NSString *gesture in
            @[ AGGestureSingle, AGGestureDouble, AGGestureLong ]) {
        if ([self configurationForGesture:gesture
                                direction:AGDirectionPortrait
                              synchronize:NO]) {
            continue;
        }
        AGGestureConfiguration *configuration =
            [self configurationForGesture:gesture
                                direction:nil
                              synchronize:NO];
        if (!configuration) continue;
        [self storeConfiguration:configuration
                      forGesture:gesture
                       direction:AGDirectionPortrait
                     synchronize:NO];
    }
    CFPreferencesAppSynchronize(CFSTR("com.huami.actiongesture"));
}

- (void)removeConfigurationForGesture:(NSString *)gesture
                            direction:(NSString *)direction
                          synchronize:(BOOL)synchronize {
    for (NSString *suffix in
            @[ @"initialized", @"hasSection", @"hasArchive",
               @"section", @"archive" ]) {
        [self setPreferenceValue:nil
                          forKey:[self storageKeyForGesture:gesture
                                                 direction:direction
                                                    suffix:suffix]];
    }
    if (synchronize) {
        CFPreferencesAppSynchronize(CFSTR("com.huami.actiongesture"));
    }
}

- (BOOL)configuration:(AGGestureConfiguration *)configuration
    isEqualToConfiguration:(AGGestureConfiguration *)otherConfiguration {
    if (!configuration || !otherConfiguration ||
        configuration.hasSection != otherConfiguration.hasSection ||
        configuration.hasArchive != otherConfiguration.hasArchive) {
        return NO;
    }
    BOOL sectionsEqual =
        configuration.sectionIdentifier ==
            otherConfiguration.sectionIdentifier ||
        [configuration.sectionIdentifier
            isEqual:otherConfiguration.sectionIdentifier];
    BOOL archivesEqual =
        configuration.configuredActionArchive ==
            otherConfiguration.configuredActionArchive ||
        [configuration.configuredActionArchive
            isEqual:otherConfiguration.configuredActionArchive];
    return sectionsEqual && archivesEqual;
}

- (void)migrateDirectionalFallbackModelIfNeeded {
    CFPreferencesAppSynchronize(CFSTR("com.huami.actiongesture"));
    if ([[self preferenceValueForKey:@"directionFallbackModelVersion"]
            integerValue] >= 1) {
        return;
    }

    for (NSString *gesture in
            @[ AGGestureSingle, AGGestureDouble, AGGestureLong ]) {
        AGGestureConfiguration *baseline =
            [self configurationForGesture:gesture
                                direction:nil
                              synchronize:NO];
        AGGestureConfiguration *portrait =
            [self configurationForGesture:gesture
                                direction:AGDirectionPortrait
                              synchronize:NO];
        if (!portrait && baseline) {
            portrait = baseline;
            [self storeConfiguration:portrait
                          forGesture:gesture
                           direction:AGDirectionPortrait
                         synchronize:NO];
        }
        if (!portrait) continue;

        for (NSString *direction in [self directions]) {
            if ([direction isEqualToString:AGDirectionPortrait]) continue;

            AGGestureConfiguration *configuration =
                [self configurationForGesture:gesture
                                    direction:direction
                                  synchronize:NO];
            BOOL matchesInheritedValue =
                [self configuration:configuration
                    isEqualToConfiguration:portrait] ||
                [self configuration:configuration
                    isEqualToConfiguration:baseline];
            if (matchesInheritedValue) {
                [self removeConfigurationForGesture:gesture
                                          direction:direction
                                        synchronize:NO];
            }
        }
    }
    [self setPreferenceValue:@1 forKey:@"directionFallbackModelVersion"];
    CFPreferencesAppSynchronize(CFSTR("com.huami.actiongesture"));
}

- (AGGestureConfiguration *)effectiveConfigurationForGesture:
                                (NSString *)gesture
                                                   direction:
                                                       (NSString *)direction
                                           resolvedDirection:
                                               (NSString **)resolvedDirection
                                                 synchronize:(BOOL)synchronize {
    if (synchronize) {
        CFPreferencesAppSynchronize(CFSTR("com.huami.actiongesture"));
    }
    if (direction) {
        AGGestureConfiguration *configuration =
            [self configurationForGesture:gesture
                                direction:direction
                              synchronize:NO];
        if (configuration) {
            if (resolvedDirection) *resolvedDirection = direction;
            return configuration;
        }

        configuration =
            [self configurationForGesture:gesture
                                direction:AGDirectionPortrait
                              synchronize:NO];
        if (configuration) {
            if (resolvedDirection) {
                *resolvedDirection = AGDirectionPortrait;
            }
            return configuration;
        }
    }

    if (resolvedDirection) *resolvedDirection = nil;
    return [self configurationForGesture:gesture
                               direction:nil
                             synchronize:NO];
}

- (BOOL)applyConfiguration:(AGGestureConfiguration *)configuration {
    if (!configuration) return NO;

    NSUserDefaults *defaults = [self springBoardDefaults];
    BOOL wasSuppressingSnapshots = self.suppressSystemActionSnapshots;
    self.suppressSystemActionSnapshots = YES;
    BOOL synchronized = NO;
    @try {
        if (configuration.hasSection && configuration.sectionIdentifier) {
            [defaults setObject:configuration.sectionIdentifier
                         forKey:@"SBSystemActionSelectedSectionIdentifier"];
        } else {
            [defaults removeObjectForKey:
                @"SBSystemActionSelectedSectionIdentifier"];
        }

        if (configuration.hasArchive &&
            configuration.configuredActionArchive) {
            [defaults setObject:configuration.configuredActionArchive
                         forKey:@"SBSystemActionConfiguredActionArchive"];
        } else {
            [defaults removeObjectForKey:
                @"SBSystemActionConfiguredActionArchive"];
        }
        synchronized = [defaults synchronize];
    } @finally {
        self.suppressSystemActionSnapshots = wasSuppressingSnapshots;
    }
    return synchronized;
}

- (BOOL)applyNativeConfigurationForGesture:(NSString *)gesture
                                  direction:(NSString *)direction {
    return [self applyConfiguration:
        [self effectiveConfigurationForGesture:gesture
                                     direction:direction
                             resolvedDirection:nil
                                   synchronize:YES]];
}

- (void)beginSuppressingSystemActionSnapshots {
    self.suppressSystemActionSnapshots = YES;
}

- (void)endSuppressingSystemActionSnapshots {
    self.suppressSystemActionSnapshots = NO;
}

- (void)systemActionPreferenceDidChangeForKey:(NSString *)key {
    if (self.suppressSystemActionSnapshots) return;
    if (![key isEqualToString:@"SBSystemActionSelectedSectionIdentifier"] &&
        ![key isEqualToString:@"SBSystemActionConfiguredActionArchive"]) {
        return;
    }

    NSString *gesture = self.currentGesture;
    NSString *direction = [self activeEditorDirection];
    dispatch_block_t scheduleSnapshot = ^{
        self.pendingSnapshotGesture = gesture;
        self.pendingSnapshotDirection = direction;
        if (self.snapshotScheduled) return;

        self.snapshotScheduled = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *pendingGesture = self.pendingSnapshotGesture;
            NSString *pendingDirection = self.pendingSnapshotDirection;
            self.pendingSnapshotGesture = nil;
            self.pendingSnapshotDirection = nil;
            self.snapshotScheduled = NO;
            [self snapshotNativeConfigurationForGesture:pendingGesture
                                               direction:pendingDirection];
        });
    };

    if (NSThread.isMainThread) {
        scheduleSnapshot();
    } else {
        dispatch_async(dispatch_get_main_queue(), scheduleSnapshot);
    }
}

- (NSBundle *)localizationBundle {
    static NSBundle *bundle;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bundle = [NSBundle bundleWithPath:
            jbroot(@"/Library/Application Support/ActionGesture.bundle")];
    });
    return bundle;
}

- (NSString *)localizedStringForKey:(NSString *)key {
    NSArray<NSString *> *languages = NSLocale.preferredLanguages;
    if (languages.count && [languages.firstObject hasPrefix:@"zh"]) {
        NSDictionary *zh = @{
            @"gesture.single": @"单击", @"gesture.double": @"双击",
            @"gesture.long": @"长按", @"menu.title": @"选择手势",
            @"direction.all": @"所有方向", @"direction.mode": @"按方向区分",
            @"direction.mode.subtitle": @"未设置的方向跟随正对屏幕",
            @"direction.menu": @"选择方向", @"direction.help.title": @"方向说明",
            @"direction.help.done": @"完成", @"direction.faceUp": @"屏幕朝上",
            @"direction.faceDown": @"屏幕朝下", @"direction.portrait": @"正对屏幕",
            @"direction.portraitUpsideDown": @"倒立",
            @"direction.landscapeLeft": @"向左横放",
            @"direction.landscapeRight": @"向右横放",
            @"accessibility.directionHelp": @"方向说明"
        };
        NSString *value = zh[key];
        if (value) return value;
    }
    return [[self localizationBundle] localizedStringForKey:key value:key table:nil];
}

- (NSString *)titleForGesture:(NSString *)gesture {
    if ([gesture isEqualToString:AGGestureDouble]) {
        return [self localizedStringForKey:@"gesture.double"];
    }
    if ([gesture isEqualToString:AGGestureLong]) {
        return [self localizedStringForKey:@"gesture.long"];
    }
    return [self localizedStringForKey:@"gesture.single"];
}

- (NSString *)symbolForGesture:(NSString *)gesture {
    if ([gesture isEqualToString:AGGestureDouble]) return @"hand.tap.fill";
    if ([gesture isEqualToString:AGGestureLong]) {
        return @"hand.point.up.left.fill";
    }
    return @"hand.tap";
}

- (NSString *)titleForDirection:(NSString *)direction {
    if ([direction isEqualToString:AGDirectionFaceUp]) {
        return [self localizedStringForKey:@"direction.faceUp"];
    }
    if ([direction isEqualToString:AGDirectionFaceDown]) {
        return [self localizedStringForKey:@"direction.faceDown"];
    }
    if ([direction isEqualToString:AGDirectionPortrait]) {
        return [self localizedStringForKey:@"direction.portrait"];
    }
    if ([direction isEqualToString:AGDirectionPortraitUpsideDown]) {
        return [self localizedStringForKey:@"direction.portraitUpsideDown"];
    }
    if ([direction isEqualToString:AGDirectionLandscapeLeft]) {
        return [self localizedStringForKey:@"direction.landscapeLeft"];
    }
    if ([direction isEqualToString:AGDirectionLandscapeRight]) {
        return [self localizedStringForKey:@"direction.landscapeRight"];
    }
    return [self localizedStringForKey:@"direction.all"];
}

- (NSString *)subtitleForDirection:(NSString *)direction {
    NSString *key =
        [NSString stringWithFormat:@"direction.%@.subtitle", direction];
    return [self localizedStringForKey:key];
}

- (NSString *)directionForGravity:(CMAcceleration)gravity {
    double absoluteX = fabs(gravity.x);
    double absoluteY = fabs(gravity.y);
    double absoluteZ = fabs(gravity.z);
    BOOL wasFlat =
        [self.sampledDirection isEqualToString:AGDirectionFaceUp] ||
        [self.sampledDirection isEqualToString:AGDirectionFaceDown];

    if (!self.sampledDirection &&
        absoluteZ >= absoluteX &&
        absoluteZ >= absoluteY) {
        return gravity.z < 0.0
            ? AGDirectionFaceUp
            : AGDirectionFaceDown;
    }
    if ((wasFlat && absoluteZ >= 0.78) ||
        (!wasFlat && absoluteZ >= 0.88)) {
        return gravity.z < 0.0
            ? AGDirectionFaceUp
            : AGDirectionFaceDown;
    }

    BOOL wasLandscape =
        [self.sampledDirection isEqualToString:AGDirectionLandscapeLeft] ||
        [self.sampledDirection isEqualToString:AGDirectionLandscapeRight];
    BOOL wasPortrait =
        [self.sampledDirection isEqualToString:AGDirectionPortrait] ||
        [self.sampledDirection
            isEqualToString:AGDirectionPortraitUpsideDown];

    if (wasLandscape && absoluteX + 0.12 >= absoluteY) {
        return gravity.x < 0.0
            ? AGDirectionLandscapeLeft
            : AGDirectionLandscapeRight;
    }
    if (wasPortrait && absoluteY + 0.12 >= absoluteX) {
        return gravity.y < 0.0
            ? AGDirectionPortrait
            : AGDirectionPortraitUpsideDown;
    }
    if (absoluteX > absoluteY) {
        return gravity.x < 0.0
            ? AGDirectionLandscapeLeft
            : AGDirectionLandscapeRight;
    }
    return gravity.y < 0.0
        ? AGDirectionPortrait
        : AGDirectionPortraitUpsideDown;
}

- (void)beginDirectionSampling {
    if (!self.directionModeEnabled) {
        [self cancelDirectionSampling];
        return;
    }
    if (self.motionManager.deviceMotionActive) return;

    if (!self.motionManager) {
        self.motionManager = [CMMotionManager new];
        self.motionManager.deviceMotionUpdateInterval = 0.05;
    }
    if (!self.motionManager.deviceMotionAvailable) return;

    self.sampledDirection = nil;
    __weak ActionGestureHelper *weakSelf = self;
    [self.motionManager
        startDeviceMotionUpdatesToQueue:NSOperationQueue.mainQueue
                            withHandler:
                                ^(CMDeviceMotion *motion,
                                  __unused NSError *error) {
        ActionGestureHelper *helper = weakSelf;
        if (!helper || !motion || error) return;
        helper.sampledDirection =
            [helper directionForGravity:motion.gravity];
    }];
}

- (void)cancelDirectionSampling {
    [self.motionManager stopDeviceMotionUpdates];
    self.sampledDirection = nil;
}

- (NSString *)finishDirectionSampling {
    NSString *direction =
        self.directionModeEnabled &&
        [self isKnownDirection:self.sampledDirection]
            ? self.sampledDirection
            : nil;
    [self cancelDirectionSampling];
    return direction;
}

- (NSString *)assignmentIdentifierForGesture:(NSString *)gesture
                                    direction:(NSString *)direction {
    return direction
        ? [NSString stringWithFormat:@"%@.%@", gesture, direction]
        : gesture;
}

- (void)reloadDirectionMode {
    CFPreferencesAppSynchronize(CFSTR("com.huami.actiongesture"));
    self.directionModeEnabled =
        [[self preferenceValueForKey:@"directionModeEnabled"] boolValue];
    if (!self.directionModeEnabled) {
        [self cancelDirectionSampling];
    }
}

- (SBSystemActionAbstractDataSource *)dataSourceForButton:
    (SBRingerHardwareButton *)button {
    Ivar controlIvar =
        class_getInstanceVariable(object_getClass(button),
                                  "_systemActionControl");
    if (!controlIvar) return nil;

    SBSystemActionControl *control = object_getIvar(button, controlIvar);
    Ivar dataSourceIvar =
        class_getInstanceVariable(object_getClass(control), "_dataSource");
    if (!dataSourceIvar) return nil;

    SBSystemActionAbstractDataSource *dataSource =
        object_getIvar(control, dataSourceIvar);
    for (NSUInteger depth = 0; dataSource && depth < 4; depth++) {
        Ivar innerDataSourceIvar =
            class_getInstanceVariable(object_getClass(dataSource),
                                      "_innerDataSource");
        if (!innerDataSourceIvar) break;

        SBSystemActionAbstractDataSource *innerDataSource =
            object_getIvar(dataSource, innerDataSourceIvar);
        if (!innerDataSource) break;
        dataSource = innerDataSource;
    }
    return dataSource;
}

- (BOOL)prepareSpringBoardRuntime {
    Class buttonClass = objc_getClass("SBRingerHardwareButton");
    Class actionControlClass = objc_getClass("SBSystemActionControl");
    Class linkActionClass = objc_getClass("SBLinkSystemAction");
    Method downMethod =
        class_getInstanceMethod(
            buttonClass,
            @selector(performActionsForButtonDown:));
    Method longPressMethod =
        class_getInstanceMethod(
            buttonClass,
            @selector(performActionsForButtonLongPress:));
    Method upMethod =
        class_getInstanceMethod(
            buttonClass,
            @selector(performActionsForButtonUp:));

    if (!buttonClass || !downMethod || !longPressMethod || !upMethod) {
        AGWriteLog(@"[ActionGesture] SpringBoard hook unavailable: button=%@ down=%@ long=%@ up=%@",
              buttonClass, downMethod ? @"YES" : @"NO",
              longPressMethod ? @"YES" : @"NO",
              upMethod ? @"YES" : @"NO");
        return NO;
    }

    AGWriteLog(@"[ActionGesture] SpringBoard classes: button=%@ control=%@ linkAction=%@ controlIvar=%@ dataSourceIvar=%@ linkInit=%@",
          buttonClass, actionControlClass, linkActionClass,
          class_getInstanceVariable(buttonClass, "_systemActionControl") ? @"YES" : @"NO",
          class_getInstanceVariable(actionControlClass, "_dataSource") ? @"YES" : @"NO",
          class_getInstanceMethod(linkActionClass, @selector(initWithConfiguredAction:)) ? @"YES" : @"NO");
    AGLogRuntimeMethods(buttonClass);
    AGLogRuntimeMethods(actionControlClass);
    AGLogRuntimeMethods(linkActionClass);
    AGLogRuntimeMethods(objc_getClass("SBSystemActionAbstractDataSource"));

    self.originalButtonDown =
        (AGButtonEventIMP)method_getImplementation(downMethod);
    self.originalButtonLongPress =
        (AGButtonEventIMP)method_getImplementation(longPressMethod);
    self.originalButtonUp =
        (AGButtonEventIMP)method_getImplementation(upMethod);
    [self migrateDirectionalFallbackModelIfNeeded];
    [self reloadDirectionMode];
    __weak ActionGestureHelper *weakSelf = self;
    int notificationToken = 0;
    notify_register_dispatch(
        "com.huami.actiongesture.direction-mode-changed",
        &notificationToken,
        dispatch_get_main_queue(),
        ^(__unused int token) {
            [weakSelf reloadDirectionMode];
        });
    self.directionNotificationToken = notificationToken;
    return self.originalButtonDown &&
           self.originalButtonLongPress &&
           self.originalButtonUp;
}

- (BOOL)canHandleButton:(SBRingerHardwareButton *)button {
    // The data source is only needed when restoring a native system action.
    // It must not disable the gesture hook: custom URL actions execute even
    // when iOS 17 changes the private Action Button data-source ivars.
    return button && self.originalButtonDown &&
           self.originalButtonLongPress && self.originalButtonUp;
}

- (BOOL)nativeActionIsNothingOnButton:(SBRingerHardwareButton *)button
                         configuration:(AGGestureConfiguration *)configuration {
    SBSystemActionAbstractDataSource *dataSource =
        [self dataSourceForButton:button];
    SEL selectedSEL = sel_registerName("selectedSystemAction");
    if (dataSource && [dataSource respondsToSelector:selectedSEL]) {
        // The data source can retain the previous archived action after the
        // user selects Nothing. Refresh it before inspecting the selection,
        // otherwise Nothing is indistinguishable from a stale system action.
        if ([dataSource respondsToSelector:@selector(updateSelectedAction)]) {
            [dataSource updateSelectedAction];
        }
        id selected = ((id (*)(id, SEL))objc_msgSend)(dataSource, selectedSEL);
        NSString *className = selected ? NSStringFromClass([selected class]) : nil;
        AGWriteLog(@"[ActionGesture] live native selection=%@",
              className ?: @"(none)");
        // iOS 17 represents the Action Button's Nothing assignment as an
        // SBBlockSystemAction object, not nil.  Treat that concrete action
        // as Nothing while preserving SBLinkSystemAction and other real
        // native actions.
        if ([className isEqualToString:@"SBBlockSystemAction"] ||
            [className hasSuffix:@"BlockSystemAction"]) {
            return YES;
        }
        return selected == nil;
    }
    // Do not use hasSection here: on iOS 17 the section identifier may be
    // absent even when the archive represents a valid native action.
    return !configuration.hasArchive;
}

- (SBLinkSystemAction *)systemActionForAssignmentIdentifier:
                            (NSString *)assignmentIdentifier
                                      configuration:
                                          (AGGestureConfiguration *)configuration {
    if (!configuration.hasArchive ||
        !configuration.configuredActionArchive) {
        return nil;
    }

    NSDictionary *cachedAction =
        self.systemActionCache[assignmentIdentifier];
    if ([cachedAction[@"archive"]
            isEqualToData:configuration.configuredActionArchive]) {
        return cachedAction[@"action"];
    }

    NSError *error = nil;
    WFConfiguredStaccatoAction *configuredAction = nil;
    @try {
        configuredAction =
            [NSKeyedUnarchiver
                unarchiveTopLevelObjectWithData:
                    configuration.configuredActionArchive
                                       error:&error];
    } @catch (__unused NSException *exception) {
        return nil;
    }
    if (!configuredAction || error) return nil;

    SBLinkSystemAction *systemAction =
        [(SBLinkSystemAction *)[objc_getClass("SBLinkSystemAction") alloc]
            initWithConfiguredAction:configuredAction];
    if (!systemAction) return nil;

    self.systemActionCache[assignmentIdentifier] = @{
        @"archive": configuration.configuredActionArchive,
        @"action": systemAction
    };
    return systemAction;
}

- (BOOL)selectConfiguration:(AGGestureConfiguration *)configuration
       assignmentIdentifier:(NSString *)assignmentIdentifier
                   onButton:(SBRingerHardwareButton *)button {
    SBSystemActionAbstractDataSource *dataSource =
        [self dataSourceForButton:button];
    if (![dataSource
            respondsToSelector:@selector(setSelectedSystemAction:)]) {
        return NO;
    }

    if (!configuration.hasArchive) {
        [dataSource setSelectedSystemAction:nil];
        return YES;
    }

    SBLinkSystemAction *systemAction =
        [self systemActionForAssignmentIdentifier:assignmentIdentifier
                                    configuration:configuration];
    if (!systemAction) return NO;
    [dataSource setSelectedSystemAction:systemAction];
    return YES;
}

- (BOOL)reloadSelectedActionOnButton:(SBRingerHardwareButton *)button {
    SBSystemActionAbstractDataSource *dataSource =
        [self dataSourceForButton:button];
    if (![dataSource respondsToSelector:@selector(updateSelectedAction)]) {
        return NO;
    }
    [dataSource updateSelectedAction];
    return YES;
}

- (BOOL)replayNativeActionOnButton:(SBRingerHardwareButton *)button
                              event:(id<AGHardwareButtonEvent>)event {
    if (!self.originalButtonDown ||
        !self.originalButtonLongPress ||
        !self.originalButtonUp ||
        !button ||
        !event) {
        return NO;
    }

    self.originalButtonDown(
        button, @selector(performActionsForButtonDown:), event);
    self.originalButtonLongPress(
        button, @selector(performActionsForButtonLongPress:), event);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{
        self.originalButtonUp(
            button, @selector(performActionsForButtonUp:), event);
    });
    return YES;
}

- (BOOL)executeGesture:(NSString *)gesture
              onButton:(SBRingerHardwareButton *)button
                 event:(id<AGHardwareButtonEvent>)event {
    if (!button || !event) {
        [self cancelDirectionSampling];
        return NO;
    }

    NSString *direction = [self finishDirectionSampling];
    NSString *resolvedDirection = nil;
    AGGestureConfiguration *configuration =
        [self effectiveConfigurationForGesture:gesture
                                     direction:direction
                             resolvedDirection:&resolvedDirection
                                   synchronize:YES];
    if (!configuration) {
        [self snapshotNativeConfigurationForGesture:gesture direction:nil];
        configuration =
            [self effectiveConfigurationForGesture:gesture
                                         direction:direction
                                 resolvedDirection:&resolvedDirection
                                       synchronize:YES];
    }
    if (!configuration) return NO;

    NSString *customAction = [self customActionForGesture:gesture
                                                 direction:direction];
    // iOS 17 can leave a stale configured-action archive behind after the
    // user selects Nothing.  The section identifier is the authoritative
    // marker: no section means no native system action, even when an old
    // archive is still present in SpringBoard preferences.
    BOOL nativeActionIsNothing =
        [self nativeActionIsNothingOnButton:button configuration:configuration];
    AGWriteLog(@"[ActionGesture] execute %@ direction=%@ resolved=%@ nativeSection=%@ nativeArchive=%@ customAction=%@",
          gesture, direction ?: @"all", resolvedDirection ?: @"baseline",
          configuration.hasSection ? @"YES" : @"NO",
          configuration.hasArchive ? @"YES" : @"NO", customAction);

    // The live SpringBoard data source is authoritative at execution time.
    // On iOS 17 the archived section key can be absent while the live object
    // is still a valid SBLinkSystemAction. Re-applying that incomplete
    // archive would replace a working native action with an unusable object.
    // Only switch to a stored per-gesture action when both archive fields are
    // complete; otherwise leave the live native selection untouched.
    if (!nativeActionIsNothing && configuration.hasSection &&
        configuration.hasArchive) {
        NSString *assignmentIdentifier =
            [self assignmentIdentifierForGesture:gesture
                                       direction:resolvedDirection];
        BOOL selected =
            [self selectConfiguration:configuration
                 assignmentIdentifier:assignmentIdentifier
                             onButton:button];
        if (!selected) {
            AGWriteLog(@"[ActionGesture] stored native action was not selected; preserving live action");
        } else {
            [self reloadSelectedActionOnButton:button];
        }
    }

    if (nativeActionIsNothing) {
        if (![customAction isEqualToString:AGCustomActionNative]) {
            AGWriteLog(@"[ActionGesture] %@ has no native action; executing custom action %@",
                  gesture, customAction);
            return [self executeCustomAction:customAction];
        }

        AGWriteLog(@"[ActionGesture] %@ resolved to Nothing; consuming event without native replay",
              gesture);
        return YES;
    }

    if (![customAction isEqualToString:AGCustomActionNative]) {
        AGWriteLog(@"[ActionGesture] native action is active; ignoring custom action %@",
              customAction);
    }
    BOOL replayed = [self replayNativeActionOnButton:button event:event];
    AGWriteLog(@"[ActionGesture] native action replay result=%@",
          replayed ? @"YES" : @"NO");
    return replayed;
}

- (void)replayNativeTapOnButton:(SBRingerHardwareButton *)button
                      downEvent:(id<AGHardwareButtonEvent>)downEvent
                        upEvent:(id<AGHardwareButtonEvent>)upEvent {
    if (!self.originalButtonDown ||
        !self.originalButtonUp ||
        !button ||
        !downEvent ||
        !upEvent) {
        return;
    }
    self.originalButtonDown(
        button, @selector(performActionsForButtonDown:), downEvent);
    self.originalButtonUp(
        button, @selector(performActionsForButtonUp:), upEvent);
}

@end
