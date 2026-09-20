#import "../Public/SJReceiptModels.h"

@implementation SJOldReceiptInfo
- (instancetype)init { self = [super init]; if (self) { _fields = @{}; } return self; }
- (NSDictionary<NSString *, id> *)dictionaryRepresentation { return [self.fields copy] ?: @{}; }
@end

@implementation SJOldReceipt
- (instancetype)init { self = [super init]; if (self) { _signature = @""; _purchaseInfo = [SJOldReceiptInfo new]; _pod = @"44"; _signingStatus = @"0"; } return self; }
- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    return @{
        @"signature": self.signature ?: @"",
        @"purchase-info": [self.purchaseInfo dictionaryRepresentation],
        @"pod": self.pod ?: @"44",
        @"signing-status": self.signingStatus ?: @"0",
    };
}
@end

@implementation SJReceiptInfo
- (instancetype)init { self = [super init]; if (self) { _fields = @{}; } return self; }
- (NSDictionary<NSString *, id> *)dictionaryRepresentation { return [self.fields copy] ?: @{}; }
@end

@implementation SJReceipt
- (instancetype)init { self = [super init]; if (self) { _fields = @{}; _inApp = @[]; } return self; }
- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    NSMutableDictionary<NSString *, id> *result = [self.fields mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:self.inApp.count];
    for (SJReceiptInfo *info in self.inApp) {
        [items addObject:[info dictionaryRepresentation]];
    }
    result[@"in_app"] = items;
    return result;
}
@end

@implementation SJRenewalInfo
- (instancetype)init { self = [super init]; if (self) { _autoRenewProductIdentifier=@""; _originalTransactionIdentifier=@""; _productIdentifier=@""; _autoRenewStatus=@"1"; } return self; }
- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    return @{
        @"auto_renew_product_id": self.autoRenewProductIdentifier ?: @"",
        @"original_transaction_id": self.originalTransactionIdentifier ?: @"",
        @"product_id": self.productIdentifier ?: @"",
        @"auto_renew_status": self.autoRenewStatus ?: @"1",
    };
}
@end

@implementation SJReceiptResponse
- (instancetype)init { self = [super init]; if (self) { _environment=@"LocalTest"; _receipt=[SJReceipt new]; _latestReceiptInfo=@[]; _latestReceipt=@""; _pendingRenewalInfo=@[]; } return self; }
- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    NSMutableArray *latest = [NSMutableArray arrayWithCapacity:self.latestReceiptInfo.count];
    for (SJReceiptInfo *info in self.latestReceiptInfo) [latest addObject:[info dictionaryRepresentation]];
    NSMutableArray *renewal = [NSMutableArray arrayWithCapacity:self.pendingRenewalInfo.count];
    for (SJRenewalInfo *info in self.pendingRenewalInfo) [renewal addObject:[info dictionaryRepresentation]];
    return @{
        @"status": @(self.status),
        @"environment": self.environment ?: @"LocalTest",
        @"receipt": [self.receipt dictionaryRepresentation],
        @"latest_receipt_info": latest,
        @"latest_receipt": self.latestReceipt ?: @"",
        @"pending_renewal_info": renewal,
    };
}
@end
