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

// ZonoPatch v0.5.6.2 Builder mode gate.
//
// IMPORTANT: workspace.filledCount is intentionally NOT used to decide whether
// the output is Static/Mixed. filledCount counts a row when either Offset OR
// Enabled has text, so a stale/half-edited Builder row can incorrectly divert a
// Runtime-only build into Static V3 postprocess. A Static intent is considered
// real only when both Offset and Enabled are present.
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
        @"[builder-mode-m5.6.2] runtime=%lu completeStatic=%lu partialStatic=%lu mode=%@",
        (unsigned long)actions.count,
        (unsigned long)completeStaticRows,
        (unsigned long)partialStaticRows,
        runtimeOnly ? @"runtime-only" : @"static/mixed"]];

    NSArray<NSString *> *builderOutputs = nil;
    NSString *builderReport = nil;
    NSString *builderError = nil;

    if (runtimeOnly) {
        if (!ZNRuntimeOnlyBinaryBuilderBuildWorkspace(workspace,
                                                      &builderOutputs,
                                                      &builderReport,
                                                      &builderError)) {
            if (error) *error = builderError ?: @"Runtime-only Builder 生成失败";
            return NO;
        }
    } else {
        if (!ZNStaticBinaryBuilderV3BuildWorkspace(workspace,
                                                   &builderOutputs,
                                                   &builderReport,
                                                   &builderError)) {
            if (error) *error = builderError ?: @"Static Binary Builder V3 生成失败";
            return NO;
        }
    }

    NSString *actionReport = nil;
    NSString *actionError = nil;
    if (!ZNRuntimeActionEmbedIntoGeneratedOutputs(builderOutputs ?: @[],
                                                  &actionReport,
                                                  &actionError)) {
        if (error) *error = actionError ?: @"Runtime Method Call 写入失败";
        return NO;
    }

    NSString *signatureReport = nil;
    NSString *signatureError = nil;
    if (!ZNRuntimeActionAugmentGeneratedOutputsM46(builderOutputs ?: @[],
                                                   &signatureReport,
                                                   &signatureError)) {
        if (error) *error = signatureError ?: @"M4.6 Full Method Signature 写入失败";
        return NO;
    }

    NSString *verificationReport = nil;
    if (runtimeOnly) {
        NSString *verificationError = nil;
        if (!ZNM462VerifyRuntimeOnlyOutputs(builderOutputs ?: @[],
                                            actions.count,
                                            &verificationReport,
                                            &verificationError)) {
            if (error) *error = verificationError ?: @"M4.6.2 Runtime-only Verify 失败";
            return NO;
        }
    }

    NSString *combinedReport = builderReport ?: @"";
    if (actionReport.length) {
        combinedReport = combinedReport.length
            ? [combinedReport stringByAppendingFormat:@"\n%@", actionReport]
            : actionReport;
    }
    if (signatureReport.length) {
        combinedReport = combinedReport.length
            ? [combinedReport stringByAppendingFormat:@"\n%@", signatureReport]
            : signatureReport;
    }
    if (verificationReport.length) {
        combinedReport = combinedReport.length
            ? [combinedReport stringByAppendingFormat:@"\n%@", verificationReport]
            : verificationReport;
    }
    if (runtimeOnly && partialStaticRows) {
        NSString *ignored = [NSString stringWithFormat:@"M5.6.2 Runtime-only：忽略 %lu 个未完整填写的 Offset/Enabled 草稿行。",
                             (unsigned long)partialStaticRows];
        combinedReport = combinedReport.length
            ? [combinedReport stringByAppendingFormat:@"\n%@", ignored]
            : ignored;
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
                                         runtimeOnly ? @"runtime-only-m4.6.2-verified" : @"static/mixed-v3",
                                         (unsigned long)completeStaticRows,
                                         (unsigned long)partialStaticRows,
                                         (unsigned long)actions.count]];
    return YES;
}

@end
