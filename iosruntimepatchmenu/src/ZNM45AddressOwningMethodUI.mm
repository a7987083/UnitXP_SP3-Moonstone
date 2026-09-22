#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <errno.h>

#import "ZNIL2CPPOwningMethodResolver.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

// M4.5 outer Finder layer.
// Named method searches remain on M4.4.2's device-proven V3 route. Address
// queries are intercepted and resolved by an interval-aware owning-method
// resolver so an instruction inside a method can map back to MethodInfo.

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIWindow *hostWindow;
@property(nonatomic,strong) ZNTheme *theme;
- (void)renderPage;
- (NSString *)zn57mf_query;
- (void)zn57mf_setQuery:(NSString *)value;
- (NSUInteger)zn60v3_limit;
- (void)zn60v3_setCandidates:(NSArray<NSDictionary *> *)items;
- (NSArray<NSDictionary *> *)zn60v3_candidates;
- (void)zn60v3_setSelected:(NSDictionary * _Nullable)candidate;
- (NSDictionary * _Nullable)zn60v3_selected;
- (void)zn60v3_setPage:(NSInteger)page;
- (void)zn60v3_setStatus:(NSString *)status;
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)znm442_submitSearch:(id)sender;
- (void)zn60v3_renderDetailAtWidth:(CGFloat)width;
@end

static NSString *ZNM45Trim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL ZNM45AllHex(NSString *value, BOOL *hasDigit) {
    NSString *s = ZNM45Trim(value);
    if (!s.length) return NO;
    BOOL digit = NO;
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        BOOL hex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
        if (!hex) return NO;
        if (c >= '0' && c <= '9') digit = YES;
    }
    if (hasDigit) *hasDigit = digit;
    return YES;
}

static BOOL ZNM45ParseHex(NSString *body, uint64_t *value) {
    NSString *s = ZNM45Trim(body);
    if ([s.lowercaseString hasPrefix:@"0x"]) s = [s substringFromIndex:2];
    if (!s.length || !ZNM45AllHex(s, NULL)) return NO;
    const char *raw = s.UTF8String;
    if (!raw) return NO;
    errno = 0;
    char *end = NULL;
    unsigned long long parsed = strtoull(raw, &end, 16);
    if (errno || end == raw || (end && *end)) return NO;
    if (value) *value = (uint64_t)parsed;
    return YES;
}

static uintptr_t ZNM45UnityRuntimeBase(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *raw = _dyld_get_image_name(i);
        if (!raw) continue;
        NSString *path = [NSString stringWithUTF8String:raw] ?: @"";
        if ([path.lastPathComponent isEqualToString:@"UnityFramework"] ||
            [path rangeOfString:@"UnityFramework.framework/UnityFramework" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

static BOOL ZNM45NormalizeAddress(NSString *raw, uint64_t *rva, NSString **normalized, NSString **error) {
    NSString *s = ZNM45Trim(raw);
    if (!s.length) return NO;
    NSString *lower = s.lowercaseString;
    BOOL explicitRVA = [lower hasPrefix:@"rva:"];
    BOOL explicitVA = [lower hasPrefix:@"va:"];
    BOOL explicit0x = [lower hasPrefix:@"0x"];
    BOOL hasDigit = NO;
    BOOL bareHex = ZNM45AllHex(s, &hasDigit) && hasDigit && s.length >= 5;
    if (!explicitRVA && !explicitVA && !explicit0x && !bareHex) return NO;

    NSString *body = s;
    if (explicitRVA) body = [s substringFromIndex:4];
    else if (explicitVA) body = [s substringFromIndex:3];

    uint64_t value = 0;
    if (!ZNM45ParseHex(body, &value)) {
        if (error) *error = [NSString stringWithFormat:@"M4.5：地址格式无效：%@", raw ?: @""];
        return YES;
    }
    if (explicitVA) {
        uintptr_t base = ZNM45UnityRuntimeBase();
        if (!base || value < (uint64_t)base) {
            if (error) *error = [NSString stringWithFormat:@"M4.5：Runtime VA 无法换算 UnityFramework RVA：0x%llX", (unsigned long long)value];
            return YES;
        }
        value -= (uint64_t)base;
    }
    if (rva) *rva = value;
    if (normalized) *normalized = [NSString stringWithFormat:@"rva:0x%llX", (unsigned long long)value];
    return YES;
}

static CGFloat ZNM45BottomY(UIView *content) {
    CGFloat bottom = 0;
    for (UIView *view in content.subviews) bottom = MAX(bottom, CGRectGetMaxY(view.frame));
    return bottom;
}

@interface ZNRuntimeMenuControllerV040 (ZNM45AddressOwningMethod)
- (void)znm45_submitSearch:(id)sender;
- (void)znm45_renderDetailAtWidth:(CGFloat)width;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM45AddressOwningMethod)

- (void)znm45_submitSearch:(id)sender {
    NSString *raw = ZNM45Trim([self zn57mf_query]);
    uint64_t rva = 0;
    NSString *normalized = nil;
    NSString *normalizeError = nil;
    BOOL addressQuery = ZNM45NormalizeAddress(raw, &rva, &normalized, &normalizeError);
    if (!addressQuery) {
        // After swizzling, this alias reaches M4.4.2's proven named-search route.
        [self znm45_submitSearch:sender];
        return;
    }

    [self.hostWindow endEditing:YES];
    if (normalizeError.length) {
        [self zn60v3_setStatus:normalizeError];
        [self zn60v3_setPage:0];
        [self renderPage];
        return;
    }

    [self zn57mf_setQuery:normalized ?: raw];
    NSString *resolveError = nil;
    NSArray<NSDictionary *> *items = [[ZNIL2CPPOwningMethodResolver sharedResolver] resolveRVA:rva
                                                                                          limit:[self zn60v3_limit]
                                                                                          error:&resolveError];
    if (!items.count) {
        [self zn60v3_setStatus:resolveError ?: @"M4.5：找不到所属 IL2CPP 方法"];
        [self zn60v3_setPage:0];
        [self renderPage];
        return;
    }

    [self zn60v3_setCandidates:items];
    [self zn60v3_setSelected:nil];
    NSDictionary *first = items.firstObject;
    NSString *className = first[@"class"] ?: @"?";
    NSString *methodName = first[@"method"] ?: @"?";
    NSInteger argc = [first[@"argumentCount"] integerValue];
    uint64_t methodRVA = [first[@"methodRVA"] unsignedLongLongValue];
    uint64_t delta = [first[@"intraMethodOffset"] unsignedLongLongValue];
    NSString *suffix = delta ? [NSString stringWithFormat:@" +0x%llX", (unsigned long long)delta] : @" · 方法入口";
    NSString *shared = items.count > 1 ? [NSString stringWithFormat:@" · %lu 个共享代码入口候选", (unsigned long)items.count] : @"";
    [self zn60v3_setStatus:[NSString stringWithFormat:@"0x%llX → %@::%@/%ld · start=0x%llX%@%@",
                              (unsigned long long)rva,
                              className,
                              methodName,
                              (long)argc,
                              (unsigned long long)methodRVA,
                              suffix,
                              shared]];
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.5-owning-method-ui] query=%@ rva=0x%llX candidates=%lu start=0x%llX delta=0x%llX",
                                         raw,
                                         (unsigned long long)rva,
                                         (unsigned long)items.count,
                                         (unsigned long long)methodRVA,
                                         (unsigned long long)delta]];
    [self zn60v3_setPage:1];
    [self renderPage];
}

- (void)znm45_renderDetailAtWidth:(CGFloat)width {
    // Alias reaches the previous detail renderer chain (M4.3 cleanup + V3 info).
    [self znm45_renderDetailAtWidth:width];
    NSDictionary *candidate = [self zn60v3_selected];
    if (![candidate[@"ownershipKind"] isKindOfClass:NSString.class]) return;

    CGFloat y = ZNM45BottomY(self.contentView) + 8.0;
    UIView *card = [self cardAtY:y height:112 width:width compact:NO];
    UILabel *title = [self label:@"地址归属（M4.5）" size:10.6 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    title.frame = CGRectMake(13, 7, card.bounds.size.width - 26, 18);
    [card addSubview:title];

    NSString *query = candidate[@"queryRVAText"] ?: candidate[@"rvaText"] ?: @"—";
    NSString *start = candidate[@"methodRVAText"] ?: @"—";
    NSString *offset = candidate[@"intraMethodOffsetText"] ?: @"+0x0";
    NSString *next = candidate[@"nextMethodRVAText"] ?: @"—";
    NSString *kind = candidate[@"ownershipKind"] ?: @"?";
    NSArray<NSString *> *lines = @[
        [NSString stringWithFormat:@"查询 RVA      %@", query],
        [NSString stringWithFormat:@"方法入口       %@  (%@)", start, offset],
        [NSString stringWithFormat:@"下一方法入口   %@", next],
        [NSString stringWithFormat:@"判定           %@", kind],
    ];
    CGFloat ly = 30.0;
    for (NSString *line in lines) {
        UILabel *label = [self label:line size:8.5 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        label.frame = CGRectMake(13, ly, card.bounds.size.width - 26, 17);
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.7;
        [card addSubview:label];
        ly += 18.0;
    }
    [self.contentView addSubview:card];
    [self zn40_updateContentHeight:y + 120.0];
}

@end

static void ZNM45Swap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallM45AddressOwningMethodDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class menu = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!menu) return;
        ZNM45Swap(menu, @selector(znm442_submitSearch:), @selector(znm45_submitSearch:));
        ZNM45Swap(menu, @selector(zn60v3_renderDetailAtWidth:), @selector(znm45_renderDetailAtWidth:));
        [[ZNRuntimeLogger sharedLogger] log:@"[m4.5-owning-method] address queries now resolve exact entry or bounded owning method; named search remains proven-v3"];
    });
}
