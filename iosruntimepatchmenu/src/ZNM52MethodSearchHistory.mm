#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNTheme.h"
#import "ZNPatchCore.h"

static NSString * const kZNM52SearchHistoryDefaultsKey = @"zonoe.m52.method-search-history.v1";
static const NSUInteger kZNM52SearchHistoryMax = 50;
static const NSInteger kZNM52SearchHistoryButtonTagBase = 846000;
static const NSInteger kZNM52M43QueryFieldTag = 603001;
static const void *kZNM52SearchHistoryValueKey = &kZNM52SearchHistoryValueKey;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIWindow *hostWindow;
@property(nonatomic,strong) ZNTheme *theme;
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (NSString *)zn57mf_query;
- (void)zn57mf_setQuery:(NSString *)value;
- (void)znm43_renderSearchAtWidth:(CGFloat)width;
- (void)znm43_startSearch:(id)sender;
@end

@interface ZNRuntimeMenuControllerV040 (ZNM52MethodSearchHistory)
- (void)znm52h_renderM43SearchAtWidth:(CGFloat)width;
- (void)znm52h_startM43Search:(id)sender;
- (void)znm52h_historyTapped:(UIButton *)sender;
@end

static NSString *ZNM52HTrim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSArray<NSString *> *ZNM52HHistory(void) {
    id raw = [[NSUserDefaults standardUserDefaults] objectForKey:kZNM52SearchHistoryDefaultsKey];
    if (![raw isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<NSString *> *clean = [NSMutableArray array];
    for (id item in (NSArray *)raw) {
        if (![item isKindOfClass:NSString.class]) continue;
        NSString *value = ZNM52HTrim(item);
        if (!value.length) continue;
        BOOL duplicate = NO;
        for (NSString *existing in clean) {
            if ([existing caseInsensitiveCompare:value] == NSOrderedSame) { duplicate = YES; break; }
        }
        if (duplicate) continue;
        [clean addObject:value];
        if (clean.count >= kZNM52SearchHistoryMax) break;
    }
    return [clean copy];
}

static void ZNM52HRecord(NSString *query) {
    NSString *value = ZNM52HTrim(query);
    if (!value.length) return;
    NSMutableArray<NSString *> *items = [ZNM52HHistory() mutableCopy];
    NSIndexSet *matches = [items indexesOfObjectsPassingTest:^BOOL(NSString *obj, NSUInteger idx, BOOL *stop) {
        (void)idx; (void)stop;
        return [obj caseInsensitiveCompare:value] == NSOrderedSame;
    }];
    if (matches.count) [items removeObjectsAtIndexes:matches];
    [items insertObject:value atIndex:0];
    if (items.count > kZNM52SearchHistoryMax) {
        [items removeObjectsInRange:NSMakeRange(kZNM52SearchHistoryMax, items.count - kZNM52SearchHistoryMax)];
    }
    [[NSUserDefaults standardUserDefaults] setObject:items forKey:kZNM52SearchHistoryDefaultsKey];
}

static CGFloat ZNM52HMaxY(UIView *root) {
    CGFloat y = 0;
    for (UIView *view in root.subviews) y = MAX(y, CGRectGetMaxY(view.frame));
    return y;
}

@implementation ZNRuntimeMenuControllerV040 (ZNM52MethodSearchHistory)

- (void)znm52h_startM43Search:(id)sender {
    ZNM52HRecord([self zn57mf_query]);
    [self znm52h_startM43Search:sender];
}

- (void)znm52h_renderM43SearchAtWidth:(CGFloat)width {
    [self znm52h_renderM43SearchAtWidth:width];

    NSArray<NSString *> *history = ZNM52HHistory();
    if (!history.count) return;

    // M4.3 search card is fixed at y=9 / h=170 and its next section begins at y=187.
    // Insert history exactly there. The previous implementation used maxY(contentView),
    // which also saw footer/other views and pushed history below the visible Finder area.
    const CGFloat insertY = 187.0;
    const CGFloat rowH = 31.0;
    CGFloat visibleRows = MIN((CGFloat)history.count, 6.0);
    CGFloat scrollH = MAX(rowH, visibleRows * rowH);
    CGFloat panelH = 31.0 + scrollH + 8.0;
    CGFloat displacement = panelH + 8.0;

    // Move the M4.3 status card and every later main-content view down before adding history.
    // This keeps the history directly under the search controls and avoids overlap.
    NSArray<UIView *> *existing = [self.contentView.subviews copy];
    for (UIView *view in existing) {
        if (CGRectGetMinY(view.frame) + 0.5 < insertY) continue;
        CGRect frame = view.frame;
        frame.origin.y += displacement;
        view.frame = frame;
    }

    UIView *card = [self cardAtY:insertY height:panelH width:width compact:NO];
    UILabel *title = [self label:[NSString stringWithFormat:@"搜索记录 · %lu/50", (unsigned long)history.count]
                               size:9.8
                             weight:UIFontWeightSemibold
                              color:self.theme.primaryTextColor];
    title.frame = CGRectMake(13, 6, card.bounds.size.width - 26, 20);
    [card addSubview:title];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(10, 29, card.bounds.size.width - 20, scrollH)];
    scroll.showsVerticalScrollIndicator = YES;
    scroll.alwaysBounceVertical = history.count > (NSUInteger)visibleRows;
    scroll.backgroundColor = UIColor.clearColor;

    for (NSUInteger i = 0; i < history.count; i++) {
        NSString *value = history[i];
        UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
        row.frame = CGRectMake(0, i * rowH, scroll.bounds.size.width, rowH - 2.0);
        row.tag = kZNM52SearchHistoryButtonTagBase + (NSInteger)i;
        [row setTitle:value forState:UIControlStateNormal];
        [row setTitleColor:self.theme.primaryTextColor forState:UIControlStateNormal];
        row.titleLabel.font = [UIFont systemFontOfSize:9.2 weight:UIFontWeightRegular];
        row.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        row.contentEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 8);
        row.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        row.backgroundColor = [self.theme.controlColor colorWithAlphaComponent:0.72];
        row.layer.cornerRadius = 5.0;
        row.layer.borderWidth = 0.5;
        row.layer.borderColor = self.theme.borderColor.CGColor;
        objc_setAssociatedObject(row, kZNM52SearchHistoryValueKey, value, OBJC_ASSOCIATION_COPY_NONATOMIC);
        [row addTarget:self action:@selector(znm52h_historyTapped:) forControlEvents:UIControlEventTouchUpInside];
        [scroll addSubview:row];
    }

    scroll.contentSize = CGSizeMake(scroll.bounds.size.width, history.count * rowH);
    [card addSubview:scroll];
    [self.contentView addSubview:card];

    CGFloat bottom = MAX(CGRectGetMaxY(card.frame), ZNM52HMaxY(self.contentView));
    [self zn40_updateContentHeight:bottom + 8.0];
}

- (void)znm52h_historyTapped:(UIButton *)sender {
    NSString *value = objc_getAssociatedObject(sender, kZNM52SearchHistoryValueKey);
    if (!value.length) return;

    // Requested UX: tapping history only fills the Method Name field.
    // It must NOT launch another search automatically.
    [self zn57mf_setQuery:value];
    UIView *candidate = [self.contentView viewWithTag:kZNM52M43QueryFieldTag];
    if ([candidate isKindOfClass:UITextField.class]) {
        UITextField *field = (UITextField *)candidate;
        field.text = value;
        [field becomeFirstResponder];
    }
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m5.2-search-history] autofill-only query=%@", value]];
}

@end

static void ZNM52HSwap(Class cls, SEL a, SEL b) {
    Method ma = class_getInstanceMethod(cls, a), mb = class_getInstanceMethod(cls, b);
    if (ma && mb) method_exchangeImplementations(ma, mb);
}

extern "C" void ZNInstallM52MethodSearchHistoryDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class menu = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (menu) {
            ZNM52HSwap(menu, @selector(znm43_startSearch:), @selector(znm52h_startM43Search:));
            ZNM52HSwap(menu, @selector(znm43_renderSearchAtWidth:), @selector(znm52h_renderM43SearchAtWidth:));
        }
        [[ZNRuntimeLogger sharedLogger] log:@"[m5.3-search-history-fix] M4.3 fixed insertion y=187 max=50 tap=autofill-only"];
    });
}
