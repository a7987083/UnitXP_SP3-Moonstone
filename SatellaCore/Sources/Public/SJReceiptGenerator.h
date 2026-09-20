#import <Foundation/Foundation.h>
#import "SJReceiptModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface SJReceiptGenerator : NSObject
+ (SJOldReceipt *)oldReceiptForProductIdentifier:(NSString *)productIdentifier;
+ (SJReceipt *)receiptForProductIdentifier:(NSString *)productIdentifier;
+ (SJReceiptResponse *)verificationResponseForProductIdentifier:(NSString *)productIdentifier;
+ (NSData * _Nullable)JSONDataForOldReceipt:(SJOldReceipt *)receipt error:(NSError * _Nullable * _Nullable)error;
+ (NSData * _Nullable)JSONDataForVerificationResponse:(SJReceiptResponse *)response error:(NSError * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
