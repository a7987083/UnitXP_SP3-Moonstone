#import "ZNStaticBinaryBuilder.h"
#import "ZNStaticBinaryBuilderV3Internal.h"
#import "ZNGeneratedBinaryPostprocess.h"
#import "ZNRuntimeOnlyBinaryBuilder.h"
#import "ZNBinaryPatchWorkspace.h"
#import "ZNRuntimeActionBuilder.h"
#import "ZNRuntimeActionModel.h"
#import "ZNRuntimeActionSignaturePostprocess.h"

// ZonoPatch v0.5.4 Builder Consolidation + M4.6.1 runtime-only route.
//
// Public buildWorkspace stays single-entry. Static/mixed builds keep the proven
// V3 pipeline. A workspace with zero Static Patch rows but one or more Runtime
// Method Actions uses an owned-data-only Mach-O container, so no dummy Static
// Patch, validation gate, or temporary Runtime Patch restoration is required.
@implementation ZNStaticBinaryBuilder

+ (BOOL)buildWorkspace:(ZNBinaryPatchWorkspace *)workspace
               outputs:(NSArray<NSString *> **)outputs
                report:(NSString **)report
                 error:(NSString **)error {
    NSArray<ZNRuntimeMethodAction *> *actions = [[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    BOOL runtimeOnly = actions.count > 0 && workspace.filledCount == 0;

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

    // M4.6 extends the existing Runtime Action string pool in-place. This runs
    // after the M4 table is embedded, while the generated output is still an
    // unsigned Builder artifact, so final postprocess/signing covers the exact
    // signature metadata too. Entry/header sizes and version remain unchanged.
    NSString *signatureReport = nil;
    NSString *signatureError = nil;
    if (!ZNRuntimeActionAugmentGeneratedOutputsM46(builderOutputs ?: @[],
                                                   &signatureReport,
                                                   &signatureError)) {
        if (error) *error = signatureError ?: @"M4.6 Full Method Signature 写入失败";
        return NO;
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

    NSString *postprocessError = nil;
    BOOL postprocessOK = runtimeOnly
        ? ZNRuntimeOnlyPostProcessGeneratedOutputsM461(builderOutputs ?: @[], combinedReport, outputs, report, &postprocessError)
        : ZNPostProcessGeneratedBinaryOutputs(builderOutputs ?: @[], combinedReport, outputs, report, &postprocessError);
    if (!postprocessOK) {
        if (error) *error = postprocessError ?: @"生成后二进制后处理失败";
        return NO;
    }

    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[builder-pipeline] mode=%@ static=%lu runtime=%lu",
                                         runtimeOnly ? @"runtime-only-m4.6.1" : @"static/mixed-v3",
                                         (unsigned long)workspace.filledCount,
                                         (unsigned long)actions.count]];
    return YES;
}

@end
