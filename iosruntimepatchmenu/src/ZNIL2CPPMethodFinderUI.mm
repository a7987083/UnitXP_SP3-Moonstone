#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNIL2CPPHybridFinder.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

// v0.5.7 Method Finder UI.
// Developer authoring surface only. Search resolves runtime metadata/address
// information but never patches code itself. "加入 Builder" creates an empty
// Builder row that must still pass the existing Runtime Validator before apply
// or generated-binary build.

static const void *kZN57MFQueryKey = &kZN57MFQueryKey;
static const void *kZN57MFResultKey = &kZN57MFResultKey;
static const void *kZN57MFStatusKey = &kZN57MFStatusKey;
static const NSInteger kZN57MFQueryFieldTag = 571001;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIScrollView *contentScroll;
@property(nonatomic,strong) UIWindow *hostWindow;
@property(nonatomic,copy) NSArray<NSString *> *categories;
@property(nonatomic,copy) NSArray<NSString *> *categorySymbols;
@property(nonatomic,assign) NSInteger selectedCategory;
@property(nonatomic,strong) ZNTheme *theme;
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIFont *)menuFont:(CGFloat)size weight:(UIFontWeight)weight;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (NSArray<NSString *> *)zn40_baseCategories;
- (NSArray<NSString *> *)zn40_baseSymbols;
- (void)zn40_refreshDeveloperCategories:(BOOL)force;
- (void)renderFullPage;
- (void)renderPage;
- (CGSize)fullSizeForWindow:(UIWindow *)window;
@end

static NSString *ZN57MFTrim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *ZN57MFHex(uint64_t value) {
    return [NSString stringWithFormat:@"0x%llX", (unsigned long long)value];
}

static NSString *ZN57MFShortName(NSDictionary *result) {
    NSString *method = result[@"method"] ?: @"Method";
    NSInteger argc = [result[@"argumentCount"] integerValue];
    return argc >= 0 ? [NSString stringWithFormat:@"%@/%ld", method, (long)argc] : method;
}

static NSString *ZN57MFFullCopyText(NSDictionary *result) {
    NSDictionary *stats = result[@"searchStats"] ?: @{};
    return [NSString stringWithFormat:
            @"%@\nModule: UnityFramework\nAssembly: %@\nNamespace: %@\nClass: %@\nMethod: %@\nRVA: %@\nPreferred/IDA VA: %@\nRuntime VA: %@\nMethodInfo: %@\nMethod Pointer: %@\nPointer Source: %@\nPointer Type: %@\nSearch: %@ · classes=%@ · %@ms",
            result[@"canonical"] ?: @"IL2CPP Method",
            result[@"assembly"] ?: @"",
            result[@"namespace"] ?: @"",
            result[@"class"] ?: @"",
            result[@"method"] ?: @"",
            result[@"rvaText"] ?: @"?",
            ZN57MFHex([result[@"preferredVA"] unsignedLongLongValue]),
            ZN57MFHex([result[@"runtimeVA"] unsignedLongLongValue]),
            ZN57MFHex([result[@"methodInfo"] unsignedLongLongValue]),
            ZN57MFHex([result[@"methodPointer"] unsignedLongLongValue]),
            result[@"pointerSource"] ?: @"?",
            result[@"pointerKind"] ?: @"?",
            result[@"searchMode"] ?: @"?",
            stats[@"classesScanned"] ?: @0,
            stats[@"elapsedMs"] ?: @0];
}

@interface ZNRuntimeMenuControllerV040 (ZNIL2CPPMethodFinderUI)
- (NSArray<NSString *> *)zn57mf_baseCategories;
- (NSArray<NSString *> *)zn57mf_baseSymbols;
- (void)zn57mf_renderFullPage;
- (CGSize)zn57mf_fullSizeForWindow:(UIWindow *)window;
- (void)zn57mf_renderFinder;
- (void)zn57mf_search:(id)sender;
- (void)zn57mf_queryChanged:(UITextField *)field;
- (void)zn57mf_copyResult:(id)sender;
- (void)zn57mf_addToBuilder:(id)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNIL2CPPMethodFinderUI)

- (NSString *)zn57mf_query {
    return objc_getAssociatedObject(self, kZN57MFQueryKey) ?: @"";
}

- (void)zn57mf_setQuery:(NSString *)value {
    objc_setAssociatedObject(self, kZN57MFQueryKey, ZN57MFTrim(value), OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (NSDictionary *)zn57mf_result {
    return objc_getAssociatedObject(self, kZN57MFResultKey);
}

- (void)zn57mf_setResult:(NSDictionary *)value {
    objc_setAssociatedObject(self, kZN57MFResultKey, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSString *)zn57mf_status {
    return objc_getAssociatedObject(self, kZN57MFStatusKey) ?: @"输入方法名，例如 gethp / GetMoney/0 / Game.Player::GetHP/0";
}

- (void)zn57mf_setStatus:(NSString *)value {
    objc_setAssociatedObject(self, kZN57MFStatusKey, value ?: @"", OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (NSArray<NSString *> *)zn57mf_baseCategories {
    NSArray<NSString *> *base = [self zn57mf_baseCategories];
    if ([base containsObject:@"方法查找"] || ![base containsObject:@"其他"]) return base;
    NSMutableArray<NSString *> *items = [base mutableCopy];
    NSUInteger other = [items indexOfObject:@"其他"];
    [items insertObject:@"方法查找" atIndex:MIN(other + 1, items.count)];
    return items;
}

- (NSArray<NSString *> *)zn57mf_baseSymbols {
    NSArray<NSString *> *base = [self zn57mf_baseSymbols];
    NSArray<NSString *> *cats = [self zn57mf_baseCategories];
    if (base.count == cats.count) return base;
    NSMutableArray<NSString *> *items = [base mutableCopy];
    NSUInteger finder = [cats indexOfObject:@"方法查找"];
    if (finder != NSNotFound && finder <= items.count) [items insertObject:@"magnifyingglass" atIndex:finder];
    return items;
}

- (CGSize)zn57mf_fullSizeForWindow:(UIWindow *)window {
    CGSize size = [self zn57mf_fullSizeForWindow:window];
    NSString *category = (self.selectedCategory >= 0 && self.selectedCategory < (NSInteger)self.categories.count)
        ? self.categories[(NSUInteger)self.selectedCategory]
        : @"";
    if ([category isEqualToString:@"方法查找"]) {
        UIEdgeInsets insets = window.safeAreaInsets;
        CGFloat available = MAX(300.0, CGRectGetHeight(window.bounds) - insets.top - insets.bottom - 20.0);
        size.height = MIN(MAX(size.height, 470.0), available);
    }
    return size;
}

- (void)zn57mf_renderFullPage {
    NSString *category = (self.selectedCategory >= 0 && self.selectedCategory < (NSInteger)self.categories.count)
        ? self.categories[(NSUInteger)self.selectedCategory]
        : @"";
    if ([category isEqualToString:@"方法查找"]) {
        [self zn57mf_renderFinder];
        return;
    }
    [self zn57mf_renderFullPage];
}

- (UITextField *)zn57mf_field:(CGRect)frame {
    UITextField *field = [[UITextField alloc] initWithFrame:frame];
    field.tag = kZN57MFQueryFieldTag;
    field.text = [self zn57mf_query];
    field.placeholder = @"gethp / Class::Method/0";
    field.textColor = self.theme.primaryTextColor;
    field.backgroundColor = self.theme.controlColor;
    field.tintColor = self.theme.accentColor;
    field.font = [self menuFont:10.8 weight:UIFontWeightMedium];
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.spellCheckingType = UITextSpellCheckingTypeNo;
    field.returnKeyType = UIReturnKeySearch;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.layer.cornerRadius = 8.0;
    field.layer.borderWidth = 1.0;
    field.layer.borderColor = self.theme.borderColor.CGColor;
    UIView *padding = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 9, 1)];
    field.leftView = padding;
    field.leftViewMode = UITextFieldViewModeAlways;
    [field addTarget:self action:@selector(zn57mf_queryChanged:) forControlEvents:UIControlEventEditingChanged];
    [field addTarget:self action:@selector(zn57mf_search:) forControlEvents:UIControlEventEditingDidEndOnExit];
    return field;
}

- (void)zn57mf_renderFinder {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat y = 9.0;

    UIView *searchCard = [self cardAtY:y height:82 width:width compact:NO];
    UILabel *title = [self label:@"IL2CPP 方法查找" size:12.6 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    title.frame = CGRectMake(13, 8, searchCard.bounds.size.width - 26, 20);
    [searchCard addSubview:title];
    CGFloat buttonW = 68.0;
    UITextField *field = [self zn57mf_field:CGRectMake(13, 34, searchCard.bounds.size.width - 26 - buttonW - 7, 36)];
    [searchCard addSubview:field];
    UIButton *search = [self zn40_button:@"搜索" selector:@selector(zn57mf_search:) frame:CGRectMake(CGRectGetMaxX(field.frame) + 7, 34, buttonW, 36)];
    search.backgroundColor = [self.theme.accentColor colorWithAlphaComponent:0.20];
    search.layer.borderColor = self.theme.accentColor.CGColor;
    [searchCard addSubview:search];
    [self.contentView addSubview:searchCard];
    y += 90.0;

    UIView *hintCard = [self cardAtY:y height:54 width:width compact:NO];
    UILabel *hint = [self label:@"大小写不敏感精确匹配 · Assembly-CSharp 优先 · bounded streaming · 不建立全量索引"
                              size:8.9
                            weight:UIFontWeightRegular
                             color:self.theme.secondaryTextColor];
    hint.frame = CGRectMake(13, 8, hintCard.bounds.size.width - 26, 38);
    hint.numberOfLines = 2;
    hint.lineBreakMode = NSLineBreakByWordWrapping;
    [hintCard addSubview:hint];
    [self.contentView addSubview:hintCard];
    y += 62.0;

    NSDictionary *result = [self zn57mf_result];
    NSString *statusText = [self zn57mf_status];
    if (!result) {
        UIView *statusCard = [self cardAtY:y height:70 width:width compact:NO];
        UILabel *status = [self label:statusText size:9.5 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        status.frame = CGRectMake(13, 9, statusCard.bounds.size.width - 26, 52);
        status.numberOfLines = 3;
        status.lineBreakMode = NSLineBreakByWordWrapping;
        [statusCard addSubview:status];
        [self.contentView addSubview:statusCard];
        y += 78.0;
        [self zn40_updateContentHeight:y];
        return;
    }

    NSString *canonical = result[@"canonical"] ?: @"IL2CPP Method";
    UIView *methodCard = [self cardAtY:y height:76 width:width compact:NO];
    UILabel *methodTitle = [self label:canonical size:11.3 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    methodTitle.frame = CGRectMake(13, 8, methodCard.bounds.size.width - 26, 22);
    methodTitle.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [methodCard addSubview:methodTitle];
    UILabel *owner = [self label:[NSString stringWithFormat:@"%@ · %@%@%@",
                                  result[@"assembly"] ?: @"?",
                                  result[@"namespace"] ?: @"",
                                  [result[@"namespace"] length] ? @"." : @"",
                                  result[@"class"] ?: @""]
                              size:9.2 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    owner.frame = CGRectMake(13, 32, methodCard.bounds.size.width - 26, 17);
    owner.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [methodCard addSubview:owner];
    UILabel *source = [self label:[NSString stringWithFormat:@"%@ · %@", result[@"pointerKind"] ?: @"?", result[@"pointerSource"] ?: @"?"]
                               size:8.8 weight:UIFontWeightRegular color:self.theme.accentColor];
    source.frame = CGRectMake(13, 51, methodCard.bounds.size.width - 26, 16);
    [methodCard addSubview:source];
    [self.contentView addSubview:methodCard];
    y += 84.0;

    NSArray<NSString *> *addressLines = @[
        [NSString stringWithFormat:@"RVA / Offset      %@", result[@"rvaText"] ?: @"?"],
        [NSString stringWithFormat:@"Preferred / IDA   %@", ZN57MFHex([result[@"preferredVA"] unsignedLongLongValue])],
        [NSString stringWithFormat:@"Runtime VA        %@", ZN57MFHex([result[@"runtimeVA"] unsignedLongLongValue])],
        [NSString stringWithFormat:@"MethodInfo        %@", ZN57MFHex([result[@"methodInfo"] unsignedLongLongValue])],
        [NSString stringWithFormat:@"Method Pointer    %@", ZN57MFHex([result[@"methodPointer"] unsignedLongLongValue])],
    ];
    CGFloat addressH = 30.0 + 18.0 * addressLines.count + 8.0;
    UIView *addressCard = [self cardAtY:y height:addressH width:width compact:NO];
    UILabel *addressTitle = [self label:@"地址信息" size:11.0 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    addressTitle.frame = CGRectMake(13, 7, addressCard.bounds.size.width - 26, 18);
    [addressCard addSubview:addressTitle];
    CGFloat lineY = 29.0;
    for (NSString *line in addressLines) {
        UILabel *label = [self label:line size:9.2 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        label.frame = CGRectMake(13, lineY, addressCard.bounds.size.width - 26, 17);
        label.font = [UIFont monospacedDigitSystemFontOfSize:9.2 weight:UIFontWeightRegular];
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.70;
        [addressCard addSubview:label];
        lineY += 18.0;
    }
    [self.contentView addSubview:addressCard];
    y += addressH + 8.0;

    NSDictionary *stats = result[@"searchStats"] ?: @{};
    UIView *statsCard = [self cardAtY:y height:52 width:width compact:NO];
    UILabel *statsLabel = [self label:[NSString stringWithFormat:@"搜索：%@ · classes=%@ · %.1fms · candidates=%@",
                                      result[@"searchMode"] ?: @"?",
                                      stats[@"classesScanned"] ?: @0,
                                      [stats[@"elapsedMs"] doubleValue],
                                      stats[@"candidateCount"] ?: @1]
                                  size:8.8 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    statsLabel.frame = CGRectMake(13, 7, statsCard.bounds.size.width - 26, 38);
    statsLabel.numberOfLines = 2;
    [statsCard addSubview:statsLabel];
    [self.contentView addSubview:statsCard];
    y += 60.0;

    CGFloat gap = 8.0;
    CGFloat inner = width - 26.0;
    CGFloat bw = (inner - gap) / 2.0;
    UIView *actions = [self cardAtY:y height:52 width:width compact:NO];
    UIButton *copy = [self zn40_button:@"复制信息" selector:@selector(zn57mf_copyResult:) frame:CGRectMake(13, 9, bw, 34)];
    UIButton *builder = [self zn40_button:@"加入 Builder" selector:@selector(zn57mf_addToBuilder:) frame:CGRectMake(13 + bw + gap, 9, bw, 34)];
    builder.backgroundColor = [self.theme.accentColor colorWithAlphaComponent:0.20];
    builder.layer.borderColor = self.theme.accentColor.CGColor;
    [actions addSubview:copy];
    [actions addSubview:builder];
    [self.contentView addSubview:actions];
    y += 60.0;

    if (statusText.length) {
        UIView *statusCard = [self cardAtY:y height:48 width:width compact:NO];
        UILabel *status = [self label:statusText size:8.6 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        status.frame = CGRectMake(13, 6, statusCard.bounds.size.width - 26, 36);
        status.numberOfLines = 2;
        [statusCard addSubview:status];
        [self.contentView addSubview:statusCard];
        y += 56.0;
    }

    [self zn40_updateContentHeight:y];
}

- (void)zn57mf_queryChanged:(UITextField *)field {
    [self zn57mf_setQuery:field.text];
}

- (void)zn57mf_search:(id)sender {
    (void)sender;
    UITextField *field = (UITextField *)[self.contentView viewWithTag:kZN57MFQueryFieldTag];
    NSString *query = ZN57MFTrim(field.text.length ? field.text : [self zn57mf_query]);
    [self zn57mf_setQuery:query];
    [self.hostWindow endEditing:YES];
    if (!query.length) {
        [self zn57mf_setResult:nil];
        [self zn57mf_setStatus:@"请输入 IL2CPP 方法名"];
        [self renderPage];
        return;
    }

    CFAbsoluteTime began = CFAbsoluteTimeGetCurrent();
    NSString *searchError = nil;
    NSDictionary *result = [[ZNIL2CPPHybridFinder sharedFinder] resolveExpression:query error:&searchError];
    double elapsedMs = (CFAbsoluteTimeGetCurrent() - began) * 1000.0;
    [self zn57mf_setResult:result];
    if (result) {
        NSDictionary *stats = result[@"searchStats"] ?: @{};
        [self zn57mf_setStatus:[NSString stringWithFormat:@"找到 %@ · %@ · classes=%@ · %.1fms",
                                ZN57MFShortName(result),
                                result[@"searchMode"] ?: @"?",
                                stats[@"classesScanned"] ?: @0,
                                elapsedMs]];
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[method-finder] %@ -> %@ (%@, %.1fms)",
                                             query,
                                             result[@"rvaText"] ?: @"?",
                                             result[@"pointerKind"] ?: @"?",
                                             elapsedMs]];
    } else {
        [self zn57mf_setStatus:searchError ?: @"Method Finder 搜索失败"];
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[method-finder] %@ failed: %@", query, searchError ?: @"unknown"]];
    }
    [self renderPage];
}

- (void)zn57mf_copyResult:(id)sender {
    (void)sender;
    NSDictionary *result = [self zn57mf_result];
    if (!result) return;
    UIPasteboard.generalPasteboard.string = ZN57MFFullCopyText(result);
    [self zn57mf_setStatus:@"方法信息已复制"];
    [self renderPage];
}

- (void)zn57mf_addToBuilder:(id)sender {
    (void)sender;
    NSDictionary *result = [self zn57mf_result];
    NSString *query = [self zn57mf_query];
    if (!result || !query.length) return;

    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    if (workspace.hasAnyApplied || workspace.isBuilding) {
        [self zn57mf_setStatus:@"Builder 当前被 Runtime Patch/生成任务锁定，请先恢复或等待生成结束"];
        [self renderPage];
        return;
    }

    NSString *featureName = [workspace addFeature];
    if (!featureName.length || !workspace.rows.count) {
        [self zn57mf_setStatus:workspace.lastStatus.length ? workspace.lastStatus : @"无法创建 Builder 行"];
        [self renderPage];
        return;
    }

    ZNBinaryPatchRow *row = workspace.rows.lastObject;
    NSString *suggested = ZN57MFShortName(result);
    if (suggested.length) {
        NSString *renameError = nil;
        if (![workspace renameFeature:featureName to:suggested error:&renameError]) {
            (void)renameError;
        }
    }
    row.target = @"UnityFramework";
    row.explicitTarget = YES;
    row.offsetText = query;
    row.enabledText = @"";
    row.originalHex = @"";
    row.validated = NO;
    row.validator = nil;
    row.statusText = @"来自 Method Finder · 请填写 Patch 字节后执行读取验证";
    workspace.lastStatus = [NSString stringWithFormat:@"Method Finder 已加入 Builder：%@；尚未写入 Patch 字节", suggested.length ? suggested : query];

    NSInteger other = [self.categories indexOfObject:@"其他"];
    if (other != NSNotFound) {
        self.selectedCategory = other;
        [NSUserDefaults.standardUserDefaults setInteger:other forKey:@"ZonoePatch.SelectedCategory"];
    }
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[method-finder] added to Builder: %@", query]];
    [self renderPage];
}

@end

static void ZN57MFSwapInstanceMethod(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallIL2CPPMethodFinderUIDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZN57MFSwapInstanceMethod(cls, @selector(zn40_baseCategories), @selector(zn57mf_baseCategories));
        ZN57MFSwapInstanceMethod(cls, @selector(zn40_baseSymbols), @selector(zn57mf_baseSymbols));
        ZN57MFSwapInstanceMethod(cls, @selector(renderFullPage), @selector(zn57mf_renderFullPage));
        ZN57MFSwapInstanceMethod(cls, @selector(fullSizeForWindow:), @selector(zn57mf_fullSizeForWindow:));
        [[ZNRuntimeLogger sharedLogger] log:@"[bootstrap][main] v0.5.7 Method Finder UI installed: bounded search -> detail -> Builder"];
    });
}
