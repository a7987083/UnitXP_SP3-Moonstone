# SatellaCore Objective-C API

Pure Objective-C, UI-free, constructor-free API component intended to be copied directly into an Objective-C project.

This implementation is a local StoreKit test/mock harness. It does not intercept live StoreKit, modify App Store transactions, or forge production receipts.

## Integration

Add the files under `Sources/` to the target and expose the headers under `Sources/Public/`.

```objc
#import "SatellaCore.h"
#import "SJStoreKitMock.h"

NSError *error = nil;
[SatellaCore setFeature:SJFeatureProductCatalogMock enabled:YES error:&error];

SJMockProduct *product = [[SJMockProduct alloc]
    initWithProductIdentifier:@"com.example.test.coin100"
    price:[NSDecimalNumber decimalNumberWithString:@"0.99"]];

[SJStoreKitMock setProducts:@[product] error:&error];
```

No `start`, constructor, `+load`, Swift runtime, SwiftUI, Combine, Jinx, or internal UI is required.
