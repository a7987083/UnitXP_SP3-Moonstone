#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SJConfiguration : NSObject <NSCopying>

@property (nonatomic) BOOL productCatalogMockEnabled;
@property (nonatomic) BOOL transactionMockEnabled;
@property (nonatomic) BOOL receiptFixtureEnabled;

+ (instancetype)defaultConfiguration;
- (NSDictionary<NSString *, NSNumber *> *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END
