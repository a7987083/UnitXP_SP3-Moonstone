#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <errno.h>

#import "ZNPatchCore.h"

// M4.4.2 search-route restore
//
// M4.3 swaps zn60v3_startSearch: <-> znm43_startSearch:. After that swap the
// selector znm43_startSearch: intentionally points at the original, device-
// proven V3 search implementation. M4.4.1 accidentally bypassed that path by
// rebinding both keyboard Search and the visible Search button to a third
// implementation. This outer hotfix keeps M4.4.1's input improvements but
// routes both UI entry points back through the proven V3 implementation.
//
// Assembly semantics are also restored:
// - before the user explicitly chooses an Assembly, search remains global and
//   the V3 backend keeps its original Assembly-CSharp-first priority;
// - after an explicit picker choice, a non-empty Assembly becomes a strict
//   Assembly filter by temporarily qualifying the query as Assembly!query.

static const void *kZNM442AssemblyExplicitKey = &kZNM442AssemblyExplicitKey;
static const NSInteger kZNM442LimitTag = 643001;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIWindow *hostWindow;
- (NSString *)zn57mf_query;
- (void)zn57mf_setQuery:(NSString *)value;
- (NSUInteger)zn60v3_limit;
- (void)zn60v3_setLimit:(NSUInteger)value;
- (NSString *)znm43_selectedAssembly;
- (void)znm43_setSelectedAssembly:(NSString *)value;
// After M4.3's swap this selector resolves to the original V3 search IMP.
- (void)znm43_startSearch:(id)sender;
@end

static NSString *ZNM442Trim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static void ZNM442Walk(UIView *root, void (^block)(UIView *view)) {
    if (!root || !block) return;
    block(root);
    for (UIView *subview in root.subviews) ZNM442Walk(subview, block);
}

static BOOL ZNM442AllHex(NSString *value, BOOL *hasDigit) {
    NSString *s = ZNM442Trim(value);
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

static BOOL ZNM442ParseHexBody(NSString *body, uint64_t *outValue) {
    NSString *s = ZNM442Trim(body);
    if ([s.lowercaseString hasPrefix:@"0x"]) s = [s substringFromIndex:2];
    if (!s.length || !ZNM442AllHex(s, NULL)) return NO;
    const char *raw = s.UTF8String;
    if (!raw) return NO;
    errno = 0;
    char *end = NULL;
    unsigned long long value = strtoull(raw, &end, 16);
    if (errno || end == raw || (end && *end)) return NO;
    if (outValue) *outValue = (uint64_t)value;
    return YES;
}

static uintptr_t ZNM442UnityRuntimeBase(void) {
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

static NSString *ZNM442NormalizeQuery(NSString *raw, BOOL *isAddress, NSString **error) {
    NSString *s = ZNM442Trim(raw);
    if (isAddress) *isAddress = NO;
    if (!s.length) return s;

    NSString *lower = s.lowercaseString;
    BOOL explicitRVA = [lower hasPrefix:@"rva:"];
    BOOL explicitVA = [lower hasPrefix:@"va:"];
    BOOL explicit0x = [lower hasPrefix:@"0x"];
    BOOL hasDigit = NO;
    BOOL bareHex = ZNM442AllHex(s, &hasDigit) && hasDigit && s.length >= 5;
    if (!explicitRVA && !explicitVA && !explicit0x && !bareHex) return s;

    NSString *body = s;
    if (explicitRVA) body = [s substringFromIndex:4];
    else if (explicitVA) body = [s substringFromIndex:3];

    uint64_t value = 0;
    if (!ZNM442ParseHexBody(body, &value)) {
        if (error) *error = [NSString stringWithFormat:@"地址格式无效：%@", raw ?: @""];
        return nil;
    }
    if (explicitVA) {
        uintptr_t base = ZNM442UnityRuntimeBase();
        if (!base || value < (uint64_t)base) {
            if (error) *error = [NSString stringWithFormat:@"Runtime VA 无法换算 UnityFramework RVA：0x%llX", (unsigned long long)value];
            return nil;
        }
        value -= (uint64_t)base;
    }
    if (isAddress) *isAddress = YES;
    return [NSString stringWithFormat:@"rva:0x%llX", (unsigned long long)value];
}

@interface ZNRuntimeMenuControllerV040 (ZNM442SearchRestore)
- (void)znm442_renderSearchAtWidth:(CGFloat)width;
- (void)znm442_submitSearch:(id)sender;
- (void)znm442_setSelectedAssembly:(NSString *)value;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM442SearchRestore)

- (void)znm442_setSelectedAssembly:(NSString *)value {
    // This method is swapped with znm43_setSelectedAssembly:. Calling the alias
    // reaches the original setter while this flag records explicit user intent.
    objc_setAssociatedObject(self, kZNM442AssemblyExplicitKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self znm442_setSelectedAssembly:value];
}

- (void)znm442_renderSearchAtWidth:(CGFloat)width {
    // Call the previous outer render chain (M4.4.1 -> M4.3 -> V3).
    [self znm442_renderSearchAtWidth:width];

    __block UITextField *queryField = nil;
    __block UIButton *searchButton = nil;
    __block UIButton *assemblyButton = nil;
    ZNM442Walk(self.contentView, ^(UIView *view) {
        if ([view isKindOfClass:UITextField.class]) {
            UITextField *field = (UITextField *)view;
            if (field.tag != kZNM442LimitTag && field.returnKeyType == UIReturnKeySearch) queryField = field;
        } else if ([view isKindOfClass:UIButton.class]) {
            UIButton *button = (UIButton *)view;
            NSString *title = [button titleForState:UIControlStateNormal] ?: @"";
            if ([title isEqualToString:@"搜索"]) searchButton = button;
            if ([title containsString:@"Assembly-CSharp"] && [title containsString:@"›"]) assemblyButton = button;
        }
    });

    if (queryField) {
        [queryField removeTarget:nil action:NULL forControlEvents:UIControlEventEditingDidEndOnExit];
        [queryField addTarget:self action:@selector(znm442_submitSearch:) forControlEvents:UIControlEventEditingDidEndOnExit];
    }
    if (searchButton) {
        [searchButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        [searchButton addTarget:self action:@selector(znm442_submitSearch:) forControlEvents:UIControlEventTouchUpInside];
    }

    BOOL explicitAssembly = [objc_getAssociatedObject(self, kZNM442AssemblyExplicitKey) boolValue];
    if (!explicitAssembly && assemblyButton) {
        [assemblyButton setTitle:@"Assembly-CSharp · 优先  ›" forState:UIControlStateNormal];
    }
}

- (void)znm442_submitSearch:(id)sender {
    UITextField *limitField = (UITextField *)[self.contentView viewWithTag:kZNM442LimitTag];
    if ([limitField isKindOfClass:UITextField.class] && limitField.text.length) {
        NSInteger raw = limitField.text.integerValue;
        [self zn60v3_setLimit:(NSUInteger)MAX(1, MIN(1024, raw))];
    }

    NSString *rawQuery = ZNM442Trim([self zn57mf_query]);
    if (!rawQuery.length) return;

    BOOL addressQuery = NO;
    NSString *normalizeError = nil;
    NSString *normalized = ZNM442NormalizeQuery(rawQuery, &addressQuery, &normalizeError);
    if (!normalized) {
        // Fall back to the proven V3 path with the original text so the existing
        // UI/status chain reports the same error semantics as before.
        normalized = rawQuery;
    }

    BOOL explicitAssembly = [objc_getAssociatedObject(self, kZNM442AssemblyExplicitKey) boolValue];
    NSString *assembly = [self znm43_selectedAssembly] ?: @"";
    NSString *expression = normalized;
    if (!addressQuery && explicitAssembly && assembly.length && [normalized rangeOfString:@"!"].location == NSNotFound) {
        expression = [NSString stringWithFormat:@"%@!%@", assembly, normalized];
    }

    // Critical behavior: delegate execution to selector znm43_startSearch:.
    // Because M4.3 already exchanged implementations, this selector is the
    // original V3 search implementation that was device-proven by the visible
    // Search button before M4.4.1.
    [self zn57mf_setQuery:expression];
    [self znm43_startSearch:sender];

    // Do not leak temporary Assembly! qualification back into the visible field.
    [self zn57mf_setQuery:normalized];
    ZNM442Walk(self.contentView, ^(UIView *view) {
        if (![view isKindOfClass:UITextField.class]) return;
        UITextField *field = (UITextField *)view;
        if (field.tag != kZNM442LimitTag && field.returnKeyType == UIReturnKeySearch) field.text = normalized;
    });

    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.4.2-search-restore] raw=%@ normalized=%@ explicitAssembly=%@ assembly=%@ engine=proven-v3",
                                         rawQuery,
                                         normalized,
                                         explicitAssembly ? @"YES" : @"NO",
                                         assembly.length ? assembly : @"<all>"]];
}

@end

static void ZNM442Swap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallM442SearchRestoreDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class menu = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!menu) return;
        ZNM442Swap(menu, @selector(zn60v3_renderSearchAtWidth:), @selector(znm442_renderSearchAtWidth:));
        ZNM442Swap(menu, @selector(znm43_setSelectedAssembly:), @selector(znm442_setSelectedAssembly:));
        [[ZNRuntimeLogger sharedLogger] log:@"[m4.4.2-search-restore] proven V3 engine restored for keyboard + button; Assembly-CSharp default is priority, explicit picker choice is strict"];
    });
}
