#import <Foundation/Foundation.h>
#include <stdlib.h>
#import "SatellaCore.h"

static void SJAssert(BOOL condition, NSString *message) { if(!condition){ NSLog(@"TEST FAILURE: %@",message); exit(1); } }

@interface SJProductsProbe : NSObject <SJProductsRequestTestDelegate>
@property (nonatomic, strong) SJProductsResponse *lastResponse;
@end
@implementation SJProductsProbe
- (void)sj_productsRequestDidReceiveResponse:(SJProductsResponse *)response { self.lastResponse=response; }
@end

@interface SJTransactionsProbe : NSObject <SJTransactionTestObserver>
@property (nonatomic, copy) NSArray<SJMockTransaction *> *lastTransactions;
@property (nonatomic) NSUInteger callbackCount;
@end
@implementation SJTransactionsProbe
- (void)sj_paymentQueueUpdatedTransactions:(NSArray<SJMockTransaction *> *)transactions { self.lastTransactions=transactions; self.callbackCount += 1; }
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
    NSString *suite=[NSString stringWithFormat:@"SatellaCoreTests.%@",NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults=[[NSUserDefaults alloc] initWithSuiteName:suite];
    [defaults setBool:YES forKey:SJPreferenceIsObserverKey];
    [defaults setBool:YES forKey:SJPreferenceIsPriceZeroKey];
    [defaults setBool:YES forKey:SJPreferenceIsReceiptKey];
    NSError *error=nil;
    SJAssert([SatellaCore reloadPreferencesFromUserDefaults:defaults error:&error],@"reload preferences");
    SJConfiguration *config=[SatellaCore configuration];
    SJAssert(config.observerBridgeEnabled,@"observer preference mapping");
    SJAssert(config.priceOverrideEnabled,@"price preference mapping");
    SJAssert(config.receiptSimulationEnabled,@"receipt preference mapping");
    [SJPreferences resetUserDefaults:defaults];
    [defaults removePersistentDomainForName:suite];
}

static void TestProductsAndTransactions(void) {
    [SatellaCore resetConfiguration];
    NSError *error=nil;
    SJProductsProbe *delegate=[SJProductsProbe new];
    [SJStoreKitTestEngine addProductsDelegate:delegate];
    NSSet *ids=[NSSet setWithObjects:@"com.example.coin100",@"com.example.pro",nil];
    SJAssert([SJStoreKitTestEngine deliverProductsForIdentifiers:ids originalProducts:@[] error:&error],@"fallback product response");
    SJAssert(delegate.lastResponse.products.count==2,@"delegate receives two fallback products");
    // Upstream caches the first fallback product list once.
    SJAssert([SJStoreKitTestEngine deliverProductsForIdentifiers:[NSSet setWithObject:@"com.example.other"] originalProducts:@[] error:&error],@"second empty response");
    SJAssert(delegate.lastResponse.products.count==2,@"second empty response reuses first cached product list");
    SJMockProduct *product=[SJStoreKitMock productForIdentifier:@"com.example.coin100"];
    SJAssert(product!=nil,@"fallback product cached");
    SJAssert([[SJStoreKitTestEngine effectivePriceForProduct:product] isEqualToNumber:product.price],@"price unchanged while override disabled");
    SJAssert([SatellaCore setFeature:SJFeaturePriceOverride enabled:YES error:&error],@"enable price override");
    SJAssert([[[SJStoreKitTestEngine effectivePriceForProduct:product] stringValue] isEqual:@"0.01"],@"price override parity");
    SJAssert([SJStoreKitTestEngine canMakePaymentsWithSystemValue:NO],@"canMakePayments parity");

    SJMockTransaction *transaction=[SJStoreKitTestEngine makePurchasedTransactionForProductIdentifier:product.productIdentifier error:&error];
    SJAssert(transaction!=nil,@"purchased transaction fixture");
    SJAssert(transaction.state==SJMockTransactionStatePurchased,@"transaction forced purchased");
    SJAssert(transaction.error==nil,@"transaction error nil");

    SJAssert([SatellaCore setFeature:SJFeatureObserverBridge enabled:YES error:&error],@"enable observer bridge");
    SJTransactionsProbe *observer=[SJTransactionsProbe new];
    [SJStoreKitTestEngine addTransactionObserver:observer];
    SJAssert([SJStoreKitTestEngine publishTransactions:@[transaction] error:&error],@"publish first transaction");
    SJAssert(observer.callbackCount==1,@"observer callback once");
    SJAssert([SJStoreKitTestEngine publishTransactions:@[transaction] error:&error],@"duplicate publish accepted but suppressed");
    SJAssert(observer.callbackCount==1,@"duplicate transaction suppressed by identity");
}

static void TestReceiptAndVerifyResponse(void) {
    NSError *error=nil;
    SJAssert([SatellaCore setFeature:SJFeatureReceiptSimulation enabled:YES error:&error],@"enable receipt simulation");
    NSData *old=[SJStoreKitTestEngine oldReceiptDataForProductIdentifier:@"com.example.coin100" error:&error];
    SJAssert(old.length>0,@"old receipt JSON data");
    NSDictionary *oldJSON=[NSJSONSerialization JSONObjectWithData:old options:0 error:&error];
    SJAssert([oldJSON[@"purchase-info"] isKindOfClass:NSDictionary.class],@"old receipt purchase-info shape");

    NSURL *URL=[NSURL URLWithString:@"https://example.test/verifyReceipt"];
    NSData *response=[SJStoreKitTestEngine verificationResponseDataForURL:URL productIdentifier:@"com.example.coin100" error:&error];
    SJAssert(response.length>0,@"verification response data");
    NSDictionary *JSON=[NSJSONSerialization JSONObjectWithData:response options:0 error:&error];
    SJAssert([JSON[@"status"] integerValue]==0,@"verification response status parity");
    SJAssert([JSON[@"environment"] isEqual:@"LocalTest"],@"response marked LocalTest");
    SJAssert([JSON[@"latest_receipt_info"] count]==1,@"latest receipt info present");
    SJAssert([JSON[@"pending_renewal_info"] count]==1,@"renewal info present");

    // Match the upstream URLHook edge case: with no cached product it still
    // generates a verification response using an empty product identifier.
    [SJStoreKitTestEngine resetSession];
    NSData *emptyProductResponse=[SJStoreKitTestEngine verificationResponseDataForURL:URL error:&error];
    SJAssert(emptyProductResponse.length>0,@"verifyReceipt response works with no cached product");

    SJAssert([SatellaCore setFeature:SJFeatureStealthSimulation enabled:YES error:&error],@"enable stealth simulation");
    NSString *visible=[SJRuntimeTestAdapter simulatedVisibleImageNameForOriginalImageName:@"/tmp/SatellaJailed.dylib"];
    SJAssert([visible isEqual:@"/usr/lib/libcrane.dylib"],@"dyld concealment decision parity without live hook");
}

static void TestValidationAndAtomicReset(void) {
    NSError *error=nil;
    SJConfiguration *bad=[SatellaCore configuration];
    bad.productCatalogFallbackEnabled=NO;
    bad.transactionSimulationEnabled=YES;
    SJAssert(![SatellaCore applyConfiguration:bad error:&error],@"dependency validation rejects invalid configuration");
    SJAssert(error.code==SJCoreErrorMissingDependency,@"dependency error code");

    error=nil;
    SJAssert(![SJStoreKitMock setProducts:nil error:&error],@"nil products rejected");
    SJAssert(error.code==SJCoreErrorInvalidArgument,@"nil products error code");

    SJNotificationProbe *probe=[SJNotificationProbe new];
    [[NSNotificationCenter defaultCenter] addObserver:probe selector:@selector(configurationChanged:) name:SJCoreConfigurationDidChangeNotification object:nil];
    [SatellaCore resetConfiguration];
    [[NSNotificationCenter defaultCenter] removeObserver:probe];
    NSDictionary *status=[SatellaCore status];
    SJAssert(probe.callbackCount==1,@"reset emits exactly one configuration notification");
    SJAssert([probe.lastConfiguration[@"productCatalogFallback"] boolValue],@"reset notification contains final configuration snapshot");
    SJAssert([status[@"mockProductCount"] unsignedIntegerValue]==0,@"reset clears products atomically");
    SJAssert([status[@"productDelegateCount"] unsignedIntegerValue]==0,@"reset clears delegates");
    SJAssert([status[@"transactionObserverCount"] unsignedIntegerValue]==0,@"reset clears observers");
}

static void TestConcurrentAccess(void) {
    dispatch_group_t group=dispatch_group_create();
    dispatch_queue_t queue=dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0);
    for(NSUInteger i=0;i<200;i++){
        dispatch_group_async(group,queue,^{ (void)[SatellaCore status]; });
        dispatch_group_async(group,queue,^{ (void)[SatellaCore configuration]; });
        dispatch_group_async(group,queue,^{ (void)[SJStoreKitMock products]; });
    }
    long result=dispatch_group_wait(group,dispatch_time(DISPATCH_TIME_NOW,(int64_t)(10*NSEC_PER_SEC)));
    SJAssert(result==0,@"concurrent readers complete without deadlock");
}

int main(void) {
    @autoreleasepool {
        TestProductsAndTransactions();
        TestReceiptAndVerifyResponse();
        TestPreferences();
        TestValidationAndAtomicReset();
        TestConcurrentAccess();
        NSError *error=nil;
        NSData *statusJSON=[SatellaCore statusJSONWithError:&error];
        SJAssert(statusJSON.length>0,@"status JSON serializes");
        NSLog(@"SatellaCore full security-test port tests passed");
    }
    return 0;
}
