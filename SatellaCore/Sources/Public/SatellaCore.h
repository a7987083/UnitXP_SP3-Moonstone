#import <Foundation/Foundation.h>
#import "SJConfiguration.h"
#import "SJPreferences.h"
#import "SJReceiptGenerator.h"
#import "SJReceiptModels.h"
#import "SJRuntimeTestAdapter.h"
#import "SJStoreKitMock.h"
#import "SJStoreKitTestEngine.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const SJCoreErrorDomain;
FOUNDATION_EXPORT NSNotificationName const SJCoreStateDidChangeNotification;
FOUNDATION_EXPORT NSNotificationName const SJCoreConfigurationDidChangeNotification;

typedef NS_ENUM(NSInteger, SJFeature) {
    SJFeatureProductCatalogFallback = 0,
    SJFeatureTransactionSimulation = 1,
    SJFeatureReceiptSimulation = 2,
    SJFeatureCanMakePaymentsOverride = 3,
    SJFeaturePriceOverride = 4,
    SJFeatureObserverBridge = 5,
    SJFeatureStealthSimulation = 6,
};

// Compatibility aliases for the v1.0 API names.
#define SJFeatureProductCatalogMock SJFeatureProductCatalogFallback
#define SJFeatureTransactionMock SJFeatureTransactionSimulation
#define SJFeatureReceiptFixture SJFeatureReceiptSimulation

typedef NS_ENUM(NSInteger, SJFeatureState) {
    SJFeatureStateUnavailable = 0,
    SJFeatureStateDisabled = 1,
    SJFeatureStateEnabled = 2,
    SJFeatureStateError = 3,
};

typedef NS_ENUM(NSInteger, SJCoreErrorCode) {
    SJCoreErrorInvalidFeature = 1001,
    SJCoreErrorInvalidConfiguration = 1002,
    SJCoreErrorFeatureUnavailable = 1003,
    SJCoreErrorInvalidArgument = 1004,
    SJCoreErrorFeatureDisabled = 1005,
    SJCoreErrorMissingDependency = 1006,
};

@interface SatellaCore : NSObject
+ (NSString *)version;
+ (NSDictionary<NSString *, id> *)capabilities;
+ (SJConfiguration *)configuration;
+ (BOOL)applyConfiguration:(SJConfiguration *)configuration error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)setFeature:(SJFeature)feature enabled:(BOOL)enabled error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)isFeatureEnabled:(SJFeature)feature;
+ (BOOL)isFeatureAvailable:(SJFeature)feature;
+ (SJFeatureState)stateForFeature:(SJFeature)feature;
+ (NSDictionary<NSString *, id> *)status;
+ (NSData * _Nullable)statusJSONWithError:(NSError * _Nullable * _Nullable)error;
+ (NSArray<NSDictionary<NSString *, id> *> *)recentDiagnostics;
+ (BOOL)reloadPreferencesFromUserDefaults:(NSUserDefaults *)defaults error:(NSError * _Nullable * _Nullable)error;
+ (void)persistConfigurationToUserDefaults:(NSUserDefaults *)defaults;
+ (void)resetConfiguration;
@end

NS_ASSUME_NONNULL_END
