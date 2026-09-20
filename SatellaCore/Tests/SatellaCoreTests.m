#import <Foundation/Foundation.h>
#include <stdlib.h>
#import "SatellaCore.h"

static void SJAssert(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"TEST FAILURE: %@", message);
        exit(1);
    }
}

@interface SJProductsProbe : NSObject <SJProductsRequestTestDelegate>
@property (nonatomic, strong) SJProductsResponse *lastResponse;
@property (nonatomic) NSUInteger callbackCount;
@end

@implementation SJProductsProbe
- (void)sj_productsRequestDidReceiveResponse:(SJProductsResponse *)response {
    self.lastResponse = response;
    self.callbackCount += 1;
}
@end

@interface SJTransactionsProbe : NSObject <SJTransactionTestObserver>
@property (nonatomic, copy) NSArray<SJMockTransaction *> *lastTransactions;
@property (nonatomic) NSUInteger callbackCount;
@end

@implementation SJTransactionsProbe
- (void)sj_paymentQueueUpdatedTransactions:(NSArray<SJMockTransaction *> *)transactions {
    self.lastTransactions = transactions;
    self.callbackCount += 1;
}
@end

@interface SJNotificationProbe : NSObject
@property (nonatomic, copy) NSDictionary<NSString *, id> *lastConfiguration;
@property (nonatomic) NSUInteger callbackCount;
@end

@implementation SJNotificationProbe
- (void)configurationChanged:(NSNotification *)notification {
    self.lastConfiguration = [notification.userInfo[@"configuration"] copy];
    self.callbackCount += 1;
}
@end

static void TestPreferences(void) {
    NSString *suite = [NSString stringWithFormat:@"SatellaCoreTests.%@", NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    [defaults setBool:YES forKey:SJPreferenceIsObserverKey];
    [defaults setBool:YES forKey:SJPreferenceIsPriceZeroKey];
    [defaults setBool:YES forKey:SJPreferenceIsReceiptKey];

    NSError *error = nil;
    SJAssert([SatellaCore reloadPreferencesFromUserDefaults:defaults error:&error], @"reload preferences");
    SJConfiguration *config = [SatellaCore configuration];
    SJAssert(config.observerBridgeEnabled, @"observer preference mapping");
    SJAssert(config.priceOverrideEnabled, @"price preference mapping");
    SJAssert(config.receiptSimulationEnabled, @"receipt preference mapping");

    [SJPreferences resetUserDefaults:defaults];
    [defaults removePersistentDomainForName:suite];
}

static void TestProductsAndTransactions(void) {
    [SatellaCore resetConfiguration];
    NSError *error = nil;

    SJProductsProbe *delegateA = [SJProductsProbe new];
    SJProductsProbe *delegateB = [SJProductsProbe new];
    [SJStoreKitTestEngine addProductsDelegate:delegateA];
    [SJStoreKitTestEngine addProductsDelegate:delegateB];

    NSSet *ids = [NSSet setWithObjects:@"com.example.coin100", @"com.example.pro", nil];
    SJAssert([SJStoreKitTestEngine deliverProductsForIdentifiers:ids originalProducts:@[] error:&error], @"fallback product response");
    SJAssert(delegateA.lastResponse.products.count == 2, @"delegate receives two fallback products");
    SJAssert(delegateA.lastResponse == delegateB.lastResponse, @"all product delegates receive the same response object");
    SJMockProduct *firstFallbackObject = delegateA.lastResponse.products.firstObject;

    // Non-empty upstream responses are forwarded as a complete result. Preserve
    // invalid product identifiers instead of silently dropping them.
    SJMockProduct *realProduct = [[SJMockProduct alloc] initWithProductIdentifier:@"com.example.real"
                                                                            price:[NSDecimalNumber decimalNumberWithString:@"2.99"]];
    SJProductsResponse *nonEmpty = [SJStoreKitTestEngine responseForProductIdentifiers:[NSSet setWithObjects:@"com.example.real", @"com.example.invalid", nil]
                                                                          originalProducts:@[realProduct]
                                                                 invalidProductIdentifiers:@[@"com.example.invalid"]
                                                                                     error:&error];
    SJAssert(nonEmpty.products.firstObject == realProduct, @"non-empty response preserves product object identity");
    SJAssert([nonEmpty.invalidProductIdentifiers isEqual:@[@"com.example.invalid"]], @"non-empty response preserves invalid product identifiers");

    // SatellaDelegate caches the first fallback list once.
    SJAssert([SJStoreKitTestEngine deliverProductsForIdentifiers:[NSSet setWithObject:@"com.example.other"] originalProducts:@[] error:&error], @"second empty response");
    SJAssert(delegateA.lastResponse.products.count == 2, @"second empty response reuses first cached product list");
    SJAssert([delegateA.lastResponse.products containsObject:firstFallbackObject], @"second empty response reuses cached product object identity");

    SJMockProduct *product = [SJStoreKitMock productForIdentifier:@"com.example.coin100"];
    SJAssert(product != nil, @"fallback product cached");
    SJAssert([product.price isEqualToNumber:[NSDecimalNumber decimalNumberWithString:@"0.01"]], @"fallback product price matches upstream literal");
    SJAssert([[SJStoreKitTestEngine effectivePriceForProduct:product] isEqualToNumber:product.price], @"price unchanged while override disabled");

    // Default configuration matches ProductHook.swift's literal 0.01.
    SJAssert([SatellaCore setFeature:SJFeaturePriceOverride enabled:YES error:&error], @"enable price override");
    SJAssert([[[SJStoreKitTestEngine effectivePriceForProduct:product] stringValue] isEqual:@"0.01"], @"default price override matches upstream literal 0.01");
    SJConfiguration *strictPrice = [SatellaCore configuration];
    strictPrice.testPrice = [NSDecimalNumber decimalNumberWithString:@"99.99"];
    strictPrice.canMakePaymentsOverrideEnabled = NO;
    SJAssert([SatellaCore applyConfiguration:strictPrice error:&error], @"apply OC-only extension values in parity mode");
    SJAssert([[[SJStoreKitTestEngine effectivePriceForProduct:product] stringValue] isEqual:@"0.01"], @"parity mode ignores OC-only testPrice");
    SJAssert([SJStoreKitTestEngine canMakePaymentsWithSystemValue:NO], @"parity mode ignores OC-only canMakePayments disable switch");

    // TransactionHook.swift is independent from DelegateHook/product fallback.
    SJAssert([SatellaCore setFeature:SJFeatureProductCatalogFallback enabled:NO error:&error], @"toggle OC-only product fallback switch");
    SJProductsResponse *strictFallback = [SJStoreKitTestEngine responseForProductIdentifiers:[NSSet setWithObject:@"com.example.strict"] originalProducts:@[] error:&error];
    SJAssert(strictFallback != nil, @"upstream parity keeps DelegateHook fallback active despite OC-only switch");
    SJMockTransaction *transaction = [SJStoreKitTestEngine makePurchasedTransactionForProductIdentifier:@"com.example.notcached" error:&error];
    SJAssert(transaction != nil, @"transaction simulation does not require a cached mock product");

    // TransactionHook getters are dynamic on every read.
    transaction.state = SJMockTransactionStateFailed;
    SJAssert(transaction.state == SJMockTransactionStatePurchased, @"transaction state forced purchased on read");
    NSString *matchingA = transaction.matchingIdentifier;
    NSString *matchingB = transaction.matchingIdentifier;
    SJAssert(![matchingA isEqualToString:matchingB], @"matchingIdentifier is regenerated on every read");
    NSString *identifierA = transaction.transactionIdentifier;
    NSString *identifierB = transaction.transactionIdentifier;
    SJAssert(![identifierA isEqualToString:identifierB], @"transactionIdentifier is regenerated on every read");
    transaction.error = [NSError errorWithDomain:@"test" code:1 userInfo:nil];
    SJAssert(transaction.error == nil, @"transaction error getter is always nil");
    NSDate *dateA = transaction.transactionDate;
    [NSThread sleepForTimeInterval:0.002];
    NSDate *dateB = transaction.transactionDate;
    SJAssert([dateB compare:dateA] != NSOrderedAscending, @"transactionDate is evaluated at read time");

    SJAssert([SatellaCore setFeature:SJFeatureObserverBridge enabled:YES error:&error], @"enable observer bridge");
    SJTransactionsProbe *observer = [SJTransactionsProbe new];
    [SJStoreKitTestEngine addTransactionObserver:observer];
    SJAssert([SJStoreKitTestEngine publishTransactions:@[transaction] error:&error], @"publish first transaction");
    SJAssert(observer.callbackCount == 1, @"observer callback once");
    SJAssert(observer.lastTransactions.firstObject == transaction, @"observer receives original transaction object identity");
    SJAssert([SJStoreKitTestEngine publishTransactions:@[transaction] error:&error], @"duplicate publish accepted but suppressed");
    SJAssert(observer.callbackCount == 1, @"duplicate transaction suppressed by identity");
}

static void TestReceiptAndVerifyResponse(void) {
    [SatellaCore resetConfiguration];
    NSError *error = nil;
    NSURL *disabledURL = [NSURL URLWithString:@"https://example.test/verifyReceipt"];
    NSData *disabledReceipt = [SJStoreKitTestEngine verificationResponseDataForURL:disabledURL productIdentifier:@"com.example.coin100" error:&error];
    SJAssert(disabledReceipt == nil && error == nil, @"disabled receipt hook is pass-through, not FeatureDisabled error");
    SJAssert([SatellaCore setFeature:SJFeatureReceiptSimulation enabled:YES error:&error], @"enable receipt simulation");

    SJConfiguration *strictEnvironment = [SatellaCore configuration];
    strictEnvironment.testEnvironment = @"Sandbox";
    SJAssert([SatellaCore applyConfiguration:strictEnvironment error:&error], @"apply OC-only environment override in parity mode");

    NSData *old = [SJStoreKitTestEngine oldReceiptDataForProductIdentifier:@"com.example.coin100" error:&error];
    SJAssert(old.length > 0, @"old receipt JSON data");
    NSDictionary *oldJSON = [NSJSONSerialization JSONObjectWithData:old options:0 error:&error];
    SJAssert([oldJSON[@"purchase-info"] isKindOfClass:NSDictionary.class], @"old receipt purchase-info shape");
    NSData *signature = [[NSData alloc] initWithBase64EncodedString:oldJSON[@"signature"] options:0];
    SJAssert(signature.length == 1667, @"old receipt signature matches upstream byte payload length");

    NSData *nilProductOld = [SJStoreKitTestEngine oldReceiptDataForProductIdentifier:nil error:&error];
    NSDictionary *nilProductOldJSON = [NSJSONSerialization JSONObjectWithData:nilProductOld options:0 error:&error];
    SJAssert([nilProductOldJSON[@"purchase-info"][@"product-id"] isEqual:@"emt.paisseon.satella.product"], @"old receipt nil-product fallback matches upstream");

    NSURL *URL = [NSURL URLWithString:@"https://example.test/verifyReceipt"];
    SJAssert([SJStoreKitTestEngine shouldReplaceVerificationResponseForURL:URL], @"verifyReceipt URL is intercepted");
    NSData *response = [SJStoreKitTestEngine verificationResponseDataForURL:URL productIdentifier:@"com.example.coin100" error:&error];
    SJAssert(response.length > 0, @"verification response data");
    NSDictionary *JSON = [NSJSONSerialization JSONObjectWithData:response options:0 error:&error];
    SJAssert([JSON[@"status"] integerValue] == 0, @"verification response status parity");
    SJAssert([JSON[@"environment"] isEqual:@"Production"], @"response environment matches upstream");
    SJAssert([JSON[@"receipt"][@"receipt_type"] isEqual:@"Production"], @"receipt_type matches upstream");
    SJAssert([JSON[@"latest_receipt_info"] count] == 1, @"latest receipt info present");
    SJAssert([JSON[@"pending_renewal_info"] count] == 1, @"renewal info present");

    NSDictionary *receiptInfo = [JSON[@"latest_receipt_info"] firstObject];
    SJAssert([receiptInfo[@"original_purchase_date_ms"] containsString:@"Europe/Copenhagen"], @"preserve upstream original_purchase_date_ms source behaviour");

    NSData *latestReceiptData = [[NSData alloc] initWithBase64EncodedString:JSON[@"latest_receipt"] options:0];
    NSDictionary *latestReceiptJSON = [NSJSONSerialization JSONObjectWithData:latestReceiptData options:0 error:&error];
    SJAssert([latestReceiptJSON[@"receipt_type"] isEqual:@"Production"], @"latest_receipt base64 contains upstream receipt payload");

    NSURL *otherURL = [NSURL URLWithString:@"https://example.test/api/purchase"];
    error = nil;
    SJAssert(![SJStoreKitTestEngine shouldReplaceVerificationResponseForURL:otherURL], @"non-verifyReceipt URL is pass-through");
    NSData *passThrough = [SJStoreKitTestEngine verificationResponseDataForURL:otherURL productIdentifier:@"com.example.coin100" error:&error];
    SJAssert(passThrough == nil && error == nil, @"non-verifyReceipt URL returns pass-through decision without an error");

    // URLHook edge case: when no cached product exists it uses an empty ID.
    [SJStoreKitTestEngine resetSession];
    NSData *emptyProductResponse = [SJStoreKitTestEngine verificationResponseDataForURL:URL error:&error];
    SJAssert(emptyProductResponse.length > 0, @"verifyReceipt response works with no cached product");
    NSDictionary *emptyJSON = [NSJSONSerialization JSONObjectWithData:emptyProductResponse options:0 error:&error];
    SJAssert([[emptyJSON[@"pending_renewal_info"] firstObject][@"product_id"] isEqual:@""], @"no-cache verification uses empty product identifier");

    SJAssert([SatellaCore setFeature:SJFeatureStealthSimulation enabled:YES error:&error], @"enable stealth simulation");
    NSString *visible = [SJRuntimeTestAdapter simulatedVisibleImageNameForOriginalImageName:@"/tmp/SatellaJailed.dylib"];
    SJAssert([visible isEqual:@"/usr/lib/libcrane.dylib"], @"dyld concealment decision parity without live hook");
}

static void TestExtendedTestingIsolation(void) {
    [SatellaCore resetConfiguration];
    NSError *error = nil;
    SJConfiguration *config = [SatellaCore configuration];
    config.behaviorMode = SJBehaviorModeExtendedTesting;
    config.priceOverrideEnabled = YES;
    config.testPrice = [NSDecimalNumber decimalNumberWithString:@"9.99"];
    config.receiptSimulationEnabled = YES;
    config.testEnvironment = @"Sandbox";
    config.canMakePaymentsOverrideEnabled = NO;
    SJAssert([SatellaCore applyConfiguration:config error:&error], @"apply ExtendedTesting configuration");

    SJMockProduct *product = [[SJMockProduct alloc] initWithProductIdentifier:@"com.example.extended"
                                                                        price:[NSDecimalNumber decimalNumberWithString:@"4.99"]];
    SJAssert([[[SJStoreKitTestEngine effectivePriceForProduct:product] stringValue] isEqual:@"9.99"], @"ExtendedTesting keeps configurable testPrice");
    SJAssert(![SJStoreKitTestEngine canMakePaymentsWithSystemValue:NO], @"ExtendedTesting keeps configurable canMakePayments behavior");
    SJReceiptResponse *response = [SJReceiptGenerator verificationResponseForProductIdentifier:@"com.example.extended"];
    SJAssert([response.environment isEqual:@"Sandbox"], @"ExtendedTesting keeps configurable environment");
}

static void TestValidationAndAtomicReset(void) {
    [SatellaCore resetConfiguration];
    NSError *error = nil;

    // The old OC port invented a product-catalog dependency that does not exist
    // in TransactionHook.swift.  This combination must now be valid.
    SJConfiguration *independent = [SatellaCore configuration];
    independent.productCatalogFallbackEnabled = NO;
    independent.transactionSimulationEnabled = YES;
    SJAssert([SatellaCore applyConfiguration:independent error:&error], @"transaction simulation and product fallback are independent");

    SJConfiguration *bad = [SatellaCore configuration];
    bad.testPrice = [NSDecimalNumber decimalNumberWithString:@"-1"];
    SJAssert(![SatellaCore applyConfiguration:bad error:&error], @"invalid negative test price rejected");
    SJAssert(error.code == SJCoreErrorInvalidConfiguration, @"invalid configuration error code");

    error = nil;
    SJAssert(![SJStoreKitMock setProducts:nil error:&error], @"nil products rejected");
    SJAssert(error.code == SJCoreErrorInvalidArgument, @"nil products error code");

    SJNotificationProbe *probe = [SJNotificationProbe new];
    [[NSNotificationCenter defaultCenter] addObserver:probe
                                             selector:@selector(configurationChanged:)
                                                 name:SJCoreConfigurationDidChangeNotification
                                               object:nil];
    [SatellaCore resetConfiguration];
    [[NSNotificationCenter defaultCenter] removeObserver:probe];

    NSDictionary *status = [SatellaCore status];
    SJAssert(probe.callbackCount == 1, @"reset emits exactly one configuration notification");
    SJAssert([probe.lastConfiguration[@"productCatalogFallback"] boolValue], @"reset notification contains final configuration snapshot");
    SJAssert([status[@"mockProductCount"] unsignedIntegerValue] == 0, @"reset clears products atomically");
    SJAssert([status[@"productDelegateCount"] unsignedIntegerValue] == 0, @"reset clears delegates");
    SJAssert([status[@"transactionObserverCount"] unsignedIntegerValue] == 0, @"reset clears observers");
}

static void TestConcurrentAccess(void) {
    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    for (NSUInteger i = 0; i < 200; i++) {
        dispatch_group_async(group, queue, ^{ (void)[SatellaCore status]; });
        dispatch_group_async(group, queue, ^{ (void)[SatellaCore configuration]; });
        dispatch_group_async(group, queue, ^{ (void)[SJStoreKitMock products]; });
    }
    long result = dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)));
    SJAssert(result == 0, @"concurrent readers complete without deadlock");
}

int main(void) {
    @autoreleasepool {
        TestProductsAndTransactions();
        TestReceiptAndVerifyResponse();
        TestPreferences();
        TestExtendedTestingIsolation();
        TestValidationAndAtomicReset();
        TestConcurrentAccess();

        NSError *error = nil;
        NSData *statusJSON = [SatellaCore statusJSONWithError:&error];
        SJAssert(statusJSON.length > 0, @"status JSON serializes");
        SJAssert([[SatellaCore version] isEqual:@"1.3.0-result-parity"], @"parity build version");
        NSLog(@"SatellaCore result-parity tests passed");
    }
    return 0;
}
