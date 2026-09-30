#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNFeatureControlModel.h"
#import "ZNPatchRuntimeValidator.h"
#import "ZNStaticBinaryBuilder.h"
#import "ZNPatchCore.h"

// M5.9.3 — Canonical Offset Architecture
//
// Scope is intentionally limited to the ordinary Offset/Static Patch path.
// Runtime Method / IL2CPP invocation is not touched here.
//
// Architectural rule:
//   * ZNPatchRuntimeValidator + the installed Offset Resolver is the only
//     component allowed to interpret author-entered Offset text.
//   * Slider/Number Offset-Hook rows must resolve through that same path.
//   * Downstream physical-site operations consume validator.target +
//     validator.rva only. Raw row.target/offsetText remain authoring/UI data.
//
// M5.9.1/M5.9.2 remain compiled for their UI/persistence/runtime-hook behavior,
// but this final adapter is installed after them and prevents their legacy raw
// Offset interpretation from being authoritative.

static NSString *ZNM593Trim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL ZNM593IsOffsetHookRow(ZNBinaryPatchRow *row) {
    if (!ZNM593Trim(row.offsetText).length) return NO;
    ZNFeatureControlType type = row.featureControlType;
    return type == ZNFeatureControlTypeSlider || type == ZNFeatureControlTypeNumber;
}

static NSString *ZNM593TargetForRow(ZNBinaryPatchWorkspace *workspace, ZNBinaryPatchRow *row) {
    if (row.explicitTarget && ZNM593Trim(row.target).length) return ZNM593Trim(row.target);
    NSString *fallback = ZNM593Trim(workspace.defaultTarget);
    return fallback.length ? fallback : @"main";
}

static NSString *ZNM593Hex(NSData *data) {
    if (!data.length) return @"";
    const uint8_t *p = (const uint8_t *)data.bytes;
    NSMutableString *s = [NSMutableString stringWithCapacity:data.length * 2];
    for (NSUInteger i = 0; i < data.length; i++) [s appendFormat:@"%02X", p[i]];
    return s;
}

@interface ZNM593ResolvedHookValidator : ZNPatchRuntimeValidator
@property(nonatomic,copy) NSString *mTarget;
@property(nonatomic,assign) uint64_t mRVA;
@property(nonatomic,copy) NSData *mBytes;
@property(nonatomic,assign) uintptr_t mAddress;
@end

@implementation ZNM593ResolvedHookValidator
- (NSString *)target { return self.mTarget ?: @""; }
- (uint64_t)rva { return self.mRVA; }
- (NSData *)patchBytes { return self.mBytes ?: NSData.data; }
- (NSData *)capturedOriginalBytes { return self.mBytes ?: NSData.data; }
- (NSData *)currentBytes { return self.mBytes ?: NSData.data; }
- (uintptr_t)runtimeAddress { return self.mAddress; }
- (BOOL)isConfigured { return YES; }
- (BOOL)isValidated { return YES; }
- (BOOL)isApplied { return NO; }
- (NSString *)lastResult { return @"Canonical Offset Hook · resolved by shared validator"; }
@end

// Resolve an Offset-Hook through the exact same validator/resolver stack used
// by ordinary Offset patches. Two harmless probe byte patterns are used only
// because the validator needs a 4-byte patch payload in order to capture the
// live original bytes. At least one pattern differs from any 4-byte site.
static BOOL ZNM593ResolveHookRow(ZNBinaryPatchWorkspace *workspace,
                                 ZNBinaryPatchRow *row,
                                 NSString **error) {
    NSString *target = ZNM593TargetForRow(workspace, row);
    NSString *rawOffset = [row.offsetText copy] ?: @"";
    if (!rawOffset.length) {
        if (error) *error = @"Offset 不能为空";
        return NO;
    }

    NSArray<NSString *> *probeHex = @[@"00000000", @"FFFFFFFF"];
    NSString *lastError = nil;
    for (NSString *hex in probeHex) {
        ZNPatchRuntimeValidator *probe = [ZNPatchRuntimeValidator new];
        NSString *e = nil;
        if (![probe configureTarget:target offsetString:rawOffset patchHex:hex error:&e]) {
            lastError = e ?: @"Offset 配置失败";
            break;
        }
        if (![probe validate:&e]) {
            lastError = e ?: @"Offset 解析/验证失败";
            // If the live bytes equal this probe payload, retry with the other
            // payload. Any genuine address/identity error must be surfaced.
            if ([lastError containsString:@"当前位置已经等于 Patch"] ||
                [lastError containsString:@"无法现场推断 Original"]) {
                continue;
            }
            break;
        }

        NSData *original = probe.capturedOriginalBytes;
        if (original.length != 4 || !probe.target.length || !probe.runtimeAddress) {
            lastError = @"Canonical Offset Resolver 未返回完整 4-byte 地址身份";
            break;
        }

        ZNM593ResolvedHookValidator *resolved = [ZNM593ResolvedHookValidator new];
        resolved.mTarget = probe.target;
        resolved.mRVA = probe.rva;
        resolved.mBytes = original;
        resolved.mAddress = probe.runtimeAddress;
        row.validator = resolved;
        row.validated = YES;
        row.originalHex = ZNM593Hex(original);
        // Builder compatibility: Offset-Hook carries an equivalent-original
        // variant. Author-facing Number/Slider UI does not consume this field.
        row.enabledText = ZNM593Hex(original);
        row.statusText = [NSString stringWithFormat:@"✅ Canonical Offset · %@ + 0x%llX",
                          resolved.target,
                          (unsigned long long)resolved.rva];
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:
            @"[m5.9.3-canonical-offset] hook resolved rawTarget=%@ rawOffset=%@ -> target=%@ rva=0x%llX runtime=%p",
            target, rawOffset, resolved.target, (unsigned long long)resolved.rva, (void *)resolved.runtimeAddress]];
        return YES;
    }

    if (error) *error = lastError ?: @"Canonical Offset 解析失败";
    return NO;
}

static NSArray<NSDictionary *> *ZNM593CanonicalizeRowsForExecution(ZNBinaryPatchWorkspace *workspace,
                                                                    NSString **error) {
    NSMutableArray<NSDictionary *> *saved = [NSMutableArray array];
    for (ZNBinaryPatchRow *row in workspace.rows) {
        if (!row.offsetText.length && !row.enabledText.length) continue;
        if (ZNM593IsOffsetHookRow(row) && (!row.validated || !row.validator)) {
            NSString *e = nil;
            if (!ZNM593ResolveHookRow(workspace, row, &e)) {
                if (error) *error = e ?: @"Offset Hook 解析失败";
                return nil;
            }
        }
        if (!row.validated || !row.validator || !row.validator.target.length) {
            if (error) *error = @"存在尚未通过 Canonical Offset 验证的 Patch";
            return nil;
        }
        [saved addObject:@{
            @"row": row,
            @"target": row.target ?: @"",
            @"explicit": @(row.explicitTarget),
            @"offset": row.offsetText ?: @""
        }];
        row.target = row.validator.target;
        row.explicitTarget = YES;
        row.offsetText = [NSString stringWithFormat:@"0x%llX", (unsigned long long)row.validator.rva];
    }
    return saved;
}

static void ZNM593RestoreAuthoringRows(NSArray<NSDictionary *> *saved) {
    for (NSDictionary *item in saved) {
        ZNBinaryPatchRow *row = item[@"row"];
        if (![row isKindOfClass:ZNBinaryPatchRow.class]) continue;
        row.target = item[@"target"] ?: @"";
        row.explicitTarget = [item[@"explicit"] boolValue];
        row.offsetText = item[@"offset"] ?: @"";
    }
}

@interface ZNBinaryPatchWorkspace (ZNM593CanonicalOffset)
- (BOOL)znm593_validateAll:(NSString **)error;
- (BOOL)znm593_applyAll:(NSString **)error;
@end

@implementation ZNBinaryPatchWorkspace (ZNM593CanonicalOffset)

- (BOOL)znm593_validateAll:(NSString **)error {
    NSMutableArray<ZNBinaryPatchRow *> *hooks = [NSMutableArray array];
    NSMutableArray<ZNBinaryPatchRow *> *legacy = [NSMutableArray array];
    for (ZNBinaryPatchRow *row in self.rows) {
        if (!row.offsetText.length && !row.enabledText.length) continue;
        if (ZNM593IsOffsetHookRow(row)) [hooks addObject:row];
        else [legacy addObject:row];
    }
    if (!hooks.count) return [self znm593_validateAll:error];
    if (self.hasAnyApplied) {
        if (error) *error = @"请先恢复当前临时 Patch";
        return NO;
    }

    for (ZNBinaryPatchRow *row in hooks) {
        NSString *e = nil;
        if (!ZNM593ResolveHookRow(self, row, &e)) {
            row.validated = NO;
            row.validator = nil;
            row.originalHex = @"";
            row.statusText = [NSString stringWithFormat:@"❌ %@", e ?: @"Canonical Offset 验证失败"];
            self.lastStatus = [NSString stringWithFormat:@"Canonical Offset 验证失败：%@", e ?: @"未知错误"];
            if (error) *error = e ?: @"Canonical Offset 验证失败";
            return NO;
        }
    }

    BOOL legacyOK = YES;
    NSString *legacyError = nil;
    if (legacy.count) {
        NSMutableArray<ZNBinaryPatchRow *> *storage = self.rows;
        NSArray<ZNBinaryPatchRow *> *snapshot = [storage copy];
        [storage removeAllObjects];
        [storage addObjectsFromArray:legacy];
        legacyOK = [self znm593_validateAll:&legacyError];
        [storage removeAllObjects];
        [storage addObjectsFromArray:snapshot];
    }
    if (!legacyOK) {
        self.lastStatus = [NSString stringWithFormat:@"传统 Patch 验证失败：%@", legacyError ?: @"未知错误"];
        if (error) *error = legacyError ?: @"传统 Patch 验证失败";
        return NO;
    }

    self.lastStatus = [NSString stringWithFormat:@"Canonical Offset：Hook %lu%@",
                       (unsigned long)hooks.count,
                       legacy.count ? [NSString stringWithFormat:@" · 传统 Patch %lu", (unsigned long)legacy.count] : @""];
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:
        @"[m5.9.3-canonical-offset] validation complete hooks=%lu legacy=%lu",
        (unsigned long)hooks.count, (unsigned long)legacy.count]];
    return YES;
}

- (BOOL)znm593_applyAll:(NSString **)error {
    NSString *canonicalError = nil;
    NSArray<NSDictionary *> *saved = ZNM593CanonicalizeRowsForExecution(self, &canonicalError);
    if (!saved) {
        if (error) *error = canonicalError ?: @"Canonical Offset 执行准备失败";
        return NO;
    }
    BOOL ok = [self znm593_applyAll:error];
    ZNM593RestoreAuthoringRows(saved);
    return ok;
}

@end

@interface ZNStaticBinaryBuilder (ZNM593CanonicalOffset)
+ (BOOL)znm593_buildWorkspace:(ZNBinaryPatchWorkspace *)workspace
                      outputs:(NSArray<NSString *> **)outputs
                       report:(NSString **)report
                        error:(NSString **)error;
@end

@implementation ZNStaticBinaryBuilder (ZNM593CanonicalOffset)

+ (BOOL)znm593_buildWorkspace:(ZNBinaryPatchWorkspace *)workspace
                      outputs:(NSArray<NSString *> **)outputs
                       report:(NSString **)report
                        error:(NSString **)error {
    NSString *canonicalError = nil;
    NSArray<NSDictionary *> *saved = ZNM593CanonicalizeRowsForExecution(workspace, &canonicalError);
    if (!saved) {
        if (error) *error = canonicalError ?: @"Canonical Offset Builder 准备失败";
        return NO;
    }

    // The previous M5.9.2 builder adapter may still run for persistence/UI
    // compatibility, but it now receives canonical target + canonical RVA only;
    // it no longer gets to interpret author-entered Offset text.
    BOOL ok = [self znm593_buildWorkspace:workspace outputs:outputs report:report error:error];
    ZNM593RestoreAuthoringRows(saved);
    return ok;
}

@end

static void ZNM593SwapInstance(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallM593CanonicalOffsetArchitectureDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class workspace = NSClassFromString(@"ZNBinaryPatchWorkspace");
        ZNM593SwapInstance(workspace, @selector(validateAll:), @selector(znm593_validateAll:));
        ZNM593SwapInstance(workspace, @selector(applyAll:), @selector(znm593_applyAll:));

        Class builder = NSClassFromString(@"ZNStaticBinaryBuilder");
        Method b1 = class_getClassMethod(builder, @selector(buildWorkspace:outputs:report:error:));
        Method b2 = class_getClassMethod(builder, @selector(znm593_buildWorkspace:outputs:report:error:));
        if (b1 && b2) method_exchangeImplementations(b1, b2);

        [[ZNRuntimeLogger sharedLogger] log:
            @"[m5.9.3-canonical-offset] installed after M5.9.2: one author-input resolver path; Runtime Method/IL2CPP untouched"];
    });
}
