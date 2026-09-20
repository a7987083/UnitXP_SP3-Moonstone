#import "../Public/SJConfiguration.h"

@implementation SJConfiguration

+ (instancetype)defaultConfiguration {
    SJConfiguration *config = [[self alloc] init];
    // These three behaviours were installed unconditionally by the upstream
    // Swift entry point. They remain opt-in at API integration time because
    // SatellaCore itself has no constructor/+load entry point.
    config.productCatalogFallbackEnabled = YES;
    config.transactionSimulationEnabled = YES;
    config.canMakePaymentsOverrideEnabled = YES;
    config.receiptSimulationEnabled = NO;
    config.priceOverrideEnabled = NO;
    config.observerBridgeEnabled = NO;
    config.testPrice = [NSDecimalNumber decimalNumberWithString:@"0.01"];
    config.testEnvironment = @"LocalTest";

    config.enabledPreference = YES;
    config.gesturePreferenceEnabled = YES;
    config.hiddenPreferenceEnabled = NO;
    config.stealthPreferenceEnabled = NO;
    return config;
}

- (id)copyWithZone:(NSZone *)zone {
    SJConfiguration *copy = [[[self class] allocWithZone:zone] init];
    copy.productCatalogFallbackEnabled = self.productCatalogFallbackEnabled;
    copy.transactionSimulationEnabled = self.transactionSimulationEnabled;
    copy.receiptSimulationEnabled = self.receiptSimulationEnabled;
    copy.canMakePaymentsOverrideEnabled = self.canMakePaymentsOverrideEnabled;
    copy.priceOverrideEnabled = self.priceOverrideEnabled;
    copy.observerBridgeEnabled = self.observerBridgeEnabled;
    copy.testPrice = [self.testPrice copy];
    copy.testEnvironment = [self.testEnvironment copy];
    copy.enabledPreference = self.enabledPreference;
    copy.gesturePreferenceEnabled = self.gesturePreferenceEnabled;
    copy.hiddenPreferenceEnabled = self.hiddenPreferenceEnabled;
    copy.stealthPreferenceEnabled = self.stealthPreferenceEnabled;
    return copy;
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    return @{
        @"productCatalogFallback": @(self.productCatalogFallbackEnabled),
        @"transactionSimulation": @(self.transactionSimulationEnabled),
        @"receiptSimulation": @(self.receiptSimulationEnabled),
        @"canMakePaymentsOverride": @(self.canMakePaymentsOverrideEnabled),
        @"priceOverride": @(self.priceOverrideEnabled),
        @"observerBridge": @(self.observerBridgeEnabled),
        @"testPrice": self.testPrice.stringValue ?: @"0.01",
        @"testEnvironment": self.testEnvironment ?: @"LocalTest",
        @"enabledPreference": @(self.enabledPreference),
        @"gesturePreference": @(self.gesturePreferenceEnabled),
        @"hiddenPreference": @(self.hiddenPreferenceEnabled),
        @"stealthPreference": @(self.stealthPreferenceEnabled),
    };
}

@end
