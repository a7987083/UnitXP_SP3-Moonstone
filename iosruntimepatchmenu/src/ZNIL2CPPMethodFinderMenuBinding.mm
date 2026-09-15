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
extern "C" void ZNInstallMenuPresentationHostFixDeferred(void);

// Corrects Method Finder category/symbol visibility after the v0.5.7 UI
// swizzles. Method Finder is a developer-authoring surface, so it follows the
// developer `g` authorization and must not depend on the independent `q`
// authorization that owns the Other category.

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
        // Device-verified V2 resolver stays authoritative for Named Offset and
        // single-result authoring. Later layers must not alter that contract.
        ZNInstallIL2CPPMethodFinderSearchV2Deferred();
        ZNInstallIL2CPPMethodFinderZeroVMAddrFixDeferred();

        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;

        Method categoriesOriginal = class_getInstanceMethod(cls, @selector(zn40_baseCategories));
        Method categoriesReplacement = class_getInstanceMethod(cls, @selector(zn57mfb_baseCategories));
        if (categoriesOriginal && categoriesReplacement) {
            method_exchangeImplementations(categoriesOriginal, categoriesReplacement);
        }

        Method symbolsOriginal = class_getInstanceMethod(cls, @selector(zn40_baseSymbols));
        Method symbolsReplacement = class_getInstanceMethod(cls, @selector(zn57mfb_baseSymbols));
        if (symbolsOriginal && symbolsReplacement) {
            method_exchangeImplementations(symbolsOriginal, symbolsReplacement);
        }

        // Preserve the device-accepted M2.2 stack. M3.1 only decorates the
        // existing detail renderer with ABI/signature metadata and does not
        // install a hook or mutate target memory.
        ZNInstallIL2CPPMethodFinderUXV2Deferred();
        ZNInstallIL2CPPMethodFinderV3Deferred();
        ZNInstallIL2CPPMethodFinderPatchBridgeV3Deferred();
        ZNInstallIL2CPPMethodFinderM2Deferred();
        ZNInstallIL2CPPMethodFinderM21CancelUXDeferred();
        ZNInstallIL2CPPMethodFinderM22StableCancelUXDeferred();
        ZNInstallIL2CPPABIDetailUIDeferred();

        // Keep editable menu controls inside the root view-controller
        // hierarchy so UIKit Translate / Look Up / Share presentation is not
        // obscured or reparented by the menu's periodic window tracking.
        ZNInstallMenuPresentationHostFixDeferred();

        ZNInstallFeatureBuilderControlsV2Deferred();
        ZNInstallFeatureRuntimeControlsV2Deferred();
    });
}
