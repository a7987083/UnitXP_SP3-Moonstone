#import "ZNBuilderPolicy.h"

#import "ZNBinaryPatchWorkspace.h"
#import "ZNRuntimeActionModel.h"
#import "ZNNativeHookAction.h"

ZNBuilderPolicyResult ZNBuilderPolicyEvaluate(ZNBuilderPolicyInput input) {
    const BOOL hasRuntime = input.runtimeActionCount > 0 || input.nativeHookCount > 0;
    const BOOL runtimeOnly = hasRuntime && input.completeStaticRows == 0;
    const BOOL hasAnyAuthoring = hasRuntime || input.filledStaticRows > 0;

    ZNBuilderPolicyResult result = {};
    result.hasRuntimeAuthoring = hasRuntime;
    result.runtimeOnly = runtimeOnly;
    result.mode = runtimeOnly
        ? ZNBuilderModeRuntimeOnly
        : (hasAnyAuthoring ? ZNBuilderModeStaticOrMixed : ZNBuilderModeEmpty);

    // Preserve the historical FeatureBuilderUI behavior: any filled Static row
    // or any Runtime/Native authoring enables the button, unless the workspace
    // is currently locked by build/apply state.
    result.authoringUIReady = !input.isBuilding &&
                              !input.hasAnyApplied &&
                              hasAnyAuthoring;

    // Preserve the old M5.7 post-render gate semantics separately. Keeping this
    // explicit prevents a "cleanup" from silently tightening/loosening the
    // main authoring UI contract.
    result.staticValidatedReady = input.completeStaticRows > 0 &&
                                  input.filledStaticRows == input.completeStaticRows &&
                                  input.validatedStaticRows == input.completeStaticRows;
    result.strictGateReady = !input.isBuilding &&
                             !input.hasAnyApplied &&
                             (runtimeOnly || result.staticValidatedReady);
    return result;
}

NSString *ZNBuilderModeName(ZNBuilderMode mode) {
    switch (mode) {
        case ZNBuilderModeRuntimeOnly: return @"runtime-only";
        case ZNBuilderModeStaticOrMixed: return @"static/mixed";
        default: return @"empty";
    }
}

static void ZNBuilderPolicyCountStaticRows(NSArray<ZNBinaryPatchRow *> *rows,
                                           NSUInteger *complete,
                                           NSUInteger *partial) {
    NSUInteger c=0,p=0;
    for (ZNBinaryPatchRow *row in rows ?: @[]) {
        BOOL hasOffset=row.offsetText.length>0;
        BOOL hasEnabled=row.enabledText.length>0;
        if (hasOffset&&hasEnabled)c++;
        else if (hasOffset||hasEnabled)p++;
    }
    if(complete)*complete=c;
    if(partial)*partial=p;
}

ZNBuilderPolicyInput ZNBuilderPolicyCapture(ZNBinaryPatchWorkspace *workspace,
                                            NSUInteger runtimeActionCount,
                                            NSUInteger nativeHookCount) {
    ZNBuilderPolicyInput input = {};
    if (!workspace) return input;
    ZNBuilderPolicyCountStaticRows(workspace.rows,&input.completeStaticRows,&input.partialStaticRows);
    input.filledStaticRows=workspace.filledCount;
    input.validatedStaticRows=workspace.validatedCount;
    input.runtimeActionCount=runtimeActionCount;
    input.nativeHookCount=nativeHookCount;
    input.isBuilding=workspace.isBuilding;
    input.hasAnyApplied=workspace.hasAnyApplied;
    return input;
}

ZNBuilderPolicyInput ZNBuilderPolicyCaptureCurrent(ZNBinaryPatchWorkspace *workspace) {
    NSUInteger runtime=[[ZNRuntimeActionStore sharedStore] actionsSnapshot].count;
    NSUInteger hooks=[[ZNNativeHookStore sharedStore] actionsSnapshot].count;
    return ZNBuilderPolicyCapture(workspace,runtime,hooks);
}
