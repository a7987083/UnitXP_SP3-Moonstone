#import "../Public/SJStoreKitTestEngine.h"
#import "../Public/SJReceiptGenerator.h"
#import "../Public/SatellaCore.h"
#import "SJDiagnostics.h"
#import "SJStateCoordinator.h"

@implementation SJProductsResponse
- (instancetype)init { self=[super init]; if(self){ _products=@[]; _invalidProductIdentifiers=@[]; } return self; }
- (id)copyWithZone:(NSZone *)zone { SJProductsResponse *copy=[[[self class] allocWithZone:zone] init]; copy.products=[[NSArray alloc] initWithArray:self.products copyItems:YES]; copy.invalidProductIdentifiers=[self.invalidProductIdentifiers copy]; return copy; }
- (NSDictionary<NSString *,id> *)dictionaryRepresentation { NSMutableArray *p=[NSMutableArray arrayWithCapacity:self.products.count]; for(SJMockProduct *x in self.products)[p addObject:[x dictionaryRepresentation]]; return @{@"products":p,@"invalidProductIdentifiers":self.invalidProductIdentifiers ?: @[]}; }
@end

@implementation SJMockTransaction
- (instancetype)init { self=[super init]; if(self){ _productIdentifier=@""; _state=SJMockTransactionStatePurchased; _matchingIdentifier=NSUUID.UUID.UUIDString; _transactionIdentifier=NSUUID.UUID.UUIDString; _originalTransactionIdentifier=_transactionIdentifier; _transactionDate=[NSDate date]; } return self; }
- (id)copyWithZone:(NSZone *)zone { SJMockTransaction *copy=[[[self class] allocWithZone:zone] init]; copy.productIdentifier=self.productIdentifier; copy.state=self.state; copy.matchingIdentifier=self.matchingIdentifier; copy.transactionIdentifier=self.transactionIdentifier; copy.originalTransactionIdentifier=self.originalTransactionIdentifier; copy.error=self.error; copy.transactionDate=self.transactionDate; return copy; }
- (NSDictionary<NSString *,id> *)dictionaryRepresentation { return @{@"productIdentifier":self.productIdentifier ?: @"",@"state":@(self.state),@"matchingIdentifier":self.matchingIdentifier ?: @"",@"transactionIdentifier":self.transactionIdentifier ?: @"",@"originalTransactionIdentifier":self.originalTransactionIdentifier ?: @"",@"error":self.error.localizedDescription ?: [NSNull null],@"transactionDate":@(self.transactionDate.timeIntervalSince1970)}; }
@end

@implementation SJStoreKitTestEngine

static NSError *SJEngineError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:SJCoreErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message ?: @"Unknown error"}];
}

+ (BOOL)canMakePaymentsWithSystemValue:(BOOL)systemValue {
    SJStateCoordinator *state=[SJStateCoordinator shared];
    @synchronized(state){ return state.configuration.canMakePaymentsOverrideEnabled ? YES : systemValue; }
}

+ (NSDecimalNumber *)effectivePriceForProduct:(SJMockProduct *)product {
    NSParameterAssert(product != nil);
    SJStateCoordinator *state=[SJStateCoordinator shared];
    @synchronized(state){ return state.configuration.priceOverrideEnabled ? [state.configuration.testPrice copy] : [product.price copy]; }
}

+ (void)addProductsDelegate:(id<SJProductsRequestTestDelegate>)delegate {
    if (!delegate) return;
    SJStateCoordinator *state=[SJStateCoordinator shared];
    @synchronized(state){ [state.productDelegates addObject:delegate]; }
}
+ (void)removeProductsDelegate:(id<SJProductsRequestTestDelegate>)delegate { if(!delegate)return; SJStateCoordinator *state=[SJStateCoordinator shared]; @synchronized(state){[state.productDelegates removeObjectIdenticalTo:delegate];} }

+ (SJProductsResponse * _Nullable)responseForProductIdentifiers:(NSSet<NSString *> *)productIdentifiers originalProducts:(NSArray<SJMockProduct *> *)originalProducts error:(NSError **)error {
    if(error)*error=nil;
    if(!productIdentifiers || !originalProducts){ if(error)*error=SJEngineError(SJCoreErrorInvalidArgument,@"Identifiers and original products must not be nil."); return nil; }
    SJProductsResponse *response=[SJProductsResponse new];
    if(originalProducts.count>0){ response.products=[[NSArray alloc] initWithArray:originalProducts copyItems:YES]; return response; }

    SJStateCoordinator *state=[SJStateCoordinator shared];
    @synchronized(state){
        if(!state.configuration.productCatalogFallbackEnabled){ if(error)*error=SJEngineError(SJCoreErrorFeatureDisabled,@"Product catalog fallback is disabled."); return nil; }
        // Upstream builds the fallback product array only once. Later empty
        // responses reuse that first cached list, even for a different request.
        if(state.products.count==0){
            NSArray<NSString *> *ids=[[productIdentifiers allObjects] sortedArrayUsingSelector:@selector(compare:)];
            for(NSString *identifier in ids){
                if(identifier.length==0) continue;
                SJMockProduct *product=[[SJMockProduct alloc] initWithProductIdentifier:identifier price:state.configuration.testPrice];
                product.priceLocale=[NSLocale localeWithLocaleIdentifier:@"da_DK"];
                product.localizedTitle=identifier;
                product.localizedDescription=identifier;
                state.products[identifier]=product;
                [state.productOrder addObject:identifier];
            }
        }
        NSMutableArray<SJMockProduct *> *products=[NSMutableArray arrayWithCapacity:state.productOrder.count];
        for(NSString *identifier in state.productOrder){
            SJMockProduct *product=state.products[identifier];
            if(product) [products addObject:[product copy]];
        }
        response.products=products;
    }
    return response;
}

+ (BOOL)deliverProductsForIdentifiers:(NSSet<NSString *> *)productIdentifiers originalProducts:(NSArray<SJMockProduct *> *)originalProducts error:(NSError **)error {
    SJProductsResponse *response=[self responseForProductIdentifiers:productIdentifiers originalProducts:originalProducts error:error];
    if(!response) return NO;
    NSArray *delegates;
    SJStateCoordinator *state=[SJStateCoordinator shared];
    @synchronized(state){ delegates=[state.productDelegates copy]; }
    for(id<SJProductsRequestTestDelegate> delegate in delegates){ [delegate sj_productsRequestDidReceiveResponse:[response copy]]; }
    [SJDiagnostics appendModule:@"ProductsDelegate" message:@"Delivered product response to registered test delegates." code:0];
    return YES;
}

+ (void)addTransactionObserver:(id<SJTransactionTestObserver>)observer { if(!observer)return; SJStateCoordinator *state=[SJStateCoordinator shared]; @synchronized(state){[state.transactionObservers addObject:observer];} }
+ (void)removeTransactionObserver:(id<SJTransactionTestObserver>)observer { if(!observer)return; SJStateCoordinator *state=[SJStateCoordinator shared]; @synchronized(state){[state.transactionObservers removeObjectIdenticalTo:observer];} }

+ (SJMockTransaction * _Nullable)makePurchasedTransactionForProductIdentifier:(NSString *)productIdentifier error:(NSError **)error {
    if(error)*error=nil;
    if(productIdentifier.length==0){ if(error)*error=SJEngineError(SJCoreErrorInvalidArgument,@"Product identifier must not be empty."); return nil; }
    SJStateCoordinator *state=[SJStateCoordinator shared];
    @synchronized(state){
        if(!state.configuration.transactionSimulationEnabled){ if(error)*error=SJEngineError(SJCoreErrorFeatureDisabled,@"Transaction simulation is disabled."); return nil; }
        if(!state.configuration.productCatalogFallbackEnabled || !state.products[productIdentifier]){ if(error)*error=SJEngineError(SJCoreErrorMissingDependency,@"Transaction simulation requires an available mock product."); return nil; }
    }
    SJMockTransaction *transaction=[SJMockTransaction new];
    transaction.productIdentifier=productIdentifier;
    transaction.state=SJMockTransactionStatePurchased;
    transaction.matchingIdentifier=NSUUID.UUID.UUIDString;
    transaction.transactionIdentifier=NSUUID.UUID.UUIDString;
    transaction.originalTransactionIdentifier=transaction.transactionIdentifier;
    transaction.error=nil;
    transaction.transactionDate=[NSDate date];
    return transaction;
}

+ (BOOL)publishTransactions:(NSArray<SJMockTransaction *> *)transactions error:(NSError **)error {
    if(error)*error=nil;
    if(!transactions){ if(error)*error=SJEngineError(SJCoreErrorInvalidArgument,@"Transactions array must not be nil."); return NO; }
    NSArray *observers;
    NSMutableArray<SJMockTransaction *> *current=[NSMutableArray array];
    SJStateCoordinator *state=[SJStateCoordinator shared];
    @synchronized(state){
        if(!state.configuration.observerBridgeEnabled){ if(error)*error=SJEngineError(SJCoreErrorFeatureDisabled,@"Observer bridge is disabled."); return NO; }
        for(id object in transactions){
            if(![object isKindOfClass:[SJMockTransaction class]]){ if(error)*error=SJEngineError(SJCoreErrorInvalidArgument,@"Transactions must contain SJMockTransaction instances."); return NO; }
            SJMockTransaction *transaction=object;
            // Preserve upstream observer semantics: encountering any transaction
            // object that has already been observed aborts the entire delivery.
            if([state.seenTransactions containsObject:transaction]) return YES;
            [state.seenTransactions addObject:transaction];
            [current addObject:transaction];
        }
        observers=[state.transactionObservers copy];
    }
    for(id<SJTransactionTestObserver> observer in observers){ [observer sj_paymentQueueUpdatedTransactions:[[NSArray alloc] initWithArray:current copyItems:YES]]; }
    [SJDiagnostics appendModule:@"TransactionObserver" message:@"Delivered transaction update to registered test observers." code:0];
    return YES;
}

+ (NSData * _Nullable)oldReceiptDataForProductIdentifier:(NSString *)productIdentifier error:(NSError **)error {
    if(error)*error=nil;
    SJStateCoordinator *state=[SJStateCoordinator shared];
    @synchronized(state){ if(!state.configuration.receiptSimulationEnabled){ if(error)*error=SJEngineError(SJCoreErrorFeatureDisabled,@"Receipt simulation is disabled."); return nil; } }
    return [SJReceiptGenerator JSONDataForOldReceipt:[SJReceiptGenerator oldReceiptForProductIdentifier:productIdentifier] error:error];
}

+ (NSData * _Nullable)verificationResponseDataForURL:(NSURL *)URL productIdentifier:(NSString *)productIdentifier error:(NSError **)error {
    if(error)*error=nil;
    if(!URL || !productIdentifier){ if(error)*error=SJEngineError(SJCoreErrorInvalidArgument,@"URL and product identifier are required."); return nil; }
    if(![URL.absoluteString hasSuffix:@"/verifyReceipt"]){ if(error)*error=SJEngineError(SJCoreErrorInvalidArgument,@"URL does not target /verifyReceipt."); return nil; }
    SJStateCoordinator *state=[SJStateCoordinator shared];
    @synchronized(state){ if(!state.configuration.receiptSimulationEnabled){ if(error)*error=SJEngineError(SJCoreErrorFeatureDisabled,@"Receipt simulation is disabled."); return nil; } }
    return [SJReceiptGenerator JSONDataForVerificationResponse:[SJReceiptGenerator verificationResponseForProductIdentifier:productIdentifier] error:error];
}

+ (NSData * _Nullable)verificationResponseDataForURL:(NSURL *)URL error:(NSError **)error {
    SJStateCoordinator *state=[SJStateCoordinator shared];
    NSString *productIdentifier;
    @synchronized(state){ productIdentifier=[state.productOrder.lastObject copy] ?: @""; }
    // Upstream falls back to an empty product identifier when no cached product
    // exists. Preserve that edge-case behaviour in the explicit test seam.
    return [self verificationResponseDataForURL:URL productIdentifier:productIdentifier error:error];
}

+ (void)resetSession {
    SJStateCoordinator *state=[SJStateCoordinator shared];
    @synchronized(state){ [state.products removeAllObjects]; [state.productOrder removeAllObjects]; [state.productDelegates removeAllObjects]; [state.transactionObservers removeAllObjects]; [state.seenTransactions removeAllObjects]; }
    [SJDiagnostics appendModule:@"StoreKitTestEngine" message:@"Test session state reset." code:0];
}

@end
