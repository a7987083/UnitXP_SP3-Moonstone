#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "ZNDeveloperGate.h"

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
    // After swapping, this selector points at the Method Finder UI layer's
    // previously installed category implementation. Preserve its result, then
    // repair the visibility rule for devices that have developer `g` access
    // but do not have the independent Other-category `q` access.
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
    // After swapping, this selector points at the previously installed symbol
    // implementation. It intentionally gives us the pre-binding list.
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
    });
}
