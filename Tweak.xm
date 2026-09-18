// Home Screen DND icon logic and live Focus state handling.
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <math.h>

@interface DNDState : NSObject
@property (getter=isActive, nonatomic, readonly) BOOL active;
@property (nonatomic, readonly, copy) NSString *activeModeIdentifier;
@property (nonatomic, readonly, copy) NSArray *activeModeIdentifiers;
@end

@interface DNDStateUpdate : NSObject
@property (nonatomic, readonly, copy) DNDState *state;
@end

@interface DNDStateService : NSObject
- (DNDState *)queryCurrentStateWithError:(NSError **)error;
@end

@interface SBIconController : NSObject
+ (instancetype)sharedInstance;
- (id)_rootFolderController;
- (id)homeScreenViewController;
- (id)rootViewController;
- (UIView *)contentView;
- (DNDStateService *)dndStateService;
- (void)updateRootFolderWithCurrentDoNotDisturbState;
@end

@interface SBUIProudLockIconView : UIView
@end

static NSString * const DNDIPrefsDomain = @"com.551.dndicon16";
static NSString * const DNDIPrefsChanged = @"com.551.dndicon16/preferences.changed";
static NSString * const DNDIDoNotDisturbIdentifier = @"com.apple.donotdisturb.mode.default";

static BOOL DNDIEnabled = YES;
static CGFloat DNDIXOffset = 0.0;
static CGFloat DNDIYOffset = 0.0;
static UIColor *DNDIColor = nil;

static BOOL DNDIDoNotDisturbActive = NO;
static __weak UIView *DNDIHomeContainer = nil;
static UIImageView *DNDIIconView = nil;
static CGPoint DNDILockAnchor = {0.0, 0.0};
static BOOL DNDIHasLockAnchor = NO;

static id DNDICopyPreference(NSString *key) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)DNDIPrefsDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                        (__bridge CFStringRef)DNDIPrefsDomain);
    return value ? CFBridgingRelease(value) : nil;
}

static CGFloat DNDIClampOffset(CGFloat value) {
    if (value < -220.0) return -220.0;
    if (value > 220.0) return 220.0;
    return value;
}

static UIColor *DNDIColorFromHexString(NSString *string) {
    UIColor *fallback = [UIColor colorWithRed:0.494 green:0.341 blue:0.761 alpha:1.0];
    if (![string isKindOfClass:[NSString class]]) return fallback;

    NSString *hex = [[string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    if ([hex hasPrefix:@"#"]) hex = [hex substringFromIndex:1];
    if (hex.length != 6) return fallback;

    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hex];
    if (![scanner scanHexInt:&rgb]) return fallback;

    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

static void DNDILoadPrefs(void) {
    id value = DNDICopyPreference(@"enabled");
    DNDIEnabled = value ? [value boolValue] : YES;

    value = DNDICopyPreference(@"xOffset");
    DNDIXOffset = DNDIClampOffset(value ? [value doubleValue] : 0.0);

    value = DNDICopyPreference(@"yOffset");
    DNDIYOffset = DNDIClampOffset(value ? [value doubleValue] : 0.0);

    value = DNDICopyPreference(@"symbolColor");
    DNDIColor = DNDIColorFromHexString([value isKindOfClass:[NSString class]] ? value : @"#7E57C2");
}

static UIImage *DNDITemplateImage(void) {
    static UIImage *image = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *path = @"/var/jb/Library/Application Support/DNDIcon16/DNDIconTemplate.png";
        UIImage *loaded = [UIImage imageWithContentsOfFile:path];
        if (loaded) image = [loaded imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    });
    return image;
}

static UIView *DNDIViewForKey(id object, NSString *key) {
    if (!object) return nil;
    @try {
        id value = [object valueForKey:key];
        return [value isKindOfClass:[UIView class]] ? value : nil;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id DNDIObjectForKey(id object, NSString *key) {
    if (!object) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static UIView *DNDIHomeContainerForController(SBIconController *controller) {
    if (!controller) return nil;

    id homeVC = DNDIObjectForKey(controller, @"homeScreenViewController");
    UIView *view = DNDIViewForKey(homeVC, @"view");
    if (view.window) return view;

    id rootVC = DNDIObjectForKey(controller, @"rootViewController");
    view = DNDIViewForKey(rootVC, @"view");
    if (view.window) return view;

    id rootFolder = nil;
    if ([controller respondsToSelector:@selector(_rootFolderController)]) {
        @try {
            rootFolder = [controller _rootFolderController];
        } @catch (__unused NSException *exception) {
            rootFolder = nil;
        }
    }

    view = DNDIViewForKey(rootFolder, @"contentView");
    if (view.window) return view;

    view = DNDIViewForKey(rootFolder, @"view");
    if (view.window) return view;

    if ([controller respondsToSelector:@selector(contentView)]) {
        @try {
            view = [controller contentView];
        } @catch (__unused NSException *exception) {
            view = nil;
        }
        if ([view isKindOfClass:[UIView class]] && view.window) return view;
    }

    return nil;
}

static BOOL DNDIIsIPhone14ProMax(void) {
    CGRect nativeBounds = UIScreen.mainScreen.nativeBounds;
    CGFloat nativeWidth = MIN(CGRectGetWidth(nativeBounds), CGRectGetHeight(nativeBounds));
    CGFloat nativeHeight = MAX(CGRectGetWidth(nativeBounds), CGRectGetHeight(nativeBounds));

    // iPhone 14 Pro Max native panel size. Keeping this device-specific means
    // the existing notch-device/LatchKey positioning remains untouched.
    return fabs(nativeWidth - 1290.0) < 2.0 &&
           fabs(nativeHeight - 2796.0) < 2.0;
}

static CGPoint DNDIDefaultAnchorForView(UIView *view) {
    CGFloat width = CGRectGetWidth(view.bounds);

    // On iPhone 14 Pro Max, place the DND glyph dead-centre horizontally in
    // the clear gap below the Dynamic Island and above the first icon row.
    // 92 pt is the visual centre of that gap on the stock 430 x 932 layout.
    if (DNDIIsIPhone14ProMax()) {
        return CGPointMake(width * 0.5, 98.0);
    }

    CGFloat topInset = view.window ? view.window.safeAreaInsets.top : view.safeAreaInsets.top;
    CGFloat y = topInset > 24.0 ? topInset + 5.0 : 30.0;
    return CGPointMake(width * 0.5, y);
}

static void DNDIUpdateOverlay(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *container = DNDIHomeContainer;
        if (!DNDIIconView || !container) return;

        DNDIIconView.hidden = !(DNDIEnabled && DNDIDoNotDisturbActive);
        DNDIIconView.alpha = 1.0;
        DNDIIconView.tintColor = DNDIColor ?: UIColor.whiteColor;

        BOOL use14ProMaxHomeAnchor = DNDIIsIPhone14ProMax();
        CGPoint anchor = use14ProMaxHomeAnchor
            ? DNDIDefaultAnchorForView(container)
            : (DNDIHasLockAnchor ? DNDILockAnchor : DNDIDefaultAnchorForView(container));

        if (!use14ProMaxHomeAnchor && DNDIHasLockAnchor) {
            anchor = [container convertPoint:anchor fromView:nil];
        }

        anchor.x += DNDIXOffset;
        anchor.y += DNDIYOffset;

        DNDIIconView.bounds = CGRectMake(0.0, 0.0, 44.0, 44.0);
        DNDIIconView.center = anchor;
        DNDIIconView.layer.zPosition = 100000.0;

        if (DNDIIconView.superview == container) {
            [container bringSubviewToFront:DNDIIconView];
        }
    });
}

static void DNDIEnsureOverlay(UIView *container) {
    if (!container || !container.window) return;

    DNDIHomeContainer = container;

    if (!DNDIIconView) {
        UIImage *symbolImage = DNDITemplateImage();
        if (!symbolImage) return;

        DNDIIconView = [[UIImageView alloc] initWithImage:symbolImage];
        DNDIIconView.contentMode = UIViewContentModeScaleAspectFit;
        DNDIIconView.userInteractionEnabled = NO;
        DNDIIconView.backgroundColor = UIColor.clearColor;
        DNDIIconView.accessibilityIdentifier = @"DNDIcon16Symbol";
        DNDIIconView.hidden = YES;
    }

    if (DNDIIconView.superview != container) {
        [DNDIIconView removeFromSuperview];
        [container addSubview:DNDIIconView];
    }

    DNDIUpdateOverlay();
}

static BOOL DNDIStateIsBuiltInDND(DNDState *state) {
    if (!state || !state.isActive) return NO;

    NSString *identifier = nil;
    if ([state respondsToSelector:@selector(activeModeIdentifier)]) {
        identifier = state.activeModeIdentifier;
    }
    if ([identifier isEqualToString:DNDIDoNotDisturbIdentifier]) return YES;

    NSArray *identifiers = nil;
    if ([state respondsToSelector:@selector(activeModeIdentifiers)]) {
        identifiers = state.activeModeIdentifiers;
    }
    return [identifiers isKindOfClass:[NSArray class]] &&
           [identifiers containsObject:DNDIDoNotDisturbIdentifier];
}

static void DNDIApplyState(DNDState *state) {
    DNDIDoNotDisturbActive = DNDIStateIsBuiltInDND(state);
    DNDIUpdateOverlay();
}

static DNDStateService *DNDIStateServiceFromIconController(SBIconController *controller) {
    if (!controller) return nil;

    if ([controller respondsToSelector:@selector(dndStateService)]) {
        @try {
            id service = [controller dndStateService];
            if (service) return service;
        } @catch (__unused NSException *exception) {
        }
    }

    @try {
        id service = [controller valueForKey:@"_dndStateService"];
        return service;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static void DNDIRefreshFromIconController(SBIconController *controller) {
    if (!controller) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *container = DNDIHomeContainerForController(controller);
        if (container) DNDIEnsureOverlay(container);

        DNDStateService *service = DNDIStateServiceFromIconController(controller);
        if (service && [service respondsToSelector:@selector(queryCurrentStateWithError:)]) {
            @try {
                DNDState *state = [service queryCurrentStateWithError:NULL];
                if (state) DNDIApplyState(state);
            } @catch (__unused NSException *exception) {
            }
        }
    });
}

static UIView *DNDILockGlyphViewFromRoot(SBUIProudLockIconView *root) {
    @try {
        id value = [root valueForKey:@"_lockView"];
        return [value isKindOfClass:[UIView class]] ? value : nil;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static BOOL DNDIIsPlausibleLockAnchor(SBUIProudLockIconView *root, CGPoint point) {
    UIWindow *window = root.window;
    if (!window) return NO;

    CGRect bounds = window.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    if (width <= 0.0 || height <= 0.0) return NO;

    // The Face ID lock glyph lives near the top-centre of the display. During
    // unlock UIKit can briefly report animation/transition coordinates for it;
    // never let those transient positions become the Home Screen icon anchor.
    CGFloat midX = CGRectGetMidX(bounds);
    CGFloat maxHorizontalDistance = MAX(90.0, width * 0.30);
    CGFloat maxY = MIN(180.0, height * 0.25);

    if (point.x < CGRectGetMinX(bounds) || point.x > CGRectGetMaxX(bounds)) return NO;
    if (point.y < CGRectGetMinY(bounds) || point.y > maxY) return NO;
    if (fabs(point.x - midX) > maxHorizontalDistance) return NO;

    return YES;
}

static void DNDICaptureLockAnchor(SBUIProudLockIconView *root) {
    // The lock glyph's resting position is fixed for the SpringBoard session.
    // Do not let layout passes from the unlock animation overwrite it later.
    if (DNDIHasLockAnchor) return;
    if (!root.window) return;

    UIView *glyph = DNDILockGlyphViewFromRoot(root);
    if (!glyph || !glyph.window) return;

    CGPoint center = CGPointMake(CGRectGetMidX(glyph.bounds), CGRectGetMidY(glyph.bounds));
    CGPoint point = [glyph convertPoint:center toView:nil];
    if (!isfinite(point.x) || !isfinite(point.y)) return;
    if (!DNDIIsPlausibleLockAnchor(root, point)) return;

    DNDILockAnchor = point;
    DNDIHasLockAnchor = YES;
    DNDIUpdateOverlay();
}

%hook SBIconController

- (void)stateService:(id)service didReceiveDoNotDisturbStateUpdate:(DNDStateUpdate *)update {
    %orig;

    UIView *container = DNDIHomeContainerForController(self);
    if (container) DNDIEnsureOverlay(container);

    DNDState *state = nil;
    if ([update respondsToSelector:@selector(state)]) state = update.state;
    if (state) {
        DNDIApplyState(state);
    } else {
        DNDIRefreshFromIconController(self);
    }
}

- (void)updateRootFolderWithCurrentDoNotDisturbState {
    %orig;
    DNDIRefreshFromIconController(self);
}

%end

%hook SBUIProudLockIconView

- (void)layoutSubviews {
    %orig;

    __weak SBUIProudLockIconView *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        SBUIProudLockIconView *strongSelf = weakSelf;
        if (strongSelf) DNDICaptureLockAnchor(strongSelf);
    });
}

%end

static void DNDIPreferencesChanged(CFNotificationCenterRef center,
                                   void *observer,
                                   CFStringRef name,
                                   const void *object,
                                   CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;

    DNDILoadPrefs();
    DNDIUpdateOverlay();
}

static void DNDIRefreshSharedController(void) {
    Class cls = NSClassFromString(@"SBIconController");
    if (!cls || ![cls respondsToSelector:@selector(sharedInstance)]) return;

    SBIconController *controller = nil;
    @try {
        controller = [cls sharedInstance];
    } @catch (__unused NSException *exception) {
        controller = nil;
    }
    if (controller) DNDIRefreshFromIconController(controller);
}

%ctor {
    @autoreleasepool {
        DNDILoadPrefs();

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        DNDIPreferencesChanged,
                                        (__bridge CFStringRef)DNDIPrefsChanged,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ DNDIRefreshSharedController(); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ DNDIRefreshSharedController(); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ DNDIRefreshSharedController(); });
    }
}
