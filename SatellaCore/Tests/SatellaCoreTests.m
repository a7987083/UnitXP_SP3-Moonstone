#import <Foundation/Foundation.h>
#include <stdlib.h>
#import "SatellaCore.h"
#import "SJConfiguration.h"
#import "SJStoreKitMock.h"

static void SJAssert(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"TEST FAILURE: %@", message);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        [SatellaCore resetConfiguration];
        SJAssert(![SatellaCore isFeatureEnabled:SJFeatureProductCatalogMock], @"catalog mock should default off");
        SJAssert([SatellaCore isFeatureAvailable:SJFeatureReceiptFixture], @"receipt fixture should be available");

        NSError *error = nil;
        SJAssert([SatellaCore setFeature:SJFeatureProductCatalogMock enabled:YES error:&error], @"enable catalog mock");
        SJAssert(error == nil, @"no error expected enabling catalog mock");
        SJAssert([SatellaCore isFeatureEnabled:SJFeatureProductCatalogMock], @"catalog mock should be on");

        SJMockProduct *product = [[SJMockProduct alloc] initWithProductIdentifier:@"com.example.test.coin100"
                                                                            price:[NSDecimalNumber decimalNumberWithString:@"0.99"]];
        product.localizedTitle = @"Test Coins";
        SJAssert([SJStoreKitMock setProducts:@[product] error:&error], @"set mock products");
        SJAssert([SJStoreKitMock products].count == 1, @"one mock product expected");

        SJAssert([SatellaCore setFeature:SJFeatureTransactionMock enabled:YES error:&error], @"enable transaction fixture");
        NSDictionary *transaction = [SJStoreKitMock makeTransactionFixtureForProductIdentifier:product.productIdentifier error:&error];
        SJAssert(transaction != nil, @"transaction fixture should be generated");
        SJAssert([transaction[@"state"] isEqual:@"purchased"], @"transaction fixture should use purchased state");

        NSDictionary *disabledReceipt = [SJStoreKitMock makeReceiptFixtureForProductIdentifier:product.productIdentifier error:&error];
        SJAssert(disabledReceipt == nil, @"receipt fixture must reject while disabled");
        SJAssert(error.code == SJCoreErrorFeatureUnavailable, @"disabled receipt fixture must return feature unavailable");

        error = nil;
        SJAssert([SatellaCore setFeature:SJFeatureReceiptFixture enabled:YES error:&error], @"enable receipt fixture");
        NSDictionary *receipt = [SJStoreKitMock makeReceiptFixtureForProductIdentifier:product.productIdentifier error:&error];
        SJAssert(receipt != nil, @"receipt fixture should be generated");
        SJAssert([receipt[@"environment"] isEqual:@"LocalTest"], @"receipt fixture must be marked LocalTest");

        NSData *statusJSON = [SatellaCore statusJSONWithError:&error];
        SJAssert(statusJSON.length > 0, @"status JSON should serialize");
        SJAssert([SatellaCore recentDiagnostics].count > 0, @"diagnostics should contain entries");

        NSLog(@"SatellaCore tests passed");
    }
    return 0;
}
