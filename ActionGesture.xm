#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <unistd.h>

#import "ActionGestureHelper.h"

typedef void (*AGButtonIMP)(id, SEL, id);
typedef void (*AGConfigureIMP)(id, SEL);
typedef void (*AGSystemActionUpdateIMP)(id, SEL, id, id);

static BOOL AGButtonIsDown;
static BOOL AGDidRecognizeLongPress;
static BOOL AGWaitingForSecondTap;
static BOOL AGSecondTapInProgress;
static BOOL AGPassThroughNative;
static BOOL AGImmediateSingleTriggered;
static BOOL AGDirectHooksInstalled;
static NSUInteger AGTapGeneration;
static id<AGHardwareButtonEvent> AGCurrentButtonDownEvent;
static AGButtonIMP AGOriginalButtonDown;
static AGButtonIMP AGOriginalButtonLongPress;
static AGButtonIMP AGOriginalButtonUp;
static AGConfigureIMP AGOriginalConfigureButtonArbiter;
static AGSystemActionUpdateIMP AGOriginalSystemActionUpdate;

static void AGHookButtonDown(id self, SEL _cmd, id event) {
    ActionGestureHelper *helper = [ActionGestureHelper sharedHelper];
    if (![helper canHandleButton:(SBRingerHardwareButton *)self]) {
        AGWriteLog(@"[ActionGesture] ButtonDown bypassed: helper not ready");
        AGPassThroughNative = YES;
        if (AGOriginalButtonDown) AGOriginalButtonDown(self, _cmd, event);
        return;
    }
    AGWriteLog(@"[ActionGesture] intercepted Action Button down (%@)", self);
    [helper beginDirectionSampling];
    AGPassThroughNative = NO;
    AGButtonIsDown = YES;
    AGDidRecognizeLongPress = NO;
    AGImmediateSingleTriggered = NO;
    AGCurrentButtonDownEvent = event;
    AGSecondTapInProgress = AGWaitingForSecondTap;
    if (!AGSecondTapInProgress && [helper shouldTriggerSingleActionImmediately]) {
        AGImmediateSingleTriggered = [helper executeGesture:AGGestureSingle
                                                    onButton:(SBRingerHardwareButton *)self
                                                       event:event];
        if (AGImmediateSingleTriggered) {
            AGWaitingForSecondTap = NO;
            ++AGTapGeneration;
            AGWriteLog(@"[ActionGesture] immediate single custom action consumed ButtonDown");
        }
    }
    if (AGSecondTapInProgress) {
        AGWaitingForSecondTap = NO;
        ++AGTapGeneration;
    }
}

static void AGHookButtonLongPress(id self, SEL _cmd, id event) {
    ActionGestureHelper *helper = [ActionGestureHelper sharedHelper];
    if (AGPassThroughNative) {
        if (AGOriginalButtonLongPress) AGOriginalButtonLongPress(self, _cmd, event);
        return;
    }
    if (!AGButtonIsDown) return;
    if (AGImmediateSingleTriggered) {
        AGDidRecognizeLongPress = YES;
        AGWaitingForSecondTap = NO;
        AGSecondTapInProgress = NO;
        ++AGTapGeneration;
        return;
    }
    AGDidRecognizeLongPress = YES;
    AGWaitingForSecondTap = NO;
    AGSecondTapInProgress = NO;
    ++AGTapGeneration;
    id<AGHardwareButtonEvent> downEvent =
        [event respondsToSelector:@selector(downTime)] ? event : AGCurrentButtonDownEvent;
    if (![helper executeGesture:AGGestureLong
                       onButton:(SBRingerHardwareButton *)self
                          event:downEvent]) {
        [helper replayNativeActionOnButton:(SBRingerHardwareButton *)self event:downEvent];
    }
}

static void AGHookButtonUp(id self, SEL _cmd, id event) {
    ActionGestureHelper *helper = [ActionGestureHelper sharedHelper];
    if (AGPassThroughNative) {
        AGPassThroughNative = NO;
        AGCurrentButtonDownEvent = nil;
        if (AGOriginalButtonUp) AGOriginalButtonUp(self, _cmd, event);
        return;
    }
    if (!AGButtonIsDown) return;
    BOOL recognizedLongPress = AGDidRecognizeLongPress;
    BOOL secondTap = AGSecondTapInProgress;
    BOOL immediateSingle = AGImmediateSingleTriggered;
    id<AGHardwareButtonEvent> downEvent = AGCurrentButtonDownEvent;
    AGButtonIsDown = NO;
    AGDidRecognizeLongPress = NO;
    AGSecondTapInProgress = NO;
    AGImmediateSingleTriggered = NO;
    AGCurrentButtonDownEvent = nil;
    if (recognizedLongPress || immediateSingle) return;
    if (secondTap) {
        if (![helper executeGesture:AGGestureDouble
                           onButton:(SBRingerHardwareButton *)self
                              event:downEvent]) {
            [helper replayNativeTapOnButton:(SBRingerHardwareButton *)self
                                  downEvent:downEvent
                                    upEvent:event];
        }
        return;
    }
    AGWaitingForSecondTap = YES;
    NSUInteger generation = ++AGTapGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 90 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{
        if (AGTapGeneration != generation || !AGWaitingForSecondTap) return;
        AGWaitingForSecondTap = NO;
        if (![helper executeGesture:AGGestureSingle
                           onButton:(SBRingerHardwareButton *)self
                              event:downEvent]) {
            AGWriteLog(@"[ActionGesture] single gesture was not handled; replaying native tap");
            [helper replayNativeTapOnButton:(SBRingerHardwareButton *)self
                                  downEvent:downEvent
                                    upEvent:event];
        }
    });
}

static void AGHookConfigureButtonArbiter(id self, SEL _cmd) {
    if (AGOriginalConfigureButtonArbiter) AGOriginalConfigureButtonArbiter(self, _cmd);
    Ivar arbiterIvar = class_getInstanceVariable(object_getClass(self), "_buttonArbiter");
    id arbiter = arbiterIvar ? object_getIvar(self, arbiterIvar) : nil;
    SEL selector = sel_registerName("setMaximumRepeatedPressCount:");
    if (arbiter && [arbiter respondsToSelector:selector]) {
        ((void (*)(id, SEL, unsigned long))objc_msgSend)(arbiter, selector, 0UL);
        AGWriteLog(@"[ActionGesture] button arbiter multi-click detection disabled");
    }
}

static void AGHookSystemActionUpdate(id self, SEL _cmd, id dataSource,
                                     id selectedAction) {
    if (AGOriginalSystemActionUpdate) {
        AGOriginalSystemActionUpdate(self, _cmd, dataSource, selectedAction);
    }
    [[ActionGestureHelper sharedHelper]
        recordNativeActionSelection:selectedAction];
}

BOOL AGInstallDirectHooks(void) {
    if (AGDirectHooksInstalled) return YES;
    Class buttonClass = objc_getClass("SBRingerHardwareButton");
    if (!buttonClass) return NO;
    Method down = class_getInstanceMethod(buttonClass, @selector(performActionsForButtonDown:));
    Method longPress = class_getInstanceMethod(buttonClass, @selector(performActionsForButtonLongPress:));
    Method up = class_getInstanceMethod(buttonClass, @selector(performActionsForButtonUp:));
    if (!down || !longPress || !up) return NO;
    ActionGestureHelper *helper = [ActionGestureHelper sharedHelper];
    if (![helper prepareSpringBoardRuntime]) return NO;
    AGOriginalButtonDown = (AGButtonIMP)method_getImplementation(down);
    AGOriginalButtonLongPress = (AGButtonIMP)method_getImplementation(longPress);
    AGOriginalButtonUp = (AGButtonIMP)method_getImplementation(up);
    method_setImplementation(down, (IMP)AGHookButtonDown);
    method_setImplementation(longPress, (IMP)AGHookButtonLongPress);
    method_setImplementation(up, (IMP)AGHookButtonUp);
    Method configure = class_getInstanceMethod(buttonClass, sel_registerName("_configureButtonArbiter"));
    if (configure) {
        AGOriginalConfigureButtonArbiter = (AGConfigureIMP)method_getImplementation(configure);
        method_setImplementation(configure, (IMP)AGHookConfigureButtonArbiter);
    }
    Class actionControlClass = objc_getClass("SBSystemActionControl");
    Method actionUpdate = class_getInstanceMethod(
        actionControlClass,
        sel_registerName("systemActionDataSource:didUpdateSelectedAction:"));
    if (actionUpdate) {
        AGOriginalSystemActionUpdate =
            (AGSystemActionUpdateIMP)method_getImplementation(actionUpdate);
        method_setImplementation(actionUpdate, (IMP)AGHookSystemActionUpdate);
    }
    AGDirectHooksInstalled = YES;
    AGWriteLog(@"[ActionGesture] direct runtime hooks installed; arbiterHook=%@ actionUpdateHook=%@",
               configure ? @"YES" : @"NO", actionUpdate ? @"YES" : @"NO");
    return YES;
}

// RootHide may load the image after the normal C constructor phase has
// already passed.  Expose a second Objective-C load entry point from the
// helper class so SpringBoard always gets a chance to install the hooks.
@interface ActionGestureHelper (RuntimeBootstrap)
+ (void)ag_bootstrapRuntime;
@end

__attribute__((constructor)) static void AGConstructor(void) {
    @autoreleasepool {
        AGWriteLog(@"[ActionGesture] constructor bundle=%@ process=%d",
                   NSBundle.mainBundle.bundleIdentifier ?: @"(nil)", getpid());
        for (NSUInteger attempt = 0; attempt <= 12; attempt++) {
            NSTimeInterval delay = 0.25 * attempt;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                          (int64_t)(delay * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (AGDirectHooksInstalled) return;
                if (!AGInstallDirectHooks() && attempt == 12) {
                    AGWriteLog(@"[ActionGesture] direct hook install failed after retries");
                }
            });
        }
    }
}
