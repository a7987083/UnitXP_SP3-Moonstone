#import <Foundation/Foundation.h>
#import "SJConfiguration.h"
#import "SJStoreKitMock.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const SJCoreErrorDomain;
FOUNDATION_EXPORT NSNotificationName const SJCoreStateDidChangeNotification;
FOUNDATION_EXPORT NSNotificationName const SJCoreConfigurationDidChangeNotification;

typedef NS_ENUM(NSInteger, SJFeature) {
    SJFeatureProductCatalogMock = 0,
    SJFeatureTransactionMock = 1,
    SJFeatureReceiptFixture = 2,
};

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
};


@interface SatellaCore : NSObject

+ (NSString *)version;
+ (NSDictionary<NSString *, NSNumber *> *)capabilities;
+ (SJConfiguration *)configuration;

+ (BOOL)applyConfiguration:(SJConfiguration *)configuration
                     error:(NSError * _Nullable * _Nullable)error;

+ (BOOL)setFeature:(SJFeature)feature
           enabled:(BOOL)enabled
             error:(NSError * _Nullable * _Nullable)error;

+ (BOOL)isFeatureEnabled:(SJFeature)feature;
+ (BOOL)isFeatureAvailable:(SJFeature)feature;
+ (SJFeatureState)stateForFeature:(SJFeature)feature;

+ (NSDictionary<NSString *, id> *)status;
+ (NSData * _Nullable)statusJSONWithError:(NSError * _Nullable * _Nullable)error;
+ (NSArray<NSDictionary<NSString *, id> *> *)recentDiagnostics;
+ (void)resetConfiguration;

@end

NS_ASSUME_NONNULL_END
