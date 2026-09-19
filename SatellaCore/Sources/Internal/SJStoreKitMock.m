#import "../Public/SJStoreKitMock.h"
#import "../Public/SatellaCore.h"
#import "SJDiagnostics.h"

@implementation SJMockProduct

- (instancetype)initWithProductIdentifier:(NSString *)productIdentifier
                                    price:(NSDecimalNumber *)price {
    self = [super init];
    if (self) {
        _productIdentifier = [productIdentifier copy];
        _price = [price copy];
        _localizedTitle = [productIdentifier copy];
        _localizedDescription = [productIdentifier copy];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    SJMockProduct *copy = [[[self class] allocWithZone:zone] initWithProductIdentifier:self.productIdentifier
                                                                                price:self.price];
    copy.localizedTitle = self.localizedTitle;
    copy.localizedDescription = self.localizedDescription;
    return copy;
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    return @{
        @"productIdentifier": self.productIdentifier ?: @"",
        @"price": self.price.stringValue ?: @"0",
        @"localizedTitle": self.localizedTitle ?: @"",
        @"localizedDescription": self.localizedDescription ?: @"",
    };
}

@end

@implementation SJStoreKitMock

static NSMutableDictionary<NSString *, SJMockProduct *> *SJProducts(void) {
    static NSMutableDictionary<NSString *, SJMockProduct *> *products;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        products = [NSMutableDictionary dictionary];
    });
    return products;
}

static NSError *SJMockError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:SJCoreErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Unknown error"}];
}

+ (BOOL)setProducts:(NSArray<SJMockProduct *> *)products
              error:(NSError * _Nullable * _Nullable)error {
    if (error) *error = nil;
    if (![SatellaCore isFeatureEnabled:SJFeatureProductCatalogMock]) {
        if (error) *error = SJMockError(SJCoreErrorFeatureUnavailable, @"Product catalog mock feature is disabled.");
        return NO;
    }
    NSMutableDictionary<NSString *, SJMockProduct *> *validated = [NSMutableDictionary dictionary];
    for (id object in products ?: @[]) {
        if (![object isKindOfClass:[SJMockProduct class]]) {
            if (error) *error = SJMockError(SJCoreErrorInvalidArgument, @"Products must contain SJMockProduct instances.");
            return NO;
        }
        SJMockProduct *product = object;
        if (product.productIdentifier.length == 0 || product.price == nil || [product.price isEqualToNumber:[NSDecimalNumber notANumber]] || [product.price compare:[NSDecimalNumber zero]] == NSOrderedAscending) {
            if (error) *error = SJMockError(SJCoreErrorInvalidArgument, @"Each mock product requires a non-empty identifier and non-negative price.");
            return NO;
        }
        if (validated[product.productIdentifier] != nil) {
            if (error) *error = SJMockError(SJCoreErrorInvalidArgument, @"Duplicate product identifiers are not allowed.");
            return NO;
        }
        validated[product.productIdentifier] = [product copy];
    }

    @synchronized (SJProducts()) {
        [SJProducts() removeAllObjects];
        [SJProducts() addEntriesFromDictionary:validated];
    }
    [SJDiagnostics appendModule:@"StoreKitMock" message:@"Mock product catalog updated." code:0];
    return YES;
}

+ (NSArray<SJMockProduct *> *)products {
    @synchronized (SJProducts()) {
        NSArray<NSString *> *keys = [[SJProducts() allKeys] sortedArrayUsingSelector:@selector(compare:)];
        NSMutableArray<SJMockProduct *> *result = [NSMutableArray arrayWithCapacity:keys.count];
        for (NSString *key in keys) {
            [result addObject:[SJProducts()[key] copy]];
        }
        return result;
    }
}

+ (SJMockProduct * _Nullable)productForIdentifier:(NSString *)productIdentifier {
    if (productIdentifier.length == 0) return nil;
    @synchronized (SJProducts()) {
        return [SJProducts()[productIdentifier] copy];
    }
}

+ (NSDictionary<NSString *, id> * _Nullable)makeTransactionFixtureForProductIdentifier:(NSString *)productIdentifier
                                                                                  error:(NSError * _Nullable * _Nullable)error {
    if (error) *error = nil;
    if (![SatellaCore isFeatureEnabled:SJFeatureTransactionMock]) {
        if (error) *error = SJMockError(SJCoreErrorFeatureUnavailable, @"Transaction mock feature is disabled.");
        return nil;
    }
    SJMockProduct *product = [self productForIdentifier:productIdentifier];
    if (!product) {
        if (error) *error = SJMockError(SJCoreErrorInvalidArgument, @"Unknown mock product identifier.");
        return nil;
    }
    NSString *transactionIdentifier = [[NSUUID UUID] UUIDString];
    NSDictionary *fixture = @{
        @"productIdentifier": product.productIdentifier,
        @"transactionIdentifier": transactionIdentifier,
        @"originalTransactionIdentifier": transactionIdentifier,
        @"state": @"purchased",
        @"timestamp": @([[NSDate date] timeIntervalSince1970]),
    };
    [SJDiagnostics appendModule:@"StoreKitMock" message:@"Generated transaction fixture." code:0];
    return fixture;
}

+ (NSDictionary<NSString *, id> * _Nullable)makeReceiptFixtureForProductIdentifier:(NSString *)productIdentifier
                                                                              error:(NSError * _Nullable * _Nullable)error {
    if (error) *error = nil;
    if (![SatellaCore isFeatureEnabled:SJFeatureReceiptFixture]) {
        if (error) *error = SJMockError(SJCoreErrorFeatureUnavailable, @"Receipt fixture feature is disabled.");
        return nil;
    }
    SJMockProduct *product = [self productForIdentifier:productIdentifier];
    if (!product) {
        if (error) *error = SJMockError(SJCoreErrorInvalidArgument, @"Unknown mock product identifier.");
        return nil;
    }
    NSDictionary *fixture = @{
        @"environment": @"LocalTest",
        @"bundleIdentifier": [[NSBundle mainBundle] bundleIdentifier] ?: @"",
        @"productIdentifier": product.productIdentifier,
        @"purchaseDate": @([[NSDate date] timeIntervalSince1970]),
        @"transactionIdentifier": [[NSUUID UUID] UUIDString],
    };
    [SJDiagnostics appendModule:@"StoreKitMock" message:@"Generated local receipt fixture." code:0];
    return fixture;
}

+ (void)reset {
    @synchronized (SJProducts()) {
        [SJProducts() removeAllObjects];
    }
    [SJDiagnostics appendModule:@"StoreKitMock" message:@"Mock data reset." code:0];
}

@end
