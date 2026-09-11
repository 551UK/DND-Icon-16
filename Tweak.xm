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

@interface DNDStateService : NSObject
- (DNDState *)queryCurrentStateWithError:(NSError **)error;
@end

@interface SBIconController : NSObject
+ (instancetype)sharedInstance;
- (id)_rootFolderController;
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
static __weak UIView *DNDIHomeRootView = nil;
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
        image = [loaded imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    });
    return image;
}

static CGPoint DNDIDefaultAnchorForView(UIView *view) {
    CGFloat width = CGRectGetWidth(view.bounds);
    CGFloat topInset = view.window ? view.window.safeAreaInsets.top : view.safeAreaInsets.top;
    CGFloat y = topInset > 24.0 ? topInset + 5.0 : 30.0;
    return CGPointMake(width * 0.5, y);
}

static void DNDIUpdateOverlay(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *homeRootView = DNDIHomeRootView;
        if (!DNDIIconView || !homeRootView) return;

        DNDIIconView.hidden = !(DNDIEnabled && DNDIDoNotDisturbActive);
        DNDIIconView.alpha = 1.0;
        DNDIIconView.tintColor = DNDIColor ?: UIColor.whiteColor;

        CGPoint anchor = DNDIHasLockAnchor ? DNDILockAnchor : DNDIDefaultAnchorForView(homeRootView);
        if (DNDIHasLockAnchor) {
            anchor = [homeRootView convertPoint:anchor fromView:nil];
        }

        anchor.x += DNDIXOffset;
        anchor.y += DNDIYOffset;

        DNDIIconView.bounds = CGRectMake(0.0, 0.0, 44.0, 44.0);
        DNDIIconView.center = anchor;
    });
}

static void DNDIEnsureOverlay(UIView *homeRootView) {
    if (!homeRootView) return;

    DNDIHomeRootView = homeRootView;

    if (!DNDIIconView) {
        UIImage *templateImage = DNDITemplateImage();
        if (!templateImage) return;

        DNDIIconView = [[UIImageView alloc] initWithImage:templateImage];
        DNDIIconView.contentMode = UIViewContentModeScaleAspectFit;
        DNDIIconView.userInteractionEnabled = NO;
        DNDIIconView.backgroundColor = UIColor.clearColor;
        DNDIIconView.accessibilityIdentifier = @"DNDIcon16Symbol";
        DNDIIconView.layer.zPosition = 10000.0;
    }

    if (DNDIIconView.superview != homeRootView) {
        [DNDIIconView removeFromSuperview];
        [homeRootView addSubview:DNDIIconView];
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

static UIView *DNDIRootViewFromIconController(SBIconController *controller) {
    if (!controller || ![controller respondsToSelector:@selector(_rootFolderController)]) return nil;

    id rootController = nil;
    @try {
        rootController = [controller _rootFolderController];
    } @catch (__unused NSException *exception) {
        return nil;
    }

    if (!rootController || ![rootController respondsToSelector:@selector(view)]) return nil;

    UIView *view = nil;
    @try {
        view = [rootController view];
    } @catch (__unused NSException *exception) {
        return nil;
    }
    return [view isKindOfClass:[UIView class]] ? view : nil;
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
        UIView *rootView = DNDIRootViewFromIconController(controller);
        if (rootView) DNDIEnsureOverlay(rootView);

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

static void DNDICaptureLockAnchor(SBUIProudLockIconView *root) {
    if (!root.window) return;

    UIView *glyph = DNDILockGlyphViewFromRoot(root);
    if (!glyph || !glyph.window) return;

    CGPoint center = CGPointMake(CGRectGetMidX(glyph.bounds), CGRectGetMidY(glyph.bounds));
    CGPoint point = [glyph convertPoint:center toView:nil];
    if (!isfinite(point.x) || !isfinite(point.y)) return;

    DNDILockAnchor = point;
    DNDIHasLockAnchor = YES;
    DNDIUpdateOverlay();
}

// Use SpringBoard's own DND refresh path. This avoids registering a second
// DND service and avoids hooking SBRootFolderView/layoutSubviews, which caused
// the SpringBoard crash in 1.0.1.
%hook SBIconController

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

%ctor {
    @autoreleasepool {
        DNDILoadPrefs();

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        DNDIPreferencesChanged,
                                        (__bridge CFStringRef)DNDIPrefsChanged,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        // A short delayed refresh handles SpringBoard launches where the root
        // folder controller is created just after tweak injection.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            Class cls = NSClassFromString(@"SBIconController");
            if (cls && [cls respondsToSelector:@selector(sharedInstance)]) {
                SBIconController *controller = [cls sharedInstance];
                DNDIRefreshFromIconController(controller);
            }
        });
    }
}
