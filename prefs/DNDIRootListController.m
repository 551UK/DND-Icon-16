#import "DNDIRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <spawn.h>
#import <unistd.h>
#import <math.h>

extern char **environ;

static NSString * const DNDIPrefsDomain = @"com.551.dndicon16";
static NSString * const DNDIPrefsChanged = @"com.551.dndicon16/preferences.changed";

static BOOL DNDISpawnTool(const char *tool, char * const argv[]) {
    if (!tool || access(tool, X_OK) != 0) return NO;
    pid_t pid = 0;
    return posix_spawn(&pid, tool, NULL, NULL, argv, environ) == 0;
}

static UIColor *DNDIColorFromHexString(NSString *string) {
    if (![string isKindOfClass:[NSString class]]) {
        return [UIColor colorWithRed:0.494 green:0.341 blue:0.761 alpha:1.0];
    }

    NSString *hex = [[string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    if ([hex hasPrefix:@"#"]) hex = [hex substringFromIndex:1];
    if (hex.length != 6) {
        return [UIColor colorWithRed:0.494 green:0.341 blue:0.761 alpha:1.0];
    }

    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hex];
    if (![scanner scanHexInt:&rgb]) {
        return [UIColor colorWithRed:0.494 green:0.341 blue:0.761 alpha:1.0];
    }

    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

static NSString *DNDIHexStringFromColor(UIColor *color) {
    CGFloat red = 0.494, green = 0.341, blue = 0.761, alpha = 1.0;
    if (![color getRed:&red green:&green blue:&blue alpha:&alpha]) return @"#7E57C2";

    return [NSString stringWithFormat:@"#%02X%02X%02X",
            (unsigned int)lrint(red * 255.0),
            (unsigned int)lrint(green * 255.0),
            (unsigned int)lrint(blue * 255.0)];
}

@interface DNDIRootListController () <UIColorPickerViewControllerDelegate>
@end

@implementation DNDIRootListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"DND Icon 16";
}

- (PSSpecifier *)preferenceSpecifierNamed:(NSString *)name
                                      key:(NSString *)key
                             defaultValue:(id)defaultValue
                                     cell:(PSCellType)cell {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name
                                                            target:self
                                                               set:@selector(setPreferenceValue:specifier:)
                                                               get:@selector(readPreferenceValue:)
                                                            detail:nil
                                                              cell:cell
                                                              edit:nil];
    [specifier setProperty:DNDIPrefsDomain forKey:@"defaults"];
    [specifier setProperty:key forKey:@"key"];
    [specifier setProperty:defaultValue forKey:@"default"];
    [specifier setProperty:DNDIPrefsChanged forKey:@"PostNotification"];
    return specifier;
}

- (NSArray *)manualSpecifiers {
    NSMutableArray *specifiers = [NSMutableArray array];

    PSSpecifier *mainGroup = [PSSpecifier groupSpecifierWithName:@"DND Icon 16"];
    [mainGroup setProperty:@"Shows the moon-and-cloud symbol on the Home Screen only while the built-in Do Not Disturb Focus is active." forKey:@"footerText"];
    [specifiers addObject:mainGroup];

    [specifiers addObject:[self preferenceSpecifierNamed:@"Enable"
                                                     key:@"enabled"
                                            defaultValue:@YES
                                                    cell:PSSwitchCell]];

    PSSpecifier *appearanceGroup = [PSSpecifier groupSpecifierWithName:@"Appearance"];
    [appearanceGroup setProperty:@"Choose the colour used for the moon, stars and cloud." forKey:@"footerText"];
    [specifiers addObject:appearanceGroup];

    PSSpecifier *color = [PSSpecifier preferenceSpecifierNamed:@"Symbol Color"
                                                        target:self
                                                           set:nil
                                                           get:nil
                                                        detail:nil
                                                          cell:PSButtonCell
                                                          edit:nil];
    [color setButtonAction:@selector(openColorPicker)];
    [color setProperty:NSStringFromSelector(@selector(openColorPicker)) forKey:@"action"];
    [specifiers addObject:color];

    PSSpecifier *resetColor = [PSSpecifier preferenceSpecifierNamed:@"Reset Color"
                                                             target:self
                                                                set:nil
                                                                get:nil
                                                             detail:nil
                                                               cell:PSButtonCell
                                                               edit:nil];
    [resetColor setButtonAction:@selector(resetColor)];
    [resetColor setProperty:NSStringFromSelector(@selector(resetColor)) forKey:@"action"];
    [specifiers addObject:resetColor];

    PSSpecifier *positionGroup = [PSSpecifier groupSpecifierWithName:@"Position"];
    [positionGroup setProperty:@"0 / 0 uses the Face ID lock-glyph position that LatchKeyWhite16 uses. Positive X moves right; positive Y moves down." forKey:@"footerText"];
    [specifiers addObject:positionGroup];

    PSSpecifier *x = [self preferenceSpecifierNamed:@"Horizontal Offset"
                                                 key:@"xOffset"
                                        defaultValue:@0.0
                                                cell:PSSliderCell];
    [x setProperty:@(-220.0) forKey:@"min"];
    [x setProperty:@(220.0) forKey:@"max"];
    [x setProperty:@YES forKey:@"showValue"];
    [specifiers addObject:x];

    PSSpecifier *y = [self preferenceSpecifierNamed:@"Vertical Offset"
                                                 key:@"yOffset"
                                        defaultValue:@0.0
                                                cell:PSSliderCell];
    [y setProperty:@(-220.0) forKey:@"min"];
    [y setProperty:@(220.0) forKey:@"max"];
    [y setProperty:@YES forKey:@"showValue"];
    [specifiers addObject:y];

    PSSpecifier *resetPosition = [PSSpecifier preferenceSpecifierNamed:@"Reset Position"
                                                                 target:self
                                                                    set:nil
                                                                    get:nil
                                                                 detail:nil
                                                                   cell:PSButtonCell
                                                                   edit:nil];
    [resetPosition setButtonAction:@selector(resetPosition)];
    [resetPosition setProperty:NSStringFromSelector(@selector(resetPosition)) forKey:@"action"];
    [specifiers addObject:resetPosition];

    [specifiers addObject:[PSSpecifier groupSpecifierWithName:@"Actions"]];

    PSSpecifier *respring = [PSSpecifier preferenceSpecifierNamed:@"Respring"
                                                            target:self
                                                               set:nil
                                                               get:nil
                                                            detail:nil
                                                              cell:PSButtonCell
                                                              edit:nil];
    [respring setButtonAction:@selector(respring)];
    [respring setProperty:NSStringFromSelector(@selector(respring)) forKey:@"action"];
    [specifiers addObject:respring];

    PSSpecifier *repo = [PSSpecifier preferenceSpecifierNamed:@"GitHub Repo"
                                                        target:self
                                                           set:nil
                                                           get:nil
                                                        detail:nil
                                                          cell:PSButtonCell
                                                          edit:nil];
    [repo setButtonAction:@selector(openRepo)];
    [repo setProperty:NSStringFromSelector(@selector(openRepo)) forKey:@"action"];
    [specifiers addObject:repo];

    return specifiers;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [[self manualSpecifiers] copy];
    }
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    id fallback = [specifier propertyForKey:@"default"];
    if (!key) return fallback;

    CFPreferencesAppSynchronize((__bridge CFStringRef)DNDIPrefsDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                        (__bridge CFStringRef)DNDIPrefsDomain);
    return value ? CFBridgingRelease(value) : fallback;
}

- (void)postPreferencesChanged {
    CFPreferencesAppSynchronize((__bridge CFStringRef)DNDIPrefsDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)DNDIPrefsChanged,
                                         NULL,
                                         NULL,
                                         true);
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return;

    if ([key isEqualToString:@"xOffset"] || [key isEqualToString:@"yOffset"]) {
        double number = [value doubleValue];
        if (number < -220.0) number = -220.0;
        if (number > 220.0) number = 220.0;
        value = @(number);
    }

    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)DNDIPrefsDomain);
    [self postPreferencesChanged];
}

- (NSString *)currentColorHex {
    CFPreferencesAppSynchronize((__bridge CFStringRef)DNDIPrefsDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("symbolColor"),
                                                        (__bridge CFStringRef)DNDIPrefsDomain);
    id object = value ? CFBridgingRelease(value) : nil;
    return [object isKindOfClass:[NSString class]] ? object : @"#7E57C2";
}

- (void)openColorPicker {
    UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
    picker.delegate = self;
    picker.selectedColor = DNDIColorFromHexString([self currentColorHex]);
    if ([picker respondsToSelector:@selector(setSupportsAlpha:)]) {
        picker.supportsAlpha = NO;
    }
    picker.title = @"Symbol Color";
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)openColorPicker:(id)sender {
    (void)sender;
    [self openColorPicker];
}

- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController {
    NSString *hex = DNDIHexStringFromColor(viewController.selectedColor ?: UIColor.whiteColor);
    CFPreferencesSetAppValue(CFSTR("symbolColor"),
                             (__bridge CFPropertyListRef)hex,
                             (__bridge CFStringRef)DNDIPrefsDomain);
    [self postPreferencesChanged];
}

- (void)resetColor {
    CFPreferencesSetAppValue(CFSTR("symbolColor"),
                             (__bridge CFPropertyListRef)@"#7E57C2",
                             (__bridge CFStringRef)DNDIPrefsDomain);
    [self postPreferencesChanged];
}

- (void)resetColor:(id)sender {
    (void)sender;
    [self resetColor];
}

- (void)resetPosition {
    CFPreferencesSetAppValue(CFSTR("xOffset"), (__bridge CFPropertyListRef)@0.0, (__bridge CFStringRef)DNDIPrefsDomain);
    CFPreferencesSetAppValue(CFSTR("yOffset"), (__bridge CFPropertyListRef)@0.0, (__bridge CFStringRef)DNDIPrefsDomain);
    [self postPreferencesChanged];
    [self reloadSpecifiers];
}

- (void)resetPosition:(id)sender {
    (void)sender;
    [self resetPosition];
}

- (void)openRepo {
    NSURL *url = [NSURL URLWithString:@"https://github.com/551UK/DND-Icon-16"];
    if (!url) return;

    UIApplication *application = UIApplication.sharedApplication;
    if ([application respondsToSelector:@selector(openURL:options:completionHandler:)]) {
        [application openURL:url options:@{} completionHandler:nil];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [application openURL:url];
#pragma clang diagnostic pop
    }
}

- (void)openRepo:(id)sender {
    (void)sender;
    [self openRepo];
}

- (void)respring {
    const char *sbreload = "/var/jb/usr/bin/sbreload";
    if (access(sbreload, X_OK) == 0) {
        char *args[] = {(char *)sbreload, NULL};
        if (DNDISpawnTool(sbreload, args)) return;
    }

    const char *rootlessKillall = "/var/jb/usr/bin/killall";
    if (access(rootlessKillall, X_OK) == 0) {
        char *args[] = {(char *)rootlessKillall, (char *)"-9", (char *)"SpringBoard", NULL};
        if (DNDISpawnTool(rootlessKillall, args)) return;
    }

    const char *systemKillall = "/usr/bin/killall";
    char *args[] = {(char *)systemKillall, (char *)"-9", (char *)"SpringBoard", NULL};
    DNDISpawnTool(systemKillall, args);
}

- (void)respring:(id)sender {
    (void)sender;
    [self respring];
}

@end
