#import "ZNStaticBinaryBuilder.h"
#import "ZNStaticBinaryBuilderV3Internal.h"
#import "ZNGeneratedBinaryPostprocess.h"
#import "ZNRuntimeOnlyBinaryBuilder.h"
#import "ZNM462RuntimeOnlyVerifier.h"
#import "ZNBinaryPatchWorkspace.h"
#import "ZNRuntimeActionBuilder.h"
#import "ZNRuntimeActionModel.h"
#import "ZNRuntimeActionSignaturePostprocess.h"
#import "ZNPatchCore.h"

static NSUInteger ZNCompleteStaticRowCount(ZNBinaryPatchWorkspace *workspace,
                                           NSUInteger *partialRows) {
    NSUInteger complete = 0;
    NSUInteger partial = 0;
    for (ZNBinaryPatchRow *row in workspace.rows ?: @[]) {
        BOOL hasOffset = row.offsetText.length > 0;
        BOOL hasEnabled = row.enabledText.length > 0;
        if (hasOffset && hasEnabled) complete++;
        else if (hasOffset || hasEnabled) partial++;
    }
    if (partialRows) *partialRows = partial;
    return complete;
}

static BOOL ZNM581AugmentRuntimeOnlySignatures(NSArray<NSString *> *builderOutputs,
                                                NSString **report,
                                                NSString **error) {
    NSString *unity = nil;
    for (NSString *path in builderOutputs ?: @[]) {
        NSString *name = path.lastPathComponent.lowercaseString;
        if ([name containsString:@"unityframework"] &&
            ![name hasSuffix:@".znpatched"] &&
            [NSFileManager.defaultManager fileExistsAtPath:path]) {
            unity = path;
            break;
        }
    }
    if (!unity.length) return ZNRuntimeActionAugmentGeneratedOutputsM46(builderOutputs, report, error);

    NSString *alias = [unity stringByAppendingString:@".znpatched"];
    [NSFileManager.defaultManager removeItemAtPath:alias error:nil];
    NSError *linkError = nil;
    if (![NSFileManager.defaultManager linkItemAtPath:unity toPath:alias error:&linkError]) {
        if (error) *error = [NSString stringWithFormat:@"M5.8.1 Runtime-only Full Signature alias 创建失败：%@", linkError.localizedDescription ?: @"unknown"];
        return NO;
    }

    NSMutableArray<NSString *> *bridged = [builderOutputs mutableCopy] ?: [NSMutableArray array];
    [bridged addObject:alias];
    NSString *innerReport = nil;
    NSString *innerError = nil;
    BOOL ok = ZNRuntimeActionAugmentGeneratedOutputsM46(bridged, &innerReport, &innerError);
    [NSFileManager.defaultManager removeItemAtPath:alias error:nil];

    if (!ok) {
        if (error) *error = innerError ?: @"M4.6 Full Signature 写入失败";
        return NO;
    }
    if (report) *report = innerReport.length ? [innerReport stringByAppendingString:@" · M5.8.1 suffixless hard-link bridge"] : @"M5.8.1 Runtime-only Full Signature 完成";
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m5.8.1-runtimeonly-signature] suffixless=%@ alias=%@ success", unity.lastPathComponent, alias.lastPathComponent]];
    return YES;
}

@implementation ZNStaticBinaryBuilder

+ (BOOL)buildWorkspace:(ZNBinaryPatchWorkspace *)workspace
               outputs:(NSArray<NSString *> **)outputs
                report:(NSString **)report
                 error:(NSString **)error {
    NSArray<ZNRuntimeMethodAction *> *actions = [[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    NSUInteger partialStaticRows = 0;
    NSUInteger completeStaticRows = ZNCompleteStaticRowCount(workspace, &partialStaticRows);
    BOOL runtimeOnly = actions.count > 0 && completeStaticRows == 0;

    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:
        @"[builder-mode-m5.8.1] runtime=%lu completeStatic=%lu partialStatic=%lu mode=%@",
        (unsigned long)actions.count,
        (unsigned long)completeStaticRows,
        (unsigned long)partialStaticRows,
        runtimeOnly ? @"runtime-only" : @"static/mixed"]];

    NSArray<NSString *> *builderOutputs = nil;
    NSString *builderReport = nil;
    NSString *builderError = nil;

    if (runtimeOnly) {
        if (!ZNRuntimeOnlyBinaryBuilderBuildWorkspace(workspace, &builderOutputs, &builderReport, &builderError)) {
            if (error) *error = builderError ?: @"Runtime-only Builder 生成失败";
            return NO;
        }
    } else {
        if (!ZNStaticBinaryBuilderV3BuildWorkspace(workspace, &builderOutputs, &builderReport, &builderError)) {
            if (error) *error = builderError ?: @"Static Binary Builder V3 生成失败";
            return NO;
        }
    }

    NSString *actionReport = nil;
    NSString *actionError = nil;
    if (!ZNRuntimeActionEmbedIntoGeneratedOutputs(builderOutputs ?: @[], &actionReport, &actionError)) {
        if (error) *error = actionError ?: @"Runtime Method Call 写入失败";
        return NO;
    }

    NSString *signatureReport = nil;
    NSString *signatureError = nil;
    BOOL signatureOK = runtimeOnly
        ? ZNM581AugmentRuntimeOnlySignatures(builderOutputs ?: @[], &signatureReport, &signatureError)
        : ZNRuntimeActionAugmentGeneratedOutputsM46(builderOutputs ?: @[], &signatureReport, &signatureError);
    if (!signatureOK) {
        if (error) *error = signatureError ?: @"M4.6 Full Method Signature 写入失败";
        return NO;
    }

    NSString *verificationReport = nil;
    if (runtimeOnly) {
        NSString *verificationError = nil;
        if (!ZNM462VerifyRuntimeOnlyOutputs(builderOutputs ?: @[], actions.count, &verificationReport, &verificationError)) {
            if (error) *error = verificationError ?: @"M4.6.2 Runtime-only Verify 失败";
            return NO;
        }
    }

    NSString *combinedReport = builderReport ?: @"";
    for (NSString *piece in @[actionReport ?: @"", signatureReport ?: @"", verificationReport ?: @""]) {
        if (!piece.length) continue;
        combinedReport = combinedReport.length ? [combinedReport stringByAppendingFormat:@"\n%@", piece] : piece;
    }
    if (runtimeOnly && partialStaticRows) {
        NSString *ignored = [NSString stringWithFormat:@"M5.8.1 Runtime-only：忽略 %lu 个未完整填写的 Offset/Enabled 草稿行。", (unsigned long)partialStaticRows];
        combinedReport = combinedReport.length ? [combinedReport stringByAppendingFormat:@"\n%@", ignored] : ignored;
    }

    NSString *postprocessError = nil;
    BOOL postprocessOK = runtimeOnly
        ? ZNRuntimeOnlyPostProcessGeneratedOutputsM461(builderOutputs ?: @[], combinedReport, outputs, report, &postprocessError)
        : ZNPostProcessGeneratedBinaryOutputs(builderOutputs ?: @[], combinedReport, outputs, report, &postprocessError);
    if (!postprocessOK) {
        if (error) *error = postprocessError ?: @"生成后二进制后处理失败";
        return NO;
    }

    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[builder-pipeline] mode=%@ completeStatic=%lu partialStatic=%lu runtime=%lu",
                                         runtimeOnly ? @"runtime-only-m5.8.1" : @"static/mixed-v3",
                                         (unsigned long)completeStaticRows,
                                         (unsigned long)partialStaticRows,
                                         (unsigned long)actions.count]];
    return YES;
}

@end
