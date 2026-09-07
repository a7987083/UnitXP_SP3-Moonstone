#include "ZonoeRuntimeMenuV0402.mm"
#import "ZNExecutablePageProbe.h"

// v0.4.2 UI/diagnostics layer:
// - diagnostic/debug info rows wrap instead of shrinking/truncating
// - the existing self-test button also runs the real __TEXT RX->RW->RX probe

@interface ZNRuntimeMenuControllerV040 (V042)
- (void)zn42_addInfoCard:(NSString *)title lines:(NSArray<NSString *> *)lines y:(CGFloat *)y width:(CGFloat)width;
- (void)zn42_selfTest:(id)sender;
- (void)zn42_makeUI:(UIWindow *)window;
@end

@implementation ZNRuntimeMenuControllerV040 (V042)

- (void)zn42_addInfoCard:(NSString *)title lines:(NSArray<NSString *> *)lines y:(CGFloat *)y width:(CGFloat)width {
    CGFloat cardWidth = MAX(0.0, width - 20.0);
    CGFloat textWidth = MAX(20.0, cardWidth - 26.0);
    UIFont *font = [self menuFont:9.8 weight:UIFontWeightRegular];
    NSMutableArray<NSNumber *> *heights = [NSMutableArray arrayWithCapacity:lines.count];
    CGFloat bodyHeight = 0.0;

    for (NSString *line in lines) {
        CGRect r = [line boundingRectWithSize:CGSizeMake(textWidth, CGFLOAT_MAX)
                                      options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                   attributes:@{NSFontAttributeName:font}
                                      context:nil];
        CGFloat h = MAX(17.0, ceil(CGRectGetHeight(r)) + 3.0);
        [heights addObject:@(h)];
        bodyHeight += h;
    }

    CGFloat h = 30.0 + bodyHeight + 8.0;
    UIView *card = [self cardAtY:*y height:h width:width compact:NO];
    UILabel *t = [self label:title size:12.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    t.frame = CGRectMake(13,7,card.bounds.size.width-26,19);
    [card addSubview:t];

    CGFloat ly = 28.0;
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *line = lines[i];
        CGFloat lineHeight = heights[i].doubleValue;
        UILabel *l = [self label:line size:9.8 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        l.frame = CGRectMake(13, ly, card.bounds.size.width-26, lineHeight);
        l.numberOfLines = 0;
        l.lineBreakMode = NSLineBreakByWordWrapping;
        l.adjustsFontSizeToFitWidth = NO;
        [card addSubview:l];
        ly += lineHeight;
    }

    [self.contentView addSubview:card];
    *y += h + 8.0;
}

- (void)zn42_selfTest:(id)sender {
    [self zn42_selfTest:sender];
    CFAbsoluteTime begin = CFAbsoluteTimeGetCurrent();
    BOOL supported = [[ZNExecutablePageProbe sharedProbe] runProbe];
    double totalMs = (CFAbsoluteTimeGetCurrent() - begin) * 1000.0;
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[probe][%@] __TEXT RX→RW→RX %@ total=%.2fms detail=%@",
                                         NSThread.isMainThread?@"main":@"bg",
                                         supported?@"PASS":@"UNSUPPORTED/FAIL",
                                         totalMs,
                                         [ZNExecutablePageProbe sharedProbe].lastResult ?: @""]];
    [self renderPage];
}

- (void)zn42_makeUI:(UIWindow *)window {
    [self zn42_makeUI:window];
    self.footerLabel.text = [NSString stringWithFormat:@"PatchCore 0.4.2    No JIT    iOS %@", UIDevice.currentDevice.systemVersion];
}

@end

static void ZNSwapInstanceMethodV042(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

__attribute__((constructor(105))) static void ZNInstallV042MenuDiagnostics(void) {
    @autoreleasepool {
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNSwapInstanceMethodV042(cls, @selector(zn40_addInfoCard:lines:y:width:), @selector(zn42_addInfoCard:lines:y:width:));
        ZNSwapInstanceMethodV042(cls, @selector(zn40_selfTest:), @selector(zn42_selfTest:));
        ZNSwapInstanceMethodV042(cls, @selector(makeUI:), @selector(zn42_makeUI:));
        [[ZNRuntimeLogger sharedLogger] log:@"[bootstrap][main] v0.4.2 diagnostics UI installed: wrap=ON executableProbe=ON"];
    }
}
