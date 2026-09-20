#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SJMockProduct : NSObject <NSCopying>
@property (nonatomic, copy) NSString *productIdentifier;
@property (nonatomic, copy) NSDecimalNumber *price;
@property (nonatomic, copy) NSLocale *priceLocale;
@property (nonatomic, copy) NSString *localizedTitle;
@property (nonatomic, copy) NSString *localizedDescription;
- (instancetype)initWithProductIdentifier:(NSString *)productIdentifier
                                    price:(NSDecimalNumber *)price NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
@end

@interface SJStoreKitMock : NSObject
+ (BOOL)setProducts:(NSArray<SJMockProduct *> * _Nullable)products error:(NSError * _Nullable * _Nullable)error;
+ (NSArray<SJMockProduct *> *)products;
+ (SJMockProduct * _Nullable)productForIdentifier:(NSString *)productIdentifier;
+ (NSDictionary<NSString *, id> * _Nullable)makeTransactionFixtureForProductIdentifier:(NSString *)productIdentifier error:(NSError * _Nullable * _Nullable)error;
+ (NSDictionary<NSString *, id> * _Nullable)makeReceiptFixtureForProductIdentifier:(NSString *)productIdentifier error:(NSError * _Nullable * _Nullable)error;
+ (void)reset;
@end

NS_ASSUME_NONNULL_END
