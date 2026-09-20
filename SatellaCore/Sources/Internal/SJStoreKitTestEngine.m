#import "../Public/SJStoreKitTestEngine.h"
#import "../Public/SJReceiptGenerator.h"
#import "../Public/SatellaCore.h"
#import "SJDiagnostics.h"
#import "SJStateCoordinator.h"

@implementation SJProductsResponse

- (instancetype)init {
    self = [super init];
    if (self) {
        _products = @[];
        _invalidProductIdentifiers = @[];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    SJProductsResponse *copy = [[[self class] allocWithZone:zone] init];
    copy.products = [self.products copy];
    copy.invalidProductIdentifiers = [self.invalidProductIdentifiers copy];
    return copy;
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    NSMutableArray *products = [NSMutableArray arrayWithCapacity:self.products.count];
    for (SJMockProduct *product in self.products) {
        [products addObject:[product dictionaryRepresentation]];
    }
    return @{
        @"products": products,
        @"invalidProductIdentifiers": self.invalidProductIdentifiers ?: @[],
    };
}

@end

@implementation SJMockTransaction

- (instancetype)init {
    self = [super init];
    if (self) {
        _productIdentifier = @"";
        _originalTransactionIdentifier = NSUUID.UUID.UUIDString;
    }
    return self;
}

// TransactionHook.swift replaces these getters, not the stored values.  Keep
// the explicit test object semantically identical: every getter invocation is
// evaluated at read time.
- (SJMockTransactionState)state {
    return SJMockTransactionStatePurchased;
}

- (void)setState:(SJMockTransactionState)state {
    (void)state;
}

- (NSString *)matchingIdentifier {
    return NSUUID.UUID.UUIDString;
}

- (void)setMatchingIdentifier:(NSString *)matchingIdentifier {
    (void)matchingIdentifier;
}

- (NSString *)transactionIdentifier {
    return NSUUID.UUID.UUIDString;
}

- (void)setTransactionIdentifier:(NSString *)transactionIdentifier {
    (void)transactionIdentifier;
}

- (NSError * _Nullable)error {
    return nil;
}

- (void)setError:(NSError * _Nullable)error {
    (void)error;
}

- (NSDate *)transactionDate {
    return [NSDate date];
}

- (void)setTransactionDate:(NSDate *)transactionDate {
    (void)transactionDate;
}

- (id)copyWithZone:(NSZone *)zone {
    SJMockTransaction *copy = [[[self class] allocWithZone:zone] init];
    copy.productIdentifier = self.productIdentifier;
    copy.originalTransactionIdentifier = self.originalTransactionIdentifier;
    return copy;
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    // Evaluate each dynamic getter exactly once for a coherent snapshot.
    NSString *matchingIdentifier = self.matchingIdentifier;
    NSString *transactionIdentifier = self.transactionIdentifier;
    NSDate *transactionDate = self.transactionDate;
    return @{
        @"productIdentifier": self.productIdentifier ?: @"",
        @"state": @(self.state),
        @"matchingIdentifier": matchingIdentifier ?: @"",
        @"transactionIdentifier": transactionIdentifier ?: @"",
        @"originalTransactionIdentifier": self.originalTransactionIdentifier ?: @"",
        @"error": [NSNull null],
        @"transactionDate": @(transactionDate.timeIntervalSince1970),
    };
}

@end

@implementation SJStoreKitTestEngine

static NSError *SJEngineError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:SJCoreErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Unknown error"}];
}

+ (BOOL)canMakePaymentsWithSystemValue:(BOOL)systemValue {
    SJStateCoordinator *state = [SJStateCoordinator shared];
    // Upstream Preferences are static values and CanPayHook itself is always
    // installed. Avoid adding OC synchronization to the strict result path.
    if (state.configuration.behaviorMode == SJBehaviorModeUpstreamParity) return YES;
    @synchronized (state) {
        return state.configuration.canMakePaymentsOverrideEnabled ? YES : systemValue;
    }
}

+ (NSDecimalNumber *)effectivePriceForProduct:(SJMockProduct *)product {
    NSParameterAssert(product != nil);
    SJStateCoordinator *state = [SJStateCoordinator shared];
    if (state.configuration.behaviorMode == SJBehaviorModeUpstreamParity) {
        return state.configuration.priceOverrideEnabled
            ? [NSDecimalNumber decimalNumberWithString:@"0.01"]
            : [product.price copy];
    }
    @synchronized (state) {
        return state.configuration.priceOverrideEnabled ? [state.configuration.testPrice copy] : [product.price copy];
    }
}

+ (void)addProductsDelegate:(id<SJProductsRequestTestDelegate>)delegate {
    if (!delegate) return;
    SJStateCoordinator *state = [SJStateCoordinator shared];
    if (state.configuration.behaviorMode == SJBehaviorModeUpstreamParity) {
        [state.productDelegates addObject:delegate];
    } else {
        @synchronized (state) { [state.productDelegates addObject:delegate]; }
    }
}

+ (void)removeProductsDelegate:(id<SJProductsRequestTestDelegate>)delegate {
    if (!delegate) return;
    SJStateCoordinator *state = [SJStateCoordinator shared];
    if (state.configuration.behaviorMode == SJBehaviorModeUpstreamParity) {
        [state.productDelegates removeObjectIdenticalTo:delegate];
    } else {
        @synchronized (state) { [state.productDelegates removeObjectIdenticalTo:delegate]; }
    }
}

+ (SJProductsResponse * _Nullable)responseForProductIdentifiers:(NSSet<NSString *> *)productIdentifiers
                                                originalProducts:(NSArray<SJMockProduct *> *)originalProducts
                                                           error:(NSError **)error {
    return [self responseForProductIdentifiers:productIdentifiers
                              originalProducts:originalProducts
                     invalidProductIdentifiers:@[]
                                         error:error];
}

+ (SJProductsResponse * _Nullable)responseForProductIdentifiers:(NSSet<NSString *> *)productIdentifiers
                                                originalProducts:(NSArray<SJMockProduct *> *)originalProducts
                                       invalidProductIdentifiers:(NSArray<NSString *> *)invalidProductIdentifiers
                                                           error:(NSError **)error {
    if (error) *error = nil;
    if (!productIdentifiers || !originalProducts || !invalidProductIdentifiers) {
        if (error) *error = SJEngineError(SJCoreErrorInvalidArgument, @"Identifiers, original products, and invalid identifiers must not be nil.");
        return nil;
    }

    for (id identifier in productIdentifiers) {
        if (![identifier isKindOfClass:NSString.class]) {
            if (error) *error = SJEngineError(SJCoreErrorInvalidArgument, @"Product identifiers must be NSString instances.");
            return nil;
        }
    }
    for (id product in originalProducts) {
        if (![product isKindOfClass:SJMockProduct.class]) {
            if (error) *error = SJEngineError(SJCoreErrorInvalidArgument, @"Original products must contain SJMockProduct instances.");
            return nil;
        }
    }
    for (id identifier in invalidProductIdentifiers) {
        if (![identifier isKindOfClass:NSString.class]) {
            if (error) *error = SJEngineError(SJCoreErrorInvalidArgument, @"Invalid product identifiers must contain NSString instances.");
            return nil;
        }
    }

    SJProductsResponse *response = [SJProductsResponse new];
    if (originalProducts.count > 0) {
        // Delegate.swift forwards the original non-empty SKProductsResponse.
        // The mock seam cannot preserve the concrete StoreKit response class,
        // but it does preserve both product object identity and invalid IDs.
        response.products = originalProducts;
        response.invalidProductIdentifiers = invalidProductIdentifiers;
        return response;
    }

    SJStateCoordinator *state = [SJStateCoordinator shared];
    void (^buildFallback)(void) = ^{
        if (state.products.count == 0) {
            for (NSString *identifier in productIdentifiers) {
                if (identifier.length == 0) continue;
                SJMockProduct *product = [[SJMockProduct alloc] initWithProductIdentifier:identifier
                                                                                   price:[NSDecimalNumber decimalNumberWithString:@"0.01"]];
                product.priceLocale = [NSLocale localeWithLocaleIdentifier:@"da_DK"];
                product.localizedTitle = identifier;
                product.localizedDescription = identifier;
                state.products[identifier] = product;
                [state.productOrder addObject:identifier];
            }
        }
        NSMutableArray<SJMockProduct *> *products = [NSMutableArray arrayWithCapacity:state.productOrder.count];
        for (NSString *identifier in state.productOrder) {
            SJMockProduct *product = state.products[identifier];
            if (product) [products addObject:product];
        }
        response.products = products;
        response.invalidProductIdentifiers = @[];
    };

    if (state.configuration.behaviorMode == SJBehaviorModeUpstreamParity) {
        // Helpers/Delegate.swift does not synchronize products/delegates. Keep
        // the strict path free of OC-only locking; ExtendedTesting stays safe.
        buildFallback();
    } else {
        @synchronized (state) {
            if (!state.configuration.productCatalogFallbackEnabled) return nil;
            buildFallback();
        }
    }
    return response;
}

+ (BOOL)deliverProductsForIdentifiers:(NSSet<NSString *> *)productIdentifiers
                      originalProducts:(NSArray<SJMockProduct *> *)originalProducts
                                 error:(NSError **)error {
    return [self deliverProductsForIdentifiers:productIdentifiers
                              originalProducts:originalProducts
                     invalidProductIdentifiers:@[]
                                         error:error];
}

+ (BOOL)deliverProductsForIdentifiers:(NSSet<NSString *> *)productIdentifiers
                      originalProducts:(NSArray<SJMockProduct *> *)originalProducts
             invalidProductIdentifiers:(NSArray<NSString *> *)invalidProductIdentifiers
                                 error:(NSError **)error {
    SJProductsResponse *response = [self responseForProductIdentifiers:productIdentifiers
                                                       originalProducts:originalProducts
                                              invalidProductIdentifiers:invalidProductIdentifiers
                                                                  error:error];
    if (!response) {
        // ExtendedTesting disabled state is modeled as no synthetic delivery,
        // not a business error. The caller's original path remains authoritative.
        return error == NULL || *error == nil;
    }

    NSArray *delegates;
    SJStateCoordinator *state = [SJStateCoordinator shared];
    if (state.configuration.behaviorMode == SJBehaviorModeUpstreamParity) {
        delegates = [state.productDelegates copy];
    } else {
        @synchronized (state) { delegates = [state.productDelegates copy]; }
    }

    for (id<SJProductsRequestTestDelegate> delegate in delegates) {
        [delegate sj_productsRequestDidReceiveResponse:response];
    }
    [SJDiagnostics appendModule:@"ProductsDelegate"
                         message:@"Delivered product response to registered test delegates."
                            code:0];
    return YES;
}

+ (void)addTransactionObserver:(id<SJTransactionTestObserver>)observer {
    if (!observer) return;
    SJStateCoordinator *state = [SJStateCoordinator shared];
    if (state.configuration.behaviorMode == SJBehaviorModeUpstreamParity) {
        [state.transactionObservers addObject:observer];
    } else {
        @synchronized (state) { [state.transactionObservers addObject:observer]; }
    }
}

+ (void)removeTransactionObserver:(id<SJTransactionTestObserver>)observer {
    if (!observer) return;
    SJStateCoordinator *state = [SJStateCoordinator shared];
    if (state.configuration.behaviorMode == SJBehaviorModeUpstreamParity) {
        [state.transactionObservers removeObjectIdenticalTo:observer];
    } else {
        @synchronized (state) { [state.transactionObservers removeObjectIdenticalTo:observer]; }
    }
}

+ (SJMockTransaction * _Nullable)makePurchasedTransactionForProductIdentifier:(NSString *)productIdentifier
                                                                        error:(NSError **)error {
    if (error) *error = nil;
    if (productIdentifier.length == 0) {
        if (error) *error = SJEngineError(SJCoreErrorInvalidArgument, @"Product identifier must not be empty.");
        return nil;
    }

    SJStateCoordinator *state = [SJStateCoordinator shared];
    if (state.configuration.behaviorMode == SJBehaviorModeExtendedTesting) {
        @synchronized (state) {
            if (!state.configuration.transactionSimulationEnabled) return nil;
        }
    }

    // TransactionHook.swift is independent of DelegateHook/product fallback.
    // Do not require a cached mock product here.
    SJMockTransaction *transaction = [SJMockTransaction new];
    transaction.productIdentifier = productIdentifier;
    return transaction;
}

+ (BOOL)publishTransactions:(NSArray<SJMockTransaction *> *)transactions error:(NSError **)error {
    if (error) *error = nil;
    if (!transactions) {
        if (error) *error = SJEngineError(SJCoreErrorInvalidArgument, @"Transactions array must not be nil.");
        return NO;
    }

    SJStateCoordinator *state = [SJStateCoordinator shared];
    __block NSArray *observers = nil;
    __block NSMutableArray<SJMockTransaction *> *current = [NSMutableArray array];
    __block BOOL shouldDeliver = YES;
    void (^prepare)(void) = ^{
        if (!state.configuration.observerBridgeEnabled) {
            shouldDeliver = NO;
            return;
        }
        for (id object in transactions) {
            if (![object isKindOfClass:SJMockTransaction.class]) {
                if (error) *error = SJEngineError(SJCoreErrorInvalidArgument, @"Transactions must contain SJMockTransaction instances.");
                shouldDeliver = NO;
                return;
            }
            SJMockTransaction *transaction = object;
            if ([state.seenTransactions containsObject:transaction]) {
                shouldDeliver = NO;
                return;
            }
            [state.seenTransactions addObject:transaction];
            [current addObject:transaction];
        }
        observers = [state.transactionObservers copy];
    };

    if (state.configuration.behaviorMode == SJBehaviorModeUpstreamParity) {
        prepare();
    } else {
        @synchronized (state) { prepare(); }
    }
    if (error && *error) return NO;
    if (!shouldDeliver) return YES;

    NSArray<SJMockTransaction *> *delivery = [current copy];
    for (id<SJTransactionTestObserver> observer in observers) {
        [observer sj_paymentQueueUpdatedTransactions:delivery];
    }
    [SJDiagnostics appendModule:@"TransactionObserver"
                         message:@"Delivered transaction update to registered test observers."
                            code:0];
    return YES;
}

+ (NSData * _Nullable)oldReceiptDataForProductIdentifier:(NSString * _Nullable)productIdentifier error:(NSError **)error {
    if (error) *error = nil;
    SJStateCoordinator *state = [SJStateCoordinator shared];
    if (!state.configuration.receiptSimulationEnabled) {
        return nil;
    }
    return [SJReceiptGenerator JSONDataForOldReceipt:[SJReceiptGenerator oldReceiptForProductIdentifier:productIdentifier]
                                               error:error];
}

+ (BOOL)shouldReplaceVerificationResponseForURL:(NSURL * _Nullable)URL {
    return URL != nil && [URL.absoluteString hasSuffix:@"/verifyReceipt"];
}

+ (NSData * _Nullable)verificationResponseDataForURL:(NSURL *)URL
                                   productIdentifier:(NSString * _Nullable)productIdentifier
                                               error:(NSError **)error {
    if (error) *error = nil;
    if (!URL) {
        if (error) *error = SJEngineError(SJCoreErrorInvalidArgument, @"URL is required.");
        return nil;
    }

    // URLHook.swift passes non-/verifyReceipt requests through untouched.  In
    // the explicit API, nil + no error means "do not replace the response".
    if (![self shouldReplaceVerificationResponseForURL:URL]) return nil;

    SJStateCoordinator *state = [SJStateCoordinator shared];
    if (!state.configuration.receiptSimulationEnabled) {
        return nil;
    }

    NSString *normalizedProductIdentifier = productIdentifier ?: @"";
    return [SJReceiptGenerator JSONDataForVerificationResponse:[SJReceiptGenerator verificationResponseForProductIdentifier:normalizedProductIdentifier]
                                                         error:error];
}

+ (NSData * _Nullable)verificationResponseDataForURL:(NSURL *)URL error:(NSError **)error {
    SJStateCoordinator *state = [SJStateCoordinator shared];
    NSString *productIdentifier;
    if (state.configuration.behaviorMode == SJBehaviorModeUpstreamParity) {
        productIdentifier = [state.productOrder.lastObject copy] ?: @"";
    } else {
        @synchronized (state) { productIdentifier = [state.productOrder.lastObject copy] ?: @""; }
    }
    // URLHook.swift uses SatellaDelegate.shared.products.last?.productIdentifier ?? "".
    return [self verificationResponseDataForURL:URL productIdentifier:productIdentifier error:error];
}

+ (void)resetSession {
    SJStateCoordinator *state = [SJStateCoordinator shared];
    @synchronized (state) {
        [state.products removeAllObjects];
        [state.productOrder removeAllObjects];
        [state.productDelegates removeAllObjects];
        [state.transactionObservers removeAllObjects];
        [state.seenTransactions removeAllObjects];
    }
    [SJDiagnostics appendModule:@"StoreKitTestEngine" message:@"Test session state reset." code:0];
}

@end
