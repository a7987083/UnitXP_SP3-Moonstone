#import "../Public/SJPreferences.h"
#import "../Public/SJConfiguration.h"

NSString * const SJPreferenceIsEnabledKey = @"tella_isEnabled";
NSString * const SJPreferenceIsGestureKey = @"tella_isGesture";
NSString * const SJPreferenceIsHiddenKey = @"tella_isHidden";
NSString * const SJPreferenceIsObserverKey = @"tella_isObserver";
NSString * const SJPreferenceIsPriceZeroKey = @"tella_isPriceZero";
NSString * const SJPreferenceIsReceiptKey = @"tella_isReceipt";
NSString * const SJPreferenceIsStealthKey = @"tella_isStealth";

@implementation SJPreferences

+ (NSDictionary<NSString *, NSNumber *> *)defaultValues {
    return @{
        SJPreferenceIsEnabledKey: @YES,
        SJPreferenceIsGestureKey: @YES,
        SJPreferenceIsHiddenKey: @NO,
        SJPreferenceIsObserverKey: @NO,
        SJPreferenceIsPriceZeroKey: @NO,
        SJPreferenceIsReceiptKey: @NO,
        SJPreferenceIsStealthKey: @NO,
    };
}

+ (BOOL)boolForKey:(NSString *)key defaults:(NSUserDefaults *)defaults fallback:(BOOL)fallback {
    id value = [defaults objectForKey:key];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : fallback;
}

+ (SJConfiguration *)configurationFromUserDefaults:(NSUserDefaults *)defaults {
    NSParameterAssert(defaults != nil);
    NSDictionary<NSString *, NSNumber *> *fallback = [self defaultValues];
    SJConfiguration *config = [SJConfiguration defaultConfiguration];
    config.enabledPreference = [self boolForKey:SJPreferenceIsEnabledKey defaults:defaults fallback:[fallback[SJPreferenceIsEnabledKey] boolValue]];
    config.gesturePreferenceEnabled = [self boolForKey:SJPreferenceIsGestureKey defaults:defaults fallback:[fallback[SJPreferenceIsGestureKey] boolValue]];
    config.hiddenPreferenceEnabled = [self boolForKey:SJPreferenceIsHiddenKey defaults:defaults fallback:[fallback[SJPreferenceIsHiddenKey] boolValue]];
    config.observerBridgeEnabled = [self boolForKey:SJPreferenceIsObserverKey defaults:defaults fallback:[fallback[SJPreferenceIsObserverKey] boolValue]];
    config.priceOverrideEnabled = [self boolForKey:SJPreferenceIsPriceZeroKey defaults:defaults fallback:[fallback[SJPreferenceIsPriceZeroKey] boolValue]];
    config.receiptSimulationEnabled = [self boolForKey:SJPreferenceIsReceiptKey defaults:defaults fallback:[fallback[SJPreferenceIsReceiptKey] boolValue]];
    config.stealthPreferenceEnabled = [self boolForKey:SJPreferenceIsStealthKey defaults:defaults fallback:[fallback[SJPreferenceIsStealthKey] boolValue]];
    return config;
}

+ (void)writeConfiguration:(SJConfiguration *)configuration toUserDefaults:(NSUserDefaults *)defaults {
    NSParameterAssert(configuration != nil);
    NSParameterAssert(defaults != nil);
    [defaults setBool:configuration.enabledPreference forKey:SJPreferenceIsEnabledKey];
    [defaults setBool:configuration.gesturePreferenceEnabled forKey:SJPreferenceIsGestureKey];
    [defaults setBool:configuration.hiddenPreferenceEnabled forKey:SJPreferenceIsHiddenKey];
    [defaults setBool:configuration.observerBridgeEnabled forKey:SJPreferenceIsObserverKey];
    [defaults setBool:configuration.priceOverrideEnabled forKey:SJPreferenceIsPriceZeroKey];
    [defaults setBool:configuration.receiptSimulationEnabled forKey:SJPreferenceIsReceiptKey];
    [defaults setBool:configuration.stealthPreferenceEnabled forKey:SJPreferenceIsStealthKey];
}

+ (void)resetUserDefaults:(NSUserDefaults *)defaults {
    NSParameterAssert(defaults != nil);
    for (NSString *key in [self defaultValues]) {
        [defaults removeObjectForKey:key];
    }
}

@end
