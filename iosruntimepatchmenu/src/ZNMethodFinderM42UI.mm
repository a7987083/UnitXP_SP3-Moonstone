#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNIL2CPPABIMetadata.h"
#import "ZNIL2CPPInvokeEngine.h"
#import "ZNRuntimeActionModel.h"
#import "ZNBinaryPatchWorkspace.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

static const void *kZNM42FilterKey = &kZNM42FilterKey;
static const void *kZNM42InputStoreKey = &kZNM42InputStoreKey;
static const void *kZNM42CandidateKey = &kZNM42CandidateKey;
static const void *kZNM42ArityKey = &kZNM42ArityKey;

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
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)renderPage;
- (NSArray<NSDictionary *> *)zn60v3_candidates;
- (NSDictionary *)zn60v3_selected;
- (void)zn60v3_setSelected:(NSDictionary *)candidate;
- (void)zn60v3_setPage:(NSInteger)page;
- (NSString *)zn60v3_status;
- (void)zn60v3_setStatus:(NSString *)status;
- (void)zn60v3_renderResultsAtWidth:(CGFloat)width;
- (void)znux_binaryPickerTapped:(UIButton *)sender;
@end

static NSString *ZNM42ShortName(NSDictionary *candidate) {
    NSString *method = [candidate[@"method"] isKindOfClass:NSString.class] ? candidate[@"method"] : @"Method";
    NSInteger argc = [candidate[@"argumentCount"] respondsToSelector:@selector(integerValue)] ? [candidate[@"argumentCount"] integerValue] : -1;
    return argc >= 0 ? [NSString stringWithFormat:@"%@/%ld", method, (long)argc] : method;
}

static NSString *ZNM42CandidateIdentity(NSDictionary *candidate) {
    NSString *canonical = [candidate[@"canonical"] isKindOfClass:NSString.class] ? candidate[@"canonical"] : @"";
    if (canonical.length) return canonical;
    return [NSString stringWithFormat:@"%@|%@|%@|%@|%@",
            candidate[@"assembly"] ?: @"",
            candidate[@"namespace"] ?: @"",
            candidate[@"class"] ?: @"",
            candidate[@"method"] ?: @"",
            candidate[@"argumentCount"] ?: @(-1)];
}

static NSString *ZNM42AssemblyDisplay(NSDictionary *candidate) {
    NSString *assembly = [candidate[@"assembly"] isKindOfClass:NSString.class] ? candidate[@"assembly"] : @"?";
    if ([assembly.lowercaseString hasSuffix:@".dll"] && assembly.length > 4) {
        return [assembly substringToIndex:assembly.length - 4];
    }
    return assembly;
}

static BOOL ZNM42IsStringType(NSString *typeName) {
    NSString *n = [[typeName ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    return [n isEqualToString:@"system.string"] || [n isEqualToString:@"string"];
}

static NSDictionary *ZNM42ArgumentInfo(NSDictionary *candidate) {
    NSInteger argc = [candidate[@"argumentCount"] integerValue];
    if (argc == 0) return @{@"supported": @YES, @"type": @"", @"name": @""};
    if (argc != 1) {
        return @{@"supported": @NO,
                 @"reason": [NSString stringWithFormat:@"M4.2 首版暂不执行 /%ld", (long)argc],
                 @"type": @"", @"name": @""};
    }
    NSDictionary *abi = ZNIL2CPPDescribeMethodABI(candidate);
    if (![abi[@"available"] boolValue] || [abi[@"parameterCount"] unsignedIntegerValue] != 1) {
        return @{@"supported": @NO,
                 @"reason": abi[@"reason"] ?: @"参数 ABI 不可用",
                 @"type": @"?", @"name": @""};
    }
    NSArray *parameters = abi[@"parameters"];
    NSDictionary *param = parameters.count ? parameters[0] : nil;
    if (!param) return @{@"supported": @NO, @"reason": @"参数元数据为空", @"type": @"?", @"name": @""};

    NSString *typeName = param[@"name"] ?: @"?";
    NSString *paramName = param[@"paramName"] ?: @"";
    if ([param[@"byRef"] boolValue]) return @{@"supported": @NO, @"reason": @"ref/out 暂不支持", @"type": typeName, @"name": paramName};
    if ([param[@"pointer"] boolValue]) return @{@"supported": @NO, @"reason": @"pointer 暂不支持", @"type": typeName, @"name": paramName};
    if (ZNM42IsStringType(typeName)) return @{@"supported": @YES, @"type": typeName, @"name": paramName, @"string": @YES};

    ZNIL2CPPABIValueKind kind = (ZNIL2CPPABIValueKind)[param[@"kind"] integerValue];
    BOOL supported = kind == ZNIL2CPPABIValueKindBool ||
                     kind == ZNIL2CPPABIValueKindSigned32 ||
                     kind == ZNIL2CPPABIValueKindUnsigned32 ||
                     kind == ZNIL2CPPABIValueKindSigned64 ||
                     kind == ZNIL2CPPABIValueKindUnsigned64 ||
                     kind == ZNIL2CPPABIValueKindFloat32 ||
                     kind == ZNIL2CPPABIValueKindFloat64;
    return @{@"supported": @(supported),
             @"reason": supported ? @"" : [NSString stringWithFormat:@"%@ 暂不支持", typeName],
             @"type": typeName,
             @"name": paramName,
             @"kind": @(kind),
             @"enum": param[@"enum"] ?: @NO};
}

static NSString *ZNM42ShortType(NSString *typeName) {
    if (!typeName.length) return @"";
    NSArray<NSString *> *parts = [typeName componentsSeparatedByString:@"."];
    return parts.lastObject.length ? parts.lastObject : typeName;
}

static UIViewController *ZNM42TopController(UIViewController *vc) {
    if (!vc) return nil;
    UIViewController *presented = vc.presentedViewController;
    if (presented && !presented.isBeingDismissed) return ZNM42TopController(presented);
    if ([vc isKindOfClass:UINavigationController.class]) {
        return ZNM42TopController(((UINavigationController *)vc).visibleViewController ?: vc);
    }
    if ([vc isKindOfClass:UITabBarController.class]) {
        return ZNM42TopController(((UITabBarController *)vc).selectedViewController ?: vc);
    }
    if ([vc isKindOfClass:UISplitViewController.class]) {
        return ZNM42TopController(((UISplitViewController *)vc).viewControllers.lastObject ?: vc);
    }
    return vc;
}

static NSString *ZNM42StandardPath(NSString *path) {
    return path.length ? path.stringByStandardizingPath : @"";
}

static BOOL ZNM42IsAppLocalImage(NSDictionary<NSString *, id> *item) {
    NSString *path = ZNM42StandardPath(item[@"path"]);
    NSString *bundle = ZNM42StandardPath(NSBundle.mainBundle.bundlePath);
    NSString *main = ZNM42StandardPath(NSBundle.mainBundle.executablePath);
    if (!path.length || !bundle.length) return NO;
    if ([path isEqualToString:main]) return YES;
    NSString *frameworks = [bundle stringByAppendingPathComponent:@"Frameworks"];
    return [path hasPrefix:[frameworks stringByAppendingString:@"/"]];
}

static NSInteger ZNM42ImageRank(NSDictionary<NSString *, id> *item) {
    NSString *name = item[@"name"] ?: @"";
    NSString *path = ZNM42StandardPath(item[@"path"]);
    if ([name caseInsensitiveCompare:@"UnityFramework"] == NSOrderedSame ||
        [path hasSuffix:@"/UnityFramework.framework/UnityFramework"]) return 0;
    if ([path isEqualToString:ZNM42StandardPath(NSBundle.mainBundle.executablePath)]) return 1;
    if ([path.pathExtension caseInsensitiveCompare:@"dylib"] == NSOrderedSame) return 2;
    return 3;
}

static NSArray<NSDictionary<NSString *, id> *> *ZNM42AppLocalImages(void) {
    NSMutableArray *items = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSDictionary *item in [ZNModuleManager sharedManager].loadedImages) {
        if (!ZNM42IsAppLocalImage(item)) continue;
        NSString *path = ZNM42StandardPath(item[@"path"]);
        if (!path.length || [seen containsObject:path]) continue;
        [seen addObject:path];
        [items addObject:item];
    }
    [items sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSInteger ra = ZNM42ImageRank(a), rb = ZNM42ImageRank(b);
        if (ra != rb) return ra < rb ? NSOrderedAscending : NSOrderedDescending;
        return [(a[@"name"] ?: @"") localizedCaseInsensitiveCompare:(b[@"name"] ?: @"")];
    }];
    return items;
}

@interface ZNRuntimeMenuControllerV040 (ZNMethodFinderM42UI)
- (void)znm42_renderResultsAtWidth:(CGFloat)width;
- (void)znm42_filterTapped:(UIButton *)sender;
- (void)znm42_argumentChanged:(UITextField *)field;
- (void)znm42_openDetail:(UIButton *)sender;
- (void)znm42_testCandidate:(UIButton *)sender;
- (void)znm42_createCandidate:(UIButton *)sender;
- (void)znm42_binaryPickerTapped:(UIButton *)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNMethodFinderM42UI)

- (NSMutableDictionary<NSString *, NSString *> *)znm42_inputStore {
    NSMutableDictionary *store = objc_getAssociatedObject(self, kZNM42InputStoreKey);
    if (!store) {
        store = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(self, kZNM42InputStoreKey, store, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return store;
}

- (NSInteger)znm42_filter {
    NSNumber *value = objc_getAssociatedObject(self, kZNM42FilterKey);
    return value ? value.integerValue : -1;
}

- (void)znm42_setFilter:(NSInteger)value {
    objc_setAssociatedObject(self, kZNM42FilterKey, @(value), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSArray<NSString *> *)znm42_argumentValuesForCandidate:(NSDictionary *)candidate {
    NSInteger argc = [candidate[@"argumentCount"] integerValue];
    if (argc == 0) return @[];
    if (argc != 1) return @[];
    NSString *key = ZNM42CandidateIdentity(candidate);
    NSString *value = [self znm42_inputStore][key];
    return value ? @[value] : @[@""];
}

- (void)znm42_renderResultsAtWidth:(CGFloat)width {
    NSArray<NSDictionary *> *allItems = [self zn60v3_candidates] ?: @[];
    NSMutableSet<NSNumber *> *aritySet = [NSMutableSet set];
    for (NSDictionary *candidate in allItems) {
        if ([candidate[@"argumentCount"] respondsToSelector:@selector(integerValue)]) {
            [aritySet addObject:@([candidate[@"argumentCount"] integerValue])];
        }
    }
    NSArray<NSNumber *> *arities = [[aritySet allObjects] sortedArrayUsingSelector:@selector(compare:)];
    NSInteger filter = [self znm42_filter];
    if (filter >= 0 && ![aritySet containsObject:@(filter)]) {
        filter = -1;
        [self znm42_setFilter:-1];
    }

    NSMutableArray<NSDictionary *> *visible = [NSMutableArray array];
    for (NSDictionary *candidate in allItems) {
        NSInteger argc = [candidate[@"argumentCount"] integerValue];
        if (filter < 0 || argc == filter) [visible addObject:candidate];
    }

    CGFloat y = 9.0;
    UIView *header = [self cardAtY:y height:48 width:width compact:NO];
    UIButton *back = [self zn60v3_plainButton:@"‹ 搜索" selector:@selector(zn60v3_backToSearch:) frame:CGRectMake(10, 8, 70, 31)];
    [header addSubview:back];
    NSString *countText = filter < 0
        ? [NSString stringWithFormat:@"搜索结果（%lu）", (unsigned long)allItems.count]
        : [NSString stringWithFormat:@"搜索结果（%lu/%lu）", (unsigned long)visible.count, (unsigned long)allItems.count];
    UILabel *title = [self label:countText size:11.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    title.frame = CGRectMake(88, 8, header.bounds.size.width - 100, 31);
    [header addSubview:title];
    [self.contentView addSubview:header];
    y += 56.0;

    NSDictionary *stats = allItems.firstObject[@"searchStats"] ?: @{};
    UIView *summary = [self cardAtY:y height:42 width:width compact:NO];
    NSString *summaryText = [NSString stringWithFormat:@"%@ · classes=%@ · %.1fms%@",
                             stats[@"mode"] ?: @"candidate-list",
                             stats[@"classesScanned"] ?: @0,
                             [stats[@"elapsedMs"] doubleValue],
                             [stats[@"truncated"] boolValue] ? @" · 结果已截断" : @""];
    UILabel *sl = [self label:summaryText size:8.4 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    sl.frame = CGRectMake(13, 7, summary.bounds.size.width - 26, 28);
    sl.numberOfLines = 2;
    [summary addSubview:sl];
    [self.contentView addSubview:summary];
    y += 50.0;

    UIView *filterCard = [self cardAtY:y height:44 width:width compact:NO];
    UIScrollView *filterScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(10, 5, filterCard.bounds.size.width - 20, 34)];
    filterScroll.showsHorizontalScrollIndicator = NO;
    filterScroll.alwaysBounceHorizontal = YES;
    CGFloat bx = 0;
    NSMutableArray<NSNumber *> *filterValues = [NSMutableArray arrayWithObject:@(-1)];
    [filterValues addObjectsFromArray:arities];
    for (NSNumber *number in filterValues) {
        NSInteger value = number.integerValue;
        NSString *label = value < 0 ? @"全部" : number.stringValue;
        CGFloat bw = value < 0 ? 54.0 : 38.0;
        UIButton *button = [self zn40_button:label selector:@selector(znm42_filterTapped:) frame:CGRectMake(bx, 2, bw, 30)];
        objc_setAssociatedObject(button, kZNM42ArityKey, number, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
    if (statusText.length && ([statusText containsString:@"Runtime"] || [statusText containsString:@"Builder"] || [statusText containsString:@"FAILED"] || [statusText containsString:@"SUCCESS"])) {
        UIView *statusCard = [self cardAtY:y height:44 width:width compact:NO];
        UILabel *status = [self label:statusText size:8.2 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        status.frame = CGRectMake(13, 6, statusCard.bounds.size.width - 26, 32);
        status.numberOfLines = 2;
        [statusCard addSubview:status];
        [self.contentView addSubview:statusCard];
        y += 52.0;
    }

    for (NSDictionary *candidate in visible) {
        NSInteger argc = [candidate[@"argumentCount"] integerValue];
        NSDictionary *argInfo = ZNM42ArgumentInfo(candidate);
        BOOL callable = [argInfo[@"supported"] boolValue] && argc <= 1;
        UIView *card = [self cardAtY:y height:76 width:width compact:NO];
        CGFloat rightW = 78.0;
        CGFloat leftW = card.bounds.size.width - rightW - 22.0;

        UIButton *detail = [UIButton buttonWithType:UIButtonTypeCustom];
        detail.frame = CGRectMake(0, 0, leftW + 10.0, card.bounds.size.height);
        objc_setAssociatedObject(detail, kZNM42CandidateKey, candidate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [detail addTarget:self action:@selector(znm42_openDetail:) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:detail];

        NSString *shortName = ZNM42ShortName(candidate);
        CGFloat nameW = argc == 1 ? MIN(112.0, leftW * 0.52) : leftW - 8.0;
        UILabel *name = [self label:shortName size:10.6 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
        name.frame = CGRectMake(13, 7, nameW, 21);
        name.adjustsFontSizeToFitWidth = YES;
        name.minimumScaleFactor = 0.72;
        [card addSubview:name];

        if (argc == 1) {
            CGFloat inputX = CGRectGetMaxX(name.frame) + 5.0;
            CGFloat inputW = MAX(58.0, leftW - inputX + 10.0);
            UITextField *input = [[UITextField alloc] initWithFrame:CGRectMake(inputX, 5, inputW, 26)];
            NSString *key = ZNM42CandidateIdentity(candidate);
            input.text = [self znm42_inputStore][key] ?: @"";
            NSString *paramName = argInfo[@"name"] ?: @"";
            NSString *type = ZNM42ShortType(argInfo[@"type"] ?: @"?");
            input.placeholder = paramName.length ? [NSString stringWithFormat:@"%@ · %@", paramName, type] : type;
            input.textColor = self.theme.primaryTextColor;
            input.backgroundColor = self.theme.controlColor;
            input.tintColor = self.theme.accentColor;
            input.font = [UIFont monospacedDigitSystemFontOfSize:9.2 weight:UIFontWeightMedium];
            input.autocorrectionType = UITextAutocorrectionTypeNo;
            input.autocapitalizationType = UITextAutocapitalizationTypeNone;
            input.layer.cornerRadius = 6.0;
            input.layer.borderWidth = 1.0;
            input.layer.borderColor = (callable ? self.theme.borderColor : [self.theme.secondaryTextColor colorWithAlphaComponent:0.4]).CGColor;
            input.enabled = callable;
            input.alpha = callable ? 1.0 : 0.55;
            if (callable && ![argInfo[@"string"] boolValue]) {
                ZNIL2CPPABIValueKind kind = (ZNIL2CPPABIValueKind)[argInfo[@"kind"] integerValue];
                input.keyboardType = (kind == ZNIL2CPPABIValueKindFloat32 || kind == ZNIL2CPPABIValueKindFloat64)
                    ? UIKeyboardTypeDecimalPad : UIKeyboardTypeNumbersAndPunctuation;
            }
            objc_setAssociatedObject(input, kZNM42CandidateKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
            [input addTarget:self action:@selector(znm42_argumentChanged:) forControlEvents:UIControlEventEditingChanged];
            [card addSubview:input];
        }

        UILabel *owner = [self label:([candidate[@"class"] isKindOfClass:NSString.class] ? candidate[@"class"] : @"?")
                                    size:8.8 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        owner.frame = CGRectMake(13, 33, leftW - 8.0, 17);
        owner.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [card addSubview:owner];

        UILabel *assembly = [self label:ZNM42AssemblyDisplay(candidate) size:8.1 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        assembly.frame = CGRectMake(13, 53, leftW - 8.0, 16);
        assembly.lineBreakMode = NSLineBreakByTruncatingTail;
        [card addSubview:assembly];

        UIButton *test = [self zn40_button:@"测试执行" selector:@selector(znm42_testCandidate:) frame:CGRectMake(card.bounds.size.width - rightW - 10, 7, rightW, 28)];
        objc_setAssociatedObject(test, kZNM42CandidateKey, candidate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        test.enabled = callable;
        test.alpha = callable ? 1.0 : 0.48;
        test.titleLabel.font = [self menuFont:8.3 weight:UIFontWeightSemibold];
        test.backgroundColor = [self.theme.accentColor colorWithAlphaComponent:0.17];
        test.layer.borderColor = self.theme.accentColor.CGColor;
        [card addSubview:test];

        UIButton *create = [self zn40_button:@"创建方法" selector:@selector(znm42_createCandidate:) frame:CGRectMake(card.bounds.size.width - rightW - 10, 41, rightW, 28)];
        objc_setAssociatedObject(create, kZNM42CandidateKey, candidate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        create.enabled = callable;
        create.alpha = callable ? 1.0 : 0.48;
        create.titleLabel.font = [self menuFont:8.3 weight:UIFontWeightSemibold];
        [card addSubview:create];

        [self.contentView addSubview:card];
        y += 84.0;
    }

    [self zn40_updateContentHeight:y];
}

- (void)znm42_filterTapped:(UIButton *)sender {
    NSNumber *value = objc_getAssociatedObject(sender, kZNM42ArityKey);
    [self znm42_setFilter:value ? value.integerValue : -1];
    [self renderPage];
}

- (void)znm42_argumentChanged:(UITextField *)field {
    NSString *key = objc_getAssociatedObject(field, kZNM42CandidateKey);
    if (!key.length) return;
    [self znm42_inputStore][key] = field.text ?: @"";
}

- (void)znm42_openDetail:(UIButton *)sender {
    NSDictionary *candidate = objc_getAssociatedObject(sender, kZNM42CandidateKey);
    if (!candidate) return;
    [self zn60v3_setSelected:candidate];
    [self zn60v3_setPage:2];
    [self renderPage];
}

- (void)znm42_testCandidate:(UIButton *)sender {
    NSDictionary *candidate = objc_getAssociatedObject(sender, kZNM42CandidateKey);
    if (!candidate) return;
    NSUInteger argc = [candidate[@"argumentCount"] unsignedIntegerValue];
    NSArray<NSString *> *values = [self znm42_argumentValuesForCandidate:candidate];
    if (argc == 1 && !ZNM42IsStringType(ZNM42ArgumentInfo(candidate)[@"type"]) && ![values.firstObject length]) {
        [self zn60v3_setStatus:@"Runtime Invoke FAILED：请输入 /1 参数值"];
        [self renderPage];
        return;
    }
    NSString *error = nil;
    NSDictionary *result = [[ZNIL2CPPInvokeEngine sharedEngine] executeAssembly:([candidate[@"assembly"] isKindOfClass:NSString.class] ? candidate[@"assembly"] : @"Assembly-CSharp.dll")
                                                                      namespace:([candidate[@"namespace"] isKindOfClass:NSString.class] ? candidate[@"namespace"] : @"")
                                                                      className:([candidate[@"class"] isKindOfClass:NSString.class] ? candidate[@"class"] : @"")
                                                                         method:([candidate[@"method"] isKindOfClass:NSString.class] ? candidate[@"method"] : @"")
                                                                  argumentCount:argc
                                                                 argumentValues:values
                                                                          error:&error];
    if (result) {
        [self zn60v3_setStatus:[NSString stringWithFormat:@"Runtime Invoke SUCCESS：%@ args=%@", ZNM42ShortName(candidate), values]];
    } else {
        [self zn60v3_setStatus:error ?: @"Runtime Invoke FAILED"];
    }
    [self renderPage];
}

- (void)znm42_createCandidate:(UIButton *)sender {
    NSDictionary *candidate = objc_getAssociatedObject(sender, kZNM42CandidateKey);
    if (!candidate) return;
    NSUInteger argc = [candidate[@"argumentCount"] unsignedIntegerValue];
    NSArray<NSString *> *values = [self znm42_argumentValuesForCandidate:candidate];
    NSDictionary *info = ZNM42ArgumentInfo(candidate);
    if (argc == 1 && !ZNM42IsStringType(info[@"type"]) && ![values.firstObject length]) {
        [self zn60v3_setStatus:@"Builder：请输入 /1 参数值后再创建方法"];
        [self renderPage];
        return;
    }
    NSString *error = nil;
    ZNRuntimeMethodAction *action = [[ZNRuntimeActionStore sharedStore] addMethodCandidate:candidate
                                                                                     title:candidate[@"method"]
                                                                            argumentValues:values
                                                                                     error:&error];
    if (!action) {
        [self zn60v3_setStatus:error ?: @"创建 Runtime Method Call 失败"];
    } else if (error.length) {
        [self zn60v3_setStatus:error];
    } else {
        [self zn60v3_setStatus:[NSString stringWithFormat:@"已加入 Builder：%@ args=%@", action.canonicalIdentity, action.argumentValues]];
    }
    [self renderPage];
}

- (void)znm42_binaryPickerTapped:(UIButton *)sender {
    NSArray<NSDictionary<NSString *, id> *> *images = ZNM42AppLocalImages();
    if (!images.count) {
        [ZNBinaryPatchWorkspace sharedWorkspace].lastStatus = @"当前 App 没有发现可选择的本地 Mach-O image";
        [self renderPage];
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"App Libraries"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (NSDictionary *item in images) {
        NSString *name = [item[@"name"] isKindOfClass:NSString.class] ? item[@"name"] : @"";
        NSString *path = [item[@"path"] isKindOfClass:NSString.class] ? item[@"path"] : @"";
        if (!name.length) name = path.lastPathComponent ?: @"";
        if (!name.length) continue;
        NSString *selectedName = [name copy];
        UIAlertAction *action = [UIAlertAction actionWithTitle:selectedName style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
            [workspace updateDefaultTarget:selectedName];
            [NSUserDefaults.standardUserDefaults setObject:selectedName forKey:@"ZonoePatch.Builder.SelectedTarget"];
            workspace.lastStatus = [NSString stringWithFormat:@"当前二进制：%@", selectedName];
            [weakSelf renderPage];
        }];
        [alert addAction:action];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    UIWindow *window = self.hostWindow ?: [self currentWindow];
    UIViewController *presenter = ZNM42TopController(window.rootViewController);
    if (!presenter) return;
    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    if (popover) {
        popover.sourceView = sender;
        popover.sourceRect = sender.bounds;
        popover.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }
    [presenter presentViewController:alert animated:YES completion:nil];
}

@end

static void ZNM42Swap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallMethodFinderM42UIDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNM42Swap(cls, @selector(zn60v3_renderResultsAtWidth:), @selector(znm42_renderResultsAtWidth:));
        ZNM42Swap(cls, @selector(znux_binaryPickerTapped:), @selector(znm42_binaryPickerTapped:));
        [[ZNRuntimeLogger sharedLogger] log:@"[m4.2-ui] arity filter + inline /1 input + direct test/create + simple App Libraries names installed"];
    });
}
