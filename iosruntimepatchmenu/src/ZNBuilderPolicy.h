#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, ZNBuilderMode) {
    ZNBuilderModeEmpty = 0,
    ZNBuilderModeRuntimeOnly,
    ZNBuilderModeStaticOrMixed,
};

typedef struct {
    NSUInteger completeStaticRows;
    NSUInteger partialStaticRows;
    NSUInteger filledStaticRows;
    NSUInteger validatedStaticRows;
    NSUInteger runtimeActionCount;
    NSUInteger nativeHookCount;
    BOOL isBuilding;
    BOOL hasAnyApplied;
} ZNBuilderPolicyInput;

typedef struct {
    ZNBuilderMode mode;
    BOOL hasRuntimeAuthoring;
    BOOL runtimeOnly;
    BOOL staticValidatedReady;
    BOOL authoringUIReady;
    BOOL strictGateReady;
} ZNBuilderPolicyResult;

static inline ZNBuilderPolicyResult ZNBuilderPolicyEvaluate(ZNBuilderPolicyInput input) {
    const BOOL hasRuntime=input.runtimeActionCount>0||input.nativeHookCount>0;
    const BOOL runtimeOnly=hasRuntime&&input.completeStaticRows==0;
    const BOOL hasAnyAuthoring=hasRuntime||input.filledStaticRows>0;

    ZNBuilderPolicyResult result={};
    result.hasRuntimeAuthoring=hasRuntime;
    result.runtimeOnly=runtimeOnly;
    result.mode=runtimeOnly?ZNBuilderModeRuntimeOnly:(hasAnyAuthoring?ZNBuilderModeStaticOrMixed:ZNBuilderModeEmpty);
    result.authoringUIReady=!input.isBuilding&&!input.hasAnyApplied&&hasAnyAuthoring;
    result.staticValidatedReady=input.completeStaticRows>0&&
                                input.filledStaticRows==input.completeStaticRows&&
                                input.validatedStaticRows==input.completeStaticRows;
    result.strictGateReady=!input.isBuilding&&!input.hasAnyApplied&&
                           (runtimeOnly||result.staticValidatedReady);
    return result;
}

static inline NSString *ZNBuilderModeName(ZNBuilderMode mode) {
    switch(mode) {
        case ZNBuilderModeRuntimeOnly:return @"runtime-only";
        case ZNBuilderModeStaticOrMixed:return @"static/mixed";
        default:return @"empty";
    }
}

@class ZNBinaryPatchWorkspace;
FOUNDATION_EXPORT ZNBuilderPolicyInput ZNBuilderPolicyCapture(
    ZNBinaryPatchWorkspace *workspace,
    NSUInteger runtimeActionCount,
    NSUInteger nativeHookCount);
FOUNDATION_EXPORT ZNBuilderPolicyInput ZNBuilderPolicyCaptureCurrent(
    ZNBinaryPatchWorkspace *workspace);

NS_ASSUME_NONNULL_END
