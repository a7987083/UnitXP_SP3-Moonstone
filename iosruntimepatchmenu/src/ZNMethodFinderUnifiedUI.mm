#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNIL2CPPABIMetadata.h"
#import "ZNIL2CPPMethodSignature.h"
#import "ZNRuntimeActionFormat.h"
#import "ZNRuntimeActionModel.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

// M5.4 Method Finder UI consolidation.
// This is the only final Search / Results / Detail renderer. It intentionally
// does NOT call the previous renderer implementation after swizzling; older UI
// generations stay compiled only for backend/action compatibility.

static NSString * const kZNM54HistoryDefaultsKey = @"zonoe.m52.method-search-history.v1";
static const NSUInteger kZNM54HistoryMax = 50;
static const NSInteger kZNM54QueryTag = 954001;
static const NSInteger kZNM54LimitTag = 954002;
static const void *kZNM54CandidateKey = &kZNM54CandidateKey;
static const void *kZNM54StoreKey = &kZNM54StoreKey;
static const void *kZNM54FilterKey = &kZNM54FilterKey;
static const void *kZNM54HistoryKey = &kZNM54HistoryKey;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIWindow *hostWindow;
@property(nonatomic,strong) ZNTheme *theme;
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIFont *)menuFont:(CGFloat)size weight:(UIFontWeight)weight;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (UIButton *)zn60v3_plainButton:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)renderPage;

- (NSString *)zn57mf_query;
- (void)zn57mf_setQuery:(NSString *)value;
- (NSUInteger)zn60v3_limit;
- (void)zn60v3_setLimit:(NSUInteger)value;
- (NSArray<NSDictionary *> *)zn60v3_candidates;
- (void)zn60v3_setCandidates:(NSArray<NSDictionary *> *)items;
- (NSDictionary *)zn60v3_selected;
- (void)zn60v3_setSelected:(NSDictionary *)candidate;
- (void)zn60v3_setPage:(NSInteger)page;
- (NSString *)zn60v3_status;
- (void)zn60v3_setStatus:(NSString *)status;
- (void)zn60v3_backToSearch:(id)sender;
- (void)zn60v3_backToResults:(id)sender;

- (NSInteger)znm42_filter;
- (void)znm42_setFilter:(NSInteger)value;
- (NSMutableDictionary<NSString *, NSString *> *)znm42_inputStore;
- (NSArray<NSString *> *)znm43_argumentValues:(NSDictionary *)candidate;
- (NSString *)znm43_selectedAssembly;
- (void)znm43_assemblyTapped:(UIButton *)sender;
- (void)znm442_submitSearch:(id)sender;
- (void)znm43_testCandidate:(UIButton *)sender;
@end

@interface ZNRuntimeMenuControllerV040 (ZNMethodFinderUnifiedUI)
- (void)znm54_renderSearchAtWidth:(CGFloat)width;
- (void)znm54_renderResultsAtWidth:(CGFloat)width;
- (void)znm54_renderDetailAtWidth:(CGFloat)width;
- (void)znm54_queryChanged:(UITextField *)field;
- (void)znm54_limitChanged:(UITextField *)field;
- (void)znm54_submitSearch:(id)sender;
- (void)znm54_historyTapped:(UIButton *)sender;
- (void)znm54_filterTapped:(UIButton *)sender;
- (void)znm54_argumentChanged:(UITextField *)field;
- (void)znm54_done:(UITextField *)field;
- (void)znm54_openDetail:(UIButton *)sender;
- (void)znm54_createCandidate:(UIButton *)sender;
@end

static NSString *ZNM54Trim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *ZNM54AssemblyDisplay(NSString *assembly) {
    NSString *s = assembly ?: @"";
    return [s.lowercaseString hasSuffix:@".dll"] && s.length > 4 ? [s substringToIndex:s.length - 4] : s;
}

static NSString *ZNM54CandidateIdentity(NSDictionary *candidate) {
    NSString *canonical = [candidate[@"canonical"] isKindOfClass:NSString.class] ? candidate[@"canonical"] : @"";
    if (canonical.length) return canonical;
    return [NSString stringWithFormat:@"%@|%@|%@|%@|%@",
            candidate[@"assembly"] ?: @"", candidate[@"namespace"] ?: @"", candidate[@"class"] ?: @"",
            candidate[@"method"] ?: @"", candidate[@"argumentCount"] ?: @(-1)];
}

static NSString *ZNM54ArgStoreKey(NSDictionary *candidate, NSUInteger index) {
    NSUInteger argc = [candidate[@"argumentCount"] unsignedIntegerValue];
    NSString *identity = ZNM54CandidateIdentity(candidate);
    return argc <= 1 ? identity : [NSString stringWithFormat:@"%@#arg:%lu", identity, (unsigned long)index];
}

static NSString *ZNM54ShortType(NSString *type) {
    NSArray<NSString *> *parts = [(type ?: @"") componentsSeparatedByString:@"."];
    NSString *last = parts.lastObject;
    return last.length ? last : (type ?: @"?");
}

static BOOL ZNM54IsString(NSString *type) {
    NSString *n = ZNM54Trim(type).lowercaseString;
    return [n isEqualToString:@"system.string"] || [n isEqualToString:@"string"];
}

static NSUInteger ZNM54StructCount(NSString *type) {
    NSString *n = ZNM54Trim(type).lowercaseString;
    if ([n isEqualToString:@"unityengine.vector2"] || [n isEqualToString:@"vector2"]) return 2;
    if ([n isEqualToString:@"unityengine.vector3"] || [n isEqualToString:@"vector3"]) return 3;
    if ([n isEqualToString:@"unityengine.quaternion"] || [n isEqualToString:@"quaternion"] ||
        [n isEqualToString:@"unityengine.color"] || [n isEqualToString:@"color"]) return 4;
    return 0;
}

static NSString *ZNM54UnsupportedReason(NSDictionary *param) {
    if ([param[@"byRef"] boolValue]) return @"ref/out 暂不支持";
    if ([param[@"pointer"] boolValue]) return @"pointer 暂不支持";
    NSString *type = [param[@"name"] isKindOfClass:NSString.class] ? param[@"name"] : @"?";
    if (ZNM54IsString(type)) return nil;
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
            return ZNM54StructCount(type) ? nil : [NSString stringWithFormat:@"%@ 暂不支持", ZNM54ShortType(type)];
        case ZNIL2CPPABIValueKindObjectReference:
            return [NSString stringWithFormat:@"%@ 对象参数暂不支持", ZNM54ShortType(type)];
        default:
            return [NSString stringWithFormat:@"%@ 类型未识别", ZNM54ShortType(type)];
    }
}

static NSArray<NSString *> *ZNM54History(void) {
    id raw = [[NSUserDefaults standardUserDefaults] objectForKey:kZNM54HistoryDefaultsKey];
    if (![raw isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (id item in (NSArray *)raw) {
        if (![item isKindOfClass:NSString.class]) continue;
        NSString *value = ZNM54Trim(item);
        if (!value.length) continue;
        BOOL duplicate = NO;
        for (NSString *existing in out) {
            if ([existing caseInsensitiveCompare:value] == NSOrderedSame) { duplicate = YES; break; }
        }
        if (duplicate) continue;
        [out addObject:value];
        if (out.count >= kZNM54HistoryMax) break;
    }
    return [out copy];
}

static void ZNM54RecordHistory(NSString *query) {
    NSString *value = ZNM54Trim(query);
    if (!value.length) return;
    NSMutableArray<NSString *> *items = [ZNM54History() mutableCopy];
    NSIndexSet *matches = [items indexesOfObjectsPassingTest:^BOOL(NSString *obj, NSUInteger idx, BOOL *stop) {
        (void)idx; (void)stop;
        return [obj caseInsensitiveCompare:value] == NSOrderedSame;
    }];
    if (matches.count) [items removeObjectsAtIndexes:matches];
    [items insertObject:value atIndex:0];
    if (items.count > kZNM54HistoryMax) [items removeObjectsInRange:NSMakeRange(kZNM54HistoryMax, items.count - kZNM54HistoryMax)];
    [[NSUserDefaults standardUserDefaults] setObject:items forKey:kZNM54HistoryDefaultsKey];
}

static UITextField *ZNM54Field(CGRect frame, ZNTheme *theme, UIFont *font) {
    UITextField *field = [[UITextField alloc] initWithFrame:frame];
    field.textColor = theme.primaryTextColor;
    field.backgroundColor = theme.controlColor;
    field.tintColor = theme.accentColor;
    field.font = font;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.spellCheckingType = UITextSpellCheckingTypeNo;
    field.layer.cornerRadius = 7.0;
    field.layer.borderWidth = 1.0;
    field.layer.borderColor = theme.borderColor.CGColor;
    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 1)];
    field.leftView = pad;
    field.leftViewMode = UITextFieldViewModeAlways;
    return field;
}

static NSArray<NSDictionary *> *ZNM54Visible(ZNRuntimeMenuControllerV040 *controller) {
    NSArray<NSDictionary *> *all = [controller zn60v3_candidates] ?: @[];
    NSInteger filter = [controller znm42_filter];
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *candidate in all) {
        if (filter < 0 || [candidate[@"argumentCount"] integerValue] == filter) [out addObject:candidate];
    }
    return out;
}

@implementation ZNRuntimeMenuControllerV040 (ZNMethodFinderUnifiedUI)

- (void)znm54_queryChanged:(UITextField *)field {
    [self zn57mf_setQuery:field.text ?: @""];
}

- (void)znm54_limitChanged:(UITextField *)field {
    NSInteger raw = field.text.integerValue;
    if (raw > 0) [self zn60v3_setLimit:(NSUInteger)MAX(1, MIN(1024, raw))];
}

- (void)znm54_submitSearch:(id)sender {
    [self.hostWindow endEditing:YES];
    ZNM54RecordHistory([self zn57mf_query]);
    [self znm442_submitSearch:sender];
}

- (void)znm54_historyTapped:(UIButton *)sender {
    NSString *value = objc_getAssociatedObject(sender, kZNM54HistoryKey);
    if (!value.length) return;
    [self zn57mf_setQuery:value];
    UITextField *query = (UITextField *)[self.contentView viewWithTag:kZNM54QueryTag];
    if ([query isKindOfClass:UITextField.class]) {
        query.text = value;
        [query becomeFirstResponder];
    }
}

- (void)znm54_renderSearchAtWidth:(CGFloat)width {
    CGFloat y = 9.0;
    UIView *card = [self cardAtY:y height:170.0 width:width compact:NO];
    UILabel *title = [self label:@"IL2CPP 方法查找 · Unified" size:12.6 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    title.frame = CGRectMake(13, 8, card.bounds.size.width - 26, 20);
    [card addSubview:title];

    UILabel *methodLabel = [self label:@"方法名" size:8.8 weight:UIFontWeightSemibold color:self.theme.secondaryTextColor];
    methodLabel.frame = CGRectMake(13, 35, 55, 34);
    [card addSubview:methodLabel];
    CGFloat buttonW = 68.0;
    UITextField *query = ZNM54Field(CGRectMake(68, 34, card.bounds.size.width - 81 - buttonW - 7, 36), self.theme, [self menuFont:10.5 weight:UIFontWeightMedium]);
    query.tag = kZNM54QueryTag;
    query.text = [self zn57mf_query];
    query.placeholder = @"方法名 / Class::Method / RVA";
    query.returnKeyType = UIReturnKeySearch;
    query.clearButtonMode = UITextFieldViewModeWhileEditing;
    [query addTarget:self action:@selector(znm54_queryChanged:) forControlEvents:UIControlEventEditingChanged];
    [query addTarget:self action:@selector(znm54_submitSearch:) forControlEvents:UIControlEventEditingDidEndOnExit];
    [card addSubview:query];

    UIButton *search = [self zn40_button:@"搜索" selector:@selector(znm54_submitSearch:) frame:CGRectMake(CGRectGetMaxX(query.frame) + 7, 34, buttonW, 36)];
    search.backgroundColor = [self.theme.accentColor colorWithAlphaComponent:0.20];
    search.layer.borderColor = self.theme.accentColor.CGColor;
    [card addSubview:search];

    UILabel *assemblyLabel = [self label:@"Assembly" size:8.8 weight:UIFontWeightSemibold color:self.theme.secondaryTextColor];
    assemblyLabel.frame = CGRectMake(13, 79, 55, 32);
    [card addSubview:assemblyLabel];
    NSString *assembly = [self znm43_selectedAssembly] ?: @"Assembly-CSharp.dll";
    UIButton *assemblyButton = [self zn60v3_plainButton:[[ZNM54AssemblyDisplay(assembly) stringByAppendingString:@" · 优先  ›"] copy]
                                                 selector:@selector(znm43_assemblyTapped:)
                                                    frame:CGRectMake(68, 78, card.bounds.size.width - 81, 32)];
    assemblyButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    assemblyButton.contentEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 8);
    [card addSubview:assemblyButton];

    UILabel *limitLabel = [self label:@"最大结果" size:8.8 weight:UIFontWeightSemibold color:self.theme.secondaryTextColor];
    limitLabel.frame = CGRectMake(13, 121, 55, 32);
    [card addSubview:limitLabel];
    UITextField *limit = ZNM54Field(CGRectMake(68, 120, 92, 32), self.theme, [UIFont monospacedDigitSystemFontOfSize:10.0 weight:UIFontWeightMedium]);
    limit.tag = kZNM54LimitTag;
    limit.text = [NSString stringWithFormat:@"%lu", (unsigned long)[self zn60v3_limit]];
    limit.keyboardType = UIKeyboardTypeNumberPad;
    limit.textAlignment = NSTextAlignmentCenter;
    [limit addTarget:self action:@selector(znm54_limitChanged:) forControlEvents:UIControlEventEditingChanged];
    [card addSubview:limit];
    UILabel *hint = [self label:@"1–1024；较大数量仍受搜索时间预算限制" size:7.8 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    hint.frame = CGRectMake(170, 120, card.bounds.size.width - 183, 32);
    hint.numberOfLines = 2;
    [card addSubview:hint];
    [self.contentView addSubview:card];
    y += 178.0;

    NSArray<NSString *> *history = ZNM54History();
    if (history.count) {
        CGFloat rowH = 31.0;
        CGFloat visibleRows = MIN((CGFloat)history.count, 6.0);
        CGFloat scrollH = visibleRows * rowH;
        CGFloat panelH = 31.0 + scrollH + 8.0;
        UIView *historyCard = [self cardAtY:y height:panelH width:width compact:NO];
        UILabel *historyTitle = [self label:[NSString stringWithFormat:@"搜索记录 · %lu/50", (unsigned long)history.count]
                                          size:9.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
        historyTitle.frame = CGRectMake(13, 6, historyCard.bounds.size.width - 26, 20);
        [historyCard addSubview:historyTitle];
        UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(10, 29, historyCard.bounds.size.width - 20, scrollH)];
        scroll.showsVerticalScrollIndicator = YES;
        scroll.alwaysBounceVertical = history.count > (NSUInteger)visibleRows;
        for (NSUInteger i = 0; i < history.count; i++) {
            UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
            row.frame = CGRectMake(0, i * rowH, scroll.bounds.size.width, rowH);
            [row setTitle:history[i] forState:UIControlStateNormal];
            [row setTitleColor:self.theme.primaryTextColor forState:UIControlStateNormal];
            row.titleLabel.font = [self menuFont:9.2 weight:UIFontWeightRegular];
            row.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
            row.contentEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 8);
            row.backgroundColor = [self.theme.controlColor colorWithAlphaComponent:0.72];
            row.layer.cornerRadius = 5.0;
            row.layer.borderWidth = 0.5;
            row.layer.borderColor = self.theme.borderColor.CGColor;
            objc_setAssociatedObject(row, kZNM54HistoryKey, history[i], OBJC_ASSOCIATION_COPY_NONATOMIC);
            [row addTarget:self action:@selector(znm54_historyTapped:) forControlEvents:UIControlEventTouchUpInside];
            [scroll addSubview:row];
        }
        scroll.contentSize = CGSizeMake(scroll.bounds.size.width, history.count * rowH);
        [historyCard addSubview:scroll];
        [self.contentView addSubview:historyCard];
        y += panelH + 8.0;
    }

    NSString *statusText = [self zn60v3_status];
    if (statusText.length) {
        UIView *statusCard = [self cardAtY:y height:58 width:width compact:NO];
        UILabel *status = [self label:statusText size:8.8 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        status.frame = CGRectMake(13, 7, statusCard.bounds.size.width - 26, 44);
        status.numberOfLines = 3;
        [statusCard addSubview:status];
        [self.contentView addSubview:statusCard];
        y += 66.0;
    }
    [self zn40_updateContentHeight:y];
}

- (void)znm54_filterTapped:(UIButton *)sender {
    NSNumber *value = objc_getAssociatedObject(sender, kZNM54FilterKey);
    [self znm42_setFilter:value ? value.integerValue : -1];
    [self renderPage];
}

- (void)znm54_argumentChanged:(UITextField *)field {
    NSString *key = objc_getAssociatedObject(field, kZNM54StoreKey);
    if (key.length) [self znm42_inputStore][key] = field.text ?: @"";
}

- (void)znm54_done:(UITextField *)field {
    [self znm54_argumentChanged:field];
    [field resignFirstResponder];
}

- (void)znm54_openDetail:(UIButton *)sender {
    NSDictionary *candidate = objc_getAssociatedObject(sender, kZNM54CandidateKey);
    if (!candidate) return;
    [self zn60v3_setSelected:candidate];
    [self zn60v3_setPage:2];
    [self renderPage];
}

- (void)znm54_createCandidate:(UIButton *)sender {
    NSDictionary *candidate = objc_getAssociatedObject(sender, kZNM54CandidateKey);
    if (!candidate) return;
    NSArray<NSString *> *values = [self znm43_argumentValues:candidate] ?: @[];
    NSString *error = nil;
    ZNRuntimeMethodAction *action = [[ZNRuntimeActionStore sharedStore] addMethodCandidate:candidate
                                                                                     title:candidate[@"method"]
                                                                            argumentValues:values
                                                                                     error:&error];
    [self zn60v3_setStatus:action
        ? [NSString stringWithFormat:@"已加入 Builder：%@ args=%@", action.canonicalIdentity, action.argumentValues ?: @[]]
        : (error ?: @"创建 Runtime Method Call 失败")];
    [self renderPage];
}

- (void)znm54_renderResultsAtWidth:(CGFloat)width {
    NSArray<NSDictionary *> *all = [self zn60v3_candidates] ?: @[];
    NSArray<NSDictionary *> *visible = ZNM54Visible(self);
    NSMutableSet<NSNumber *> *aritySet = [NSMutableSet set];
    for (NSDictionary *candidate in all) [aritySet addObject:@([candidate[@"argumentCount"] integerValue])];
    NSArray<NSNumber *> *arities = [[aritySet allObjects] sortedArrayUsingSelector:@selector(compare:)];
    NSInteger filter = [self znm42_filter];

    CGFloat y = 9.0;
    UIView *header = [self cardAtY:y height:48 width:width compact:NO];
    UIButton *back = [self zn60v3_plainButton:@"‹ 搜索" selector:@selector(zn60v3_backToSearch:) frame:CGRectMake(10, 8, 70, 31)];
    [header addSubview:back];
    UILabel *title = [self label:(filter < 0
                                   ? [NSString stringWithFormat:@"搜索结果（%lu）", (unsigned long)all.count]
                                   : [NSString stringWithFormat:@"搜索结果（%lu/%lu）", (unsigned long)visible.count, (unsigned long)all.count])
                               size:11.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    title.frame = CGRectMake(88, 8, header.bounds.size.width - 100, 31);
    [header addSubview:title];
    [self.contentView addSubview:header];
    y += 56.0;

    UIView *filterCard = [self cardAtY:y height:44 width:width compact:NO];
    UIScrollView *filterScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(10, 5, filterCard.bounds.size.width - 20, 34)];
    CGFloat bx = 0;
    NSMutableArray<NSNumber *> *filterValues = [NSMutableArray arrayWithObject:@(-1)];
    [filterValues addObjectsFromArray:arities];
    for (NSNumber *n in filterValues) {
        NSInteger value = n.integerValue;
        CGFloat bw = value < 0 ? 54.0 : 38.0;
        UIButton *button = [self zn40_button:(value < 0 ? @"全部" : n.stringValue)
                                    selector:@selector(znm54_filterTapped:)
                                       frame:CGRectMake(bx, 2, bw, 30)];
        objc_setAssociatedObject(button, kZNM54FilterKey, n, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        BOOL selected = filter == value;
        button.backgroundColor = selected ? [self.theme.accentColor colorWithAlphaComponent:0.26] : self.theme.controlColor;
        button.layer.borderColor = (selected ? self.theme.accentColor : self.theme.borderColor).CGColor;
        [filterScroll addSubview:button];
        bx += bw + 7.0;
    }
    filterScroll.contentSize = CGSizeMake(MAX(filterScroll.bounds.size.width + 1, bx), 34);
    [filterCard addSubview:filterScroll];
    [self.contentView addSubview:filterCard];
    y += 52.0;

    NSString *statusText = [self zn60v3_status];
    if (statusText.length) {
        UIView *statusCard = [self cardAtY:y height:48 width:width compact:NO];
        UILabel *status = [self label:statusText size:8.2 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        status.frame = CGRectMake(13, 6, statusCard.bounds.size.width - 26, 36);
        status.numberOfLines = 2;
        [statusCard addSubview:status];
        [self.contentView addSubview:statusCard];
        y += 56.0;
    }

    for (NSDictionary *candidate in visible) {
        NSUInteger argc = [candidate[@"argumentCount"] unsignedIntegerValue];
        NSDictionary *abi = ZNIL2CPPDescribeMethodABI(candidate);
        NSArray<NSDictionary *> *params = [abi[@"parameters"] isKindOfClass:NSArray.class] ? abi[@"parameters"] : @[];
        BOOL metadataOK = argc == 0 || ([abi[@"available"] boolValue] && params.count == argc && argc <= ZN_RUNTIME_ACTION_MAX_ARGUMENTS);
        BOOL callable = metadataOK;
        NSMutableArray<NSString *> *types = [NSMutableArray array];
        if (argc && metadataOK) {
            for (NSDictionary *param in params) {
                [types addObject:([param[@"name"] isKindOfClass:NSString.class] ? param[@"name"] : @"?")];
                if (ZNM54UnsupportedReason(param).length) callable = NO;
            }
        }

        CGFloat rightW = 80.0;
        CGFloat leftW = width - rightW - 24.0;
        CGFloat rowH = 34.0;
        CGFloat argsH = argc ? argc * rowH : 0.0;
        CGFloat signatureH = types.count ? 18.0 : 0.0;
        CGFloat cardH = MAX(92.0, 60.0 + argsH + signatureH);
        UIView *card = [self cardAtY:y height:cardH width:width compact:NO];

        UIButton *detail = [UIButton buttonWithType:UIButtonTypeCustom];
        detail.frame = CGRectMake(0, 0, leftW + 8.0, 50.0);
        objc_setAssociatedObject(detail, kZNM54CandidateKey, candidate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [detail addTarget:self action:@selector(znm54_openDetail:) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:detail];

        NSString *method = candidate[@"method"] ?: @"Method";
        UILabel *name = [self label:[NSString stringWithFormat:@"%@/%lu", method, (unsigned long)argc]
                                size:10.7 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
        name.frame = CGRectMake(13, 7, leftW - 8, 20);
        [card addSubview:name];
        NSString *className = candidate[@"class"] ?: @"?";
        UILabel *owner = [self label:className size:8.8 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        owner.frame = CGRectMake(13, 31, leftW - 8, 17);
        owner.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [card addSubview:owner];

        CGFloat ay = 53.0;
        for (NSUInteger i = 0; i < argc; i++) {
            NSDictionary *param = i < params.count ? params[i] : nil;
            NSString *type = param ? (param[@"name"] ?: @"?") : @"?";
            NSString *paramName = param ? (param[@"paramName"] ?: @"") : @"";
            NSString *reason = param ? ZNM54UnsupportedReason(param) : (abi[@"reason"] ?: @"参数 ABI 不可用");
            CGRect frame = CGRectMake(13, ay + i * rowH, MAX(70.0, leftW - 8), 28);
            if (!reason.length) {
                UITextField *field = ZNM54Field(frame, self.theme, [self menuFont:8.9 weight:UIFontWeightMedium]);
                field.placeholder = paramName.length
                    ? [NSString stringWithFormat:@"参数%lu · %@ · %@", (unsigned long)i + 1, paramName, ZNM54ShortType(type)]
                    : [NSString stringWithFormat:@"参数%lu · %@", (unsigned long)i + 1, ZNM54ShortType(type)];
                NSString *key = ZNM54ArgStoreKey(candidate, i);
                field.text = [self znm42_inputStore][key] ?: @"";
                field.returnKeyType = UIReturnKeyDone;
                field.keyboardType = ZNM54IsString(type) ? UIKeyboardTypeDefault : UIKeyboardTypeNumbersAndPunctuation;
                objc_setAssociatedObject(field, kZNM54StoreKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
                [field addTarget:self action:@selector(znm54_argumentChanged:) forControlEvents:UIControlEventEditingChanged];
                [field addTarget:self action:@selector(znm54_done:) forControlEvents:UIControlEventEditingDidEndOnExit];
                [card addSubview:field];
            } else {
                UILabel *reasonLabel = [self label:[NSString stringWithFormat:@"参数%lu · %@ · %@", (unsigned long)i + 1, ZNM54ShortType(type), reason]
                                               size:8.1 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
                reasonLabel.frame = frame;
                reasonLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
                [card addSubview:reasonLabel];
            }
        }

        CGFloat infoY = ay + argsH;
        if (types.count) {
            UILabel *signature = [self label:ZNIL2CPPShortSignature(method, types)
                                        size:7.9 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];
            signature.frame = CGRectMake(13, infoY, leftW - 8, 16);
            signature.font = [UIFont monospacedSystemFontOfSize:7.9 weight:UIFontWeightMedium];
            signature.lineBreakMode = NSLineBreakByTruncatingMiddle;
            [card addSubview:signature];
            infoY += 18.0;
        }
        UILabel *assembly = [self label:ZNM54AssemblyDisplay(candidate[@"assembly"] ?: @"?")
                                     size:8.1 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        assembly.frame = CGRectMake(13, infoY, leftW - 8, 16);
        [card addSubview:assembly];

        UIButton *test = [self zn40_button:@"测试执行" selector:@selector(znm43_testCandidate:) frame:CGRectMake(card.bounds.size.width - rightW - 10, 7, rightW, 28)];
        test.enabled = callable;
        test.alpha = callable ? 1.0 : 0.48;
        test.titleLabel.font = [self menuFont:8.2 weight:UIFontWeightSemibold];
        test.backgroundColor = [self.theme.accentColor colorWithAlphaComponent:0.17];
        test.layer.borderColor = self.theme.accentColor.CGColor;
        [card addSubview:test];

        UIButton *create = [self zn40_button:@"创建方法" selector:@selector(znm54_createCandidate:) frame:CGRectMake(card.bounds.size.width - rightW - 10, 41, rightW, 28)];
        objc_setAssociatedObject(create, kZNM54CandidateKey, candidate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        create.enabled = callable;
        create.alpha = callable ? 1.0 : 0.48;
        create.titleLabel.font = [self menuFont:8.2 weight:UIFontWeightSemibold];
        [card addSubview:create];

        [self.contentView addSubview:card];
        y += cardH + 8.0;
    }
    [self zn40_updateContentHeight:y];
}

- (void)znm54_renderDetailAtWidth:(CGFloat)width {
    NSDictionary *candidate = [self zn60v3_selected];
    CGFloat y = 9.0;
    UIView *header = [self cardAtY:y height:48 width:width compact:NO];
    UIButton *back = [self zn60v3_plainButton:@"‹ 结果" selector:@selector(zn60v3_backToResults:) frame:CGRectMake(10, 8, 70, 31)];
    [header addSubview:back];
    UILabel *title = [self label:@"方法详情 · Unified" size:11.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    title.frame = CGRectMake(88, 8, header.bounds.size.width - 100, 31);
    [header addSubview:title];
    [self.contentView addSubview:header];
    y += 56.0;

    if (!candidate) {
        [self zn40_updateContentHeight:y];
        return;
    }

    NSDictionary *abi = ZNIL2CPPDescribeMethodABI(candidate);
    NSArray<NSDictionary *> *params = [abi[@"parameters"] isKindOfClass:NSArray.class] ? abi[@"parameters"] : @[];
    NSDictionary *ret = [abi[@"return"] isKindOfClass:NSDictionary.class] ? abi[@"return"] : @{};
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    [lines addObject:[NSString stringWithFormat:@"Assembly    %@", candidate[@"assembly"] ?: @"?"]];
    [lines addObject:[NSString stringWithFormat:@"Namespace   %@", candidate[@"namespace"] ?: @""]];
    [lines addObject:[NSString stringWithFormat:@"Class       %@", candidate[@"class"] ?: @"?"]];
    [lines addObject:[NSString stringWithFormat:@"Method      %@/%@", candidate[@"method"] ?: @"?", candidate[@"argumentCount"] ?: @0]];
    [lines addObject:[NSString stringWithFormat:@"RVA         %@", candidate[@"rvaText"] ?: @"—"]];
    [lines addObject:[NSString stringWithFormat:@"MethodInfo  0x%llX", (unsigned long long)[candidate[@"methodInfo"] unsignedLongLongValue]]];
    [lines addObject:[NSString stringWithFormat:@"Pointer     0x%llX", (unsigned long long)[candidate[@"methodPointer"] unsignedLongLongValue]]];
    if ([ret[@"name"] isKindOfClass:NSString.class]) [lines addObject:[NSString stringWithFormat:@"Return      %@", ret[@"name"]]];
    for (NSUInteger i = 0; i < params.count; i++) {
        NSDictionary *p = params[i];
        [lines addObject:[NSString stringWithFormat:@"Arg %-2lu     %@%@", (unsigned long)i, p[@"name"] ?: @"?", [p[@"byRef"] boolValue] ? @" &" : @""]];
    }
    if ([candidate[@"ownershipKind"] isKindOfClass:NSString.class]) {
        [lines addObject:[NSString stringWithFormat:@"Ownership   %@", candidate[@"ownershipKind"]]];
        [lines addObject:[NSString stringWithFormat:@"Method RVA  %@", candidate[@"methodRVAText"] ?: @"—"]];
        [lines addObject:[NSString stringWithFormat:@"Intra       %@", candidate[@"intraMethodOffsetText"] ?: @"+0x0"]];
    }

    CGFloat cardH = 34.0 + lines.count * 20.0;
    UIView *card = [self cardAtY:y height:cardH width:width compact:NO];
    UILabel *canonical = [self label:(candidate[@"canonical"] ?: @"IL2CPP Method") size:10.2 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    canonical.frame = CGRectMake(13, 7, card.bounds.size.width - 26, 20);
    canonical.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [card addSubview:canonical];
    CGFloat ly = 31.0;
    for (NSString *line in lines) {
        UILabel *label = [self label:line size:8.4 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        label.frame = CGRectMake(13, ly, card.bounds.size.width - 26, 18);
        label.font = [UIFont monospacedSystemFontOfSize:8.4 weight:UIFontWeightRegular];
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.7;
        [card addSubview:label];
        ly += 20.0;
    }
    [self.contentView addSubview:card];
    y += cardH + 8.0;
    [self zn40_updateContentHeight:y];
}

@end

static void ZNM54Swap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallMethodFinderUnifiedUIDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNM54Swap(cls, @selector(zn60v3_renderSearchAtWidth:), @selector(znm54_renderSearchAtWidth:));
        ZNM54Swap(cls, @selector(zn60v3_renderResultsAtWidth:), @selector(znm54_renderResultsAtWidth:));
        ZNM54Swap(cls, @selector(zn60v3_renderDetailAtWidth:), @selector(znm54_renderDetailAtWidth:));
        [[ZNRuntimeLogger sharedLogger] log:@"[m5.4-unified-ui] Search/Results/Detail renderer consolidated; legacy renderer chain cut"];
    });
}
