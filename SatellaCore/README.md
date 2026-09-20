# SatellaCore Objective-C security-test port

Pure Objective-C, API-driven source component for app-owned StoreKit security testing. It contains no internal UI, constructor, `+load`, Swift runtime, SwiftUI, Combine, or Jinx dependency.

## What is migrated

The non-UI Swift behaviour is represented through explicit test seams: original `tella_*` preferences, product-delegate fallback/caching, observer forwarding and pointer-identity duplicate suppression, `canMakePayments` override semantics, product-price override semantics, purchased transaction properties, old/new receipt models, renewal/verification response models, `/verifyReceipt` decision logic, and dyld-concealment decision simulation.

It intentionally does **not** globally swizzle StoreKit/URLSession or install dyld concealment. Your own app/test target calls the test APIs at the seam you want to exercise.

See `MIGRATION_MATRIX.md` for the file-by-file upstream mapping.

## Minimal use

```objc
#import "SatellaCore.h"

NSError *error = nil;
[SatellaCore resetConfiguration];

SJProductsResponse *response =
    [SJStoreKitTestEngine responseForProductIdentifiers:[NSSet setWithObject:@"com.example.pro"]
                                        originalProducts:@[]
                                                   error:&error];

SJMockTransaction *transaction =
    [SJStoreKitTestEngine makePurchasedTransactionForProductIdentifier:@"com.example.pro"
                                                                  error:&error];
```

All runtime state is lazy; importing the source has no startup side effect.
