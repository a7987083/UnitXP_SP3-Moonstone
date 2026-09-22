#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

#import "ZNIL2CPPABIMetadata.h"
#import "ZNIL2CPPHybridFinder.h"
#import "ZNIL2CPPMethodFinderSearchV3.h"
#import "ZNIL2CPPInvokeEngine.h"
#import "ZNIL2CPPResolver.h"
#import "ZNRuntimeActionModel.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

// M4.3.1 UI polish layer
// - Assembly picker using the same action-sheet interaction as App Libraries.
// - User-editable result limit.
// - /1 input moved below the method/class rows so the method name gets full width.
// - Return key becomes Done and dismisses the keyboard.
// - Result cards hide Assembly because the selected Assembly is already visible on the search page.
// - Detail page keeps information only; Runtime test/create remains on results cards.

static const void *kZNM43AssemblyKey = &kZNM43AssemblyKey;
static const void *kZNM43CandidateKey = &kZNM43CandidateKey;
static const void *kZNM43ArityKey = &kZNM43ArityKey;
static const NSInteger kZNM43LimitTag = 643001;
static const NSUInteger kZNM43LimitMax = 1024;

typedef void *(*ZNM43DomainGetFn)(void);
typedef const void **(*ZNM43DomainGetAssembliesFn)(const void *, size_t *);
typedef const void *(*ZNM43AssemblyGetImageFn)(const void *);
typedef const char *(*ZNM43ImageGetNameFn)(const void *);

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIScrollView *contentScroll;
@property(nonatomic,strong) UIWindow *hostWindow;
@property(nonatomic,strong) ZNTheme *theme;
- (UIWindow *)currentWindow;
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIFont *)menuFont:(CGFloat)size weight:(UIFontWeight)weight;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (UIButton *)zn60v3_plainButton:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (UITextField *)zn60v3_searchField:(CGRect)frame;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)renderPage;
- (NSString *)zn57mf_query;
- (void)zn57mf_setQuery:(NSString *)value;
- (NSUInteger)zn60v3_limit;
- (void)zn60v3_setLimit:(NSUInteger)value;
- (NSArray<NSDictionary *> *)zn60v3_candidates;
- (void)zn60v3_setCandidates:(NSArray<NSDictionary *> *)items;
- (void)zn60v3_setSelected:(NSDictionary * _Nullable)candidate;
- (void)zn60v3_setPage:(NSInteger)page;
- (NSString *)zn60v3_status;
- (void)zn60v3_setStatus:(NSString *)status;
- (void)zn60v3_backToSearch:(id)sender;
- (void)zn60v3_backToResults:(id)sender;
- (void)znrmc_renderDetailAtWidth:(CGFloat)width;
- (NSMutableDictionary<NSString *, NSString *> *)znm42_inputStore;
- (NSInteger)znm42_filter;
- (void)znm42_setFilter:(NSInteger)value;
@end

static NSString *ZNM43Trim(NSString *s) {
    return [s ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *ZNM43AssemblyDisplay(NSString *assembly) {
    NSString *value = assembly ?: @"";
    return [value.lowercaseString hasSuffix:@".dll"] && value.length > 4
        ? [value substringToIndex:value.length - 4] : value;
}

static NSString *ZNM43CandidateIdentity(NSDictionary *candidate) {
    NSString *canonical = [candidate[@"canonical"] isKindOfClass:NSString.class] ? candidate[@"canonical"] : @"";
    if (canonical.length) return canonical;
    return [NSString stringWithFormat:@"%@|%@|%@|%@|%@",
            candidate[@"assembly"] ?: @"", candidate[@"namespace"] ?: @"", candidate[@"class"] ?: @"",
            candidate[@"method"] ?: @"", candidate[@"argumentCount"] ?: @(-1)];
}

static NSString *ZNM43ShortName(NSDictionary *candidate) {
    NSString *method = [candidate[@"method"] isKindOfClass:NSString.class] ? candidate[@"method"] : @"Method";
    NSInteger argc = [candidate[@"argumentCount"] respondsToSelector:@selector(integerValue)] ? [candidate[@"argumentCount"] integerValue] : -1;
    return argc >= 0 ? [NSString stringWithFormat:@"%@/%ld", method, (long)argc] : method;
}

static BOOL ZNM43IsStringType(NSString *typeName) {
    NSString *n = ZNM43Trim(typeName).lowercaseString;
    return [n isEqualToString:@"system.string"] || [n isEqualToString:@"string"];
}

static NSDictionary *ZNM43ArgumentInfo(NSDictionary *candidate) {
    NSInteger argc = [candidate[@"argumentCount"] integerValue];
    if (argc == 0) return @{@"supported": @YES, @"type": @"", @"name": @""};
    if (argc != 1) return @{@"supported": @NO, @"reason": [NSString stringWithFormat:@"M4.3.1 暂不执行 /%ld", (long)argc], @"type": @"", @"name": @""};
    NSDictionary *abi = ZNIL2CPPDescribeMethodABI(candidate);
    if (![abi[@"available"] boolValue] || [abi[@"parameterCount"] unsignedIntegerValue] != 1) {
        return @{@"supported": @NO, @"reason": abi[@"reason"] ?: @"参数 ABI 不可用", @"type": @"?", @"name": @""};
    }
    NSDictionary *param = [abi[@"parameters"] firstObject];
    if (!param) return @{@"supported": @NO, @"reason": @"参数元数据为空", @"type": @"?", @"name": @""};
    NSString *typeName = param[@"name"] ?: @"?";
    NSString *paramName = param[@"paramName"] ?: @"";
    if ([param[@"byRef"] boolValue]) return @{@"supported": @NO, @"reason": @"ref/out 暂不支持", @"type": typeName, @"name": paramName};
    if ([param[@"pointer"] boolValue]) return @{@"supported": @NO, @"reason": @"pointer 暂不支持", @"type": typeName, @"name": paramName};
    if (ZNM43IsStringType(typeName)) return @{@"supported": @YES, @"type": typeName, @"name": paramName, @"string": @YES};
    ZNIL2CPPABIValueKind kind = (ZNIL2CPPABIValueKind)[param[@"kind"] integerValue];
    BOOL supported = kind == ZNIL2CPPABIValueKindBool || kind == ZNIL2CPPABIValueKindSigned32 ||
                     kind == ZNIL2CPPABIValueKindUnsigned32 || kind == ZNIL2CPPABIValueKindSigned64 ||
                     kind == ZNIL2CPPABIValueKindUnsigned64 || kind == ZNIL2CPPABIValueKindFloat32 ||
                     kind == ZNIL2CPPABIValueKindFloat64;
    return @{@"supported": @(supported), @"reason": supported ? @"" : [NSString stringWithFormat:@"%@ 暂不支持", typeName],
             @"type": typeName, @"name": paramName, @"kind": @(kind), @"enum": param[@"enum"] ?: @NO};
}

static NSString *ZNM43ShortType(NSString *typeName) {
    NSArray<NSString *> *parts = [typeName ?: @"" componentsSeparatedByString:@"."];
    return parts.lastObject.length ? parts.lastObject : (typeName ?: @"");
}

static UIViewController *ZNM43TopController(UIViewController *vc) {
    if (!vc) return nil;
    if (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) return ZNM43TopController(vc.presentedViewController);
    if ([vc isKindOfClass:UINavigationController.class]) return ZNM43TopController(((UINavigationController *)vc).visibleViewController ?: vc);
    if ([vc isKindOfClass:UITabBarController.class]) return ZNM43TopController(((UITabBarController *)vc).selectedViewController ?: vc);
    if ([vc isKindOfClass:UISplitViewController.class]) return ZNM43TopController(((UISplitViewController *)vc).viewControllers.lastObject ?: vc);
    return vc;
}

static NSArray<NSString *> *ZNM43Assemblies(void) {
    ZNIL2CPPResolver *resolver = [ZNIL2CPPResolver sharedResolver];
    [resolver refresh];
    NSString *path = resolver.unityPath ?: @"";
    void *handle = NULL;
#ifdef RTLD_NOLOAD
    if (path.length) handle = dlopen(path.fileSystemRepresentation, RTLD_LAZY | RTLD_NOLOAD);
#endif
    ZNM43DomainGetFn domainGet = (ZNM43DomainGetFn)(dlsym(RTLD_DEFAULT, "il2cpp_domain_get") ?: (handle ? dlsym(handle, "il2cpp_domain_get") : NULL));
    ZNM43DomainGetAssembliesFn getAssemblies = (ZNM43DomainGetAssembliesFn)(dlsym(RTLD_DEFAULT, "il2cpp_domain_get_assemblies") ?: (handle ? dlsym(handle, "il2cpp_domain_get_assemblies") : NULL));
    ZNM43AssemblyGetImageFn getImage = (ZNM43AssemblyGetImageFn)(dlsym(RTLD_DEFAULT, "il2cpp_assembly_get_image") ?: (handle ? dlsym(handle, "il2cpp_assembly_get_image") : NULL));
    ZNM43ImageGetNameFn getName = (ZNM43ImageGetNameFn)(dlsym(RTLD_DEFAULT, "il2cpp_image_get_name") ?: (handle ? dlsym(handle, "il2cpp_image_get_name") : NULL));
    if (!domainGet || !getAssemblies || !getImage || !getName) return @[];
    void *domain = domainGet();
    size_t count = 0;
    const void **assemblies = domain ? getAssemblies(domain, &count) : NULL;
    NSMutableArray<NSString *> *items = [NSMutableArray array];
    for (size_t i = 0; assemblies && i < count; i++) {
        const void *image = getImage(assemblies[i]);
        const char *raw = image ? getName(image) : NULL;
        NSString *name = raw ? [NSString stringWithUTF8String:raw] : @"";
        if (name.length && ![items containsObject:name]) [items addObject:name];
    }
    [items sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        BOOL ap = [ZNM43AssemblyDisplay(a) caseInsensitiveCompare:@"Assembly-CSharp"] == NSOrderedSame;
        BOOL bp = [ZNM43AssemblyDisplay(b) caseInsensitiveCompare:@"Assembly-CSharp"] == NSOrderedSame;
        if (ap != bp) return ap ? NSOrderedAscending : NSOrderedDescending;
        return [ZNM43AssemblyDisplay(a) localizedCaseInsensitiveCompare:ZNM43AssemblyDisplay(b)];
    }];
    return items;
}

@interface ZNRuntimeMenuControllerV040 (ZNMethodFinderM43UI)
- (void)znm43_renderSearchAtWidth:(CGFloat)width;
- (void)znm43_startSearch:(id)sender;
- (void)znm43_renderResultsAtWidth:(CGFloat)width;
- (void)znm43_renderDetailAtWidth:(CGFloat)width;
- (void)znm43_assemblyTapped:(UIButton *)sender;
- (void)znm43_filterTapped:(UIButton *)sender;
- (void)znm43_argumentChanged:(UITextField *)field;
- (void)znm43_doneEditing:(UITextField *)field;
- (void)znm43_limitChanged:(UITextField *)field;
- (void)znm43_openDetail:(UIButton *)sender;
- (void)znm43_testCandidate:(UIButton *)sender;
- (void)znm43_createCandidate:(UIButton *)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNMethodFinderM43UI)

- (NSString *)znm43_selectedAssembly {
    NSString *value = objc_getAssociatedObject(self, kZNM43AssemblyKey);
    return value ?: @"Assembly-CSharp.dll";
}

- (void)znm43_setSelectedAssembly:(NSString *)value {
    objc_setAssociatedObject(self, kZNM43AssemblyKey, [value copy] ?: @"", OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (void)znm43_renderSearchAtWidth:(CGFloat)width {
    CGFloat y = 9.0;
    UIView *card = [self cardAtY:y height:170 width:width compact:NO];
    UILabel *title = [self label:@"IL2CPP 方法查找 · M4.3.1" size:12.6 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    title.frame = CGRectMake(13, 8, card.bounds.size.width - 26, 20);
    [card addSubview:title];

    UILabel *methodLabel = [self label:@"方法名" size:8.8 weight:UIFontWeightSemibold color:self.theme.secondaryTextColor];
    methodLabel.frame = CGRectMake(13, 35, 55, 34);
    [card addSubview:methodLabel];
    CGFloat buttonW = 68.0;
    UITextField *query = [self zn60v3_searchField:CGRectMake(68, 34, card.bounds.size.width - 81 - buttonW - 7, 36)];
    [card addSubview:query];
    UIButton *search = [self zn40_button:@"搜索" selector:@selector(znm43_startSearch:) frame:CGRectMake(CGRectGetMaxX(query.frame) + 7, 34, buttonW, 36)];
    search.backgroundColor = [self.theme.accentColor colorWithAlphaComponent:0.20];
    search.layer.borderColor = self.theme.accentColor.CGColor;
    [card addSubview:search];

    UILabel *assemblyLabel = [self label:@"Assembly" size:8.8 weight:UIFontWeightSemibold color:self.theme.secondaryTextColor];
    assemblyLabel.frame = CGRectMake(13, 79, 55, 32);
    [card addSubview:assemblyLabel];
    NSString *assembly = [self znm43_selectedAssembly];
    NSString *assemblyTitle = assembly.length ? ZNM43AssemblyDisplay(assembly) : @"全部 Assembly";
    UIButton *assemblyButton = [self zn60v3_plainButton:[assemblyTitle stringByAppendingString:@"  ›"] selector:@selector(znm43_assemblyTapped:) frame:CGRectMake(68, 78, card.bounds.size.width - 81, 32)];
    assemblyButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    assemblyButton.contentEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 8);
    [card addSubview:assemblyButton];

    UILabel *limitLabel = [self label:@"最大结果" size:8.8 weight:UIFontWeightSemibold color:self.theme.secondaryTextColor];
    limitLabel.frame = CGRectMake(13, 121, 55, 32);
    [card addSubview:limitLabel];
    UITextField *limit = [[UITextField alloc] initWithFrame:CGRectMake(68, 120, 92, 32)];
    limit.tag = kZNM43LimitTag;
    limit.text = [NSString stringWithFormat:@"%lu", (unsigned long)[self zn60v3_limit]];
    limit.textColor = self.theme.primaryTextColor;
    limit.backgroundColor = self.theme.controlColor;
    limit.tintColor = self.theme.accentColor;
    limit.font = [UIFont monospacedDigitSystemFontOfSize:10.0 weight:UIFontWeightMedium];
    limit.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    limit.returnKeyType = UIReturnKeyDone;
    limit.layer.cornerRadius = 7.0;
    limit.layer.borderWidth = 1.0;
    limit.layer.borderColor = self.theme.borderColor.CGColor;
    limit.textAlignment = NSTextAlignmentCenter;
    [limit addTarget:self action:@selector(znm43_limitChanged:) forControlEvents:UIControlEventEditingChanged];
    [limit addTarget:self action:@selector(znm43_doneEditing:) forControlEvents:UIControlEventEditingDidEndOnExit];
    [card addSubview:limit];
    UILabel *limitHint = [self label:@"1–1024；较大数量仍受搜索时间预算限制" size:7.8 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    limitHint.frame = CGRectMake(170, 120, card.bounds.size.width - 183, 32);
    limitHint.numberOfLines = 2;
    [card addSubview:limitHint];

    [self.contentView addSubview:card];
    y += 178.0;
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

- (void)znm43_limitChanged:(UITextField *)field {
    NSUInteger value = (NSUInteger)MAX(1, MIN((NSInteger)kZNM43LimitMax, field.text.integerValue));
    if (field.text.length) [self zn60v3_setLimit:value];
}

- (void)znm43_doneEditing:(UITextField *)field {
    [field resignFirstResponder];
}

- (void)znm43_assemblyTapped:(UIButton *)sender {
    NSArray<NSString *> *assemblies = ZNM43Assemblies();
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Assemblies" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    NSString *selected = [self znm43_selectedAssembly];
    NSString *(^decorated)(NSString *) = ^NSString *(NSString *name) {
        NSString *display = name.length ? ZNM43AssemblyDisplay(name) : @"全部 Assembly";
        BOOL hit = (!name.length && !selected.length) || (name.length && [name caseInsensitiveCompare:selected] == NSOrderedSame);
        return hit ? [@"✓ " stringByAppendingString:display] : display;
    };
    [alert addAction:[UIAlertAction actionWithTitle:decorated(@"") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        [weakSelf znm43_setSelectedAssembly:@""];
        [weakSelf renderPage];
    }]];
    for (NSString *assembly in assemblies) {
        [alert addAction:[UIAlertAction actionWithTitle:decorated(assembly) style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            [weakSelf znm43_setSelectedAssembly:assembly];
            [weakSelf renderPage];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    UIWindow *window = self.hostWindow ?: [self currentWindow];
    UIViewController *presenter = ZNM43TopController(window.rootViewController);
    if (!presenter) return;
    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    if (popover) { popover.sourceView = sender; popover.sourceRect = sender.bounds; popover.permittedArrowDirections = UIPopoverArrowDirectionAny; }
    [presenter presentViewController:alert animated:YES completion:nil];
}

- (void)znm43_startSearch:(id)sender {
    (void)sender;
    [self.hostWindow endEditing:YES];
    UITextField *limitField = (UITextField *)[self.contentView viewWithTag:kZNM43LimitTag];
    if (limitField.text.length) {
        NSUInteger value = (NSUInteger)MAX(1, MIN((NSInteger)kZNM43LimitMax, limitField.text.integerValue));
        [self zn60v3_setLimit:value];
    }
    NSString *query = ZNM43Trim([self zn57mf_query]);
    if (!query.length) {
        [self zn60v3_setStatus:@"请输入方法名"];
        [self renderPage];
        return;
    }
    NSString *assembly = [self znm43_selectedAssembly];
    NSString *expression = query;
    NSString *lower = query.lowercaseString;
    BOOL reverse = [lower hasPrefix:@"0x"] || [lower hasPrefix:@"rva:"];
    if (assembly.length && !reverse && [query rangeOfString:@"!"].location == NSNotFound) {
        expression = [NSString stringWithFormat:@"%@!%@", assembly, query];
    }
    NSString *searchError = nil;
    NSArray *items = [[ZNIL2CPPHybridFinder sharedFinder] zn60_searchCandidates:expression limit:[self zn60v3_limit] error:&searchError];
    if (!items.count) {
        [self zn60v3_setStatus:searchError ?: @"没有搜索结果"];
        [self zn60v3_setPage:0];
        [self renderPage];
        return;
    }
    [self zn60v3_setCandidates:items];
    [self zn60v3_setSelected:nil];
    NSDictionary *stats = items.firstObject[@"searchStats"] ?: @{};
    NSString *scope = assembly.length ? ZNM43AssemblyDisplay(assembly) : @"全部 Assembly";
    [self zn60v3_setStatus:[NSString stringWithFormat:@"%@ · %@：%lu 个候选 · %@ classes · %.1fms", scope, query, (unsigned long)items.count, stats[@"classesScanned"] ?: @0, [stats[@"elapsedMs"] doubleValue]]];
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.3.1-search] assembly=%@ query=%@ limit=%lu -> %lu", scope, query, (unsigned long)[self zn60v3_limit], (unsigned long)items.count]];
    [self zn60v3_setPage:1];
    [self renderPage];
}

- (void)znm43_renderResultsAtWidth:(CGFloat)width {
    NSArray<NSDictionary *> *allItems = [self zn60v3_candidates] ?: @[];
    NSMutableSet<NSNumber *> *aritySet = [NSMutableSet set];
    for (NSDictionary *candidate in allItems) if ([candidate[@"argumentCount"] respondsToSelector:@selector(integerValue)]) [aritySet addObject:@([candidate[@"argumentCount"] integerValue])];
    NSArray<NSNumber *> *arities = [[aritySet allObjects] sortedArrayUsingSelector:@selector(compare:)];
    NSInteger filter = [self znm42_filter];
    if (filter >= 0 && ![aritySet containsObject:@(filter)]) { filter = -1; [self znm42_setFilter:-1]; }
    NSMutableArray<NSDictionary *> *visible = [NSMutableArray array];
    for (NSDictionary *candidate in allItems) if (filter < 0 || [candidate[@"argumentCount"] integerValue] == filter) [visible addObject:candidate];

    CGFloat y = 9.0;
    UIView *header = [self cardAtY:y height:48 width:width compact:NO];
    UIButton *back = [self zn60v3_plainButton:@"‹ 搜索" selector:@selector(zn60v3_backToSearch:) frame:CGRectMake(10, 8, 70, 31)];
    [header addSubview:back];
    UILabel *title = [self label:(filter < 0 ? [NSString stringWithFormat:@"搜索结果（%lu）", (unsigned long)allItems.count] : [NSString stringWithFormat:@"搜索结果（%lu/%lu）", (unsigned long)visible.count, (unsigned long)allItems.count]) size:11.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    title.frame = CGRectMake(88, 8, header.bounds.size.width - 100, 31);
    [header addSubview:title]; [self.contentView addSubview:header]; y += 56.0;

    UIView *filterCard = [self cardAtY:y height:44 width:width compact:NO];
    UIScrollView *filterScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(10, 5, filterCard.bounds.size.width - 20, 34)];
    filterScroll.showsHorizontalScrollIndicator = NO; filterScroll.alwaysBounceHorizontal = YES;
    CGFloat bx = 0; NSMutableArray<NSNumber *> *values = [NSMutableArray arrayWithObject:@(-1)]; [values addObjectsFromArray:arities];
    for (NSNumber *number in values) {
        NSInteger value = number.integerValue; NSString *label = value < 0 ? @"全部" : number.stringValue; CGFloat bw = value < 0 ? 54.0 : 38.0;
        UIButton *button = [self zn40_button:label selector:@selector(znm43_filterTapped:) frame:CGRectMake(bx, 2, bw, 30)];
        objc_setAssociatedObject(button, kZNM43ArityKey, number, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        BOOL selected = filter == value; button.backgroundColor = selected ? [self.theme.accentColor colorWithAlphaComponent:0.26] : self.theme.controlColor;
        button.layer.borderColor = (selected ? self.theme.accentColor : self.theme.borderColor).CGColor;
        [filterScroll addSubview:button]; bx += bw + 7.0;
    }
    filterScroll.contentSize = CGSizeMake(MAX(filterScroll.bounds.size.width + 1, bx), 34); [filterCard addSubview:filterScroll]; [self.contentView addSubview:filterCard]; y += 52.0;

    NSString *statusText = [self zn60v3_status];
    if (statusText.length) {
        UIView *statusCard = [self cardAtY:y height:44 width:width compact:NO];
        UILabel *status = [self label:statusText size:8.1 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        status.frame = CGRectMake(13, 6, statusCard.bounds.size.width - 26, 32); status.numberOfLines = 2;
        [statusCard addSubview:status]; [self.contentView addSubview:statusCard]; y += 52.0;
    }

    for (NSDictionary *candidate in visible) {
        NSInteger argc = [candidate[@"argumentCount"] integerValue];
        NSDictionary *argInfo = ZNM43ArgumentInfo(candidate);
        BOOL callable = [argInfo[@"supported"] boolValue] && argc <= 1;
        CGFloat cardH = argc == 1 ? 88.0 : 76.0;
        UIView *card = [self cardAtY:y height:cardH width:width compact:NO];
        CGFloat rightW = 78.0; CGFloat leftW = card.bounds.size.width - rightW - 22.0;

        UIButton *detail = [UIButton buttonWithType:UIButtonTypeCustom];
        detail.frame = CGRectMake(0, 0, leftW + 10.0, argc == 1 ? 50.0 : card.bounds.size.height);
        objc_setAssociatedObject(detail, kZNM43CandidateKey, candidate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [detail addTarget:self action:@selector(znm43_openDetail:) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:detail];

        UILabel *name = [self label:ZNM43ShortName(candidate) size:10.7 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
        name.frame = CGRectMake(13, 7, leftW - 8.0, 20); name.adjustsFontSizeToFitWidth = YES; name.minimumScaleFactor = 0.65; [card addSubview:name];
        UILabel *owner = [self label:([candidate[@"class"] isKindOfClass:NSString.class] ? candidate[@"class"] : @"?") size:8.8 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        owner.frame = CGRectMake(13, 31, leftW - 8.0, 17); owner.lineBreakMode = NSLineBreakByTruncatingMiddle; [card addSubview:owner];

        if (argc == 1) {
            UITextField *input = [[UITextField alloc] initWithFrame:CGRectMake(13, 52, leftW - 8.0, 27)];
            NSString *key = ZNM43CandidateIdentity(candidate); input.text = [self znm42_inputStore][key] ?: @"";
            NSString *paramName = argInfo[@"name"] ?: @""; NSString *type = ZNM43ShortType(argInfo[@"type"] ?: @"?");
            input.placeholder = paramName.length ? [NSString stringWithFormat:@"%@ · %@", paramName, type] : type;
            input.textColor = self.theme.primaryTextColor; input.backgroundColor = self.theme.controlColor; input.tintColor = self.theme.accentColor;
            input.font = [UIFont monospacedDigitSystemFontOfSize:9.2 weight:UIFontWeightMedium]; input.autocorrectionType = UITextAutocorrectionTypeNo; input.autocapitalizationType = UITextAutocapitalizationTypeNone;
            input.returnKeyType = UIReturnKeyDone; input.keyboardType = [argInfo[@"string"] boolValue] ? UIKeyboardTypeDefault : UIKeyboardTypeNumbersAndPunctuation;
            input.layer.cornerRadius = 6.0; input.layer.borderWidth = 1.0; input.layer.borderColor = self.theme.borderColor.CGColor; input.enabled = callable; input.alpha = callable ? 1.0 : 0.55;
            objc_setAssociatedObject(input, kZNM43CandidateKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
            [input addTarget:self action:@selector(znm43_argumentChanged:) forControlEvents:UIControlEventEditingChanged];
            [input addTarget:self action:@selector(znm43_doneEditing:) forControlEvents:UIControlEventEditingDidEndOnExit];
            [card addSubview:input];
        }

        UIButton *test = [self zn40_button:@"测试执行" selector:@selector(znm43_testCandidate:) frame:CGRectMake(card.bounds.size.width - rightW - 10, 7, rightW, 28)];
        objc_setAssociatedObject(test, kZNM43CandidateKey, candidate, OBJC_ASSOCIATION_RETAIN_NONATOMIC); test.enabled = callable; test.alpha = callable ? 1.0 : 0.48; test.titleLabel.font = [self menuFont:8.3 weight:UIFontWeightSemibold]; test.backgroundColor = [self.theme.accentColor colorWithAlphaComponent:0.17]; test.layer.borderColor = self.theme.accentColor.CGColor; [card addSubview:test];
        UIButton *create = [self zn40_button:@"创建方法" selector:@selector(znm43_createCandidate:) frame:CGRectMake(card.bounds.size.width - rightW - 10, 41, rightW, 28)];
        objc_setAssociatedObject(create, kZNM43CandidateKey, candidate, OBJC_ASSOCIATION_RETAIN_NONATOMIC); create.enabled = callable; create.alpha = callable ? 1.0 : 0.48; create.titleLabel.font = [self menuFont:8.3 weight:UIFontWeightSemibold]; [card addSubview:create];
        [self.contentView addSubview:card]; y += cardH + 8.0;
    }
    [self zn40_updateContentHeight:y];
}

- (void)znm43_filterTapped:(UIButton *)sender { NSNumber *n = objc_getAssociatedObject(sender, kZNM43ArityKey); [self znm42_setFilter:n ? n.integerValue : -1]; [self renderPage]; }
- (void)znm43_argumentChanged:(UITextField *)field { NSString *key = objc_getAssociatedObject(field, kZNM43CandidateKey); if (key.length) [self znm42_inputStore][key] = field.text ?: @""; }
- (void)znm43_openDetail:(UIButton *)sender { NSDictionary *candidate = objc_getAssociatedObject(sender, kZNM43CandidateKey); if (!candidate) return; [self zn60v3_setSelected:candidate]; [self zn60v3_setPage:2]; [self renderPage]; }

- (NSArray<NSString *> *)znm43_argumentValues:(NSDictionary *)candidate {
    NSInteger argc = [candidate[@"argumentCount"] integerValue]; if (argc == 0) return @[]; if (argc != 1) return @[];
    NSString *value = [self znm42_inputStore][ZNM43CandidateIdentity(candidate)]; return value ? @[value] : @[@""];
}

- (void)znm43_testCandidate:(UIButton *)sender {
    NSDictionary *candidate = objc_getAssociatedObject(sender, kZNM43CandidateKey); if (!candidate) return;
    NSUInteger argc = [candidate[@"argumentCount"] unsignedIntegerValue]; NSArray<NSString *> *values = [self znm43_argumentValues:candidate]; NSDictionary *info = ZNM43ArgumentInfo(candidate);
    if (argc == 1 && !ZNM43IsStringType(info[@"type"]) && ![values.firstObject length]) { [self zn60v3_setStatus:@"Runtime Invoke FAILED：请输入 /1 参数值"]; [self renderPage]; return; }
    NSString *error = nil;
    NSDictionary *result = [[ZNIL2CPPInvokeEngine sharedEngine] executeAssembly:([candidate[@"assembly"] isKindOfClass:NSString.class] ? candidate[@"assembly"] : @"Assembly-CSharp.dll") namespace:([candidate[@"namespace"] isKindOfClass:NSString.class] ? candidate[@"namespace"] : @"") className:([candidate[@"class"] isKindOfClass:NSString.class] ? candidate[@"class"] : @"") method:([candidate[@"method"] isKindOfClass:NSString.class] ? candidate[@"method"] : @"") argumentCount:argc argumentValues:values error:&error];
    if (result) {
        BOOL isStatic = [result[@"static"] boolValue];
        NSString *suffix = isStatic ? @"static" : [NSString stringWithFormat:@"instance=0x%llX", (unsigned long long)[result[@"instance"] unsignedLongLongValue]];
        [self zn60v3_setStatus:[NSString stringWithFormat:@"Runtime Invoke SUCCESS：%@ · %@", ZNM43ShortName(candidate), suffix]];
    } else [self zn60v3_setStatus:error ?: @"Runtime Invoke FAILED"];
    [self renderPage];
}

- (void)znm43_createCandidate:(UIButton *)sender {
    NSDictionary *candidate = objc_getAssociatedObject(sender, kZNM43CandidateKey); if (!candidate) return;
    NSUInteger argc = [candidate[@"argumentCount"] unsignedIntegerValue]; NSArray<NSString *> *values = [self znm43_argumentValues:candidate]; NSDictionary *info = ZNM43ArgumentInfo(candidate);
    if (argc == 1 && !ZNM43IsStringType(info[@"type"]) && ![values.firstObject length]) { [self zn60v3_setStatus:@"Builder：请输入 /1 参数值后再创建方法"]; [self renderPage]; return; }
    NSString *error = nil;
    ZNRuntimeMethodAction *action = [[ZNRuntimeActionStore sharedStore] addMethodCandidate:candidate title:candidate[@"method"] argumentValues:values error:&error];
    [self zn60v3_setStatus:action ? [NSString stringWithFormat:@"已加入 Builder：%@ args=%@", action.canonicalIdentity, action.argumentValues] : (error ?: @"创建 Runtime Method Call 失败")];
    [self renderPage];
}

- (void)znm43_renderDetailAtWidth:(CGFloat)width {
    // RuntimeMethodCallFinderUI previously wrapped detail with another test/create card.
    // Call its alias that points to the pre-wrapper detail chain, keeping ABI/address info only.
    [self znrmc_renderDetailAtWidth:width];
}

@end

static void ZNM43Swap(Class cls, SEL a, SEL b) {
    Method ma = class_getInstanceMethod(cls, a); Method mb = class_getInstanceMethod(cls, b); if (ma && mb) method_exchangeImplementations(ma, mb);
}

extern "C" void ZNInstallMethodFinderM43UIDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040"); if (!cls) return;
        ZNM43Swap(cls, @selector(zn60v3_renderSearchAtWidth:), @selector(znm43_renderSearchAtWidth:));
        ZNM43Swap(cls, @selector(zn60v3_startSearch:), @selector(znm43_startSearch:));
        ZNM43Swap(cls, @selector(zn60v3_renderResultsAtWidth:), @selector(znm43_renderResultsAtWidth:));
        ZNM43Swap(cls, @selector(zn60v3_renderDetailAtWidth:), @selector(znm43_renderDetailAtWidth:));
        [[ZNRuntimeLogger sharedLogger] log:@"[m4.3.1-ui] assembly picker + custom limit + hidden result Assembly + lower /1 input + Done key + detail cleanup installed"];
    });
}
