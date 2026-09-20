#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SJOldReceiptInfo : NSObject
@property (nonatomic, copy) NSDictionary<NSString *, id> *fields;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
@end

@interface SJOldReceipt : NSObject
@property (nonatomic, copy) NSString *signature;
@property (nonatomic, strong) SJOldReceiptInfo *purchaseInfo;
@property (nonatomic, copy) NSString *pod;
@property (nonatomic, copy) NSString *signingStatus;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
@end

@interface SJReceiptInfo : NSObject
@property (nonatomic, copy) NSDictionary<NSString *, id> *fields;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
@end

@interface SJReceipt : NSObject
@property (nonatomic, copy) NSDictionary<NSString *, id> *fields;
@property (nonatomic, copy) NSArray<SJReceiptInfo *> *inApp;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
@end

@interface SJRenewalInfo : NSObject
@property (nonatomic, copy) NSString *autoRenewProductIdentifier;
@property (nonatomic, copy) NSString *originalTransactionIdentifier;
@property (nonatomic, copy) NSString *productIdentifier;
@property (nonatomic, copy) NSString *autoRenewStatus;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
@end

@interface SJReceiptResponse : NSObject
@property (nonatomic) NSInteger status;
@property (nonatomic, copy) NSString *environment;
@property (nonatomic, strong) SJReceipt *receipt;
@property (nonatomic, copy) NSArray<SJReceiptInfo *> *latestReceiptInfo;
@property (nonatomic, copy) NSString *latestReceipt;
@property (nonatomic, copy) NSArray<SJRenewalInfo *> *pendingRenewalInfo;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
@end

NS_ASSUME_NONNULL_END
