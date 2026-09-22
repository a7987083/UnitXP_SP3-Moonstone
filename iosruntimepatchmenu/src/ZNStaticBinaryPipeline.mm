#import "ZNStaticBinaryBuilder.h"
#import "ZNStaticBinaryBuilderV3Internal.h"
#import "ZNGeneratedBinaryPostprocess.h"
#import "ZNBinaryPatchWorkspace.h"
#import "ZNRuntimeActionBuilder.h"
#import "ZNRuntimeActionSignaturePostprocess.h"

// ZonoPatch v0.5.4 Builder Consolidation.
//
// There is exactly one public buildWorkspace implementation and its stage order
// is explicit in source. Builder selection no longer depends on runtime swizzle
// hooks, constructor ordering, or a delayed main-queue wrapper.
@implementation ZNStaticBinaryBuilder

+ (BOOL)buildWorkspace:(ZNBinaryPatchWorkspace *)workspace
               outputs:(NSArray<NSString *> **)outputs
                report:(NSString **)report
                 error:(NSString **)error {
    NSArray<NSString *> *builderOutputs = nil;
    NSString *builderReport = nil;
    NSString *builderError = nil;

    if (!ZNStaticBinaryBuilderV3BuildWorkspace(workspace,
                                               &builderOutputs,
                                               &builderReport,
                                               &builderError)) {
        if (error) *error = builderError ?: @"Static Binary Builder V3 生成失败";
        return NO;
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
    if (!ZNPostProcessGeneratedBinaryOutputs(builderOutputs ?: @[],
                                             combinedReport,
                                             outputs,
                                             report,
                                             &postprocessError)) {
        if (error) *error = postprocessError ?: @"生成后二进制后处理失败";
        return NO;
    }
    return YES;
}

@end
