#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
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
+ (instancetype)serviceForClientIdentifier:(NSString *)identifier;
- (BOOL)addStateUpdateListener:(id)listener error:(NSError **)error;
- (void)addStateUpdateListener:(id)listener withCompletionHandler:(id)completion;
- (DNDState *)queryCurrentStateWithError:(NSError **)error;
- (void)queryCurrentStateWithCompletionHandler:(id)completion;
@end

@interface SBIconController : NSObject
@end

@interface SBRootFolderController : UIViewController
@end

@interface SBRootFolderView : UIView
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

        if (DNDIIconView.superview == homeRootView) {
            [homeRootView bringSubviewToFront:DNDIIconView];
        }
    });
}

static void DNDIEnsureOverlay(UIView *homeRootView) {
    if (!homeRootView) return;

    DNDIHomeRootView = homeRootView;

    if (!DNDIIconView) {
        DNDIIconView = [[UIImageView alloc] initWithImage:DNDITemplateImage()];
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

    NSString *identifier = state.activeModeIdentifier;
    if ([identifier isEqualToString:DNDIDoNotDisturbIdentifier]) return YES;

    NSArray *identifiers = state.activeModeIdentifiers;
    return [identifiers isKindOfClass:[NSArray class]] &&
           [identifiers containsObject:DNDIDoNotDisturbIdentifier];
}

static void DNDIApplyState(DNDState *state) {
    DNDIDoNotDisturbActive = DNDIStateIsBuiltInDND(state);
    DNDIUpdateOverlay();
}

@interface DNDIcon16StateMonitor : NSObject
@property (nonatomic, strong) DNDStateService *service;
+ (instancetype)sharedMonitor;
- (void)start;
- (void)refreshNow;
@end

@implementation DNDIcon16StateMonitor

+ (instancetype)sharedMonitor {
    static DNDIcon16StateMonitor *monitor = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        monitor = [[self alloc] init];
    });
    return monitor;
}

- (void)start {
    if (self.service) {
        [self refreshNow];
        return;
    }

    dlopen("/System/Library/PrivateFrameworks/DoNotDisturb.framework/DoNotDisturb", RTLD_LAZY);

    Class serviceClass = NSClassFromString(@"DNDStateService");
    if (!serviceClass || ![serviceClass respondsToSelector:@selector(serviceForClientIdentifier:)]) return;

    // SpringBoard itself uses this client identifier for its icon-controller DND state service.
    self.service = [serviceClass serviceForClientIdentifier:@"com.apple.springboard.SBIconController"];
    if (!self.service) return;

    if ([self.service respondsToSelector:@selector(addStateUpdateListener:withCompletionHandler:)]) {
        [self.service addStateUpdateListener:self withCompletionHandler:nil];
    } else if ([self.service respondsToSelector:@selector(addStateUpdateListener:error:)]) {
        [self.service addStateUpdateListener:self error:NULL];
    }

    [self refreshNow];
}

- (void)refreshNow {
    if (!self.service) return;

    if ([self.service respondsToSelector:@selector(queryCurrentStateWithError:)]) {
        DNDState *state = [self.service queryCurrentStateWithError:NULL];
        if (state) DNDIApplyState(state);
        return;
    }

    if ([self.service respondsToSelector:@selector(queryCurrentStateWithCompletionHandler:)]) {
        [self.service queryCurrentStateWithCompletionHandler:^(DNDState *state, NSError *error) {
            (void)error;
            if (state) DNDIApplyState(state);
        }];
    }
}

- (void)stateService:(DNDStateService *)service didReceiveDoNotDisturbStateUpdate:(DNDStateUpdate *)update {
    (void)service;
    DNDState *state = update.state;
    if (state) DNDIApplyState(state);
}

@end

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

// SBIconController is an NSObject, not a view controller. v1.0.0 incorrectly
// tried to attach the overlay through view-controller callbacks on this class.
// We still hook its native DND update callback as an extra live-state source.
%hook SBIconController

- (void)stateService:(DNDStateService *)service didReceiveDoNotDisturbStateUpdate:(DNDStateUpdate *)update {
    %orig;
    DNDState *state = update.state;
    if (state) DNDIApplyState(state);
}

%end

// The root folder controller/view are the real Home Screen view hierarchy.
%hook SBRootFolderController

- (void)viewDidLoad {
    %orig;
    DNDIEnsureOverlay(self.view);
    [[DNDIcon16StateMonitor sharedMonitor] refreshNow];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);
    DNDIEnsureOverlay(self.view);
    [[DNDIcon16StateMonitor sharedMonitor] refreshNow];
}

- (void)viewDidLayoutSubviews {
    %orig;
    DNDIEnsureOverlay(self.view);
}

%end

// Direct view hook as a fallback for iOS 16 builds where the controller's
// lifecycle callbacks differ.
%hook SBRootFolderView

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        DNDIEnsureOverlay(self);
        [[DNDIcon16StateMonitor sharedMonitor] refreshNow];
    }
}

- (void)layoutSubviews {
    %orig;
    if (self.window) DNDIEnsureOverlay(self);
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

%ctor {
    @autoreleasepool {
        DNDILoadPrefs();

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        DNDIPreferencesChanged,
                                        (__bridge CFStringRef)DNDIPrefsChanged,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        dispatch_async(dispatch_get_main_queue(), ^{
            [[DNDIcon16StateMonitor sharedMonitor] start];
        });
    }
}
