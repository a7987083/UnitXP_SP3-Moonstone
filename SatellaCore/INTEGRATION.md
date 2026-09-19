# Integration

Add every `.m` file in `Sources/Internal/` to the Objective-C target and add `Sources/Public/` to the header search path.

```objc
#import "SatellaCore.h"

NSError *error = nil;
[SatellaCore setFeature:SJFeatureProductCatalogMock enabled:YES error:&error];

SJMockProduct *product = [[SJMockProduct alloc]
    initWithProductIdentifier:@"com.example.test.coin100"
    price:[NSDecimalNumber decimalNumberWithString:@"0.99"]];

if (![SJStoreKitMock setProducts:@[product] error:&error]) {
    NSLog(@"SatellaCore: %@", error);
}
```

There is no `start`, constructor, `+load`, or internal UI lifecycle. Internal state is initialized lazily when the API is first called.
