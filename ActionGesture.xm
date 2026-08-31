#import <Foundation/Foundation.h>

#import "ActionGestureHelper.h"

static BOOL AGButtonIsDown;
static BOOL AGDidRecognizeLongPress;
static BOOL AGWaitingForSecondTap;
static BOOL AGSecondTapInProgress;
static BOOL AGPassThroughNative;
static BOOL AGHooksInstalled;
static BOOL AGImmediateSingleTriggered;
static NSUInteger AGTapGeneration;
static id<AGHardwareButtonEvent> AGCurrentButtonDownEvent;

%group ActionGestureSpringBoard

%hook SBRingerHardwareButton

- (void)performActionsForButtonDown:(id<AGHardwareButtonEvent>)buttonDown {
    ActionGestureHelper *helper = [ActionGestureHelper sharedHelper];
    if (![helper canHandleButton:self]) {
        NSLog(@"[ActionGesture] Action Button hook bypassed: runtime not ready");
        [helper cancelDirectionSampling];
        AGPassThroughNative = YES;
        %orig;
        return;
    }

    NSLog(@"[ActionGesture] intercepted Action Button down (%@)", self);

    [helper beginDirectionSampling];
    AGPassThroughNative = NO;
    AGButtonIsDown = YES;
    AGDidRecognizeLongPress = NO;
    AGImmediateSingleTriggered = NO;
    AGCurrentButtonDownEvent = buttonDown;
    AGSecondTapInProgress = AGWaitingForSecondTap;

    if (!AGSecondTapInProgress && [helper shouldTriggerSingleActionImmediately]) {
        AGImmediateSingleTriggered =
            [helper executeGesture:AGGestureSingle onButton:self event:buttonDown];
        if (AGImmediateSingleTriggered) {
            AGWaitingForSecondTap = NO;
            ++AGTapGeneration;
            NSLog(@"[ActionGesture] immediate single custom action consumed ButtonDown");
        }
    }

    if (AGSecondTapInProgress) {
        AGWaitingForSecondTap = NO;
        ++AGTapGeneration;
    }
}

- (void)performActionsForButtonLongPress:
    (id<AGHardwareButtonEvent>)longPress {
    if (AGPassThroughNative) {
        [[ActionGestureHelper sharedHelper] cancelDirectionSampling];
        %orig;
        return;
    }
    if (!AGButtonIsDown) {
        [[ActionGestureHelper sharedHelper] cancelDirectionSampling];
        return;
    }

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

    id<AGHardwareButtonEvent> event =
        [longPress respondsToSelector:@selector(downTime)]
            ? longPress
            : AGCurrentButtonDownEvent;
    ActionGestureHelper *helper = [ActionGestureHelper sharedHelper];
    if (![helper executeGesture:AGGestureLong onButton:self event:event]) {
        [helper replayNativeActionOnButton:self event:event];
    }
}

- (void)performActionsForButtonUp:(id<AGHardwareButtonEvent>)buttonUp {
    if (AGPassThroughNative) {
        [[ActionGestureHelper sharedHelper] cancelDirectionSampling];
        AGPassThroughNative = NO;
        AGCurrentButtonDownEvent = nil;
        %orig;
        return;
    }
    if (!AGButtonIsDown) {
        [[ActionGestureHelper sharedHelper] cancelDirectionSampling];
        return;
    }

    BOOL recognizedLongPress = AGDidRecognizeLongPress;
    BOOL secondTap = AGSecondTapInProgress;
    BOOL immediateSingle = AGImmediateSingleTriggered;
    id<AGHardwareButtonEvent> event = AGCurrentButtonDownEvent;

    AGButtonIsDown = NO;
    AGDidRecognizeLongPress = NO;
    AGSecondTapInProgress = NO;
    AGImmediateSingleTriggered = NO;
    AGCurrentButtonDownEvent = nil;

    if (recognizedLongPress) return;
    if (immediateSingle) return;

    ActionGestureHelper *helper = [ActionGestureHelper sharedHelper];
    if (secondTap) {
        if (![helper executeGesture:AGGestureDouble
                           onButton:self
                              event:event]) {
            [helper replayNativeTapOnButton:self
                                  downEvent:event
                                    upEvent:buttonUp];
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
                           onButton:self
                              event:event]) {
            NSLog(@"[ActionGesture] single gesture was not handled; replaying native tap");
            [helper replayNativeTapOnButton:self
                                  downEvent:event
                                    upEvent:buttonUp];
        }
    });
}

%end

%end

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier
                isEqualToString:@"com.apple.springboard"]) {
            return;
        }

        // SpringBoard can load the Action Button classes after tweak
        // constructors have run.  A one-shot %init would then silently miss
        // the class forever, leaving only the native Dynamic Island feedback.
        for (NSUInteger attempt = 0; attempt <= 8; attempt++) {
            NSTimeInterval delay = 0.25 * attempt;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                          (int64_t)(delay * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (AGHooksInstalled) return;

                ActionGestureHelper *helper = [ActionGestureHelper sharedHelper];
                if ([helper prepareSpringBoardRuntime]) {
                    NSLog(@"[ActionGesture] installing SBRingerHardwareButton hooks (retry %.2fs)",
                          delay);
                    %init(ActionGestureSpringBoard);
                    AGHooksInstalled = YES;
                } else if (delay >= 2.0) {
                    NSLog(@"[ActionGesture] SpringBoard runtime unavailable after retries; no hook installed");
                }
            });
        }
    }
}
