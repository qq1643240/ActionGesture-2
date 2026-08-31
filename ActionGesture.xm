#import <Foundation/Foundation.h>

#import "ActionGestureHelper.h"

static BOOL AGButtonIsDown;
static BOOL AGDidRecognizeLongPress;
static BOOL AGWaitingForSecondTap;
static BOOL AGSecondTapInProgress;
static BOOL AGPassThroughNative;
static NSUInteger AGTapGeneration;
static id<AGHardwareButtonEvent> AGCurrentButtonDownEvent;

%group ActionGestureSpringBoard

%hook SBRingerHardwareButton

- (void)performActionsForButtonDown:(id<AGHardwareButtonEvent>)buttonDown {
    ActionGestureHelper *helper = [ActionGestureHelper sharedHelper];
    if (![helper canHandleButton:self]) {
        [helper cancelDirectionSampling];
        AGPassThroughNative = YES;
        %orig;
        return;
    }

    [helper beginDirectionSampling];
    AGPassThroughNative = NO;
    AGButtonIsDown = YES;
    AGDidRecognizeLongPress = NO;
    AGCurrentButtonDownEvent = buttonDown;
    AGSecondTapInProgress = AGWaitingForSecondTap;

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
    id<AGHardwareButtonEvent> event = AGCurrentButtonDownEvent;

    AGButtonIsDown = NO;
    AGDidRecognizeLongPress = NO;
    AGSecondTapInProgress = NO;
    AGCurrentButtonDownEvent = nil;

    if (recognizedLongPress) return;

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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{
        if (AGTapGeneration != generation || !AGWaitingForSecondTap) return;

        AGWaitingForSecondTap = NO;
        if (![helper executeGesture:AGGestureSingle
                           onButton:self
                              event:event]) {
            [helper replayNativeTapOnButton:self
                                  downEvent:event
                                    upEvent:event];
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
        if (![[ActionGestureHelper sharedHelper] prepareSpringBoardRuntime]) {
            return;
        }
        %init(ActionGestureSpringBoard);
    }
}
