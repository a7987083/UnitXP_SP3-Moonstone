#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SJConfiguration : NSObject <NSCopying>

@property (nonatomic) BOOL productCatalogFallbackEnabled;
@property (nonatomic) BOOL transactionSimulationEnabled;
@property (nonatomic) BOOL receiptSimulationEnabled;
@property (nonatomic) BOOL canMakePaymentsOverrideEnabled;
@property (nonatomic) BOOL priceOverrideEnabled;
@property (nonatomic) BOOL observerBridgeEnabled;
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
