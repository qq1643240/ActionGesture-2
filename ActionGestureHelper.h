#import <Foundation/Foundation.h>

#import "ActionGestureHeaders.h"

NS_ASSUME_NONNULL_BEGIN

// Implemented by ActionGesture.xm; used by the Objective-C +load bootstrap.
FOUNDATION_EXPORT BOOL AGInstallDirectHooks(void);

FOUNDATION_EXPORT NSString *const AGGestureSingle;
FOUNDATION_EXPORT NSString *const AGGestureDouble;
FOUNDATION_EXPORT NSString *const AGGestureLong;

FOUNDATION_EXPORT NSString *const AGDirectionFaceUp;
FOUNDATION_EXPORT NSString *const AGDirectionFaceDown;
FOUNDATION_EXPORT NSString *const AGDirectionPortrait;
FOUNDATION_EXPORT NSString *const AGDirectionPortraitUpsideDown;
FOUNDATION_EXPORT NSString *const AGDirectionLandscapeLeft;
FOUNDATION_EXPORT NSString *const AGDirectionLandscapeRight;

FOUNDATION_EXPORT NSString *const AGCustomActionNative;
FOUNDATION_EXPORT NSString *const AGCustomActionWechatScan;
FOUNDATION_EXPORT NSString *const AGCustomActionWechatPayCode;
FOUNDATION_EXPORT NSString *const AGCustomActionAlipayScan;
FOUNDATION_EXPORT NSString *const AGCustomActionAlipayPayCode;

FOUNDATION_EXPORT void AGWriteLog(NSString *format, ...);

@interface ActionGestureHelper : NSObject
+ (void)ag_bootstrapRuntime;

@property (nonatomic, copy) NSString *currentGesture;
@property (nonatomic, copy) NSString *currentDirection;
@property (nonatomic) BOOL directionModeEnabled;
@property (nonatomic, readonly) NSBundle *settingsBundle;

+ (instancetype)sharedHelper;

- (void)loadEditorState;
- (BOOL)isKnownGesture:(NSString *)gesture;
- (BOOL)isKnownDirection:(NSString *)direction;
- (NSArray<NSString *> *)directions;
- (nullable NSString *)activeEditorDirection;
- (BOOL)hasStoredConfigurationForGesture:(NSString *)gesture
                               direction:(nullable NSString *)direction;
- (void)snapshotNativeConfigurationForGesture:(NSString *)gesture
                                     direction:(nullable NSString *)direction;
- (BOOL)applyNativeConfigurationForGesture:(NSString *)gesture
                                  direction:(nullable NSString *)direction;
- (void)saveCurrentGesture:(NSString *)gesture;
- (void)saveCurrentDirection:(NSString *)direction;
- (void)saveDirectionModeEnabled:(BOOL)enabled;
- (NSString *)customActionForGesture:(NSString *)gesture
                           direction:(nullable NSString *)direction;
- (void)saveCustomAction:(NSString *)action
               forGesture:(NSString *)gesture
                direction:(nullable NSString *)direction;
- (NSString *)titleForCustomAction:(NSString *)action;
- (BOOL)executeCustomAction:(NSString *)action;
- (BOOL)shouldTriggerSingleActionImmediately;
- (void)beginSuppressingSystemActionSnapshots;
- (void)endSuppressingSystemActionSnapshots;
- (void)systemActionPreferenceDidChangeForKey:(NSString *)key;

- (NSString *)localizedStringForKey:(NSString *)key;
- (NSString *)titleForGesture:(NSString *)gesture;
- (NSString *)symbolForGesture:(NSString *)gesture;
- (NSString *)titleForDirection:(nullable NSString *)direction;
- (NSString *)subtitleForDirection:(NSString *)direction;

- (BOOL)prepareSpringBoardRuntime;
- (BOOL)canHandleButton:(SBRingerHardwareButton *)button;
- (BOOL)nativeActionIsNothingOnButton:(SBRingerHardwareButton *)button
                         configuration:(id)configuration;
- (void)beginDirectionSampling;
- (void)cancelDirectionSampling;
- (BOOL)executeGesture:(NSString *)gesture
              onButton:(SBRingerHardwareButton *)button
                 event:(id<AGHardwareButtonEvent>)event;
- (BOOL)replayNativeActionOnButton:(SBRingerHardwareButton *)button
                              event:(id<AGHardwareButtonEvent>)event;
- (void)replayNativeTapOnButton:(SBRingerHardwareButton *)button
                      downEvent:(id<AGHardwareButtonEvent>)downEvent
                        upEvent:(id<AGHardwareButtonEvent>)upEvent;

@end

NS_ASSUME_NONNULL_END
