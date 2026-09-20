#import "../Public/SJStoreKitMock.h"
#import "../Public/SatellaCore.h"
#import "SJDiagnostics.h"
#import "SJStateCoordinator.h"
#import "../Public/SJStoreKitTestEngine.h"
#import "../Public/SJReceiptGenerator.h"

@implementation SJMockProduct

- (instancetype)initWithProductIdentifier:(NSString *)productIdentifier price:(NSDecimalNumber *)price {
    self = [super init];
    if (self) {
        _productIdentifier = [productIdentifier copy];
        _price = [price copy];
        _priceLocale = [NSLocale localeWithLocaleIdentifier:@"da_DK"];
        _localizedTitle = [productIdentifier copy];
        _localizedDescription = [productIdentifier copy];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    SJMockProduct *copy = [[[self class] allocWithZone:zone] initWithProductIdentifier:self.productIdentifier price:self.price];
    copy.priceLocale = self.priceLocale;
    copy.localizedTitle = self.localizedTitle;
    copy.localizedDescription = self.localizedDescription;
    return copy;
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    return @{
        @"productIdentifier": self.productIdentifier ?: @"",
        @"price": self.price.stringValue ?: @"0",
        @"priceLocale": self.priceLocale.localeIdentifier ?: @"da_DK",
        @"localizedTitle": self.localizedTitle ?: @"",
        @"localizedDescription": self.localizedDescription ?: @"",
    };
}

@end

@implementation SJStoreKitMock

static NSError *SJMockError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:SJCoreErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message ?: @"Unknown error"}];
}

+ (BOOL)setProducts:(NSArray<SJMockProduct *> * _Nullable)products error:(NSError **)error {
    if (error) *error = nil;
    if (!products) {
        if (error) *error = SJMockError(SJCoreErrorInvalidArgument, @"Products array must not be nil.");
        return NO;
    }
    SJStateCoordinator *state = [SJStateCoordinator shared];
    NSMutableDictionary<NSString *, SJMockProduct *> *validated = [NSMutableDictionary dictionary];
    for (id object in products) {
        if (![object isKindOfClass:[SJMockProduct class]]) {
            if (error) *error = SJMockError(SJCoreErrorInvalidArgument, @"Products must contain SJMockProduct instances.");
            return NO;
        }
        SJMockProduct *product = object;
        if (product.productIdentifier.length == 0 || !product.price || [product.price isEqualToNumber:NSDecimalNumber.notANumber] || [product.price compare:NSDecimalNumber.zero] == NSOrderedAscending) {
            if (error) *error = SJMockError(SJCoreErrorInvalidArgument, @"Each mock product requires a non-empty identifier and non-negative price.");
            return NO;
        }
        if (validated[product.productIdentifier]) {
            if (error) *error = SJMockError(SJCoreErrorInvalidArgument, @"Duplicate product identifiers are not allowed.");
            return NO;
        }
        validated[product.productIdentifier] = [product copy];
    }

    @synchronized (state) {
        if (!state.configuration.productCatalogFallbackEnabled) {
            if (error) *error = SJMockError(SJCoreErrorFeatureDisabled, @"Product catalog fallback is disabled.");
            return NO;
        }
        [state.products removeAllObjects];
        [state.productOrder removeAllObjects];
        [state.products addEntriesFromDictionary:validated];
        for (SJMockProduct *product in products) [state.productOrder addObject:product.productIdentifier];
    }
    [SJDiagnostics appendModule:@"StoreKitMock" message:@"Mock product catalog updated." code:0];
    return YES;
}

+ (NSArray<SJMockProduct *> *)products {
    SJStateCoordinator *state = [SJStateCoordinator shared];
    @synchronized (state) {
        if (!state.configuration.productCatalogFallbackEnabled) return @[];
        NSArray<NSString *> *keys = [state.productOrder copy];
        NSMutableArray<SJMockProduct *> *result = [NSMutableArray arrayWithCapacity:keys.count];
        for (NSString *key in keys) if (state.products[key]) [result addObject:[state.products[key] copy]];
        return result;
    }
}

+ (SJMockProduct * _Nullable)productForIdentifier:(NSString *)productIdentifier {
    if (productIdentifier.length == 0) return nil;
    SJStateCoordinator *state = [SJStateCoordinator shared];
    @synchronized (state) {
        if (!state.configuration.productCatalogFallbackEnabled) return nil;
        return [state.products[productIdentifier] copy];
    }
}

+ (NSDictionary<NSString *, id> * _Nullable)makeTransactionFixtureForProductIdentifier:(NSString *)productIdentifier error:(NSError **)error {
    SJMockTransaction *transaction = [SJStoreKitTestEngine makePurchasedTransactionForProductIdentifier:productIdentifier error:error];
    return transaction ? [transaction dictionaryRepresentation] : nil;
}

+ (NSDictionary<NSString *, id> * _Nullable)makeReceiptFixtureForProductIdentifier:(NSString *)productIdentifier error:(NSError **)error {
    if (error) *error = nil;
    if (![SatellaCore isFeatureEnabled:SJFeatureReceiptSimulation]) {
        if (error) *error = SJMockError(SJCoreErrorFeatureDisabled, @"Receipt simulation is disabled.");
        return nil;
    }
    return [[SJReceiptGenerator receiptForProductIdentifier:productIdentifier] dictionaryRepresentation];
}

+ (void)reset {
    SJStateCoordinator *state = [SJStateCoordinator shared];
    @synchronized (state) { [state.products removeAllObjects]; [state.productOrder removeAllObjects]; }
    [SJDiagnostics appendModule:@"StoreKitMock" message:@"Mock product catalog reset." code:0];
}

@end
