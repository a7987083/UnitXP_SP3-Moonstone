#import <Foundation/Foundation.h>
#import "SJStoreKitMock.h"

NS_ASSUME_NONNULL_BEGIN

@class SJProductsResponse;
@class SJMockTransaction;

@protocol SJProductsRequestTestDelegate <NSObject>
- (void)sj_productsRequestDidReceiveResponse:(SJProductsResponse *)response;
@end

@protocol SJTransactionTestObserver <NSObject>
- (void)sj_paymentQueueUpdatedTransactions:(NSArray<SJMockTransaction *> *)transactions;
@end

@interface SJProductsResponse : NSObject <NSCopying>
@property (nonatomic, copy) NSArray<SJMockProduct *> *products;
@property (nonatomic, copy) NSArray<NSString *> *invalidProductIdentifiers;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
@end

typedef NS_ENUM(NSInteger, SJMockTransactionState) {
    SJMockTransactionStatePurchasing = 0,
    SJMockTransactionStatePurchased = 1,
    SJMockTransactionStateFailed = 2,
    SJMockTransactionStateRestored = 3,
    SJMockTransactionStateDeferred = 4,
};

@interface SJMockTransaction : NSObject <NSCopying>
@property (nonatomic, copy) NSString *productIdentifier;
@property (nonatomic) SJMockTransactionState state;
@property (nonatomic, copy) NSString *matchingIdentifier;
@property (nonatomic, copy) NSString *transactionIdentifier;
@property (nonatomic, copy) NSString *originalTransactionIdentifier;
@property (nonatomic, strong, nullable) NSError *error;
@property (nonatomic, strong) NSDate *transactionDate;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
@end

@interface SJStoreKitTestEngine : NSObject

// Safe equivalents of the upstream hook behaviours. Call these from your own
// app/test seam; SatellaCore never swizzles or intercepts StoreKit globally.
+ (BOOL)canMakePaymentsWithSystemValue:(BOOL)systemValue;
+ (NSDecimalNumber *)effectivePriceForProduct:(SJMockProduct *)product;

+ (void)addProductsDelegate:(id<SJProductsRequestTestDelegate>)delegate;
+ (void)removeProductsDelegate:(id<SJProductsRequestTestDelegate>)delegate;
+ (SJProductsResponse * _Nullable)responseForProductIdentifiers:(NSSet<NSString *> *)productIdentifiers
                                                originalProducts:(NSArray<SJMockProduct *> *)originalProducts
                                                           error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)deliverProductsForIdentifiers:(NSSet<NSString *> *)productIdentifiers
                      originalProducts:(NSArray<SJMockProduct *> *)originalProducts
                                 error:(NSError * _Nullable * _Nullable)error;

+ (void)addTransactionObserver:(id<SJTransactionTestObserver>)observer;
+ (void)removeTransactionObserver:(id<SJTransactionTestObserver>)observer;
+ (SJMockTransaction * _Nullable)makePurchasedTransactionForProductIdentifier:(NSString *)productIdentifier
                                                                        error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)publishTransactions:(NSArray<SJMockTransaction *> *)transactions error:(NSError * _Nullable * _Nullable)error;

+ (NSData * _Nullable)oldReceiptDataForProductIdentifier:(NSString *)productIdentifier error:(NSError * _Nullable * _Nullable)error;
+ (NSData * _Nullable)verificationResponseDataForURL:(NSURL *)URL
                                   productIdentifier:(NSString *)productIdentifier
                                               error:(NSError * _Nullable * _Nullable)error;
+ (NSData * _Nullable)verificationResponseDataForURL:(NSURL *)URL error:(NSError * _Nullable * _Nullable)error;

+ (void)resetSession;

@end

NS_ASSUME_NONNULL_END
