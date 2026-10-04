#import "ZNBuilderPolicy.h"

#import "ZNBinaryPatchWorkspace.h"
#import "ZNRuntimeActionModel.h"
#import "ZNNativeHookAction.h"

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
