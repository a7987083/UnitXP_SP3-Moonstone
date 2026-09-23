#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "ZNDeveloperGate.h"

extern "C" void ZNInstallIL2CPPMethodFinderSearchV2Deferred(void);
extern "C" void ZNInstallIL2CPPMethodFinderZeroVMAddrFixDeferred(void);
extern "C" void ZNInstallIL2CPPMethodFinderUXV2Deferred(void);
extern "C" void ZNInstallIL2CPPMethodFinderV3Deferred(void);
extern "C" void ZNInstallIL2CPPMethodFinderPatchBridgeV3Deferred(void);
extern "C" void ZNInstallIL2CPPMethodFinderM2Deferred(void);
extern "C" void ZNInstallIL2CPPMethodFinderM21CancelUXDeferred(void);
extern "C" void ZNInstallIL2CPPMethodFinderM22StableCancelUXDeferred(void);
extern "C" void ZNInstallIL2CPPABIDetailUIDeferred(void);
extern "C" void ZNInstallFeatureBuilderControlsV2Deferred(void);
extern "C" void ZNInstallFeatureRuntimeControlsV2Deferred(void);
extern "C" void ZNInstallOffsetResolverV2Deferred(void);
extern "C" void ZNInstallBinaryPatchWorkspaceAddressV2Deferred(void);
extern "C" void ZNInstallRuntimeMenuModalShellDeferred(void);
extern "C" void ZNInstallRuntimeMethodCallDeferred(void);
extern "C" void ZNInstallUXFixesV2Deferred(void);
extern "C" void ZNInstallMethodFinderM43UIDeferred(void);
extern "C" void ZNInstallMethodFinderM43PolishDeferred(void);
extern "C" void ZNInstallInstanceSelectionV2UIDeferred(void);
extern "C" void ZNInstallM441HotfixDeferred(void);
extern "C" void ZNInstallM442SearchRestoreDeferred(void);
extern "C" void ZNInstallM45AddressOwningMethodDeferred(void);
extern "C" void ZNInstallM46SignatureExecutionDeferred(void);
extern "C" void ZNInstallM46FullSignatureUIDeferred(void);
extern "C" void ZNInstallM461PolishDeferred(void);
extern "C" void ZNInstallM462InstanceSafetyDeferred(void);
extern "C" void ZNInstallM462CandidateBindingUIDeferred(void);
extern "C" void ZNInstallM47ReceiverCaptureUIDeferred(void);
extern "C" void ZNInstallM47MultiArgInvokeDeferred(void);
extern "C" void ZNInstallM47MultiArgUIDeferred(void);
extern "C" void ZNInstallM47BuilderArgsUIDeferred(void);
extern "C" void ZNInstallM47VersionUIDeferred(void);

@interface ZNRuntimeMenuControllerV040 : NSObject
- (NSArray<NSString *> *)zn40_baseCategories;
@end

@interface ZNRuntimeMenuControllerV040 (ZNIL2CPPMethodFinderMenuBinding)
- (NSArray<NSString *> *)zn57mfb_baseCategories;
- (NSArray<NSString *> *)zn57mfb_baseSymbols;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNIL2CPPMethodFinderMenuBinding)

- (NSArray<NSString *> *)zn57mfb_baseCategories {
    NSArray<NSString *> *base = [self zn57mfb_baseCategories];
    if ([base containsObject:@"方法查找"] || ![ZNDeveloperGate sharedGate].authorized) return base;
    NSMutableArray<NSString *> *items = [base mutableCopy];
    NSUInteger other = [items indexOfObject:@"其他"];
    NSUInteger settings = [items indexOfObject:@"设置"];
    NSUInteger insertion = items.count;
    if (other != NSNotFound) insertion = MIN(other + 1, items.count);
    else if (settings != NSNotFound) insertion = settings;
    else if (items.count > 0) insertion = 1;
    [items insertObject:@"方法查找" atIndex:insertion];
    return items;
}

- (NSArray<NSString *> *)zn57mfb_baseSymbols {
    NSArray<NSString *> *base = [self zn57mfb_baseSymbols];
    NSArray<NSString *> *categories = [self zn40_baseCategories];
    if (base.count == categories.count) return base;
    NSUInteger finder = [categories indexOfObject:@"方法查找"];
    if (finder == NSNotFound || finder > base.count) return base;
    NSMutableArray<NSString *> *symbols = [base mutableCopy];
    [symbols insertObject:@"magnifyingglass" atIndex:finder];
    return symbols;
}

@end

extern "C" void ZNInstallIL2CPPMethodFinderMenuBindingDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ZNInstallIL2CPPMethodFinderSearchV2Deferred();
        ZNInstallIL2CPPMethodFinderZeroVMAddrFixDeferred();

        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;

        Method categoriesOriginal = class_getInstanceMethod(cls, @selector(zn40_baseCategories));
        Method categoriesReplacement = class_getInstanceMethod(cls, @selector(zn57mfb_baseCategories));
        if (categoriesOriginal && categoriesReplacement) method_exchangeImplementations(categoriesOriginal, categoriesReplacement);

        Method symbolsOriginal = class_getInstanceMethod(cls, @selector(zn40_baseSymbols));
        Method symbolsReplacement = class_getInstanceMethod(cls, @selector(zn57mfb_baseSymbols));
        if (symbolsOriginal && symbolsReplacement) method_exchangeImplementations(symbolsOriginal, symbolsReplacement);

        ZNInstallIL2CPPMethodFinderUXV2Deferred();
        ZNInstallIL2CPPMethodFinderV3Deferred();
        ZNInstallIL2CPPMethodFinderPatchBridgeV3Deferred();
        ZNInstallIL2CPPMethodFinderM2Deferred();
        ZNInstallIL2CPPMethodFinderM21CancelUXDeferred();
        ZNInstallIL2CPPMethodFinderM22StableCancelUXDeferred();
        ZNInstallIL2CPPABIDetailUIDeferred();
        ZNInstallFeatureBuilderControlsV2Deferred();
        ZNInstallFeatureRuntimeControlsV2Deferred();

        ZNInstallOffsetResolverV2Deferred();
        ZNInstallBinaryPatchWorkspaceAddressV2Deferred();
        ZNInstallRuntimeMenuModalShellDeferred();
        ZNInstallRuntimeMethodCallDeferred();
        ZNInstallUXFixesV2Deferred();
        ZNInstallMethodFinderM43UIDeferred();
        ZNInstallMethodFinderM43PolishDeferred();

        ZNInstallInstanceSelectionV2UIDeferred();
        ZNInstallM441HotfixDeferred();
        ZNInstallM442SearchRestoreDeferred();
        ZNInstallM45AddressOwningMethodDeferred();
        ZNInstallM46SignatureExecutionDeferred();
        ZNInstallM46FullSignatureUIDeferred();
        ZNInstallM461PolishDeferred();
        ZNInstallM462InstanceSafetyDeferred();
        ZNInstallM462CandidateBindingUIDeferred();

        // M4.7 layers are outermost. Receiver capture observes the real method
        // entry and stores x0/this through the M4.6.2 GCHandle-backed selection
        // path. Multi-arg invocation consumes exact full-signature candidates
        // and exposes dynamic /2-/8 parameter rows without disturbing /0-/1.
        ZNInstallM47ReceiverCaptureUIDeferred();
        ZNInstallM47MultiArgInvokeDeferred();
        ZNInstallM47MultiArgUIDeferred();
        ZNInstallM47BuilderArgsUIDeferred();
        ZNInstallM47VersionUIDeferred();
    });
}
