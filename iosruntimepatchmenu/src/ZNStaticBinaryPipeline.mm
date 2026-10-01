#import "ZNStaticBinaryBuilder.h"
#import "ZNStaticBinaryBuilderV3Internal.h"
#import "ZNGeneratedBinaryPostprocess.h"
#import "ZNRuntimeOnlyBinaryBuilder.h"
#import "ZNTypedOnlyBinaryBuilder.h"
#import "ZNM462RuntimeOnlyVerifier.h"
#import "ZNBinaryPatchWorkspace.h"
#import "ZNTypedValueOffset.h"
#import "ZNRuntimeActionBuilder.h"
#import "ZNRuntimeActionModel.h"
#import "ZNRuntimeActionSignaturePostprocess.h"
#import "ZNTypedValueBinaryPersistence.h"
#import "ZNPatchCore.h"
#include <math.h>

static NSUInteger ZNCompleteStaticRowCount(ZNBinaryPatchWorkspace *workspace,
                                           NSUInteger *partialRows) {
    NSUInteger complete = 0;
    NSUInteger partial = 0;
    for (ZNBinaryPatchRow *row in workspace.rows ?: @[]) {
        if (row.controlKind != ZNOffsetControlKindSwitch) continue;
        BOOL hasOffset = row.offsetText.length > 0;
        BOOL hasEnabled = row.enabledText.length > 0;
        if (hasOffset && hasEnabled) complete++;
        else if (hasOffset || hasEnabled) partial++;
    }
    if (partialRows) *partialRows = partial;
    return complete;
}

static NSArray<NSString *> *ZNValidatedTypedTargets(ZNBinaryPatchWorkspace *workspace,
                                                     NSUInteger *typedCount,
                                                     NSString **error) {
    NSMutableOrderedSet<NSString *> *targets = [NSMutableOrderedSet orderedSet];
    NSUInteger count = 0;
    for (ZNBinaryPatchRow *row in workspace.rows ?: @[]) {
        if (row.controlKind == ZNOffsetControlKindSwitch) continue;
        if (!row.offsetText.length && !row.enabledText.length) continue;
        ZNTypedValueOffset *entry = row.typedEntry;
        if (!row.validated || !entry.isValidated) {
            if (error) *error = [NSString stringWithFormat:@"Typed Offset「%@」必须先读取验证通过", row.group.length ? row.group : (row.title.length ? row.title : @"未命名")];
            return nil;
        }
        NSString *target = [entry.target ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!target.length) target = @"main";
        [targets addObject:target];
        count++;
    }
    if (typedCount) *typedCount = count;
    return targets.array ?: @[];
}

static ZNBinaryPatchWorkspace *ZNStaticOnlyWorkspace(ZNBinaryPatchWorkspace *source) {
    ZNBinaryPatchWorkspace *filtered = [ZNBinaryPatchWorkspace new];
    filtered.defaultTarget = source.defaultTarget;
    [filtered.rows removeAllObjects];
    for (ZNBinaryPatchRow *row in source.rows ?: @[]) {
        if (row.controlKind != ZNOffsetControlKindSwitch) continue;
        if (!row.offsetText.length && !row.enabledText.length) continue;
        [filtered.rows addObject:row];
    }
    return filtered;
}

static NSString *ZNM583Trim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL ZNM583PrepareSliderAuthoring(NSString **error) {
    ZNRuntimeActionStore *store = [ZNRuntimeActionStore sharedStore];
    NSArray<ZNRuntimeMethodAction *> *actions = [store actionsSnapshot];

    for (NSUInteger actionIndex = 0; actionIndex < actions.count; actionIndex++) {
        ZNRuntimeMethodAction *action = actions[actionIndex];
        if (action.argumentControlConfigs.count != action.argumentCount) continue;

        NSMutableArray<NSDictionary<NSString *, id> *> *configs = [action.argumentControlConfigs mutableCopy];
        BOOL changed = NO;
        for (NSUInteger arg = 0; arg < action.argumentCount; arg++) {
            NSDictionary *original = configs[arg];
            if (![original[@"enabled"] boolValue] ||
                ZNRuntimeArgumentControlTypeFromKey(original[@"type"]) != ZNRuntimeArgumentControlTypeSlider) continue;

            NSString *text = arg < action.argumentValues.count ? ZNM583Trim(action.argumentValues[arg]) : @"";
            NSDecimalNumber *number = text.length
                ? [NSDecimalNumber decimalNumberWithString:text locale:@{NSLocaleDecimalSeparator: @"."}]
                : NSDecimalNumber.notANumber;
            double maxValue = number.doubleValue;
            if (!text.length || [number isEqualToNumber:NSDecimalNumber.notANumber] || !isfinite(maxValue) || maxValue <= 0.0) {
                if (error) *error = [NSString stringWithFormat:@"%@ 参数%lu：滑块必须在生成时填写大于 0 的最大值",
                                     action.title.length ? action.title : action.methodName,
                                     (unsigned long)arg + 1];
                return NO;
            }

            NSMutableDictionary *cfg = [original mutableCopy];
            cfg[@"min"] = @0;
            cfg[@"max"] = number;
            cfg[@"step"] = @1;
            cfg[@"default"] = number;
            configs[arg] = [cfg copy];
            changed = YES;
        }

        if (changed) {
            NSString *localError = nil;
            if (![store updateArgumentControlConfigs:configs atIndex:actionIndex error:&localError]) {
                if (error) *error = localError ?: @"Slider 范围写入失败";
                return NO;
            }
        }
    }
    return YES;
}

static BOOL ZNM581AugmentRuntimeOnlySignatures(NSArray<NSString *> *builderOutputs,
                                                NSString **report,
                                                NSString **error) {
    NSString *unity = nil;
    for (NSString *path in builderOutputs ?: @[]) {
        NSString *name = path.lastPathComponent.lowercaseString;
        if ([name containsString:@"unityframework"] && ![name hasSuffix:@".znpatched"] && [NSFileManager.defaultManager fileExistsAtPath:path]) { unity = path; break; }
    }
    if (!unity.length) return ZNRuntimeActionAugmentGeneratedOutputsM46(builderOutputs, report, error);

    NSString *alias = [unity stringByAppendingString:@".znpatched"];
    [NSFileManager.defaultManager removeItemAtPath:alias error:nil];
    NSError *linkError = nil;
    if (![NSFileManager.defaultManager linkItemAtPath:unity toPath:alias error:&linkError]) {
        if (error) *error = [NSString stringWithFormat:@"M5.8.1 Runtime-only Full Signature alias 创建失败：%@", linkError.localizedDescription ?: @"unknown"];
        return NO;
    }
    NSMutableArray<NSString *> *bridged = [builderOutputs mutableCopy] ?: [NSMutableArray array]; [bridged addObject:alias];
    NSString *innerReport = nil, *innerError = nil; BOOL ok = ZNRuntimeActionAugmentGeneratedOutputsM46(bridged, &innerReport, &innerError);
    [NSFileManager.defaultManager removeItemAtPath:alias error:nil];
    if (!ok) { if (error) *error = innerError ?: @"M4.6 Full Signature 写入失败"; return NO; }
    if (report) *report = innerReport.length ? [innerReport stringByAppendingString:@" · M5.8.1 suffixless hard-link bridge"] : @"M5.8.1 Runtime-only Full Signature 完成";
    return YES;
}

@implementation ZNStaticBinaryBuilder

+ (BOOL)buildWorkspace:(ZNBinaryPatchWorkspace *)workspace
               outputs:(NSArray<NSString *> **)outputs
                report:(NSString **)report
                 error:(NSString **)error {
    NSString *sliderError = nil;
    if (!ZNM583PrepareSliderAuthoring(&sliderError)) { if (error) *error = sliderError ?: @"Slider authoring validation failed"; return NO; }

    NSString *typedValidationError = nil;
    NSUInteger typedCount = 0;
    NSArray<NSString *> *typedTargets = ZNValidatedTypedTargets(workspace, &typedCount, &typedValidationError);
    if (!typedTargets) { if (error) *error = typedValidationError ?: @"Typed Offset 验证失败"; return NO; }

    NSArray<ZNRuntimeMethodAction *> *actions = [[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    NSUInteger partialStaticRows = 0;
    NSUInteger completeStaticRows = ZNCompleteStaticRowCount(workspace, &partialStaticRows);
    BOOL typedOnly = typedCount > 0 && completeStaticRows == 0 && actions.count == 0;
    BOOL runtimeOnly = actions.count > 0 && completeStaticRows == 0;
    NSString *mode = typedOnly ? @"typed-only" : (runtimeOnly ? @"runtime-only" : @"static/mixed");

    NSArray<NSString *> *builderOutputs = nil; NSString *builderReport = nil, *builderError = nil;
    if (typedOnly) {
        if (!ZNTypedOnlyBinaryBuilderBuild(typedTargets, &builderOutputs, &builderReport, &builderError)) { if (error) *error = builderError ?: @"M5.11 Typed-only Builder 生成失败"; return NO; }
    } else if (runtimeOnly) {
        if (!ZNRuntimeOnlyBinaryBuilderBuildWorkspace(workspace, &builderOutputs, &builderReport, &builderError)) { if (error) *error = builderError ?: @"Runtime-only Builder 生成失败"; return NO; }
    } else {
        ZNBinaryPatchWorkspace *staticWorkspace = ZNStaticOnlyWorkspace(workspace);
        if (!ZNStaticBinaryBuilderV3BuildWorkspace(staticWorkspace, &builderOutputs, &builderReport, &builderError)) { if (error) *error = builderError ?: @"Static Binary Builder V3 生成失败"; return NO; }
    }

    NSString *actionReport = nil, *actionError = nil;
    if (!ZNRuntimeActionEmbedIntoGeneratedOutputs(builderOutputs ?: @[], &actionReport, &actionError)) { if (error) *error = actionError ?: @"Runtime Method Call 写入失败"; return NO; }

    NSString *typedValueReport = nil, *typedValueError = nil;
    if (!ZNTypedValueEmbedIntoGeneratedOutputs(builderOutputs ?: @[], &typedValueReport, &typedValueError)) { if (error) *error = typedValueError ?: @"M5.11 Typed Value metadata 写入失败"; return NO; }

    NSString *signatureReport = nil, *signatureError = nil; BOOL signatureOK = YES;
    if (actions.count) {
        signatureOK = runtimeOnly ? ZNM581AugmentRuntimeOnlySignatures(builderOutputs ?: @[], &signatureReport, &signatureError)
                                  : ZNRuntimeActionAugmentGeneratedOutputsM46(builderOutputs ?: @[], &signatureReport, &signatureError);
    }
    if (!signatureOK) { if (error) *error = signatureError ?: @"M4.6 Full Method Signature 写入失败"; return NO; }

    NSString *verificationReport = nil;
    if (runtimeOnly) {
        NSString *verificationError = nil;
        if (!ZNM462VerifyRuntimeOnlyOutputs(builderOutputs ?: @[], actions.count, &verificationReport, &verificationError)) { if (error) *error = verificationError ?: @"M4.6.2 Runtime-only Verify 失败"; return NO; }
    }

    NSString *combinedReport = builderReport ?: @"";
    for (NSString *piece in @[actionReport ?: @"", typedValueReport ?: @"", signatureReport ?: @"", verificationReport ?: @""]) {
        if (!piece.length) continue; combinedReport = combinedReport.length ? [combinedReport stringByAppendingFormat:@"\n%@", piece] : piece;
    }
    if ((runtimeOnly || typedOnly) && partialStaticRows) {
        NSString *ignored = [NSString stringWithFormat:@"%@：忽略 %lu 个未完整填写的 Switch Offset 草稿行。", mode, (unsigned long)partialStaticRows];
        combinedReport = combinedReport.length ? [combinedReport stringByAppendingFormat:@"\n%@", ignored] : ignored;
    }

    NSString *postprocessError = nil; BOOL containerOnly = runtimeOnly || typedOnly;
    BOOL postprocessOK = containerOnly ? ZNRuntimeOnlyPostProcessGeneratedOutputsM461(builderOutputs ?: @[], combinedReport, outputs, report, &postprocessError)
                                       : ZNPostProcessGeneratedBinaryOutputs(builderOutputs ?: @[], combinedReport, outputs, report, &postprocessError);
    if (!postprocessOK) { if (error) *error = postprocessError ?: @"生成后二进制后处理失败"; return NO; }

    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[builder-pipeline-m5.11-unified] mode=%@ static=%lu runtime=%lu typed=%lu persist=%@", mode, (unsigned long)completeStaticRows, (unsigned long)actions.count, (unsigned long)typedCount, typedValueReport.length ? typedValueReport : @"none"]];
    return YES;
}

@end
