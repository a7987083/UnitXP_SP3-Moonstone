#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNRuntimeActionModel.h"
#import "ZNPatchCore.h"

// M5.7 Builder gate: Runtime-only is a first-class build mode. The historical
// Feature Builder enabled the build button only when workspace.filledCount > 0,
// which forced Runtime Method authoring to depend on a Static Offset row.
//
// This post-render gate does not change the Builder pipeline itself. It only
// reflects the same mode rule used by ZNStaticBinaryPipeline:
//   Runtime Actions > 0 && complete Static rows == 0 -> Runtime-only.
// A complete Static row requires both Offset and Enabled.

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
- (void)zn50b_renderOther;
@end

static NSUInteger ZNM57CompleteStaticRows(ZNBinaryPatchWorkspace *workspace) {
    NSUInteger count = 0;
    for (ZNBinaryPatchRow *row in workspace.rows ?: @[]) {
        if (row.offsetText.length > 0 && row.enabledText.length > 0) count++;
    }
    return count;
}

static UIButton *ZNM57FindBuildButton(UIView *root) {
    for (UIView *view in root.subviews ?: @[]) {
        if ([view isKindOfClass:UIButton.class]) {
            NSString *title = [(UIButton *)view titleForState:UIControlStateNormal] ?: @"";
            if ([title isEqualToString:@"生成新二进制"] || [title isEqualToString:@"正在生成…"]) return (UIButton *)view;
        }
        UIButton *nested = ZNM57FindBuildButton(view);
        if (nested) return nested;
    }
    return nil;
}

@interface ZNRuntimeMenuControllerV040 (ZNM57RuntimeOnlyBuilderGate)
- (void)znm57_renderOtherWithRuntimeOnlyGate;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM57RuntimeOnlyBuilderGate)
- (void)znm57_renderOtherWithRuntimeOnlyGate {
    [self znm57_renderOtherWithRuntimeOnlyGate];

    UIButton *build = ZNM57FindBuildButton(self.contentView);
    if (!build) return;

    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    NSUInteger completeStatic = ZNM57CompleteStaticRows(workspace);
    NSUInteger runtimeActions = [[ZNRuntimeActionStore sharedStore] actionsSnapshot].count;
    BOOL runtimeOnlyReady = runtimeActions > 0 && completeStatic == 0;
    BOOL staticReady = completeStatic > 0 &&
                       workspace.filledCount == completeStatic &&
                       workspace.validatedCount == completeStatic;

    build.enabled = !workspace.isBuilding &&
                    !workspace.hasAnyApplied &&
                    (runtimeOnlyReady || staticReady);
    build.alpha = build.enabled ? 1.0 : 0.5;

    if (runtimeOnlyReady) {
        build.accessibilityHint = @"Runtime-only：无需 Static Offset Patch";
    }
}
@end

extern "C" void ZNInstallM57RuntimeOnlyBuilderGateDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        Method current = class_getInstanceMethod(cls, @selector(zn50b_renderOther));
        Method gate = class_getInstanceMethod(cls, @selector(znm57_renderOtherWithRuntimeOnlyGate));
        if (current && gate) method_exchangeImplementations(current, gate);
        [[ZNRuntimeLogger sharedLogger] log:@"[m5.7-builder-gate] Runtime-only build enabled with zero complete Static rows; partial drafts ignored"];
    });
}
