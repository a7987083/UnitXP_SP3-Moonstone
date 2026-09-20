#import "../Public/SJReceiptGenerator.h"
#import "../Public/SatellaCore.h"
#include <stdlib.h>

@implementation SJReceiptGenerator

+ (NSString *)bundleIdentifier {
    return NSBundle.mainBundle.bundleIdentifier ?: @"local.test.satella";
}

+ (NSString *)version {
    id value = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return [value isKindOfClass:[NSString class]] && [value length] > 0 ? value : @"1.0";
}

+ (NSString *)nowText:(NSDate *)date {
    // Upstream used Date.description followed by a fixed location suffix.
    return [NSString stringWithFormat:@"%@ Europe/Copenhagen", date];
}

+ (NSString *)milliseconds:(NSDate *)date {
    long long value = (long long)(date.timeIntervalSince1970 * 1000.0);
    return [NSString stringWithFormat:@"%lld", value];
}

+ (NSString *)receiptIdentifier {
    uint32_t value = arc4random_uniform(0x07151129u - 1u) + 1u;
    return [NSString stringWithFormat:@"%u", value];
}

+ (SJOldReceipt *)oldReceiptForProductIdentifier:(NSString *)productIdentifier {
    NSDate *now = [NSDate date];
    NSString *receiptID = [self receiptIdentifier];
    NSString *bundleID = [self bundleIdentifier];
    NSString *version = [self version];
    NSString *nowText = [self nowText:now];
    NSString *nowMs = [self milliseconds:now];

    SJOldReceiptInfo *info = [SJOldReceiptInfo new];
    info.fields = @{
        @"app-item-id": receiptID,
        @"bid": bundleID,
        @"bvrs": version,
        @"version-external-identifier": version,
        @"item-id": receiptID,
        @"original-purchase-date": nowText,
        @"original-purchase-date-ms": nowMs,
        @"original-purchase-date-pst": nowText,
        @"original-transaction-id": receiptID,
        @"product-id": productIdentifier.length ? productIdentifier : @"local.test.satella.product",
        @"purchase-date": nowText,
        @"purchase-date-ms": nowMs,
        @"purchase-date-pst": nowText,
        @"quantity": @"1",
        @"transaction-id": receiptID,
        @"unique-identifier": receiptID,
        @"unique-vendor-identifier": NSUUID.UUID.UUIDString,
    };

    SJOldReceipt *receipt = [SJOldReceipt new];
    // Deliberately test-only. This is not an Apple production receipt signature.
    NSData *signatureMarker = [@"SATELLA-LOCAL-TEST-SIGNATURE" dataUsingEncoding:NSUTF8StringEncoding];
    receipt.signature = [signatureMarker base64EncodedStringWithOptions:0];
    receipt.purchaseInfo = info;
    receipt.pod = @"44";
    receipt.signingStatus = @"0";
    return receipt;
}

+ (SJReceipt *)receiptForProductIdentifier:(NSString *)productIdentifier {
    NSDate *now = [NSDate date];
    NSDate *expiry = [NSDate dateWithTimeIntervalSince1970:0xf2a52380];
    NSString *receiptID = [self receiptIdentifier];
    NSString *bundleID = [self bundleIdentifier];
    NSString *version = [self version];
    NSString *nowText = [self nowText:now];
    NSString *nowMs = [self milliseconds:now];
    NSString *expiryText = [self nowText:expiry];
    NSString *expiryMs = [self milliseconds:expiry];

    SJReceiptInfo *info = [SJReceiptInfo new];
    info.fields = @{
        @"quantity": @"1",
        @"product_id": productIdentifier.length ? productIdentifier : bundleID,
        @"transaction_id": receiptID,
        @"original_transaction_id": receiptID,
        @"purchase_date": nowText,
        @"purchase_date_ms": nowMs,
        @"purchase_date_pst": nowText,
        @"original_purchase_date": nowText,
        @"original_purchase_date_ms": nowMs,
        @"original_purchase_date_pst": nowText,
        @"expires_date": expiryText,
        @"expires_date_ms": expiryMs,
        @"expires_date_pst": expiryText,
        @"is_trial_period": @"false",
        @"is_in_intro_offer_period": @"false",
    };

    SJReceipt *receipt = [SJReceipt new];
    receipt.fields = @{
        // Keep the complete upstream field shape, but mark the environment as
        // local test data so it cannot be confused with a production receipt.
        @"receipt_type": @"LocalTest",
        @"adam_id": @([receiptID longLongValue]),
        @"app_item_id": @([receiptID longLongValue]),
        @"bundle_id": bundleID,
        @"application_version": version,
        @"download_id": @([receiptID integerValue]),
        @"version_external_identifier": @0,
        @"receipt_creation_date": nowText,
        @"receipt_creation_date_ms": nowMs,
        @"receipt_creation_date_pst": nowText,
        @"request_date": nowText,
        @"request_date_ms": nowMs,
        @"request_date_pst": nowText,
        @"original_purchase_date": nowText,
        @"original_purchase_date_ms": nowMs,
        @"original_purchase_date_pst": nowText,
        @"original_application_version": version,
    };
    receipt.inApp = @[info];
    return receipt;
}

+ (SJReceiptResponse *)verificationResponseForProductIdentifier:(NSString *)productIdentifier {
    SJReceipt *receipt = [self receiptForProductIdentifier:productIdentifier];
    NSError *error = nil;
    NSData *receiptData = [NSJSONSerialization dataWithJSONObject:[receipt dictionaryRepresentation] options:0 error:&error];
    NSString *encoded = error ? @"" : [receiptData base64EncodedStringWithOptions:0];

    SJRenewalInfo *renewal = [SJRenewalInfo new];
    renewal.autoRenewProductIdentifier = productIdentifier ?: @"";
    renewal.originalTransactionIdentifier = NSUUID.UUID.UUIDString;
    renewal.productIdentifier = productIdentifier ?: @"";
    renewal.autoRenewStatus = @"1";

    SJReceiptResponse *response = [SJReceiptResponse new];
    response.status = 0;
    response.environment = @"LocalTest";
    response.receipt = receipt;
    response.latestReceiptInfo = receipt.inApp;
    response.latestReceipt = encoded;
    response.pendingRenewalInfo = @[renewal];
    return response;
}

+ (NSData * _Nullable)JSONDataForOldReceipt:(SJOldReceipt *)receipt error:(NSError **)error {
    return [NSJSONSerialization dataWithJSONObject:[receipt dictionaryRepresentation] options:0 error:error];
}

+ (NSData * _Nullable)JSONDataForVerificationResponse:(SJReceiptResponse *)response error:(NSError **)error {
    return [NSJSONSerialization dataWithJSONObject:[response dictionaryRepresentation] options:0 error:error];
}

@end
