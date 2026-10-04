#import <Foundation/Foundation.h>
#include <assert.h>
#import "ZNBuilderPolicy.h"

static ZNBuilderPolicyInput ZNInput(NSUInteger completeStatic,
                                    NSUInteger partialStatic,
                                    NSUInteger filledStatic,
                                    NSUInteger validatedStatic,
                                    NSUInteger runtimeActions,
                                    NSUInteger nativeHooks,
                                    BOOL building,
                                    BOOL applied) {
    ZNBuilderPolicyInput i={};
    i.completeStaticRows=completeStatic;
    i.partialStaticRows=partialStatic;
    i.filledStaticRows=filledStatic;
    i.validatedStaticRows=validatedStatic;
    i.runtimeActionCount=runtimeActions;
    i.nativeHookCount=nativeHooks;
    i.isBuilding=building;
    i.hasAnyApplied=applied;
    return i;
}

int main(void) {
    @autoreleasepool {
        ZNBuilderPolicyResult r;

        r=ZNBuilderPolicyEvaluate(ZNInput(0,0,0,0,0,0,NO,NO));
        assert(r.mode==ZNBuilderModeEmpty);
        assert(!r.runtimeOnly);
        assert(!r.authoringUIReady);
        assert(!r.strictGateReady);

        r=ZNBuilderPolicyEvaluate(ZNInput(0,0,0,0,1,0,NO,NO));
        assert(r.mode==ZNBuilderModeRuntimeOnly);
        assert(r.runtimeOnly);
        assert(r.hasRuntimeAuthoring);
        assert(r.authoringUIReady);
        assert(r.strictGateReady);

        r=ZNBuilderPolicyEvaluate(ZNInput(0,0,0,0,0,3,NO,NO));
        assert(r.mode==ZNBuilderModeRuntimeOnly);
        assert(r.runtimeOnly);
        assert(r.authoringUIReady);
        assert(r.strictGateReady);

        r=ZNBuilderPolicyEvaluate(ZNInput(0,2,0,0,0,2,NO,NO));
        assert(r.mode==ZNBuilderModeRuntimeOnly);
        assert(r.runtimeOnly);
        assert(r.authoringUIReady);
        assert(r.strictGateReady);

        r=ZNBuilderPolicyEvaluate(ZNInput(1,0,1,0,0,0,NO,NO));
        assert(r.mode==ZNBuilderModeStaticOrMixed);
        assert(!r.runtimeOnly);
        assert(r.authoringUIReady);
        assert(!r.staticValidatedReady);
        assert(!r.strictGateReady);

        r=ZNBuilderPolicyEvaluate(ZNInput(1,0,1,1,0,0,NO,NO));
        assert(r.mode==ZNBuilderModeStaticOrMixed);
        assert(r.staticValidatedReady);
        assert(r.authoringUIReady);
        assert(r.strictGateReady);

        r=ZNBuilderPolicyEvaluate(ZNInput(1,0,1,1,1,2,NO,NO));
        assert(r.mode==ZNBuilderModeStaticOrMixed);
        assert(!r.runtimeOnly);
        assert(r.authoringUIReady);
        assert(r.strictGateReady);

        r=ZNBuilderPolicyEvaluate(ZNInput(0,0,0,0,0,2,YES,NO));
        assert(r.runtimeOnly);
        assert(!r.authoringUIReady);
        assert(!r.strictGateReady);

        r=ZNBuilderPolicyEvaluate(ZNInput(0,0,0,0,0,2,NO,YES));
        assert(r.runtimeOnly);
        assert(!r.authoringUIReady);
        assert(!r.strictGateReady);

        assert([ZNBuilderModeName(ZNBuilderModeRuntimeOnly) isEqualToString:@"runtime-only"]);
        assert([ZNBuilderModeName(ZNBuilderModeStaticOrMixed) isEqualToString:@"static/mixed"]);
        assert([ZNBuilderModeName(ZNBuilderModeEmpty) isEqualToString:@"empty"]);
    }
    return 0;
}
