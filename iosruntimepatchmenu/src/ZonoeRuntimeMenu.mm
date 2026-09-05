#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

static NSString * const kZNMenuVersion = @"0.2.0-ui";
static NSString * const kZNFloatPositionKey = @"ZonoePatch.FloatCenter";
static NSString * const kZNPanelPositionKey = @"ZonoePatch.PanelCenter";
static NSString * const kZNAutoSnapKey = @"ZonoePatch.AutoSnap";
static NSString * const kZNRememberPositionKey = @"ZonoePatch.RememberPosition";
static const CGFloat kZNFloatSize = 52.0;
static const CGFloat kZNMargin = 10.0;
static const CGFloat kZNHeaderHeight = 52.0;
static const CGFloat kZNFooterHeight = 28.0;

static CGFloat ZNClamp(CGFloat value, CGFloat minValue, CGFloat maxValue) {
    if (maxValue < minValue) return minValue;
    return MIN(MAX(value, minValue), maxValue);
}

static NSString *ZNOrientationText(CGSize size) {
    return size.width >= size.height ? @"Landscape" : @"Portrait";
}

static UIColor *ZNPanelColor(void) { return [UIColor colorWithWhite:0.035 alpha:0.94]; }
static UIColor *ZNSidebarColor(void) { return [UIColor colorWithWhite:0.065 alpha:0.92]; }
static UIColor *ZNCardColor(void) { return [UIColor colorWithWhite:1.0 alpha:0.055]; }
static UIColor *ZNSeparatorColor(void) { return [UIColor colorWithWhite:1.0 alpha:0.09]; }
static UIColor *ZNPrimaryTextColor(void) { return [UIColor colorWithWhite:0.96 alpha:1.0]; }
static UIColor *ZNSecondaryTextColor(void) { return [UIColor colorWithWhite:0.67 alpha:1.0]; }

@interface ZNRuntimeMenuController : NSObject
@property(nonatomic, strong) UIButton *floatButton;
@property(nonatomic, strong) UIView *panel;
@property(nonatomic, strong) UIView *headerView;
@property(nonatomic, strong) UIView *sidebarView;
@property(nonatomic, strong) UIScrollView *contentScroll;
@property(nonatomic, strong) UIView *contentView;
@property(nonatomic, strong) UIView *footerView;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *subtitleLabel;
@property(nonatomic, strong) UILabel *readyLabel;
@property(nonatomic, strong) UILabel *footerLabel;
@property(nonatomic, strong) UIButton *closeButton;
@property(nonatomic, strong) NSMutableArray<UIButton *> *sidebarButtons;
@property(nonatomic, copy) NSArray<NSString *> *categories;
@property(nonatomic, assign) NSInteger selectedCategory;
@property(nonatomic, weak) UIWindow *hostWindow;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, assign) CGRect lastHostBounds;
@property(nonatomic, assign) UIEdgeInsets lastSafeInsets;
@property(nonatomic, assign) BOOL uiReady;
@property(nonatomic, assign) BOOL autoSnap;
@property(nonatomic, assign) BOOL rememberPosition;
@end

@implementation ZNRuntimeMenuController

+ (instancetype)shared {
    static ZNRuntimeMenuController *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ZNRuntimeMenuController alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _categories = @[@"首页", @"玩家", @"战斗", @"移动", @"其他", @"设置"];
        _sidebarButtons = [NSMutableArray array];
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        if ([ud objectForKey:kZNAutoSnapKey] == nil) [ud setBool:YES forKey:kZNAutoSnapKey];
        if ([ud objectForKey:kZNRememberPositionKey] == nil) [ud setBool:YES forKey:kZNRememberPositionKey];
        _autoSnap = [ud boolForKey:kZNAutoSnapKey];
        _rememberPosition = [ud boolForKey:kZNRememberPositionKey];
    }
    return self;
}

- (UIWindow *)currentWindow {
    UIApplication *app = [UIApplication sharedApplication];
    if (@available(iOS 13.0, *)) {
        UIWindow *fallback = nil;
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            if (scene.activationState != UISceneActivationStateForegroundActive &&
                scene.activationState != UISceneActivationStateForegroundInactive) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                if (window.hidden || window.alpha <= 0.01) continue;
                if (window.isKeyWindow) return window;
                if (!fallback && window.windowLevel == UIWindowLevelNormal && window.rootViewController) fallback = window;
            }
        }
        if (fallback) return fallback;
    }
    UIWindow *key = app.keyWindow;
    if (key && !key.hidden && key.alpha > 0.01) return key;
    for (UIWindow *window in [app.windows reverseObjectEnumerator]) {
        if (window.hidden || window.alpha <= 0.01) continue;
        if (window.windowLevel == UIWindowLevelNormal && window.rootViewController) return window;
    }
    return app.windows.lastObject;
}

- (CGPoint)clampedButtonCenter:(CGPoint)center inWindow:(UIWindow *)window {
    CGRect bounds = window.bounds;
    UIEdgeInsets safe = window.safeAreaInsets;
    CGFloat half = kZNFloatSize * 0.5;
    CGFloat minX = safe.left + kZNMargin + half;
    CGFloat maxX = CGRectGetWidth(bounds) - safe.right - kZNMargin - half;
    CGFloat minY = safe.top + kZNMargin + half;
    CGFloat maxY = CGRectGetHeight(bounds) - safe.bottom - kZNMargin - half;
    return CGPointMake(ZNClamp(center.x, minX, maxX), ZNClamp(center.y, minY, maxY));
}

- (CGPoint)clampedPanelCenter:(CGPoint)center inWindow:(UIWindow *)window {
    CGRect bounds = window.bounds;
    UIEdgeInsets safe = window.safeAreaInsets;
    CGSize panelSize = self.panel.bounds.size;
    CGFloat halfW = panelSize.width * 0.5;
    CGFloat halfH = panelSize.height * 0.5;
    CGFloat minX = safe.left + kZNMargin + halfW;
    CGFloat maxX = CGRectGetWidth(bounds) - safe.right - kZNMargin - halfW;
    CGFloat minY = safe.top + kZNMargin + halfH;
    CGFloat maxY = CGRectGetHeight(bounds) - safe.bottom - kZNMargin - halfH;
    return CGPointMake(ZNClamp(center.x, minX, maxX), ZNClamp(center.y, minY, maxY));
}

- (CGSize)preferredPanelSizeForWindow:(UIWindow *)window {
    CGRect bounds = window.bounds;
    UIEdgeInsets safe = window.safeAreaInsets;
    CGFloat w = CGRectGetWidth(bounds) - safe.left - safe.right;
    CGFloat h = CGRectGetHeight(bounds) - safe.top - safe.bottom;
    BOOL landscape = w >= h;
    BOOL padLike = MAX(w, h) >= 900.0 && MIN(w, h) >= 600.0;
    CGFloat panelW = 0.0, panelH = 0.0;
    if (padLike) {
        panelW = MIN(680.0, w - 28.0);
        panelH = MIN(460.0, h - 28.0);
    } else if (landscape) {
        panelW = MIN(620.0, MAX(420.0, w * 0.72));
        panelH = MIN(400.0, MAX(300.0, h * 0.82));
    } else {
        panelW = MIN(520.0, MAX(300.0, w - 28.0));
        panelH = MIN(560.0, MAX(360.0, h * 0.70));
    }
    panelW = MIN(panelW, MAX(280.0, w - kZNMargin * 2.0));
    panelH = MIN(panelH, MAX(300.0, h - kZNMargin * 2.0));
    return CGSizeMake(panelW, panelH);
}

- (CGFloat)sidebarWidthForPanelWidth:(CGFloat)panelW {
    return panelW < 430.0 ? 96.0 : 118.0;
}

- (void)savePoint:(CGPoint)point key:(NSString *)key {
    if (!self.rememberPosition) return;
    [[NSUserDefaults standardUserDefaults] setObject:NSStringFromCGPoint(point) forKey:key];
}

- (CGPoint)restoredPointForKey:(NSString *)key fallback:(CGPoint)fallback {
    if (!self.rememberPosition) return fallback;
    NSString *s = [[NSUserDefaults standardUserDefaults] stringForKey:key];
    if (!s.length) return fallback;
    return CGPointFromString(s);
}

- (UILabel *)labelWithText:(NSString *)text font:(UIFont *)font color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.numberOfLines = 0;
    return label;
}

- (UIView *)cardWithHeight:(CGFloat)height y:(CGFloat)y width:(CGFloat)width {
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(12, y, MAX(0, width - 24), height)];
    card.backgroundColor = ZNCardColor();
    card.layer.cornerRadius = 11.0;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.045].CGColor;
    return card;
}

- (void)addSectionTitle:(NSString *)title subtitle:(NSString *)subtitle y:(CGFloat *)y width:(CGFloat)width {
    UILabel *titleLabel = [self labelWithText:title font:[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold] color:ZNPrimaryTextColor()];
    titleLabel.frame = CGRectMake(12, *y, width - 24, 24);
    [self.contentView addSubview:titleLabel];
    *y += 26;
    if (subtitle.length) {
        UILabel *sub = [self labelWithText:subtitle font:[UIFont systemFontOfSize:11.5] color:ZNSecondaryTextColor()];
        sub.frame = CGRectMake(12, *y, width - 24, 34);
        [self.contentView addSubview:sub];
        *y += 40;
    }
}

- (UISwitch *)addSwitchCardTitle:(NSString *)title subtitle:(NSString *)subtitle y:(CGFloat *)y width:(CGFloat)width selector:(SEL)selector on:(BOOL)on {
    UIView *card = [self cardWithHeight:72 y:*y width:width];
    UILabel *t = [self labelWithText:title font:[UIFont systemFontOfSize:14.5 weight:UIFontWeightMedium] color:ZNPrimaryTextColor()];
    t.frame = CGRectMake(14, 12, MAX(80, card.bounds.size.width - 92), 21);
    [card addSubview:t];
    UILabel *s = [self labelWithText:subtitle font:[UIFont systemFontOfSize:10.5] color:ZNSecondaryTextColor()];
    s.frame = CGRectMake(14, 36, MAX(80, card.bounds.size.width - 92), 26);
    [card addSubview:s];
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
    sw.on = on;
    CGSize swSize = sw.bounds.size;
    sw.center = CGPointMake(card.bounds.size.width - 14 - swSize.width * 0.5, card.bounds.size.height * 0.5);
    [sw addTarget:self action:selector forControlEvents:UIControlEventValueChanged];
    [card addSubview:sw];
    [self.contentView addSubview:card];
    *y += 82;
    return sw;
}

- (void)addSliderCardTitle:(NSString *)title y:(CGFloat *)y width:(CGFloat)width {
    UIView *card = [self cardWithHeight:98 y:*y width:width];
    UILabel *t = [self labelWithText:title font:[UIFont systemFontOfSize:14.5 weight:UIFontWeightMedium] color:ZNPrimaryTextColor()];
    t.frame = CGRectMake(14, 10, card.bounds.size.width - 80, 22);
    [card addSubview:t];
    UILabel *value = [self labelWithText:@"5.0x" font:[UIFont monospacedDigitSystemFontOfSize:12.5 weight:UIFontWeightSemibold] color:ZNSecondaryTextColor()];
    value.tag = 5201;
    value.textAlignment = NSTextAlignmentRight;
    value.frame = CGRectMake(card.bounds.size.width - 70, 10, 56, 22);
    [card addSubview:value];
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(14, 43, card.bounds.size.width - 28, 30)];
    slider.minimumValue = 1.0f;
    slider.maximumValue = 20.0f;
    slider.value = 5.0f;
    [slider addTarget:self action:@selector(dummySliderChanged:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:slider];
    UILabel *range = [self labelWithText:@"1.0                                      20.0" font:[UIFont monospacedDigitSystemFontOfSize:9.0 weight:UIFontWeightRegular] color:[UIColor colorWithWhite:0.52 alpha:1.0]];
    range.frame = CGRectMake(14, 73, card.bounds.size.width - 28, 14);
    [card addSubview:range];
    [self.contentView addSubview:card];
    *y += 108;
}

- (void)addButtonCardTitle:(NSString *)title subtitle:(NSString *)subtitle y:(CGFloat *)y width:(CGFloat)width {
    UIView *card = [self cardWithHeight:92 y:*y width:width];
    UILabel *t = [self labelWithText:title font:[UIFont systemFontOfSize:14.5 weight:UIFontWeightMedium] color:ZNPrimaryTextColor()];
    t.frame = CGRectMake(14, 10, card.bounds.size.width - 28, 20);
    [card addSubview:t];
    UILabel *s = [self labelWithText:subtitle font:[UIFont systemFontOfSize:10.5] color:ZNSecondaryTextColor()];
    s.frame = CGRectMake(14, 31, card.bounds.size.width - 28, 20);
    [card addSubview:s];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(14, 56, card.bounds.size.width - 28, 27);
    button.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.075];
    button.layer.cornerRadius = 7.0;
    [button setTitle:@"执行测试" forState:UIControlStateNormal];
    [button setTitleColor:ZNPrimaryTextColor() forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [button addTarget:self action:@selector(dummyButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:button];
    [self.contentView addSubview:card];
    *y += 102;
}

- (void)renderCurrentPage {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat y = 14.0;
    NSString *category = self.categories[self.selectedCategory];

    if ([category isEqualToString:@"首页"]) {
        [self addSectionTitle:@"Runtime 状态" subtitle:@"V0.2 仍然是 UI 基线，不包含任何真实 Patch / Hook。" y:&y width:width];
        UIView *card = [self cardWithHeight:174 y:y width:width];
        NSArray *rows = @[
            @[@"状态", @"Ready · UI ONLY"],
            @[@"版本", kZNMenuVersion],
            @[@"设备", [NSString stringWithFormat:@"iOS %@ · %@", [UIDevice currentDevice].systemVersion, ZNOrientationText(self.hostWindow.bounds.size)]],
            @[@"窗口", [NSString stringWithFormat:@"%.0f × %.0f", self.hostWindow.bounds.size.width, self.hostWindow.bounds.size.height]],
            @[@"Patch", @"0 Enabled · 0 Unsupported"]
        ];
        CGFloat rowY = 10;
        for (NSArray *row in rows) {
            UILabel *l = [self labelWithText:row[0] font:[UIFont systemFontOfSize:11.5 weight:UIFontWeightMedium] color:ZNSecondaryTextColor()];
            l.frame = CGRectMake(14, rowY, 72, 24);
            [card addSubview:l];
            UILabel *r = [self labelWithText:row[1] font:[UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular] color:ZNPrimaryTextColor()];
            r.textAlignment = NSTextAlignmentRight;
            r.frame = CGRectMake(90, rowY, card.bounds.size.width - 104, 24);
            [card addSubview:r];
            rowY += 31;
        }
        [self.contentView addSubview:card];
        y += 184;
    } else if ([category isEqualToString:@"玩家"]) {
        [self addSectionTitle:@"玩家" subtitle:@"用于验证标准开关组件和后续 Patch 状态绑定。" y:&y width:width];
        [self addSwitchCardTitle:@"无敌（UI 测试）" subtitle:@"当前仅改变界面状态，不修改游戏。" y:&y width:width selector:@selector(dummySwitchChanged:) on:NO];
        [self addSwitchCardTitle:@"无限资源（UI 测试）" subtitle:@"后续将由 PatchManager 提供真实状态。" y:&y width:width selector:@selector(dummySwitchChanged:) on:NO];
    } else if ([category isEqualToString:@"战斗"]) {
        [self addSectionTitle:@"战斗" subtitle:@"验证 Slider + Switch 组合布局。" y:&y width:width];
        [self addSwitchCardTitle:@"伤害倍率（UI 测试）" subtitle:@"打开后仍不会执行 Patch。" y:&y width:width selector:@selector(dummySwitchChanged:) on:NO];
        [self addSliderCardTitle:@"倍率" y:&y width:width];
    } else if ([category isEqualToString:@"移动"]) {
        [self addSectionTitle:@"移动" subtitle:@"后续可用于速度、跳跃、移动类 Patch。" y:&y width:width];
        [self addSwitchCardTitle:@"移动速度（UI 测试）" subtitle:@"目前仅作为组件占位。" y:&y width:width selector:@selector(dummySwitchChanged:) on:NO];
        [self addSliderCardTitle:@"速度倍率" y:&y width:width];
    } else if ([category isEqualToString:@"其他"]) {
        [self addSectionTitle:@"其他" subtitle:@"用于一次性 Action/Button 类型功能。" y:&y width:width];
        [self addButtonCardTitle:@"一次性动作（UI 测试）" subtitle:@"点击只输出日志，不修改目标 App。" y:&y width:width];
    } else if ([category isEqualToString:@"设置"]) {
        [self addSectionTitle:@"界面设置" subtitle:@"设置项已经持久化，可直接沿用到后续正式版本。" y:&y width:width];
        [self addSwitchCardTitle:@"悬浮球自动贴边" subtitle:@"拖动结束后自动吸附到最近的左右边缘。" y:&y width:width selector:@selector(autoSnapChanged:) on:self.autoSnap];
        [self addSwitchCardTitle:@"记住界面位置" subtitle:@"保存悬浮球与菜单面板最后位置。" y:&y width:width selector:@selector(rememberPositionChanged:) on:self.rememberPosition];
        [self addButtonCardTitle:@"开发者测试" subtitle:@"保留给后续 Runtime / Patch 状态诊断入口。" y:&y width:width];
    }

    y += 14;
    CGRect frame = self.contentView.frame;
    frame.size.height = MAX(CGRectGetHeight(self.contentScroll.bounds), y);
    self.contentView.frame = frame;
    self.contentScroll.contentSize = CGSizeMake(CGRectGetWidth(self.contentScroll.bounds), frame.size.height);
}

- (void)layoutSidebarButtons {
    CGFloat width = CGRectGetWidth(self.sidebarView.bounds);
    CGFloat y = 10.0;
    CGFloat buttonH = 39.0;
    for (NSInteger i = 0; i < self.sidebarButtons.count; i++) {
        UIButton *button = self.sidebarButtons[i];
        button.frame = CGRectMake(8, y, MAX(0, width - 16), buttonH);
        y += buttonH + 5;
    }
}

- (void)layoutPanelContents {
    CGFloat panelW = CGRectGetWidth(self.panel.bounds);
    CGFloat panelH = CGRectGetHeight(self.panel.bounds);
    CGFloat sidebarW = [self sidebarWidthForPanelWidth:panelW];
    self.headerView.frame = CGRectMake(0, 0, panelW, kZNHeaderHeight);
    self.titleLabel.frame = CGRectMake(15, 7, MAX(110, panelW - 190), 21);
    self.subtitleLabel.frame = CGRectMake(15, 28, MAX(110, panelW - 190), 16);
    self.readyLabel.frame = CGRectMake(MAX(0, panelW - 150), 10, 92, 30);
    self.closeButton.frame = CGRectMake(MAX(0, panelW - 49), 6, 42, 40);
    CGFloat bodyH = MAX(0, panelH - kZNHeaderHeight - kZNFooterHeight);
    self.sidebarView.frame = CGRectMake(0, kZNHeaderHeight, sidebarW, bodyH);
    self.contentScroll.frame = CGRectMake(sidebarW, kZNHeaderHeight, MAX(0, panelW - sidebarW), bodyH);
    self.contentView.frame = CGRectMake(0, 0, CGRectGetWidth(self.contentScroll.bounds), MAX(bodyH, self.contentView.frame.size.height));
    self.footerView.frame = CGRectMake(0, panelH - kZNFooterHeight, panelW, kZNFooterHeight);
    self.footerLabel.frame = CGRectMake(12, 0, panelW - 24, kZNFooterHeight);
    [self layoutSidebarButtons];
    [self renderCurrentPage];
}

- (void)layoutForWindow:(UIWindow *)window initial:(BOOL)initial {
    if (!window || !self.uiReady) return;
    CGRect bounds = window.bounds;
    UIEdgeInsets safe = window.safeAreaInsets;
    CGSize panelSize = [self preferredPanelSizeForWindow:window];
    CGPoint oldPanelCenter = self.panel.center;
    self.panel.bounds = CGRectMake(0, 0, panelSize.width, panelSize.height);
    if (initial) {
        CGPoint defaultFloat = CGPointMake(CGRectGetWidth(bounds) - safe.right - kZNMargin - kZNFloatSize * 0.5,
                                           CGRectGetMidY(bounds));
        CGPoint defaultPanel = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
        self.floatButton.center = [self clampedButtonCenter:[self restoredPointForKey:kZNFloatPositionKey fallback:defaultFloat] inWindow:window];
        self.panel.center = [self clampedPanelCenter:[self restoredPointForKey:kZNPanelPositionKey fallback:defaultPanel] inWindow:window];
    } else {
        self.floatButton.center = [self clampedButtonCenter:self.floatButton.center inWindow:window];
        self.panel.center = [self clampedPanelCenter:oldPanelCenter inWindow:window];
    }
    self.lastHostBounds = bounds;
    self.lastSafeInsets = safe;
    self.footerLabel.text = [NSString stringWithFormat:@"UI ONLY · %@ · %@ · %.0fx%.0f", kZNMenuVersion, ZNOrientationText(bounds.size), bounds.size.width, bounds.size.height];
    [self layoutPanelContents];
}

- (void)updateSidebarSelection {
    for (NSInteger i = 0; i < self.sidebarButtons.count; i++) {
        UIButton *b = self.sidebarButtons[i];
        BOOL selected = (i == self.selectedCategory);
        b.backgroundColor = selected ? [UIColor colorWithWhite:1.0 alpha:0.105] : [UIColor clearColor];
        [b setTitleColor:selected ? ZNPrimaryTextColor() : ZNSecondaryTextColor() forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:12.5 weight:selected ? UIFontWeightSemibold : UIFontWeightRegular];
    }
}

- (void)makeUI:(UIWindow *)window {
    if (self.uiReady || !window) return;
    self.hostWindow = window;

    UIButton *floatButton = [UIButton buttonWithType:UIButtonTypeCustom];
    floatButton.bounds = CGRectMake(0, 0, kZNFloatSize, kZNFloatSize);
    floatButton.backgroundColor = [UIColor colorWithWhite:0.055 alpha:0.90];
    floatButton.layer.cornerRadius = kZNFloatSize * 0.5;
    floatButton.layer.borderWidth = 1.0;
    floatButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.16].CGColor;
    floatButton.layer.shadowColor = [UIColor blackColor].CGColor;
    floatButton.layer.shadowOpacity = 0.30;
    floatButton.layer.shadowRadius = 7.0;
    floatButton.layer.shadowOffset = CGSizeMake(0, 2);
    [floatButton setTitle:@"ZN" forState:UIControlStateNormal];
    [floatButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    floatButton.titleLabel.font = [UIFont boldSystemFontOfSize:13.5];
    [floatButton addTarget:self action:@selector(togglePanel:) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *buttonPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panButton:)];
    buttonPan.cancelsTouchesInView = NO;
    [floatButton addGestureRecognizer:buttonPan];
    self.floatButton = floatButton;

    UIView *panel = [[UIView alloc] initWithFrame:CGRectZero];
    panel.backgroundColor = ZNPanelColor();
    panel.layer.cornerRadius = 15.0;
    panel.layer.masksToBounds = NO;
    panel.layer.borderWidth = 1.0;
    panel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.11].CGColor;
    panel.layer.shadowColor = [UIColor blackColor].CGColor;
    panel.layer.shadowOpacity = 0.36;
    panel.layer.shadowRadius = 14.0;
    panel.layer.shadowOffset = CGSizeMake(0, 5);
    self.panel = panel;

    UIView *header = [[UIView alloc] initWithFrame:CGRectZero];
    header.backgroundColor = [UIColor colorWithWhite:0.02 alpha:0.92];
    header.layer.cornerRadius = 15.0;
    self.headerView = header;
    [panel addSubview:header];
    UIPanGestureRecognizer *panelPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panPanel:)];
    panelPan.cancelsTouchesInView = NO;
    [header addGestureRecognizer:panelPan];

    UILabel *title = [self labelWithText:@"ZONOE PATCH" font:[UIFont systemFontOfSize:16.5 weight:UIFontWeightBold] color:ZNPrimaryTextColor()];
    self.titleLabel = title;
    [header addSubview:title];

    UILabel *subtitle = [self labelWithText:@"Runtime Patch Menu" font:[UIFont systemFontOfSize:10.5 weight:UIFontWeightRegular] color:ZNSecondaryTextColor()];
    self.subtitleLabel = subtitle;
    [header addSubview:subtitle];

    UILabel *ready = [self labelWithText:@"●  Ready" font:[UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightSemibold] color:[UIColor systemGreenColor]];
    ready.textAlignment = NSTextAlignmentRight;
    self.readyLabel = ready;
    [header addSubview:ready];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"×" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor colorWithWhite:0.82 alpha:1.0] forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightLight];
    [close addTarget:self action:@selector(closePanel:) forControlEvents:UIControlEventTouchUpInside];
    self.closeButton = close;
    [header addSubview:close];

    UIView *sidebar = [[UIView alloc] initWithFrame:CGRectZero];
    sidebar.backgroundColor = ZNSidebarColor();
    self.sidebarView = sidebar;
    [panel addSubview:sidebar];

    for (NSInteger i = 0; i < self.categories.count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = 3000 + i;
        button.layer.cornerRadius = 8.0;
        button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        button.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 6);
        [button setTitle:self.categories[i] forState:UIControlStateNormal];
        [button addTarget:self action:@selector(sidebarTapped:) forControlEvents:UIControlEventTouchUpInside];
        [sidebar addSubview:button];
        [self.sidebarButtons addObject:button];
    }

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    scroll.backgroundColor = [UIColor clearColor];
    scroll.alwaysBounceVertical = YES;
    scroll.showsVerticalScrollIndicator = YES;
    scroll.delaysContentTouches = NO;
    self.contentScroll = scroll;
    [panel addSubview:scroll];

    UIView *content = [[UIView alloc] initWithFrame:CGRectZero];
    content.backgroundColor = [UIColor clearColor];
    self.contentView = content;
    [scroll addSubview:content];

    UIView *footer = [[UIView alloc] initWithFrame:CGRectZero];
    footer.backgroundColor = [UIColor colorWithWhite:0.02 alpha:0.86];
    self.footerView = footer;
    [panel addSubview:footer];
    UIView *footerLine = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 5000, 1)];
    footerLine.backgroundColor = ZNSeparatorColor();
    [footer addSubview:footerLine];
    UILabel *footerLabel = [self labelWithText:@"" font:[UIFont monospacedSystemFontOfSize:9.5 weight:UIFontWeightRegular] color:[UIColor colorWithWhite:0.54 alpha:1.0]];
    footerLabel.textAlignment = NSTextAlignmentCenter;
    self.footerLabel = footerLabel;
    [footer addSubview:footerLabel];

    panel.hidden = YES;
    [window addSubview:floatButton];
    [window addSubview:panel];
    self.uiReady = YES;
    [self updateSidebarSelection];
    [self layoutForWindow:window initial:YES];
    NSLog(@"[ZonoePatch v0.2] UI ready window=%@ bounds=%@", window, NSStringFromCGRect(window.bounds));
}

- (void)attachToWindow:(UIWindow *)window {
    if (!window || !self.uiReady) return;
    if (self.hostWindow == window && self.floatButton.superview == window && self.panel.superview == window) return;
    [self.floatButton removeFromSuperview];
    [self.panel removeFromSuperview];
    [window addSubview:self.floatButton];
    [window addSubview:self.panel];
    self.hostWindow = window;
    [self layoutForWindow:window initial:NO];
    NSLog(@"[ZonoePatch v0.2] reattached window=%@", window);
}

- (void)tick:(NSTimer *)timer {
    (void)timer;
    UIWindow *window = [self currentWindow];
    if (!window) return;
    if (!self.uiReady) {
        [self makeUI:window];
        return;
    }
    if (self.hostWindow != window || self.floatButton.superview != window || self.panel.superview != window) {
        [self attachToWindow:window];
    }
    if (!CGRectEqualToRect(self.lastHostBounds, window.bounds) ||
        !UIEdgeInsetsEqualToEdgeInsets(self.lastSafeInsets, window.safeAreaInsets)) {
        [self layoutForWindow:window initial:NO];
    }
    [window bringSubviewToFront:self.panel];
    [window bringSubviewToFront:self.floatButton];
}

- (void)start {
    if (self.timer) {
        [self show];
        return;
    }
    [self tick:nil];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    NSLog(@"[ZonoePatch v0.2] bootstrap version=%@", kZNMenuVersion);
}

- (void)show {
    if (!self.uiReady) {
        [self tick:nil];
        return;
    }
    self.floatButton.hidden = NO;
    self.panel.hidden = NO;
    [self.hostWindow bringSubviewToFront:self.panel];
    [self.hostWindow bringSubviewToFront:self.floatButton];
}

- (void)hide {
    self.panel.hidden = YES;
}

- (BOOL)isVisible {
    return self.uiReady && !self.panel.hidden;
}

- (void)togglePanel:(id)sender {
    (void)sender;
    self.panel.hidden = !self.panel.hidden;
    if (!self.panel.hidden && self.hostWindow) {
        self.panel.center = [self clampedPanelCenter:self.panel.center inWindow:self.hostWindow];
        [self.hostWindow bringSubviewToFront:self.panel];
        [self.hostWindow bringSubviewToFront:self.floatButton];
    }
}

- (void)closePanel:(id)sender {
    (void)sender;
    [self hide];
}

- (void)sidebarTapped:(UIButton *)sender {
    NSInteger index = sender.tag - 3000;
    if (index < 0 || index >= self.categories.count) return;
    self.selectedCategory = index;
    [self updateSidebarSelection];
    self.contentScroll.contentOffset = CGPointZero;
    [self renderCurrentPage];
}

- (void)dummySwitchChanged:(UISwitch *)sender {
    NSLog(@"[ZonoePatch v0.2] dummy switch=%@", sender.isOn ? @"ON" : @"OFF");
}

- (void)dummySliderChanged:(UISlider *)slider {
    UIView *card = slider.superview;
    UILabel *value = [card viewWithTag:5201];
    value.text = [NSString stringWithFormat:@"%.1fx", slider.value];
}

- (void)dummyButtonTapped:(UIButton *)sender {
    (void)sender;
    NSLog(@"[ZonoePatch v0.2] dummy action tapped");
}

- (void)autoSnapChanged:(UISwitch *)sender {
    self.autoSnap = sender.isOn;
    [[NSUserDefaults standardUserDefaults] setBool:self.autoSnap forKey:kZNAutoSnapKey];
    if (self.autoSnap && self.hostWindow) [self snapFloatButtonAnimated:YES];
}

- (void)rememberPositionChanged:(UISwitch *)sender {
    self.rememberPosition = sender.isOn;
    [[NSUserDefaults standardUserDefaults] setBool:self.rememberPosition forKey:kZNRememberPositionKey];
    if (self.rememberPosition) {
        [self savePoint:self.floatButton.center key:kZNFloatPositionKey];
        [self savePoint:self.panel.center key:kZNPanelPositionKey];
    }
}

- (void)snapFloatButtonAnimated:(BOOL)animated {
    UIWindow *window = self.hostWindow;
    if (!window || !self.floatButton) return;
    CGRect bounds = window.bounds;
    UIEdgeInsets safe = window.safeAreaInsets;
    CGFloat half = kZNFloatSize * 0.5;
    CGFloat leftX = safe.left + kZNMargin + half;
    CGFloat rightX = CGRectGetWidth(bounds) - safe.right - kZNMargin - half;
    CGPoint center = [self clampedButtonCenter:self.floatButton.center inWindow:window];
    center.x = (center.x < CGRectGetMidX(bounds)) ? leftX : rightX;
    void (^changes)(void) = ^{ self.floatButton.center = center; };
    if (animated) [UIView animateWithDuration:0.20 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:changes completion:nil];
    else changes();
    [self savePoint:center key:kZNFloatPositionKey];
}

- (void)panButton:(UIPanGestureRecognizer *)gesture {
    UIWindow *window = self.hostWindow;
    if (!window) return;
    CGPoint translation = [gesture translationInView:window];
    CGPoint center = self.floatButton.center;
    center.x += translation.x;
    center.y += translation.y;
    self.floatButton.center = [self clampedButtonCenter:center inWindow:window];
    [gesture setTranslation:CGPointZero inView:window];
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        if (self.autoSnap) [self snapFloatButtonAnimated:YES];
        else [self savePoint:self.floatButton.center key:kZNFloatPositionKey];
    }
}

- (void)panPanel:(UIPanGestureRecognizer *)gesture {
    UIWindow *window = self.hostWindow;
    if (!window) return;
    CGPoint translation = [gesture translationInView:window];
    CGPoint center = self.panel.center;
    center.x += translation.x;
    center.y += translation.y;
    self.panel.center = [self clampedPanelCenter:center inWindow:window];
    [gesture setTranslation:CGPointZero inView:window];
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        [self savePoint:self.panel.center key:kZNPanelPositionKey];
    }
}

@end

extern "C" __attribute__((visibility("default"))) uint32_t ZonoePatchGetAPIVersion(void) {
    return 1;
}

extern "C" __attribute__((visibility("default"))) const char *ZonoePatchGetVersion(void) {
    return "0.2.0-ui";
}

extern "C" __attribute__((visibility("default"))) void ZonoePatchStart(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [[ZNRuntimeMenuController shared] start]; });
}

extern "C" __attribute__((visibility("default"))) void ZonoePatchShow(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [[ZNRuntimeMenuController shared] show]; });
}

extern "C" __attribute__((visibility("default"))) void ZonoePatchHide(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [[ZNRuntimeMenuController shared] hide]; });
}

extern "C" __attribute__((visibility("default"))) bool ZonoePatchIsVisible(void) {
    __block BOOL visible = NO;
    if ([NSThread isMainThread]) return [[ZNRuntimeMenuController shared] isVisible];
    dispatch_sync(dispatch_get_main_queue(), ^{ visible = [[ZNRuntimeMenuController shared] isVisible]; });
    return visible;
}

__attribute__((constructor)) static void ZNRuntimeMenuBootstrap(void) {
    @autoreleasepool {
        NSLog(@"[ZonoePatch v0.2] dylib loaded");
        ZonoePatchStart();
    }
}
