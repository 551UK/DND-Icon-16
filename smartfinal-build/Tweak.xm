#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static NSString *const SFCurrentVersion = @"26.32.1";
static NSString *const SFCurrentBuild = @"2001009999";
static NSString *const SFOldVersion = @"24.35.8";
static NSString *const SFOldBuild = @"2001000136";

@interface RNDeviceInfo : NSObject
- (NSString *)getAppVersion;
- (NSString *)getBuildNumber;
- (NSDictionary *)constantsToExport;
@end

static BOOL SFIsMainBundle(NSBundle *bundle) {
    return bundle == [NSBundle mainBundle];
}

static NSDictionary *SFPatchBundleDictionary(NSDictionary *dictionary) {
    if (!dictionary) return dictionary;
    NSMutableDictionary *patched = [dictionary mutableCopy];
    patched[@"CFBundleShortVersionString"] = SFCurrentVersion;
    patched[@"CFBundleVersion"] = SFCurrentBuild;
    return patched;
}

static BOOL SFVersionHeader(NSString *field) {
    if (![field isKindOfClass:[NSString class]]) return NO;
    NSString *lower = field.lowercaseString;
    return [lower containsString:@"version"] ||
           [lower isEqualToString:@"x-app-version"] ||
           [lower isEqualToString:@"app-version"];
}

static id SFPatchVersionValueForKey(id value, id key) {
    if (![key isKindOfClass:[NSString class]]) return value;
    NSString *lowerKey = [(NSString *)key lowercaseString];

    if ([value isKindOfClass:[NSString class]]) {
        NSString *stringValue = (NSString *)value;
        BOOL versionKey = [lowerKey isEqualToString:@"appversion"] ||
                          [lowerKey isEqualToString:@"app_version"] ||
                          [lowerKey isEqualToString:@"applicationversion"] ||
                          [lowerKey isEqualToString:@"currentversion"] ||
                          [lowerKey isEqualToString:@"version_name"];
        BOOL buildKey = [lowerKey isEqualToString:@"buildnumber"] ||
                        [lowerKey isEqualToString:@"build_number"] ||
                        [lowerKey isEqualToString:@"version_code"];

        if (versionKey && [stringValue isEqualToString:SFOldVersion]) return SFCurrentVersion;
        if (buildKey && [stringValue isEqualToString:SFOldBuild]) return SFCurrentBuild;
    }

    return value;
}

%hook NSBundle

- (id)objectForInfoDictionaryKey:(NSString *)key {
    if (SFIsMainBundle(self)) {
        if ([key isEqualToString:@"CFBundleShortVersionString"]) return SFCurrentVersion;
        if ([key isEqualToString:@"CFBundleVersion"]) return SFCurrentBuild;
    }
    return %orig;
}

- (NSDictionary *)infoDictionary {
    NSDictionary *dictionary = %orig;
    return SFIsMainBundle(self) ? SFPatchBundleDictionary(dictionary) : dictionary;
}

- (NSDictionary *)localizedInfoDictionary {
    NSDictionary *dictionary = %orig;
    return SFIsMainBundle(self) ? SFPatchBundleDictionary(dictionary) : dictionary;
}

%end

%hook RNDeviceInfo

- (NSString *)getAppVersion {
    return SFCurrentVersion;
}

- (NSString *)getBuildNumber {
    return SFCurrentBuild;
}

- (NSDictionary *)constantsToExport {
    NSDictionary *original = %orig;
    if (!original) return original;

    NSMutableDictionary *patched = [original mutableCopy];
    patched[@"appVersion"] = SFCurrentVersion;
    patched[@"buildNumber"] = SFCurrentBuild;
    return patched;
}

%end

%hook NSMutableURLRequest

- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if (SFVersionHeader(field)) {
        if ([value isEqualToString:SFOldVersion]) value = SFCurrentVersion;
        else if ([value isEqualToString:SFOldBuild]) value = SFCurrentBuild;
    }
    %orig(value, field);
}

- (void)addValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if (SFVersionHeader(field)) {
        if ([value isEqualToString:SFOldVersion]) value = SFCurrentVersion;
        else if ([value isEqualToString:SFOldBuild]) value = SFCurrentBuild;
    }
    %orig(value, field);
}

%end

%hook NSMutableDictionary

- (void)setObject:(id)object forKey:(id<NSCopying>)key {
    object = SFPatchVersionValueForKey(object, key);
    %orig(object, key);
}

- (void)setObject:(id)object forKeyedSubscript:(id<NSCopying>)key {
    object = SFPatchVersionValueForKey(object, key);
    %orig(object, key);
}

%end

%hook UIViewController

- (void)presentViewController:(UIViewController *)viewController
                     animated:(BOOL)animated
                   completion:(void (^)(void))completion {
    if ([viewController isKindOfClass:[UIAlertController class]]) {
        UIAlertController *alert = (UIAlertController *)viewController;
        NSString *title = alert.title ?: @"";
        NSString *message = alert.message ?: @"";

        BOOL isSmartFinalUpdate = [title isEqualToString:@"Update Available"] ||
            ([message rangeOfString:@"important update for Smart and Final" options:NSCaseInsensitiveSearch].location != NSNotFound) ||
            ([message rangeOfString:@"Please update the application" options:NSCaseInsensitiveSearch].location != NSNotFound);

        if (isSmartFinalUpdate) {
            if (completion) completion();
            return;
        }
    }

    %orig(viewController, animated, completion);
}

%end
