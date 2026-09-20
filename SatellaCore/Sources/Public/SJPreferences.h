#import <Foundation/Foundation.h>
@class SJConfiguration;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const SJPreferenceIsEnabledKey;
FOUNDATION_EXPORT NSString * const SJPreferenceIsGestureKey;
FOUNDATION_EXPORT NSString * const SJPreferenceIsHiddenKey;
FOUNDATION_EXPORT NSString * const SJPreferenceIsObserverKey;
FOUNDATION_EXPORT NSString * const SJPreferenceIsPriceZeroKey;
FOUNDATION_EXPORT NSString * const SJPreferenceIsReceiptKey;
FOUNDATION_EXPORT NSString * const SJPreferenceIsStealthKey;

@interface SJPreferences : NSObject
+ (NSDictionary<NSString *, NSNumber *> *)defaultValues;
+ (SJConfiguration *)configurationFromUserDefaults:(NSUserDefaults *)defaults;
+ (void)writeConfiguration:(SJConfiguration *)configuration toUserDefaults:(NSUserDefaults *)defaults;
+ (void)resetUserDefaults:(NSUserDefaults *)defaults;
@end

NS_ASSUME_NONNULL_END
