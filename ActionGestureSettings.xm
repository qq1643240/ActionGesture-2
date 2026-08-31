#import <UIKit/UIKit.h>

#import "ActionGestureHelper.h"

%group ActionGestureOfficialSettings

%hook NSUserDefaults

- (void)setObject:(id)value forKey:(NSString *)defaultName {
    %orig;
    [[ActionGestureHelper sharedHelper]
        systemActionPreferenceDidChangeForKey:defaultName];
}

- (void)removeObjectForKey:(NSString *)defaultName {
    %orig;
    [[ActionGestureHelper sharedHelper]
        systemActionPreferenceDidChangeForKey:defaultName];
}

%end

%hook ActionButtonSettings

%new
- (void)ag_installSelectors {
    ActionGestureHelper *helper = [ActionGestureHelper sharedHelper];
    NSString *gestureTitle =
        [helper titleForGesture:helper.currentGesture];
    NSString *directionTitle =
        [helper titleForDirection:[helper activeEditorDirection]];

    UIButton *gestureButton =
        [self ag_selectorButtonWithTitle:gestureTitle
                                   menu:[self ag_gestureMenu]
                     accessibilityLabel:
                         [NSString stringWithFormat:
                             [helper localizedStringForKey:
                                 @"accessibility.current"],
                             gestureTitle]];
    UIButton *directionButton =
        [self ag_selectorButtonWithTitle:directionTitle
                                   menu:[self ag_directionMenu]
                     accessibilityLabel:
                         [NSString stringWithFormat:
                              [helper localizedStringForKey:
                                  @"accessibility.directionCurrent"],
                             directionTitle]];
    UIButton *actionButton = [self ag_actionButton];
    UIButton *helpButton = [self ag_directionHelpButton];
    UIStackView *selectors =
        [[UIStackView alloc]
            initWithArrangedSubviews:
                @[ gestureButton, directionButton, actionButton, helpButton ]];
    selectors.axis = UILayoutConstraintAxisHorizontal;
    selectors.alignment = UIStackViewAlignmentCenter;
    selectors.spacing = 5.0;

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithCustomView:selectors];
}

%new
- (UIButton *)ag_selectorButtonWithTitle:(NSString *)title
                                    menu:(UIMenu *)menu
                      accessibilityLabel:(NSString *)accessibilityLabel {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *configuration =
        [UIButtonConfiguration tintedButtonConfiguration];
    configuration.attributedTitle =
        [[NSAttributedString alloc]
            initWithString:title
                attributes:@{
                    NSFontAttributeName:
                        [UIFont systemFontOfSize:12.5
                                         weight:UIFontWeightSemibold],
                    NSForegroundColorAttributeName:
                        [UIColor colorWithWhite:1.0 alpha:0.94]
                }];
    configuration.image =
        [UIImage systemImageNamed:@"chevron.up.chevron.down"];
    configuration.preferredSymbolConfigurationForImage =
        [UIImageSymbolConfiguration
            configurationWithPointSize:7.5
                                weight:UIImageSymbolWeightSemibold
                                 scale:UIImageSymbolScaleSmall];
    configuration.imagePlacement = NSDirectionalRectEdgeTrailing;
    configuration.imagePadding = 4.0;
    configuration.contentInsets =
        NSDirectionalEdgeInsetsMake(4.5, 8.0, 4.5, 7.0);
    configuration.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    configuration.buttonSize = UIButtonConfigurationSizeSmall;
    configuration.baseForegroundColor =
        [UIColor colorWithWhite:1.0 alpha:0.78];
    configuration.baseBackgroundColor =
        [UIColor colorWithWhite:1.0 alpha:0.10];

    button.configuration = configuration;
    button.menu = menu;
    button.showsMenuAsPrimaryAction = YES;
    button.accessibilityLabel = accessibilityLabel;
    return button;
}

%new
- (UIButton *)ag_directionHelpButton {
    ActionGestureHelper *helper = [ActionGestureHelper sharedHelper];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *configuration =
        [UIButtonConfiguration plainButtonConfiguration];
    configuration.image =
        [UIImage systemImageNamed:@"questionmark.circle"];
    configuration.preferredSymbolConfigurationForImage =
        [UIImageSymbolConfiguration
            configurationWithPointSize:11.5
                                weight:UIImageSymbolWeightSemibold
                                 scale:UIImageSymbolScaleSmall];
    configuration.contentInsets =
        NSDirectionalEdgeInsetsMake(5.0, 5.0, 5.0, 5.0);
    configuration.baseForegroundColor =
        [UIColor colorWithWhite:1.0 alpha:0.72];
    button.configuration = configuration;
    button.accessibilityLabel =
        [helper localizedStringForKey:@"accessibility.directionHelp"];
    [button addTarget:self
               action:@selector(ag_showDirectionHelp)
     forControlEvents:UIControlEventTouchUpInside];
    [button.widthAnchor constraintEqualToConstant:28.0].active = YES;
    [button.heightAnchor constraintEqualToConstant:28.0].active = YES;
    return button;
}

%new
- (UIButton *)ag_actionButton {
    ActionGestureHelper *helper = [ActionGestureHelper sharedHelper];
    NSString *action =
        [helper customActionForGesture:helper.currentGesture
                             direction:[helper activeEditorDirection]];
    NSString *title = [helper titleForCustomAction:action];
    return [self ag_selectorButtonWithTitle:title
                                       menu:[self ag_actionMenu]
                         accessibilityLabel:title];
}

%new
- (UIMenu *)ag_actionMenu {
    ActionGestureHelper *helper = [ActionGestureHelper sharedHelper];
    NSArray<NSString *> *actions = @[
        AGCustomActionNative,
        AGCustomActionWechatScan,
        AGCustomActionWechatPayCode,
        AGCustomActionAlipayScan,
        AGCustomActionAlipayPayCode
    ];
    NSMutableArray<UIMenuElement *> *elements =
        [NSMutableArray arrayWithCapacity:actions.count];
    NSString *current =
        [helper customActionForGesture:helper.currentGesture
                             direction:[helper activeEditorDirection]];
    __weak ActionButtonSettings *weakSelf = self;
    for (NSString *actionID in actions) {
        UIAction *action =
            [UIAction actionWithTitle:[helper titleForCustomAction:actionID]
                                image:nil
                           identifier:nil
                              handler:^(__unused UIAction *selectedAction) {
                                  [weakSelf ag_switchToAction:actionID];
                              }];
        action.state = [actionID isEqualToString:current]
            ? UIMenuElementStateOn
            : UIMenuElementStateOff;
        [elements addObject:action];
    }
    return [UIMenu menuWithTitle:@"快捷动作"
                           image:nil
                      identifier:nil
                         options:UIMenuOptionsSingleSelection
                        children:elements];
}

%new
- (void)ag_switchToAction:(NSString *)action {
    ActionGestureHelper *helper = [ActionGestureHelper sharedHelper];
    [helper saveCustomAction:action
                  forGesture:helper.currentGesture
                   direction:[helper activeEditorDirection]];
    [self ag_replaceController];
}

%new
- (void)ag_showDirectionHelp {
    ActionGestureHelper *helper = [ActionGestureHelper sharedHelper];
    NSMutableArray<NSString *> *explanations =
        [NSMutableArray arrayWithCapacity:6];
    for (NSString *direction in [helper directions]) {
        [explanations
            addObject:
                [NSString stringWithFormat:
                    @"%@\n%@",
                    [helper titleForDirection:direction],
                    [helper subtitleForDirection:direction]]];
    }

    UIAlertController *alert =
        [UIAlertController
            alertControllerWithTitle:
                [helper localizedStringForKey:@"direction.help.title"]
                             message:
                                 [explanations
                                     componentsJoinedByString:@"\n\n"]
                      preferredStyle:UIAlertControllerStyleAlert];
    [alert
        addAction:
            [UIAlertAction
                actionWithTitle:
                    [helper localizedStringForKey:@"direction.help.done"]
                          style:UIAlertActionStyleDefault
                        handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

%new
- (UIMenu *)ag_gestureMenu {
    ActionGestureHelper *helper = [ActionGestureHelper sharedHelper];
    NSMutableArray<UIMenuElement *> *actions =
        [NSMutableArray arrayWithCapacity:3];

    for (NSString *gesture in
            @[ AGGestureSingle, AGGestureDouble, AGGestureLong ]) {
        __weak ActionButtonSettings *weakSelf = self;
        UIAction *action =
            [UIAction actionWithTitle:[helper titleForGesture:gesture]
                                image:
                                    [UIImage systemImageNamed:
                                        [helper symbolForGesture:gesture]]
                           identifier:nil
                              handler:^(__unused UIAction *selectedAction) {
                                  [weakSelf ag_switchToGesture:gesture];
                              }];
        action.state = [gesture isEqualToString:helper.currentGesture]
            ? UIMenuElementStateOn
            : UIMenuElementStateOff;
        [actions addObject:action];
    }

    return [UIMenu
        menuWithTitle:[helper localizedStringForKey:@"menu.title"]
                image:nil
           identifier:nil
              options:UIMenuOptionsSingleSelection
             children:actions];
}

%new
- (UIMenu *)ag_directionMenu {
    ActionGestureHelper *helper = [ActionGestureHelper sharedHelper];
    BOOL directionModeEnabled = helper.directionModeEnabled;
    __weak ActionButtonSettings *weakSelf = self;
    UIAction *modeAction =
        [UIAction
            actionWithTitle:
                [helper localizedStringForKey:@"direction.mode"]
                      image:[UIImage systemImageNamed:@"iphone"]
                 identifier:nil
                    handler:^(__unused UIAction *selectedAction) {
                        [weakSelf
                            ag_setDirectionModeEnabled:
                                !directionModeEnabled];
                    }];
    modeAction.subtitle =
        [helper localizedStringForKey:@"direction.mode.subtitle"];
    modeAction.state = directionModeEnabled
        ? UIMenuElementStateOn
        : UIMenuElementStateOff;

    NSMutableArray<UIMenuElement *> *directionActions =
        [NSMutableArray arrayWithCapacity:6];
    for (NSString *direction in [helper directions]) {
        UIAction *action =
            [UIAction
                actionWithTitle:[helper titleForDirection:direction]
                          image:nil
                     identifier:nil
                        handler:
                            ^(__unused UIAction *selectedAction) {
                                [weakSelf ag_switchToDirection:direction];
                            }];
        action.subtitle = [helper subtitleForDirection:direction];
        action.state =
            directionModeEnabled &&
            [direction isEqualToString:helper.currentDirection]
                ? UIMenuElementStateOn
                : UIMenuElementStateOff;
        action.attributes = directionModeEnabled
            ? 0
            : UIMenuElementAttributesDisabled;
        [directionActions addObject:action];
    }

    UIMenu *directions =
        [UIMenu
            menuWithTitle:
                [helper localizedStringForKey:@"direction.menu"]
                    image:nil
               identifier:nil
                  options:
                      UIMenuOptionsDisplayInline |
                      UIMenuOptionsSingleSelection
                 children:directionActions];
    return [UIMenu
        menuWithTitle:[helper localizedStringForKey:@"direction.menu"]
                image:nil
           identifier:nil
              options:0
             children:@[ modeAction, directions ]];
}

%new
- (void)ag_switchToGesture:(NSString *)gesture {
    ActionGestureHelper *helper = [ActionGestureHelper sharedHelper];
    if (![helper isKnownGesture:gesture] ||
        [gesture isEqualToString:helper.currentGesture]) {
        return;
    }

    NSString *direction = [helper activeEditorDirection];
    if (!direction ||
        [helper hasStoredConfigurationForGesture:helper.currentGesture
                                       direction:direction]) {
        [helper snapshotNativeConfigurationForGesture:helper.currentGesture
                                             direction:direction];
    }
    if (![helper hasStoredConfigurationForGesture:gesture
                                        direction:direction] &&
        !direction) {
        [helper snapshotNativeConfigurationForGesture:gesture
                                             direction:direction];
    }
    [helper saveCurrentGesture:gesture];
    [helper applyNativeConfigurationForGesture:gesture
                                      direction:direction];
    [self ag_replaceController];
}

%new
- (void)ag_switchToDirection:(NSString *)direction {
    ActionGestureHelper *helper = [ActionGestureHelper sharedHelper];
    if (!helper.directionModeEnabled ||
        ![helper isKnownDirection:direction] ||
        [direction isEqualToString:helper.currentDirection]) {
        return;
    }

    if ([helper hasStoredConfigurationForGesture:helper.currentGesture
                                       direction:helper.currentDirection]) {
        [helper snapshotNativeConfigurationForGesture:helper.currentGesture
                                             direction:
                                                 helper.currentDirection];
    }
    [helper saveCurrentDirection:direction];
    [helper applyNativeConfigurationForGesture:helper.currentGesture
                                      direction:direction];
    [self ag_replaceController];
}

%new
- (void)ag_setDirectionModeEnabled:(BOOL)enabled {
    ActionGestureHelper *helper = [ActionGestureHelper sharedHelper];
    if (helper.directionModeEnabled == enabled) return;

    NSString *direction = [helper activeEditorDirection];
    if (!direction ||
        [helper hasStoredConfigurationForGesture:helper.currentGesture
                                       direction:direction]) {
        [helper snapshotNativeConfigurationForGesture:helper.currentGesture
                                             direction:direction];
    }
    [helper saveDirectionModeEnabled:enabled];
    [helper applyNativeConfigurationForGesture:helper.currentGesture
                                      direction:
                                          [helper activeEditorDirection]];
    [self ag_replaceController];
}

%new
- (void)ag_replaceController {
    UINavigationController *navigationController = self.navigationController;
    NSUInteger index =
        [navigationController.viewControllers indexOfObjectIdenticalTo:self];
    if (!navigationController || index == NSNotFound) return;

    ActionButtonSettings *replacement =
        [[[self class] alloc] initWithNibName:nil
                                      bundle:[ActionGestureHelper sharedHelper]
                                                 .settingsBundle];
    replacement.title = self.title;

    NSMutableArray<UIViewController *> *controllers =
        [navigationController.viewControllers mutableCopy];
    controllers[index] = replacement;
    [navigationController setViewControllers:controllers animated:NO];
}

- (void)viewDidLoad {
    ActionGestureHelper *helper = [ActionGestureHelper sharedHelper];
    NSString *direction = [helper activeEditorDirection];
    [helper beginSuppressingSystemActionSnapshots];
    [helper applyNativeConfigurationForGesture:helper.currentGesture
                                      direction:direction];
    %orig;
    [helper endSuppressingSystemActionSnapshots];

    if (!direction &&
        ![helper hasStoredConfigurationForGesture:helper.currentGesture
                                        direction:nil]) {
        [helper snapshotNativeConfigurationForGesture:helper.currentGesture
                                             direction:nil];
    }
    [self ag_installSelectors];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    [self ag_installSelectors];
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    ActionGestureHelper *helper = [ActionGestureHelper sharedHelper];
    NSString *direction = [helper activeEditorDirection];
    if (!direction ||
        [helper hasStoredConfigurationForGesture:helper.currentGesture
                                       direction:direction]) {
        [helper snapshotNativeConfigurationForGesture:helper.currentGesture
                                             direction:direction];
    }
}

%end

%end

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier
                isEqualToString:@"com.apple.Preferences"]) {
            return;
        }

        ActionGestureHelper *helper = [ActionGestureHelper sharedHelper];
        [helper loadEditorState];
        if (!helper.settingsBundle.loaded) {
            [helper.settingsBundle loadAndReturnError:nil];
        }
        if (!NSClassFromString(@"ActionButtonSettings")) return;
        %init(ActionGestureOfficialSettings);
    }
}
