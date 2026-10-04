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

FOUNDATION_EXPORT ZNBuilderPolicyResult ZNBuilderPolicyEvaluate(ZNBuilderPolicyInput input);
FOUNDATION_EXPORT NSString *ZNBuilderModeName(ZNBuilderMode mode);

@class ZNBinaryPatchWorkspace;
FOUNDATION_EXPORT ZNBuilderPolicyInput ZNBuilderPolicyCapture(
    ZNBinaryPatchWorkspace *workspace,
    NSUInteger runtimeActionCount,
    NSUInteger nativeHookCount);
FOUNDATION_EXPORT ZNBuilderPolicyInput ZNBuilderPolicyCaptureCurrent(
    ZNBinaryPatchWorkspace *workspace);

NS_ASSUME_NONNULL_END
