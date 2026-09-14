#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNIL2CPPABIMetadata.h"
#import "ZNTheme.h"

static const void *kZN65ABICopyKey = &kZN65ABICopyKey;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIScrollView *contentScroll;
@property(nonatomic,strong) ZNTheme *theme;
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (NSDictionary *)zn60v3_selected;
- (void)zn60v3_renderDetailAtWidth:(CGFloat)width;
@end

@interface ZNRuntimeMenuControllerV040 (ZNIL2CPPABIDetailUI)
- (void)zn65abi_renderDetailAtWidth:(CGFloat)width;
- (void)zn65abi_copy:(UIButton *)sender;
@end

static CGFloat ZN65ContentBottom(UIView *root) {
    CGFloat bottom = 9.0;
    for (UIView *view in root.subviews) bottom = MAX(bottom, CGRectGetMaxY(view.frame));
    return bottom;
}

static NSString *ZN65ParameterSummary(NSArray<NSDictionary *> *params) {
    if (!params.count) return @"参数：无";
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:params.count];
    for (NSDictionary *p in params) {
        NSString *name = p[@"name"] ?: @"?";
        NSString *kind = ZNIL2CPPABIValueKindName((ZNIL2CPPABIValueKind)[p[@"kind"] integerValue]);
        [parts addObject:[NSString stringWithFormat:@"%@→%@", name, kind]];
    }
    return [NSString stringWithFormat:@"参数 ABI：%@", [parts componentsJoinedByString:@" · "]];
}

@implementation ZNRuntimeMenuControllerV040 (ZNIL2CPPABIDetailUI)

- (void)zn65abi_renderDetailAtWidth:(CGFloat)width {
    // Swizzled: this calls the complete existing V3/M2 detail renderer first.
    [self zn65abi_renderDetailAtWidth:width];
    NSDictionary *candidate = [self zn60v3_selected];
    if (!candidate) return;

    NSDictionary *abi = ZNIL2CPPDescribeMethodABI(candidate);
    CGFloat y = ZN65ContentBottom(self.contentView) + 8.0;
    UIView *card = [self cardAtY:y height:170 width:width compact:NO];

    UILabel *title = [self label:@"IL2CPP Signature / ABI · M3.1" size:10.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    title.frame = CGRectMake(13, 7, card.bounds.size.width - 70, 18);
    [card addSubview:title];

    NSString *signature = abi[@"signature"] ?: (abi[@"reason"] ?: @"ABI metadata unavailable");
    UILabel *sig = [self label:signature size:8.3 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    sig.frame = CGRectMake(13, 29, card.bounds.size.width - 26, 34);
    sig.numberOfLines = 2;
    sig.lineBreakMode = NSLineBreakByTruncatingTail;
    [card addSubview:sig];

    NSDictionary *ret = abi[@"return"] ?: @{};
    NSString *returnName = ret[@"name"] ?: @"?";
    NSString *returnKind = ZNIL2CPPABIValueKindName((ZNIL2CPPABIValueKind)[ret[@"kind"] integerValue]);
    UILabel *rl = [self label:[NSString stringWithFormat:@"返回：%@    ABI：%@", returnName, returnKind] size:8.5 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    rl.frame = CGRectMake(13, 66, card.bounds.size.width - 26, 17);
    rl.adjustsFontSizeToFitWidth = YES;
    rl.minimumScaleFactor = 0.66;
    [card addSubview:rl];

    NSString *mode = [abi[@"instanceKnown"] boolValue] ? ([abi[@"instance"] boolValue] ? @"instance" : @"static") : @"instance/static ?";
    NSString *generic = [abi[@"genericStatusKnown"] boolValue]
        ? [NSString stringWithFormat:@"generic=%@ · inflated=%@", [abi[@"generic"] boolValue] ? @"yes" : @"no", [abi[@"inflated"] boolValue] ? @"yes" : @"no"]
        : @"generic/inflated=unknown";
    UILabel *flags = [self label:[NSString stringWithFormat:@"调用：%@    %@", mode, generic] size:8.2 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    flags.frame = CGRectMake(13, 87, card.bounds.size.width - 26, 17);
    [card addSubview:flags];

    UILabel *params = [self label:ZN65ParameterSummary(abi[@"parameters"] ?: @[]) size:7.8 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    params.frame = CGRectMake(13, 107, card.bounds.size.width - 26, 20);
    params.adjustsFontSizeToFitWidth = YES;
    params.minimumScaleFactor = 0.60;
    [card addSubview:params];

    BOOL eligible = [abi[@"returnOverrideEligible"] boolValue];
    NSString *reason = abi[@"returnOverrideReason"] ?: (abi[@"reason"] ?: @"ABI metadata unavailable");
    UILabel *status = [self label:[NSString stringWithFormat:@"Return Override：%@ · %@", eligible ? @"Foundation Ready" : @"Blocked", reason] size:7.8 weight:UIFontWeightSemibold color:(eligible ? self.theme.accentColor : self.theme.secondaryTextColor)];
    status.frame = CGRectMake(13, 130, card.bounds.size.width - 69, 30);
    status.numberOfLines = 2;
    [card addSubview:status];

    NSString *copyText = [NSString stringWithFormat:@"%@\nReturn: %@ (%@)\nMode: %@\n%@\nReturn Override: %@\nReason: %@",
                          signature,
                          returnName,
                          returnKind,
                          mode,
                          ZN65ParameterSummary(abi[@"parameters"] ?: @[]),
                          eligible ? @"Foundation Ready" : @"Blocked",
                          reason];
    UIButton *copy = [self zn40_button:@"复制 ABI" selector:@selector(zn65abi_copy:) frame:CGRectMake(card.bounds.size.width - 61, 132, 48, 24)];
    copy.titleLabel.font = [UIFont systemFontOfSize:7.0 weight:UIFontWeightSemibold];
    objc_setAssociatedObject(copy, kZN65ABICopyKey, copyText, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [card addSubview:copy];

    [self.contentView addSubview:card];
    y += 178.0;

    UILabel *note = [self label:@"M3.1 只解析签名并建立 Return Override 计划；此版本不会安装 Hook、不会改写函数入口。复杂 struct、generic/inflated、托管对象返回默认阻止自动覆盖。" size:7.5 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    note.frame = CGRectMake(13, y, width - 26, 38);
    note.numberOfLines = 3;
    [self.contentView addSubview:note];
    [self zn40_updateContentHeight:y + 46.0];
}

- (void)zn65abi_copy:(UIButton *)sender {
    NSString *text = objc_getAssociatedObject(sender, kZN65ABICopyKey);
    if (text.length) UIPasteboard.generalPasteboard.string = text;
}

@end

extern "C" void ZNInstallIL2CPPABIDetailUIDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        Method original = class_getInstanceMethod(cls, @selector(zn60v3_renderDetailAtWidth:));
        Method replacement = class_getInstanceMethod(cls, @selector(zn65abi_renderDetailAtWidth:));
        if (original && replacement) method_exchangeImplementations(original, replacement);
    });
}
