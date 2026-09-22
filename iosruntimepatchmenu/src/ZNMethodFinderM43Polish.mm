#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNPatchCore.h"

static const NSInteger kZNM43PolishLimitTag = 643001;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
- (void)zn60v3_renderSearchAtWidth:(CGFloat)width;
- (void)zn60v3_renderResultsAtWidth:(CGFloat)width;
- (NSString *)znm43_selectedAssembly;
@end

static NSString *ZNM43PolishAssemblyDisplay(NSString *assembly) {
    NSString *value = assembly ?: @"";
    return [value.lowercaseString hasSuffix:@".dll"] && value.length > 4
        ? [value substringToIndex:value.length - 4] : value;
}

static void ZNM43PolishHideAssemblyLabels(UIView *root, NSString *display) {
    if (!root || !display.length) return;
    for (UIView *view in root.subviews) {
        if ([view isKindOfClass:UILabel.class]) {
            UILabel *label = (UILabel *)view;
            if ([label.text isEqualToString:display]) label.hidden = YES;
        }
        ZNM43PolishHideAssemblyLabels(view, display);
    }
}

@interface ZNRuntimeMenuControllerV040 (ZNMethodFinderM43Polish)
- (void)znm43p_renderSearchAtWidth:(CGFloat)width;
- (void)znm43p_renderResultsAtWidth:(CGFloat)width;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNMethodFinderM43Polish)

- (void)znm43p_renderSearchAtWidth:(CGFloat)width {
    [self znm43p_renderSearchAtWidth:width];
    UITextField *limit = (UITextField *)[self.contentView viewWithTag:kZNM43PolishLimitTag];
    if ([limit isKindOfClass:UITextField.class]) {
        limit.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        limit.returnKeyType = UIReturnKeyDone;
    }
}

- (void)znm43p_renderResultsAtWidth:(CGFloat)width {
    [self znm43p_renderResultsAtWidth:width];
    NSString *assembly = [self znm43_selectedAssembly];
    if (!assembly.length) return;
    ZNM43PolishHideAssemblyLabels(self.contentView, ZNM43PolishAssemblyDisplay(assembly));
}

@end

static void ZNM43PolishSwap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallMethodFinderM43PolishDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNM43PolishSwap(cls, @selector(zn60v3_renderSearchAtWidth:), @selector(znm43p_renderSearchAtWidth:));
        ZNM43PolishSwap(cls, @selector(zn60v3_renderResultsAtWidth:), @selector(znm43p_renderResultsAtWidth:));
        [[ZNRuntimeLogger sharedLogger] log:@"[m4.3-polish] Done keyboard + deduplicated single-Assembly result labels installed"];
    });
}
