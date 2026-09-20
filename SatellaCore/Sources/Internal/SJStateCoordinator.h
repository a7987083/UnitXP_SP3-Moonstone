#import <Foundation/Foundation.h>
@class SJConfiguration;
@class SJMockProduct;
@class SJMockTransaction;

NS_ASSUME_NONNULL_BEGIN

@interface SJStateCoordinator : NSObject
@property (nonatomic, strong) SJConfiguration *configuration;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SJMockProduct *> *products;
@property (nonatomic, strong) NSMutableArray<NSString *> *productOrder;
@property (nonatomic, strong) NSMutableArray *productDelegates;
@property (nonatomic, strong) NSMutableArray *transactionObservers;
@property (nonatomic, strong) NSHashTable<SJMockTransaction *> *seenTransactions;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *diagnostics;
+ (instancetype)shared;
- (void)resetSessionStateKeepingConfiguration:(BOOL)keepConfiguration;
@end

NS_ASSUME_NONNULL_END
