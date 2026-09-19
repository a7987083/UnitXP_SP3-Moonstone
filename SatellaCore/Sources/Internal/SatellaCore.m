#import "../Public/SatellaCore.h"
#import "../Public/SJConfiguration.h"
#import "../Public/SJStoreKitMock.h"
#import "SJDiagnostics.h"
#import <dispatch/dispatch.h>

NSString * const SJCoreErrorDomain = @"SatellaCore";
NSNotificationName const SJCoreStateDidChangeNotification = @"SJCoreStateDidChangeNotification";
NSNotificationName const SJCoreConfigurationDidChangeNotification = @"SJCoreConfigurationDidChangeNotification";

@implementation SatellaCore

static SJConfiguration *SJCurrentConfiguration(void) {
    static SJConfiguration *configuration;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        configuration = [SJConfiguration defaultConfiguration];
    });
    return configuration;
}

static NSError *SJCoreMakeError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:SJCoreErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Unknown error"}];
}

static BOOL SJFeatureIsValid(SJFeature feature) {
    return feature >= SJFeatureProductCatalogMock && feature <= SJFeatureReceiptFixture;
}

static NSDictionary<NSString *, NSNumber *> *SJConfigurationSnapshot(void) {
    @synchronized (SJCurrentConfiguration()) {
        return [[SJCurrentConfiguration() dictionaryRepresentation] copy];
    }
}

static void SJPostConfigurationChanged(void) {
    [[NSNotificationCenter defaultCenter] postNotificationName:SJCoreConfigurationDidChangeNotification
                                                        object:nil
                                                      userInfo:@{ @"configuration": SJConfigurationSnapshot() }];
    [[NSNotificationCenter defaultCenter] postNotificationName:SJCoreStateDidChangeNotification object:nil];
}

+ (NSString *)version {
    return @"1.0.0";
}

+ (NSDictionary<NSString *, NSNumber *> *)capabilities {
    return @{
        @"productCatalogMock": @YES,
        @"transactionMock": @YES,
        @"receiptFixture": @YES,
        @"liveStoreKitInterception": @NO,
        @"ui": @NO,
        @"constructor": @NO,
        @"swiftRuntime": @NO,
        @"jinx": @NO,
    };
}

+ (SJConfiguration *)configuration {
    @synchronized (SJCurrentConfiguration()) {
        return [SJCurrentConfiguration() copy];
    }
}

+ (BOOL)applyConfiguration:(SJConfiguration *)configuration
                     error:(NSError * _Nullable * _Nullable)error {
    if (error) *error = nil;
    if (![configuration isKindOfClass:[SJConfiguration class]]) {
        if (error) *error = SJCoreMakeError(SJCoreErrorInvalidConfiguration, @"Configuration must be an SJConfiguration instance.");
        return NO;
    }
    @synchronized (SJCurrentConfiguration()) {
        SJCurrentConfiguration().productCatalogMockEnabled = configuration.productCatalogMockEnabled;
        SJCurrentConfiguration().transactionMockEnabled = configuration.transactionMockEnabled;
        SJCurrentConfiguration().receiptFixtureEnabled = configuration.receiptFixtureEnabled;
    }
    [SJDiagnostics appendModule:@"Core" message:@"Configuration applied." code:0];
    SJPostConfigurationChanged();
    return YES;
}

+ (BOOL)setFeature:(SJFeature)feature
           enabled:(BOOL)enabled
             error:(NSError * _Nullable * _Nullable)error {
    if (error) *error = nil;
    if (!SJFeatureIsValid(feature)) {
        if (error) *error = SJCoreMakeError(SJCoreErrorInvalidFeature, @"Unknown feature identifier.");
        return NO;
    }
    if (![self isFeatureAvailable:feature]) {
        if (error) *error = SJCoreMakeError(SJCoreErrorFeatureUnavailable, @"Feature is unavailable in this build.");
        return NO;
    }
    @synchronized (SJCurrentConfiguration()) {
        switch (feature) {
            case SJFeatureProductCatalogMock:
                SJCurrentConfiguration().productCatalogMockEnabled = enabled;
                break;
            case SJFeatureTransactionMock:
                SJCurrentConfiguration().transactionMockEnabled = enabled;
                break;
            case SJFeatureReceiptFixture:
                SJCurrentConfiguration().receiptFixtureEnabled = enabled;
                break;
        }
    }
    [SJDiagnostics appendModule:@"Core"
                        message:[NSString stringWithFormat:@"Feature %ld set to %@.", (long)feature, enabled ? @"enabled" : @"disabled"]
                           code:0];
    SJPostConfigurationChanged();
    return YES;
}

+ (BOOL)isFeatureEnabled:(SJFeature)feature {
    if (!SJFeatureIsValid(feature)) return NO;
    @synchronized (SJCurrentConfiguration()) {
        switch (feature) {
            case SJFeatureProductCatalogMock:
                return SJCurrentConfiguration().productCatalogMockEnabled;
            case SJFeatureTransactionMock:
                return SJCurrentConfiguration().transactionMockEnabled;
            case SJFeatureReceiptFixture:
                return SJCurrentConfiguration().receiptFixtureEnabled;
        }
    }
    return NO;
}

+ (BOOL)isFeatureAvailable:(SJFeature)feature {
    return SJFeatureIsValid(feature);
}

+ (SJFeatureState)stateForFeature:(SJFeature)feature {
    if (![self isFeatureAvailable:feature]) return SJFeatureStateUnavailable;
    return [self isFeatureEnabled:feature] ? SJFeatureStateEnabled : SJFeatureStateDisabled;
}

+ (NSDictionary<NSString *, id> *)status {
    SJConfiguration *configuration = [self configuration];
    return @{
        @"version": [self version],
        @"capabilities": [self capabilities],
        @"configuration": configuration.dictionaryRepresentation,
        @"mockProductCount": @([SJStoreKitMock products].count),
        @"diagnosticCount": @([[self recentDiagnostics] count]),
    };
}

+ (NSData * _Nullable)statusJSONWithError:(NSError * _Nullable * _Nullable)error {
    if (error) *error = nil;
    NSDictionary<NSString *, id> *status = [self status];
    if (![NSJSONSerialization isValidJSONObject:status]) {
        if (error) *error = SJCoreMakeError(SJCoreErrorInvalidConfiguration, @"Status dictionary is not JSON serializable.");
        return nil;
    }
    return [NSJSONSerialization dataWithJSONObject:status options:NSJSONWritingPrettyPrinted error:error];
}

+ (NSArray<NSDictionary<NSString *, id> *> *)recentDiagnostics {
    return [SJDiagnostics snapshot];
}

+ (void)resetConfiguration {
    SJConfiguration *defaults = [SJConfiguration defaultConfiguration];
    [self applyConfiguration:defaults error:nil];
    [SJStoreKitMock reset];
    [SJDiagnostics reset];
    [SJDiagostics appendModule:@"Core" message:@"Configuration reset." code:0];
}

@end
