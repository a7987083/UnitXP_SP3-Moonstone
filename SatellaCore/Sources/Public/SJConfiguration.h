#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SJBehaviorMode) {
    // Default. Result-producing APIs ignore OC-only test overrides when the
    // upstream Swift source has a fixed value or an always-installed hook.
    SJBehaviorModeUpstreamParity = 0,
    // Keeps the legacy configurable test surface for isolated unit tests.
    // This mode is intentionally not used when comparing results to upstream.
    SJBehaviorModeExtendedTesting = 1,
};

@interface SJConfiguration : NSObject <NSCopying>

@property (nonatomic) SJBehaviorMode behaviorMode;
@property (nonatomic) BOOL productCatalogFallbackEnabled;
@property (nonatomic) BOOL transactionSimulationEnabled;
@property (nonatomic) BOOL receiptSimulationEnabled;
@property (nonatomic) BOOL canMakePaymentsOverrideEnabled;
@property (nonatomic) BOOL priceOverrideEnabled;
@property (nonatomic) BOOL observerBridgeEnabled;
// OC-only extensions. In SJBehaviorModeUpstreamParity these do not affect
// upstream-fixed results (price remains 0.01 and environment Production).
@property (nonatomic, copy) NSDecimalNumber *testPrice;
@property (nonatomic, copy) NSString *testEnvironment;

// Original Satella preferences retained for source-level compatibility/auditing.
// UI-specific flags are metadata only; SatellaCore never creates UI.
@property (nonatomic) BOOL enabledPreference;
@property (nonatomic) BOOL gesturePreferenceEnabled;
@property (nonatomic) BOOL hiddenPreferenceEnabled;
@property (nonatomic) BOOL stealthPreferenceEnabled;

+ (instancetype)defaultConfiguration;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END
