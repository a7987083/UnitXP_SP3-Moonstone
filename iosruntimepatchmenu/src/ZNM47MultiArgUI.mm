#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNIL2CPPABIMetadata.h"
#import "ZNIL2CPPMethodSignature.h"
#import "ZNRuntimeActionFormat.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

static const void *kZNM47ArgumentKey = &kZNM47ArgumentKey;
static const NSInteger kZNM47ArgumentTagBase = 647200;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) ZNTheme *theme;
- (void)zn60v3_renderResultsAtWidth:(CGFloat)width;
- (NSArray<NSDictionary *> *)zn60v3_candidates;
- (NSInteger)znm42_filter;
- (NSMutableDictionary<NSString *, NSString *> *)znm42_inputStore;
- (NSArray<NSString *> *)znm43_argumentValues:(NSDictionary *)candidate;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (UIFont *)menuFont:(CGFloat)size weight:(UIFontWeight)weight;
@end

static NSString *ZNM47DisplayAssembly(NSString *assembly) {
    NSString *s = assembly ?: @"";
    return [s.lowercaseString hasSuffix:@".dll"] && s.length > 4 ? [s substringToIndex:s.length - 4] : s;
}

static NSString *ZNM47CandidateIdentity(NSDictionary *candidate) {
    NSString *canonical = [candidate[@"canonical"] isKindOfClass:NSString.class] ? candidate[@"canonical"] : @"";
    if (canonical.length) return canonical;
    return [NSString stringWithFormat:@"%@|%@|%@|%@|%@",
            candidate[@"assembly"] ?: @"", candidate[@"namespace"] ?: @"", candidate[@"class"] ?: @"",
            candidate[@"method"] ?: @"", candidate[@"argumentCount"] ?: @(-1)];
}

static NSString *ZNM47ArgumentStoreKey(NSDictionary *candidate, NSUInteger index) {
    return [NSString stringWithFormat:@"%@#arg:%lu", ZNM47CandidateIdentity(candidate), (unsigned long)index];
}

static NSArray<NSDictionary *> *ZNM47Visible(ZNRuntimeMenuControllerV040 *controller) {
    NSArray<NSDictionary *> *all = [controller zn60v3_candidates] ?: @[];
    NSInteger filter = [controller znm42_filter];
    NSMutableArray *visible = [NSMutableArray array];
    for (NSDictionary *candidate in all) if (filter < 0 || [candidate[@"argumentCount"] integerValue] == filter) [visible addObject:candidate];
    return visible;
}

static void ZNM47CollectBoundButtons(UIView *root, id target, NSMutableArray<UIButton *> *out) {
    for (UIView *child in root.subviews) {
        if ([child isKindOfClass:UIButton.class]) {
            UIButton *button = (UIButton *)child;
            NSArray<NSString *> *actions = [button actionsForTarget:target forControlEvent:UIControlEventTouchUpInside] ?: @[];
            if ([actions containsObject:NSStringFromSelector(@selector(znm462_boundTestCandidate:))]) [out addObject:button];
        }
        ZNM47CollectBoundButtons(child, target, out);
    }
}

static UIButton *ZNM47CreateButton(UIView *card) {
    for (UIView *view in card.subviews) {
        if (![view isKindOfClass:UIButton.class]) continue;
        UIButton *button = (UIButton *)view;
        if ([[button titleForState:UIControlStateNormal] isEqualToString:@"创建方法"]) return button;
    }
    return nil;
}

static UILabel *ZNM47LabelWithText(UIView *card, NSString *text) {
    for (UIView *view in card.subviews) {
        if ([view isKindOfClass:UILabel.class] && [((UILabel *)view).text isEqualToString:text]) return (UILabel *)view;
    }
    return nil;
}

static CGFloat ZNM47Bottom(UIView *root) {
    CGFloat bottom = 0;
    for (UIView *view in root.subviews) bottom = MAX(bottom, CGRectGetMaxY(view.frame));
    return bottom;
}

static NSString *ZNM47ShortType(NSString *type) {
    NSArray *parts = [type ?: @"" componentsSeparatedByString:@"."];
    return parts.lastObject.length ? parts.lastObject : (type ?: @"?");
}

static NSUInteger ZNM47StructCount(NSString *type) {
    NSString *n = [type ?: @"" lowercaseString];
    if ([n isEqualToString:@"unityengine.vector2"] || [n isEqualToString:@"vector2"]) return 2;
    if ([n isEqualToString:@"unityengine.vector3"] || [n isEqualToString:@"vector3"]) return 3;
    if ([n isEqualToString:@"unityengine.quaternion"] || [n isEqualToString:@"quaternion"] ||
        [n isEqualToString:@"unityengine.color"] || [n isEqualToString:@"color"]) return 4;
    return 0;
}

static BOOL ZNM47IsString(NSString *type) {
    NSString *n = [type ?: @"" lowercaseString];
    return [n isEqualToString:@"system.string"] || [n isEqualToString:@"string"];
}

static NSString *ZNM47UnsupportedReason(NSDictionary *param) {
    if ([param[@"byRef"] boolValue]) return @"ref/out 暂不支持";
    if ([param[@"pointer"] boolValue]) return @"pointer 暂不支持";
    NSString *type = param[@"name"] ?: @"?";
    if (ZNM47IsString(type)) return nil;
    ZNIL2CPPABIValueKind kind = (ZNIL2CPPABIValueKind)[param[@"kind"] integerValue];
    switch (kind) {
        case ZNIL2CPPABIValueKindBool:
        case ZNIL2CPPABIValueKindSigned32:
        case ZNIL2CPPABIValueKindUnsigned32:
        case ZNIL2CPPABIValueKindSigned64:
        case ZNIL2CPPABIValueKindUnsigned64:
        case ZNIL2CPPABIValueKindFloat32:
        case ZNIL2CPPABIValueKindFloat64:
            return nil;
        case ZNIL2CPPABIValueKindComplexValueType:
            return ZNM47StructCount(type) ? nil : [NSString stringWithFormat:@"%@ 暂不支持", ZNM47ShortType(type)];
        case ZNIL2CPPABIValueKindObjectReference:
            return [NSString stringWithFormat:@"%@ 对象参数暂不支持", ZNM47ShortType(type)];
        default:
            return [NSString stringWithFormat:@"%@ 类型未识别", ZNM47ShortType(type)];
    }
}

static UITextField *ZNM47Field(CGRect frame, ZNTheme *theme, UIFont *font) {
    UITextField *field = [[UITextField alloc] initWithFrame:frame];
    field.textColor = theme.primaryTextColor;
    field.backgroundColor = theme.controlColor;
    field.tintColor = theme.accentColor;
    field.font = font;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.returnKeyType = UIReturnKeyDone;
    field.layer.cornerRadius = 6.0;
    field.layer.borderWidth = 1.0;
    field.layer.borderColor = theme.borderColor.CGColor;
    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 7, 1)];
    field.leftView = pad;
    field.leftViewMode = UITextFieldViewModeAlways;
    return field;
}

@interface ZNRuntimeMenuControllerV040 (ZNM47MultiArgUI)
- (void)znm47ma_renderResultsAtWidth:(CGFloat)width;
- (NSArray<NSString *> *)znm47ma_argumentValues:(NSDictionary *)candidate;
- (void)znm47ma_argumentChanged:(UITextField *)field;
- (void)znm47ma_done:(UITextField *)field;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM47MultiArgUI)

- (NSArray<NSString *> *)znm47ma_argumentValues:(NSDictionary *)candidate {
    NSUInteger argc = [candidate[@"argumentCount"] unsignedIntegerValue];
    if (argc < 2) return [self znm47ma_argumentValues:candidate];
    if (argc > ZN_RUNTIME_ACTION_MAX_ARGUMENTS) return @[];
    NSMutableArray<NSString *> *values = [NSMutableArray arrayWithCapacity:argc];
    for (NSUInteger i = 0; i < argc; i++) [values addObject:[self znm42_inputStore][ZNM47ArgumentStoreKey(candidate, i)] ?: @""];
    return [values copy];
}

- (void)znm47ma_argumentChanged:(UITextField *)field {
    NSString *key = objc_getAssociatedObject(field, kZNM47ArgumentKey);
    if (key.length) [self znm42_inputStore][key] = field.text ?: @"";
}

- (void)znm47ma_done:(UITextField *)field {
    [self znm47ma_argumentChanged:field];
    [field resignFirstResponder];
}

- (void)znm47ma_renderResultsAtWidth:(CGFloat)width {
    [self znm47ma_renderResultsAtWidth:width];

    NSArray<NSDictionary *> *visible = ZNM47Visible(self);
    NSMutableArray<UIButton *> *testButtons = [NSMutableArray array];
    ZNM47CollectBoundButtons(self.contentView, self, testButtons);
    if (!visible.count || visible.count != testButtons.count) return;

    for (NSUInteger i = 0; i < visible.count; i++) {
        NSDictionary *candidate = visible[i];
        NSUInteger argc = [candidate[@"argumentCount"] unsignedIntegerValue];
        if (argc < 2 || argc > ZN_RUNTIME_ACTION_MAX_ARGUMENTS) continue;

        UIButton *test = testButtons[i];
        UIView *card = test.superview;
        if (!card || card.superview != self.contentView) continue;
        UIButton *create = ZNM47CreateButton(card);

        NSDictionary *abi = ZNIL2CPPDescribeMethodABI(candidate);
        NSArray<NSDictionary *> *params = [abi[@"parameters"] isKindOfClass:NSArray.class] ? abi[@"parameters"] : nil;
        BOOL metadataOK = [abi[@"available"] boolValue] && params.count == argc && !([abi[@"genericStatusKnown"] boolValue] && [abi[@"generic"] boolValue]);
        BOOL callable = metadataOK;
        NSMutableArray<NSString *> *types = [NSMutableArray arrayWithCapacity:argc];
        if (metadataOK) {
            for (NSDictionary *param in params) {
                NSString *type = param[@"name"] ?: @"?";
                [types addObject:type];
                if (ZNM47UnsupportedReason(param).length) callable = NO;
            }
        }

        CGFloat oldBottom = CGRectGetMaxY(card.frame);
        CGFloat oldHeight = CGRectGetHeight(card.frame);
        CGFloat leftRight = CGRectGetMinX(test.frame) - 8.0;
        CGFloat inputY = 54.0;
        CGFloat rowStep = 34.0;

        for (NSUInteger arg = 0; arg < argc; arg++) {
            NSDictionary *param = metadataOK ? params[arg] : nil;
            NSString *type = param ? (param[@"name"] ?: @"?") : @"?";
            NSString *name = param ? (param[@"paramName"] ?: @"") : @"";
            NSString *reason = param ? ZNM47UnsupportedReason(param) : (abi[@"reason"] ?: @"参数 ABI 不可用");
            CGRect frame = CGRectMake(13.0, inputY + arg * rowStep, MAX(60.0, leftRight - 13.0), 28.0);
            if (!reason.length) {
                UITextField *field = ZNM47Field(frame, self.theme, [self menuFont:8.9 weight:UIFontWeightMedium]);
                NSString *shortType = ZNM47ShortType(type);
                field.placeholder = name.length
                    ? [NSString stringWithFormat:@"参数%lu · %@ · %@", (unsigned long)arg + 1, name, shortType]
                    : [NSString stringWithFormat:@"参数%lu · %@", (unsigned long)arg + 1, shortType];
                NSString *key = ZNM47ArgumentStoreKey(candidate, arg);
                field.text = [self znm42_inputStore][key] ?: @"";
                field.keyboardType = ZNM47IsString(type) ? UIKeyboardTypeDefault : UIKeyboardTypeNumbersAndPunctuation;
                field.tag = kZNM47ArgumentTagBase + (NSInteger)arg;
                objc_setAssociatedObject(field, kZNM47ArgumentKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
                [field addTarget:self action:@selector(znm47ma_argumentChanged:) forControlEvents:UIControlEventEditingChanged];
                [field addTarget:self action:@selector(znm47ma_done:) forControlEvents:UIControlEventEditingDidEndOnExit];
                [card addSubview:field];
            } else {
                UILabel *label = [[UILabel alloc] initWithFrame:frame];
                label.text = [NSString stringWithFormat:@"参数%lu · %@ · %@", (unsigned long)arg + 1, ZNM47ShortType(type), reason];
                label.textColor = self.theme.secondaryTextColor;
                label.font = [self menuFont:8.2 weight:UIFontWeightRegular];
                label.lineBreakMode = NSLineBreakByTruncatingMiddle;
                [card addSubview:label];
            }
        }

        NSString *assemblyText = ZNM47DisplayAssembly(candidate[@"assembly"] ?: @"?");
        UILabel *assembly = ZNM47LabelWithText(card, assemblyText);
        NSString *signatureText = metadataOK ? ZNIL2CPPShortSignature(candidate[@"method"] ?: @"Method", types) : nil;
        UILabel *signature = signatureText.length ? ZNM47LabelWithText(card, signatureText) : nil;

        CGFloat signatureY = inputY + argc * rowStep;
        if (signature) {
            CGRect f = signature.frame; f.origin.y = signatureY; signature.frame = f;
        }
        CGFloat assemblyY = signatureY + (signature ? 17.0 : 0.0);
        if (assembly) {
            CGRect f = assembly.frame; f.origin.y = assemblyY; assembly.frame = f;
        }
        CGFloat desiredHeight = assemblyY + 22.0;
        if (desiredHeight < oldHeight) desiredHeight = oldHeight;
        CGFloat delta = desiredHeight - oldHeight;
        if (delta > 0.5) {
            CGRect f = card.frame; f.size.height = desiredHeight; card.frame = f;
            for (UIView *sibling in self.contentView.subviews) {
                if (sibling == card) continue;
                if (CGRectGetMinY(sibling.frame) + 0.5 < oldBottom) continue;
                CGRect sf = sibling.frame; sf.origin.y += delta; sibling.frame = sf;
            }
        }

        test.enabled = callable;
        test.alpha = callable ? 1.0 : 0.48;
        if (create) { create.enabled = callable; create.alpha = callable ? 1.0 : 0.48; }
    }

    [self zn40_updateContentHeight:ZNM47Bottom(self.contentView) + 8.0];
}

@end

static void ZNM47UISwap(Class cls, SEL a, SEL b) {
    Method ma = class_getInstanceMethod(cls, a), mb = class_getInstanceMethod(cls, b);
    if (ma && mb) method_exchangeImplementations(ma, mb);
}

extern "C" void ZNInstallM47MultiArgUIDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNM47UISwap(cls, @selector(zn60v3_renderResultsAtWidth:), @selector(znm47ma_renderResultsAtWidth:));
        ZNM47UISwap(cls, @selector(znm43_argumentValues:), @selector(znm47ma_argumentValues:));
        [[ZNRuntimeLogger sharedLogger] log:@"[m4.7-multiarg-ui] /2-/8 dynamic parameter rows installed"];
    });
}
