#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNTheme.h"

// Method Finder V2 presentation layer. The existing v0.5.7 UI remains the
// baseline; this deferred swizzle augments it after each render so the change is
// isolated from the sealed menu lifecycle and Builder transaction semantics.

static const void *kZN58UXCopyValueKey = &kZN58UXCopyValueKey;
static const void *kZN58UXCopyLabelKey = &kZN58UXCopyLabelKey;
static const NSInteger kZN58UXQueryFieldTag = 571001;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,copy) NSArray<NSString *> *categories;
@property(nonatomic,strong) ZNTheme *theme;
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIFont *)menuFont:(CGFloat)size weight:(UIFontWeight)weight;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)renderPage;
- (NSDictionary *)zn57mf_result;
- (void)zn57mf_setStatus:(NSString *)value;
- (void)zn57mf_renderFinder;
@end

static NSString *ZN58UXHex(uint64_t value) {
    return [NSString stringWithFormat:@"0x%llX", (unsigned long long)value];
}

static NSArray<UIView *> *ZN58UXDescendants(UIView *root) {
    NSMutableArray<UIView *> *result = [NSMutableArray array];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIView *view = queue.lastObject;
        [queue removeLastObject];
        for (UIView *child in view.subviews) {
            [result addObject:child];
            [queue addObject:child];
        }
    }
    return result;
}

@interface ZNRuntimeMenuControllerV040 (ZNIL2CPPMethodFinderUXV2)
- (void)zn58ux_renderFinder;
- (void)zn58ux_copyAddress:(UIButton *)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNIL2CPPMethodFinderUXV2)

- (void)zn58ux_renderFinder {
    // After method exchange this calls the original v0.5.7 renderer.
    [self zn58ux_renderFinder];

    NSArray<UIView *> *views = ZN58UXDescendants(self.contentView);
    UITextField *queryField = (UITextField *)[self.contentView viewWithTag:kZN58UXQueryFieldTag];
    if ([queryField isKindOfClass:UITextField.class]) {
        queryField.placeholder = @"方法名 / Class::Method/0 / 0xRVA";
    }

    for (UIView *view in views) {
        if (![view isKindOfClass:UILabel.class]) continue;
        UILabel *label = (UILabel *)view;
        if ([label.text containsString:@"bounded streaming"] || [label.text containsString:@"不建立全量索引"]) {
            label.text = @"智能查找 · 完整类名直查 · 裸方法名 12000-Class 分片续扫 · 0xRVA 反查";
        }
    }

    NSDictionary *result = [self zn57mf_result];
    if (!result) return;

    NSDictionary *stats = result[@"searchStats"] ?: @{};
    NSNumber *shards = stats[@"shardsScanned"];
    if (shards) {
        for (UIView *view in views) {
            if (![view isKindOfClass:UILabel.class]) continue;
            UILabel *label = (UILabel *)view;
            if ([label.text hasPrefix:@"搜索："] && [label.text rangeOfString:@"shards="].location == NSNotFound) {
                label.text = [label.text stringByAppendingFormat:@" · shards=%@", shards];
            }
        }
    }

    NSArray<NSDictionary<NSString *, NSString *> *> *addressSpecs = @[
        @{@"old": @"RVA / Offset", @"title": @"RVA / Offset", @"value": result[@"rvaText"] ?: @"?"},
        @{@"old": @"Preferred / IDA", @"title": @"Preferred VA", @"value": ZN58UXHex([result[@"preferredVA"] unsignedLongLongValue])},
        @{@"old": @"Runtime VA", @"title": @"Runtime VA", @"value": ZN58UXHex([result[@"runtimeVA"] unsignedLongLongValue])},
        @{@"old": @"MethodInfo", @"title": @"MethodInfo", @"value": ZN58UXHex([result[@"methodInfo"] unsignedLongLongValue])},
        @{@"old": @"Method Pointer", @"title": @"Method Pointer", @"value": ZN58UXHex([result[@"methodPointer"] unsignedLongLongValue])},
    ];

    NSMutableSet<UILabel *> *usedLabels = [NSMutableSet set];
    for (NSDictionary<NSString *, NSString *> *spec in addressSpecs) {
        UILabel *target = nil;
        for (UIView *view in views) {
            if (![view isKindOfClass:UILabel.class]) continue;
            UILabel *label = (UILabel *)view;
            if ([usedLabels containsObject:label]) continue;
            NSString *oldPrefix = spec[@"old"];
            NSString *newPrefix = spec[@"title"];
            if ([label.text hasPrefix:oldPrefix] || [label.text hasPrefix:newPrefix]) {
                target = label;
                break;
            }
        }
        if (!target || !target.superview) continue;
        [usedLabels addObject:target];

        NSString *title = spec[@"title"] ?: @"地址";
        NSString *value = spec[@"value"] ?: @"?";
        target.text = [NSString stringWithFormat:@"%-14@ %@", title, value];
        CGRect frame = target.frame;
        CGFloat copyW = 42.0;
        target.frame = CGRectMake(frame.origin.x, frame.origin.y, MAX(80.0, frame.size.width - copyW - 5.0), frame.size.height);

        UIButton *copy = [UIButton buttonWithType:UIButtonTypeSystem];
        copy.frame = CGRectMake(CGRectGetWidth(target.superview.bounds) - 13.0 - copyW,
                                frame.origin.y - 1.0,
                                copyW,
                                MAX(19.0, frame.size.height + 2.0));
        [copy setTitle:@"复制" forState:UIControlStateNormal];
        [copy setTitleColor:self.theme.accentColor forState:UIControlStateNormal];
        copy.titleLabel.font = [self menuFont:8.4 weight:UIFontWeightSemibold];
        copy.backgroundColor = [self.theme.accentColor colorWithAlphaComponent:0.12];
        copy.layer.cornerRadius = 5.0;
        copy.layer.borderWidth = 0.7;
        copy.layer.borderColor = [self.theme.accentColor colorWithAlphaComponent:0.55].CGColor;
        objc_setAssociatedObject(copy, kZN58UXCopyValueKey, value, OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(copy, kZN58UXCopyLabelKey, title, OBJC_ASSOCIATION_COPY_NONATOMIC);
        [copy addTarget:self action:@selector(zn58ux_copyAddress:) forControlEvents:UIControlEventTouchUpInside];
        [target.superview addSubview:copy];
    }

    BOOL hasBuilderPage = [self.categories containsObject:@"其他"];
    for (UIView *view in views) {
        if (![view isKindOfClass:UIButton.class]) continue;
        UIButton *button = (UIButton *)view;
        if ([button.currentTitle isEqualToString:@"加入 Builder"] || [button.currentTitle hasPrefix:@"创建 Patch"]) {
            if (hasBuilderPage) {
                [button setTitle:@"创建 Patch" forState:UIControlStateNormal];
            } else {
                [button setTitle:@"创建 Patch（需其他）" forState:UIControlStateNormal];
                button.enabled = NO;
                button.alpha = 0.55;
            }
        }
    }

    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat y = 0.0;
    for (UIView *view in self.contentView.subviews) y = MAX(y, CGRectGetMaxY(view.frame));
    y += 8.0;

    UIView *addressHelp = [self cardAtY:y height:130.0 width:width compact:NO];
    UILabel *addressTitle = [self label:@"这些地址分别做什么" size:10.6 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    addressTitle.frame = CGRectMake(13, 7, addressHelp.bounds.size.width - 26, 17);
    [addressHelp addSubview:addressTitle];
    UILabel *addressText = [self label:@"RVA / Offset：UnityFramework 相对偏移，Patch/对照 dump 首选。\nPreferred VA：Mach-O __TEXT 首选基址 + RVA，适合静态反汇编；分析器若 rebase 过需以其基址为准。\nRuntime VA：本次启动真实地址，受 ASLR 影响，重启可能变化。\nMethodInfo：IL2CPP 方法元数据对象地址，不是代码入口。\nMethod Pointer：当前 native 代码入口，用于运行时反汇编/验证。"
                                  size:7.9
                                weight:UIFontWeightRegular
                                 color:self.theme.secondaryTextColor];
    addressText.frame = CGRectMake(13, 27, addressHelp.bounds.size.width - 26, 96);
    addressText.numberOfLines = 0;
    addressText.lineBreakMode = NSLineBreakByWordWrapping;
    [addressHelp addSubview:addressText];
    [self.contentView addSubview:addressHelp];
    y += 138.0;

    UIView *builderHelp = [self cardAtY:y height:66.0 width:width compact:NO];
    UILabel *builderTitle = [self label:@"创建 Patch 是什么" size:10.4 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    builderTitle.frame = CGRectMake(13, 7, builderHelp.bounds.size.width - 26, 17);
    [builderHelp addSubview:builderTitle];
    NSString *builderTextValue = hasBuilderPage
        ? @"只创建一条“未验证”的 Patch 编辑行：自动带入 UnityFramework + 当前方法；不会立即改内存。你仍需填写 Patch 字节 → 读取验证 → 再临时应用或生成。"
        : @"Patch 编辑器位于“其他”开发页；当前权限没有显示该页，因此这里不创建不可编辑的孤立 Patch 行。";
    UILabel *builderText = [self label:builderTextValue size:8.1 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    builderText.frame = CGRectMake(13, 27, builderHelp.bounds.size.width - 26, 33);
    builderText.numberOfLines = 2;
    builderText.lineBreakMode = NSLineBreakByWordWrapping;
    [builderHelp addSubview:builderText];
    [self.contentView addSubview:builderHelp];
    y += 74.0;

    [self zn40_updateContentHeight:y];
}

- (void)zn58ux_copyAddress:(UIButton *)sender {
    NSString *value = objc_getAssociatedObject(sender, kZN58UXCopyValueKey) ?: @"";
    NSString *label = objc_getAssociatedObject(sender, kZN58UXCopyLabelKey) ?: @"地址";
    if (!value.length) return;
    UIPasteboard.generalPasteboard.string = value;
    [self zn57mf_setStatus:[NSString stringWithFormat:@"已复制 %@：%@", label, value]];
    [self renderPage];
}

@end

extern "C" void ZNInstallIL2CPPMethodFinderUXV2Deferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        Method original = class_getInstanceMethod(cls, @selector(zn57mf_renderFinder));
        Method replacement = class_getInstanceMethod(cls, @selector(zn58ux_renderFinder));
        if (original && replacement) method_exchangeImplementations(original, replacement);
    });
}
