#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNIL2CPPHybridFinder.h"
#import "ZNIL2CPPMethodFinderSearchV3.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

// v0.5.8-dev Method Finder V3 UI milestone 1:
// search -> candidate list -> method detail -> existing validated Builder.
// The V2 backend remains installed for Named Offset and single-result workflows.

static const void *kZN60V3PageKey = &kZN60V3PageKey;
static const void *kZN60V3CandidatesKey = &kZN60V3CandidatesKey;
static const void *kZN60V3SelectedKey = &kZN60V3SelectedKey;
static const void *kZN60V3StatusKey = &kZN60V3StatusKey;
static const void *kZN60V3LimitKey = &kZN60V3LimitKey;
static const void *kZN60V3CopyValueKey = &kZN60V3CopyValueKey;
static const NSInteger kZN60V3FieldTag = 603001;
static const NSInteger kZN60V3CandidateTagBase = 603100;

typedef NS_ENUM(NSInteger, ZN60V3Page) {
    ZN60V3PageSearch = 0,
    ZN60V3PageResults = 1,
    ZN60V3PageDetail = 2,
};

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIScrollView *contentScroll;
@property(nonatomic,strong) UIWindow *hostWindow;
@property(nonatomic,copy) NSArray<NSString *> *categories;
@property(nonatomic,assign) NSInteger selectedCategory;
@property(nonatomic,strong) ZNTheme *theme;
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIFont *)menuFont:(CGFloat)size weight:(UIFontWeight)weight;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)renderPage;
- (NSString *)zn57mf_query;
- (void)zn57mf_setQuery:(NSString *)value;
- (void)zn57mf_setResult:(NSDictionary *)value;
- (void)zn57mf_addToBuilder:(id)sender;
- (void)zn57mf_renderFinder;
@end

static NSString *ZN60V3Hex(uint64_t value) {
    return value ? [NSString stringWithFormat:@"0x%llX", (unsigned long long)value] : @"—";
}

static NSString *ZN60V3ClassPath(NSDictionary *candidate) {
    NSString *ns = candidate[@"namespace"] ?: @"";
    NSString *cls = candidate[@"class"] ?: @"";
    return ns.length ? [NSString stringWithFormat:@"%@.%@", ns, cls] : cls;
}

static NSString *ZN60V3ShortName(NSDictionary *candidate) {
    NSString *method = candidate[@"method"] ?: @"Method";
    NSInteger argc = [candidate[@"argumentCount"] integerValue];
    return argc >= 0 ? [NSString stringWithFormat:@"%@/%ld", method, (long)argc] : method;
}

static NSString *ZN60V3CopyText(NSDictionary *candidate) {
    return [NSString stringWithFormat:
            @"%@\nAssembly: %@\nNamespace: %@\nClass: %@\nMethod: %@\nRVA: %@\nPreferred VA: %@\nRuntime VA: %@\nMethodInfo: %@\nMethod Pointer: %@\nPointer Source: %@\nPointer Type: %@\nOriginal 16B: %@",
            candidate[@"canonical"] ?: @"IL2CPP Method",
            candidate[@"assembly"] ?: @"",
            candidate[@"namespace"] ?: @"",
            candidate[@"class"] ?: @"",
            candidate[@"method"] ?: @"",
            candidate[@"rvaText"] ?: @"—",
            ZN60V3Hex([candidate[@"preferredVA"] unsignedLongLongValue]),
            ZN60V3Hex([candidate[@"runtimeVA"] unsignedLongLongValue]),
            ZN60V3Hex([candidate[@"methodInfo"] unsignedLongLongValue]),
            ZN60V3Hex([candidate[@"methodPointer"] unsignedLongLongValue]),
            candidate[@"pointerSource"] ?: @"unavailable",
            candidate[@"pointerKind"] ?: @"unavailable",
            candidate[@"codePreview"] ?: @""];
}

@interface ZNRuntimeMenuControllerV040 (ZNIL2CPPMethodFinderUIV3)
- (void)zn60v3_renderFinder;
- (void)zn60v3_queryChanged:(UITextField *)field;
- (void)zn60v3_startSearch:(id)sender;
- (void)zn60v3_cycleLimit:(id)sender;
- (void)zn60v3_candidateTapped:(UIButton *)sender;
- (void)zn60v3_backToSearch:(id)sender;
- (void)zn60v3_backToResults:(id)sender;
- (void)zn60v3_copyValue:(UIButton *)sender;
- (void)zn60v3_copyAll:(id)sender;
- (void)zn60v3_createPatch:(id)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNIL2CPPMethodFinderUIV3)

- (ZN60V3Page)zn60v3_page {
    NSNumber *value = objc_getAssociatedObject(self, kZN60V3PageKey);
    return value ? (ZN60V3Page)value.integerValue : ZN60V3PageSearch;
}

- (void)zn60v3_setPage:(ZN60V3Page)page {
    objc_setAssociatedObject(self, kZN60V3PageKey, @(page), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSArray<NSDictionary *> *)zn60v3_candidates {
    return objc_getAssociatedObject(self, kZN60V3CandidatesKey) ?: @[];
}

- (void)zn60v3_setCandidates:(NSArray<NSDictionary *> *)items {
    objc_setAssociatedObject(self, kZN60V3CandidatesKey, [items copy] ?: @[], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSDictionary *)zn60v3_selected {
    return objc_getAssociatedObject(self, kZN60V3SelectedKey);
}

- (void)zn60v3_setSelected:(NSDictionary *)candidate {
    objc_setAssociatedObject(self, kZN60V3SelectedKey, candidate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSString *)zn60v3_status {
    return objc_getAssociatedObject(self, kZN60V3StatusKey) ?: @"";
}

- (void)zn60v3_setStatus:(NSString *)status {
    objc_setAssociatedObject(self, kZN60V3StatusKey, status ?: @"", OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (NSUInteger)zn60v3_limit {
    NSNumber *value = objc_getAssociatedObject(self, kZN60V3LimitKey);
    return value ? value.unsignedIntegerValue : 32;
}

- (void)zn60v3_setLimit:(NSUInteger)limit {
    objc_setAssociatedObject(self, kZN60V3LimitKey, @(limit), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (UIButton *)zn60v3_plainButton:(NSString *)title selector:(SEL)selector frame:(CGRect)frame {
    UIButton *button = [self zn40_button:title selector:selector frame:frame];
    button.backgroundColor = [self.theme.controlColor colorWithAlphaComponent:0.78];
    button.layer.borderColor = self.theme.borderColor.CGColor;
    return button;
}

- (UITextField *)zn60v3_searchField:(CGRect)frame {
    UITextField *field = [[UITextField alloc] initWithFrame:frame];
    field.tag = kZN60V3FieldTag;
    field.text = [self zn57mf_query];
    field.placeholder = @"方法名 / Class::Method/0 / 0xRVA";
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
    [field addTarget:self action:@selector(zn60v3_queryChanged:) forControlEvents:UIControlEventEditingChanged];
    [field addTarget:self action:@selector(zn60v3_startSearch:) forControlEvents:UIControlEventEditingDidEndOnExit];
    return field;
}

- (void)zn60v3_renderSearchAtWidth:(CGFloat)width {
    CGFloat y = 9.0;
    UIView *searchCard = [self cardAtY:y height:84 width:width compact:NO];
    UILabel *title = [self label:@"IL2CPP 方法查找 · V3" size:12.6 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    title.frame = CGRectMake(13, 8, searchCard.bounds.size.width - 26, 20);
    [searchCard addSubview:title];
    CGFloat buttonW = 68.0;
    UITextField *field = [self zn60v3_searchField:CGRectMake(13, 35, searchCard.bounds.size.width - 26 - buttonW - 7, 36)];
    [searchCard addSubview:field];
    UIButton *search = [self zn40_button:@"搜索" selector:@selector(zn60v3_startSearch:) frame:CGRectMake(CGRectGetMaxX(field.frame) + 7, 35, buttonW, 36)];
    search.backgroundColor = [self.theme.accentColor colorWithAlphaComponent:0.20];
    search.layer.borderColor = self.theme.accentColor.CGColor;
    [searchCard addSubview:search];
    [self.contentView addSubview:searchCard];
    y += 92.0;

    UIView *options = [self cardAtY:y height:104 width:width compact:NO];
    UILabel *ot = [self label:@"搜索选项" size:10.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    ot.frame = CGRectMake(13, 8, options.bounds.size.width - 26, 18);
    [options addSubview:ot];
    UILabel *flags = [self label:@"✓ 忽略大小写（精确方法名）    ✓ Assembly-CSharp 优先" size:8.8 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    flags.frame = CGRectMake(13, 31, options.bounds.size.width - 26, 18);
    [options addSubview:flags];
    UILabel *formats = [self label:@"支持：Method · Class::Method · Namespace.Class::Method · Assembly!… · 0xRVA" size:8.1 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    formats.frame = CGRectMake(13, 52, options.bounds.size.width - 26, 18);
    formats.adjustsFontSizeToFitWidth = YES;
    formats.minimumScaleFactor = 0.72;
    [options addSubview:formats];
    UIButton *limit = [self zn60v3_plainButton:[NSString stringWithFormat:@"最大结果：%lu", (unsigned long)[self zn60v3_limit]] selector:@selector(zn60v3_cycleLimit:) frame:CGRectMake(13, 73, 122, 25)];
    limit.titleLabel.font = [self menuFont:8.5 weight:UIFontWeightMedium];
    [options addSubview:limit];
    UILabel *stage = [self label:@"阶段 1：多候选工作流；异步分片/本地索引将在下一里程碑接入" size:7.8 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    stage.frame = CGRectMake(143, 75, options.bounds.size.width - 156, 22);
    stage.numberOfLines = 2;
    [options addSubview:stage];
    [self.contentView addSubview:options];
    y += 112.0;

    NSString *statusText = [self zn60v3_status];
    if (statusText.length) {
        UIView *statusCard = [self cardAtY:y height:64 width:width compact:NO];
        UILabel *status = [self label:statusText size:9.0 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        status.frame = CGRectMake(13, 8, statusCard.bounds.size.width - 26, 48);
        status.numberOfLines = 3;
        status.lineBreakMode = NSLineBreakByWordWrapping;
        [statusCard addSubview:status];
        [self.contentView addSubview:statusCard];
        y += 72.0;
    }
    [self zn40_updateContentHeight:y];
}

- (void)zn60v3_renderResultsAtWidth:(CGFloat)width {
    CGFloat y = 9.0;
    NSArray<NSDictionary *> *items = [self zn60v3_candidates];
    UIView *header = [self cardAtY:y height:48 width:width compact:NO];
    UIButton *back = [self zn60v3_plainButton:@"‹ 搜索" selector:@selector(zn60v3_backToSearch:) frame:CGRectMake(10, 8, 70, 31)];
    [header addSubview:back];
    UILabel *title = [self label:[NSString stringWithFormat:@"搜索结果（%lu）", (unsigned long)items.count] size:11.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    title.frame = CGRectMake(88, 8, header.bounds.size.width - 100, 31);
    [header addSubview:title];
    [self.contentView addSubview:header];
    y += 56.0;

    NSDictionary *stats = items.firstObject[@"searchStats"] ?: @{};
    UIView *summary = [self cardAtY:y height:48 width:width compact:NO];
    NSString *summaryText = [NSString stringWithFormat:@"%@ · classes=%@ · shards=%@ · %.1fms%@", stats[@"mode"] ?: @"candidate-list", stats[@"classesScanned"] ?: @0, stats[@"shardsScanned"] ?: @0, [stats[@"elapsedMs"] doubleValue], [stats[@"truncated"] boolValue] ? @" · 结果已截断" : @""];
    UILabel *sl = [self label:summaryText size:8.6 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    sl.frame = CGRectMake(13, 8, summary.bounds.size.width - 26, 32);
    sl.numberOfLines = 2;
    [summary addSubview:sl];
    [self.contentView addSubview:summary];
    y += 56.0;

    for (NSUInteger i = 0; i < items.count; i++) {
        NSDictionary *candidate = items[i];
        UIView *card = [self cardAtY:y height:72 width:width compact:NO];
        UILabel *name = [self label:ZN60V3ShortName(candidate) size:10.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
        name.frame = CGRectMake(13, 8, card.bounds.size.width - 112, 18);
        [card addSubview:name];
        NSString *rva = candidate[@"rvaText"] ?: @"—";
        UILabel *rvaLabel = [self label:[NSString stringWithFormat:@"RVA %@", rva] size:8.8 weight:UIFontWeightSemibold color:self.theme.accentColor];
        rvaLabel.frame = CGRectMake(card.bounds.size.width - 98, 8, 85, 18);
        rvaLabel.textAlignment = NSTextAlignmentRight;
        [card addSubview:rvaLabel];
        UILabel *assembly = [self label:candidate[@"assembly"] ?: @"?" size:8.6 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        assembly.frame = CGRectMake(13, 29, card.bounds.size.width - 26, 16);
        [card addSubview:assembly];
        UILabel *owner = [self label:ZN60V3ClassPath(candidate) size:8.8 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        owner.frame = CGRectMake(13, 48, card.bounds.size.width - 120, 16);
        owner.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [card addSubview:owner];
        UILabel *kind = [self label:candidate[@"pointerKind"] ?: @"unavailable" size:7.8 weight:UIFontWeightRegular color:self.theme.accentColor];
        kind.frame = CGRectMake(card.bounds.size.width - 110, 48, 97, 16);
        kind.textAlignment = NSTextAlignmentRight;
        [card addSubview:kind];
        UIButton *tap = [UIButton buttonWithType:UIButtonTypeCustom];
        tap.frame = card.bounds;
        tap.tag = kZN60V3CandidateTagBase + (NSInteger)i;
        [tap addTarget:self action:@selector(zn60v3_candidateTapped:) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:tap];
        [self.contentView addSubview:card];
        y += 80.0;
    }
    [self zn40_updateContentHeight:y];
}

- (void)zn60v3_addCopyButtonToCard:(UIView *)card title:(NSString *)title value:(NSString *)value y:(CGFloat)y {
    UILabel *label = [self label:[NSString stringWithFormat:@"%@    %@", title, value ?: @"—"] size:8.8 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    label.frame = CGRectMake(13, y, card.bounds.size.width - 71, 17);
    label.font = [UIFont monospacedDigitSystemFontOfSize:8.8 weight:UIFontWeightRegular];
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.68;
    [card addSubview:label];
    UIButton *copy = [self zn60v3_plainButton:@"复制" selector:@selector(zn60v3_copyValue:) frame:CGRectMake(card.bounds.size.width - 53, y - 2, 40, 21)];
    copy.titleLabel.font = [self menuFont:7.6 weight:UIFontWeightSemibold];
    objc_setAssociatedObject(copy, kZN60V3CopyValueKey, value ?: @"", OBJC_ASSOCIATION_COPY_NONATOMIC);
    [card addSubview:copy];
}

- (void)zn60v3_renderDetailAtWidth:(CGFloat)width {
    NSDictionary *candidate = [self zn60v3_selected];
    if (!candidate) {
        [self zn60v3_setPage:ZN60V3PageResults];
        [self zn60v3_renderResultsAtWidth:width];
        return;
    }

    CGFloat y = 9.0;
    UIView *header = [self cardAtY:y height:48 width:width compact:NO];
    UIButton *back = [self zn60v3_plainButton:@"‹ 结果" selector:@selector(zn60v3_backToResults:) frame:CGRectMake(10, 8, 70, 31)];
    [header addSubview:back];
    UILabel *title = [self label:@"方法详细信息" size:11.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    title.frame = CGRectMake(88, 8, header.bounds.size.width - 100, 31);
    [header addSubview:title];
    [self.contentView addSubview:header];
    y += 56.0;

    UIView *identity = [self cardAtY:y height:118 width:width compact:NO];
    UILabel *name = [self label:ZN60V3ShortName(candidate) size:12.0 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    name.frame = CGRectMake(13, 8, identity.bounds.size.width - 26, 20);
    [identity addSubview:name];
    NSArray *meta = @[
        [NSString stringWithFormat:@"Assembly      %@", candidate[@"assembly"] ?: @""],
        [NSString stringWithFormat:@"Namespace     %@", candidate[@"namespace"] ?: @""],
        [NSString stringWithFormat:@"Class         %@", candidate[@"class"] ?: @""],
        [NSString stringWithFormat:@"Pointer Type  %@ · %@", candidate[@"pointerKind"] ?: @"?", candidate[@"pointerSource"] ?: @"?"]
    ];
    CGFloat my = 32;
    for (NSString *line in meta) {
        UILabel *l = [self label:line size:8.6 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        l.frame = CGRectMake(13, my, identity.bounds.size.width - 26, 17);
        l.adjustsFontSizeToFitWidth = YES;
        l.minimumScaleFactor = 0.7;
        [identity addSubview:l];
        my += 19;
    }
    [self.contentView addSubview:identity];
    y += 126.0;

    UIView *address = [self cardAtY:y height:150 width:width compact:NO];
    UILabel *at = [self label:@"地址信息" size:10.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    at.frame = CGRectMake(13, 7, address.bounds.size.width - 26, 18);
    [address addSubview:at];
    [self zn60v3_addCopyButtonToCard:address title:@"RVA / Offset" value:candidate[@"rvaText"] ?: @"—" y:29];
    [self zn60v3_addCopyButtonToCard:address title:@"Preferred VA" value:ZN60V3Hex([candidate[@"preferredVA"] unsignedLongLongValue]) y:51];
    [self zn60v3_addCopyButtonToCard:address title:@"Runtime VA" value:ZN60V3Hex([candidate[@"runtimeVA"] unsignedLongLongValue]) y:73];
    [self zn60v3_addCopyButtonToCard:address title:@"MethodInfo" value:ZN60V3Hex([candidate[@"methodInfo"] unsignedLongLongValue]) y:95];
    [self zn60v3_addCopyButtonToCard:address title:@"Method Pointer" value:ZN60V3Hex([candidate[@"methodPointer"] unsignedLongLongValue]) y:117];
    [self.contentView addSubview:address];
    y += 158.0;

    UIView *bytes = [self cardAtY:y height:70 width:width compact:NO];
    UILabel *bt = [self label:@"原始代码（前 16 字节）" size:10.0 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    bt.frame = CGRectMake(13, 7, bytes.bounds.size.width - 26, 18);
    [bytes addSubview:bt];
    NSString *preview = candidate[@"codePreview"] ?: @"";
    UILabel *bv = [self label:(preview.length ? preview : @"当前方法没有可安全读取的 native code preview") size:8.6 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    bv.frame = CGRectMake(13, 31, bytes.bounds.size.width - 66, 26);
    bv.numberOfLines = 2;
    bv.font = [UIFont monospacedDigitSystemFontOfSize:8.3 weight:UIFontWeightRegular];
    [bytes addSubview:bv];
    if (preview.length) {
        UIButton *copy = [self zn60v3_plainButton:@"复制" selector:@selector(zn60v3_copyValue:) frame:CGRectMake(bytes.bounds.size.width - 53, 32, 40, 22)];
        copy.titleLabel.font = [self menuFont:7.6 weight:UIFontWeightSemibold];
        objc_setAssociatedObject(copy, kZN60V3CopyValueKey, preview, OBJC_ASSOCIATION_COPY_NONATOMIC);
        [bytes addSubview:copy];
    }
    [self.contentView addSubview:bytes];
    y += 78.0;

    CGFloat inner = width - 26.0, gap = 8.0;
    CGFloat bw = (inner - gap) / 2.0;
    UIButton *copyAll = [self zn60v3_plainButton:@"复制信息" selector:@selector(zn60v3_copyAll:) frame:CGRectMake(13, y, bw, 34)];
    [self.contentView addSubview:copyAll];
    BOOL canBuilder = [self.categories containsObject:@"其他"] && [candidate[@"addressResolved"] boolValue];
    UIButton *patch = [self zn40_button:(canBuilder ? @"创建 Patch" : @"创建 Patch（不可用）") selector:@selector(zn60v3_createPatch:) frame:CGRectMake(13 + bw + gap, y, bw, 34)];
    patch.enabled = canBuilder;
    patch.alpha = canBuilder ? 1.0 : 0.55;
    patch.backgroundColor = [self.theme.accentColor colorWithAlphaComponent:0.20];
    patch.layer.borderColor = self.theme.accentColor.CGColor;
    [self.contentView addSubview:patch];
    y += 42.0;

    UILabel *note = [self label:@"V3 当前“创建 Patch”仍复用已验证的 V2 Builder/Validator 链路；Return Override / Hook Backend 将在后续阶段加入。" size:7.8 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    note.frame = CGRectMake(13, y, width - 26, 34);
    note.numberOfLines = 2;
    [self.contentView addSubview:note];
    y += 42.0;
    [self zn40_updateContentHeight:y];
}

- (void)zn60v3_renderFinder {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    switch ([self zn60v3_page]) {
        case ZN60V3PageResults: [self zn60v3_renderResultsAtWidth:width]; break;
        case ZN60V3PageDetail: [self zn60v3_renderDetailAtWidth:width]; break;
        case ZN60V3PageSearch:
        default: [self zn60v3_renderSearchAtWidth:width]; break;
    }
}

- (void)zn60v3_queryChanged:(UITextField *)field {
    [self zn57mf_setQuery:field.text ?: @""];
}

- (void)zn60v3_startSearch:(id)sender {
    [self.hostWindow endEditing:YES];
    NSString *query = [self zn57mf_query];
    if (!query.length) {
        UITextField *field = (UITextField *)[self.contentView viewWithTag:kZN60V3FieldTag];
        query = field.text ?: @"";
        [self zn57mf_setQuery:query];
    }
    NSString *searchError = nil;
    NSArray *items = [[ZNIL2CPPHybridFinder sharedFinder] zn60_searchCandidates:query limit:[self zn60v3_limit] error:&searchError];
    if (!items.count) {
        [self zn60v3_setStatus:searchError ?: @"没有搜索结果"];
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[method-finder-v3] %@ failed: %@", query ?: @"", searchError ?: @"unknown"]];
        [self zn60v3_setPage:ZN60V3PageSearch];
        [self renderPage];
        return;
    }
    [self zn60v3_setCandidates:items];
    [self zn60v3_setSelected:nil];
    NSDictionary *stats = items.firstObject[@"searchStats"] ?: @{};
    [self zn60v3_setStatus:[NSString stringWithFormat:@"%@：%lu 个候选 · %@ classes · %.1fms", query ?: @"搜索", (unsigned long)items.count, stats[@"classesScanned"] ?: @0, [stats[@"elapsedMs"] doubleValue]]];
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[method-finder-v3] %@ -> %lu candidates (%.1fms)", query ?: @"", (unsigned long)items.count, [stats[@"elapsedMs"] doubleValue]]];
    [self zn60v3_setPage:ZN60V3PageResults];
    [self renderPage];
}

- (void)zn60v3_cycleLimit:(id)sender {
    NSUInteger current = [self zn60v3_limit];
    NSUInteger next = current == 8 ? 16 : current == 16 ? 32 : current == 32 ? 64 : 8;
    [self zn60v3_setLimit:next];
    [self renderPage];
}

- (void)zn60v3_candidateTapped:(UIButton *)sender {
    NSInteger index = sender.tag - kZN60V3CandidateTagBase;
    NSArray *items = [self zn60v3_candidates];
    if (index < 0 || index >= (NSInteger)items.count) return;
    [self zn60v3_setSelected:items[(NSUInteger)index]];
    [self zn60v3_setPage:ZN60V3PageDetail];
    [self renderPage];
}

- (void)zn60v3_backToSearch:(id)sender {
    [self zn60v3_setPage:ZN60V3PageSearch];
    [self renderPage];
}

- (void)zn60v3_backToResults:(id)sender {
    [self zn60v3_setPage:ZN60V3PageResults];
    [self renderPage];
}

- (void)zn60v3_copyValue:(UIButton *)sender {
    NSString *value = objc_getAssociatedObject(sender, kZN60V3CopyValueKey) ?: @"";
    if (!value.length || [value isEqualToString:@"—"]) return;
    UIPasteboard.generalPasteboard.string = value;
    [self zn60v3_setStatus:[NSString stringWithFormat:@"已复制：%@", value]];
}

- (void)zn60v3_copyAll:(id)sender {
    NSDictionary *candidate = [self zn60v3_selected];
    if (!candidate) return;
    UIPasteboard.generalPasteboard.string = ZN60V3CopyText(candidate);
    [self zn60v3_setStatus:@"已复制完整方法信息"];
}

- (void)zn60v3_createPatch:(id)sender {
    NSDictionary *candidate = [self zn60v3_selected];
    if (!candidate || ![candidate[@"addressResolved"] boolValue]) return;
    // Preserve the proven Builder/Runtime Validator transaction chain. V3 only
    // changes discovery/navigation in this milestone.
    [self zn57mf_setResult:candidate];
    [self zn57mf_addToBuilder:sender];
}

@end

extern "C" void ZNInstallIL2CPPMethodFinderV3Deferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        Method original = class_getInstanceMethod(cls, @selector(zn57mf_renderFinder));
        Method replacement = class_getInstanceMethod(cls, @selector(zn60v3_renderFinder));
        if (original && replacement) method_exchangeImplementations(original, replacement);
    });
}
