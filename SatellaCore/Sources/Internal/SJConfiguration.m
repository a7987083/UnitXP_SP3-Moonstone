#import "../Public/SJConfiguration.h"

@implementation SJConfiguration

+ (instancetype)defaultConfiguration {
    SJConfiguration *config = [[self alloc] init];
    config.productCatalogMockEnabled = NO;
    config.transactionMockEnabled = NO;
    config.receiptFixtureEnabled = NO;
    return config;
}

- (id)copyWithZone:(NSZone *)zone {
    SJConfiguration *copy = [[[self class] allocWithZone:zone] init];
    copy.productCatalogMockEnabled = self.productCatalogMockEnabled;
    copy.transactionMockEnabled = self.transactionMockEnabled;
    copy.receiptFixtureEnabled = self.receiptFixtureEnabled;
    return copy;
}

- (NSDictionary<NSString *, NSNumber *> *)dictionaryRepresentation {
    return @{
        @"productCatalogMock": @(self.productCatalogMockEnabled),
        @"transactionMock": @(self.transactionMockEnabled),
        @"receiptFixture": @(self.receiptFixtureEnabled),
    };
}

@end
