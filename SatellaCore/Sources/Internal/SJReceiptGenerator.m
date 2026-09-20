#import "../Public/SJReceiptGenerator.h"
#import "../Public/SatellaCore.h"
#include <stdlib.h>

@implementation SJReceiptGenerator

+ (NSString *)bundleIdentifier {
    return NSBundle.mainBundle.bundleIdentifier ?: @"emt.paisseon.satella";
}

+ (NSString *)appVersionString {
    id value = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return [value isKindOfClass:NSString.class] && [value length] > 0 ? value : @"1.0";
}

+ (NSString *)environment {
    SJConfiguration *configuration = [SatellaCore configuration];
    if (configuration.behaviorMode == SJBehaviorModeUpstreamParity) {
        return @"Production";
    }
    NSString *environment = configuration.testEnvironment;
    return environment.length > 0 ? environment : @"Production";
}

+ (NSString *)nowText:(NSDate *)date {
    // Swift interpolation of Date uses Foundation's description, then the
    // upstream generator appends this literal location suffix.
    return [NSString stringWithFormat:@"%@ Europe/Copenhagen", date];
}

+ (NSString *)milliseconds:(NSDate *)date {
    // Upstream converts the seconds value to Int64 first, then multiplies by
    // 1000, so generated values are intentionally second-granularity.
    long long seconds = (long long)date.timeIntervalSince1970;
    long long value = seconds * 1000LL;
    return [NSString stringWithFormat:@"%lld", value];
}

+ (NSString *)receiptIdentifier {
    // Swift: Int.random(in: 1 ... 0x07151129), inclusive at both ends.
    uint32_t value = arc4random_uniform(0x07151129u) + 1u;
    return [NSString stringWithFormat:@"%u", value];
}

+ (NSString *)uniqueVendorIdentifier {
    // Keep the component Foundation-only while matching UIDevice.identifierForVendor
    // when running inside UIKit on iOS.  On non-iOS test hosts, use the same
    // UUID fallback as the Swift source.
    Class deviceClass = NSClassFromString(@"UIDevice");
    SEL currentDeviceSelector = NSSelectorFromString(@"currentDevice");
    SEL identifierSelector = NSSelectorFromString(@"identifierForVendor");
    SEL uuidStringSelector = NSSelectorFromString(@"UUIDString");
    if (deviceClass && [deviceClass respondsToSelector:currentDeviceSelector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id device = [deviceClass performSelector:currentDeviceSelector];
        id identifier = [device respondsToSelector:identifierSelector] ? [device performSelector:identifierSelector] : nil;
        NSString *uuid = [identifier respondsToSelector:uuidStringSelector] ? [identifier performSelector:uuidStringSelector] : nil;
#pragma clang diagnostic pop
        if ([uuid isKindOfClass:NSString.class] && uuid.length > 0) return uuid;
    }
    return NSUUID.UUID.UUIDString;
}

+ (NSString *)upstreamReceiptSignatureBase64 {
    // Exact base64 result of Data(ReceiptGenerator.signature).base64EncodedString()
    // from Paisseon/SatellaJailed@469e6eb7806ce19eb44e80cf03a9e61a100ba86e.
    return @"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";
}

+ (SJOldReceipt *)oldReceiptForProductIdentifier:(NSString * _Nullable)productIdentifier {
    // Upstream evaluates Date() separately for the millisecond value and the
    // textual value, in this order. Keep that observable edge behaviour.
    NSString *nowMs = [self milliseconds:[NSDate date]];
    NSString *nowText = [self nowText:[NSDate date]];
    NSString *receiptID = [self receiptIdentifier];
    NSString *bundleID = [self bundleIdentifier];
    NSString *version = [self appVersionString];

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
        @"product-id": productIdentifier ?: @"emt.paisseon.satella.product",
        @"purchase-date": nowText,
        @"purchase-date-ms": nowMs,
        @"purchase-date-pst": nowText,
        @"quantity": @"1",
        @"transaction-id": receiptID,
        @"unique-identifier": receiptID,
        @"unique-vendor-identifier": [self uniqueVendorIdentifier],
    };

    SJOldReceipt *receipt = [SJOldReceipt new];
    receipt.signature = [self upstreamReceiptSignatureBase64];
    receipt.purchaseInfo = info;
    receipt.pod = @"44";
    receipt.signingStatus = @"0";
    return receipt;
}

+ (SJReceipt *)receiptForProductIdentifier:(NSString * _Nullable)productIdentifier {
    NSString *nowMs = [self milliseconds:[NSDate date]];
    NSString *nowText = [self nowText:[NSDate date]];
    NSDate *expiry = [NSDate dateWithTimeIntervalSince1970:0xf2a52380];
    NSString *receiptID = [self receiptIdentifier];
    NSString *bundleID = [self bundleIdentifier];
    NSString *version = [self appVersionString];
    NSString *expiryText = [self nowText:expiry];
    NSString *expiryMs = [self milliseconds:expiry];

    SJReceiptInfo *info = [SJReceiptInfo new];
    info.fields = @{
        @"quantity": @"1",
        @"product_id": productIdentifier ?: bundleID,
        @"transaction_id": receiptID,
        @"original_transaction_id": receiptID,
        @"purchase_date": nowText,
        @"purchase_date_ms": nowMs,
        @"purchase_date_pst": nowText,
        @"original_purchase_date": nowText,
        // Preserve the upstream source exactly: it assigns nowDate here,
        // despite the field name ending in _ms.
        @"original_purchase_date_ms": nowText,
        @"original_purchase_date_pst": nowText,
        @"expires_date": expiryText,
        @"expires_date_ms": expiryMs,
        @"expires_date_pst": expiryText,
        @"is_trial_period": @"false",
        @"is_in_intro_offer_period": @"false",
    };

    SJReceipt *receipt = [SJReceipt new];
    receipt.fields = @{
        @"receipt_type": [self environment],
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

+ (SJReceiptResponse *)verificationResponseForProductIdentifier:(NSString * _Nullable)productIdentifier {
    NSString *normalizedProductIdentifier = productIdentifier ?: @"";
    SJReceipt *receipt = [self receiptForProductIdentifier:normalizedProductIdentifier];
    NSError *error = nil;
    NSData *receiptData = [NSJSONSerialization dataWithJSONObject:[receipt dictionaryRepresentation]
                                                          options:0
                                                            error:&error];
    NSString *encoded = error ? @"" : [receiptData base64EncodedStringWithOptions:0];

    SJRenewalInfo *renewal = [SJRenewalInfo new];
    renewal.autoRenewProductIdentifier = normalizedProductIdentifier;
    renewal.originalTransactionIdentifier = NSUUID.UUID.UUIDString;
    renewal.productIdentifier = normalizedProductIdentifier;
    renewal.autoRenewStatus = @"1";

    SJReceiptResponse *response = [SJReceiptResponse new];
    response.status = 0;
    response.environment = [self environment];
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
