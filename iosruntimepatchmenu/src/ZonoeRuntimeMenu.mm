#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <stdint.h>

#import "ZNTheme.h"

static NSString * const kZNMenuVersion = @"0.2.1-ui";
static NSString * const kZNFloatPositionKey = @"ZonoePatch.FloatCenter";
static NSString * const kZNPanelPositionKey = @"ZonoePatch.PanelCenter";
static NSString * const kZNAutoSnapKey = @"ZonoePatch.AutoSnap";
static NSString * const kZNRememberPositionKey = @"ZonoePatch.RememberPosition";
static NSString * const kZNThemeModeKey = @"ZonoePatch.ThemeMode";
static NSString * const kZNMenuAlphaKey = @"ZonoePatch.MenuAlpha";

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

static UIImage *ZNSymbol(NSString *name, CGFloat pointSize, UIImageSymbolWeight weight) {
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:weight];
        return [[UIImage systemImageNamed:name withConfiguration:config] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    return nil;
}

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
@property(nonatomic, strong) UIView *readyDot;
@property(nonatomic, strong) UILabel *readyLabel;
@property(nonatomic, strong) UIButton *themeButton;
@property(nonatomic, strong) UIButton *minimizeButton;
@property(nonatomic, strong) UIButton *closeButton;
@property(nonatomic, strong) UIView *themePopover;
@property(nonatomic, strong) UILabel *footerLabel;
@property(nonatomic, strong) NSMutableArray<UIButton *> *sidebarButtons;
@property(nonatomic, copy) NSArray<NSString *> *categories;
@property(nonatomic, copy) NSArray<NSString *> *categorySymbols;
@property(nonatomic, assign) NSInteger selectedCategory;
@property(nonatomic, weak) UIWindow *hostWindow;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, assign) CGRect lastHostBounds;
@property(nonatomic, assign) UIEdgeInsets lastSafeInsets;
@property(nonatomic, assign) UIUserInterfaceStyle lastInterfaceStyle;
@property(nonatomic, assign) BOOL uiReady;
@property(nonatomic, assign) BOOL autoSnap;
@property(nonatomic, assign) BOOL rememberPosition;
@property(nonatomic, assign) ZNThemeMode themeMode;
@property(nonatomic, strong) ZNTheme *theme;
@property(nonatomic, assign) CGFloat menuAlpha;
@end

@implementation ZNRuntimeMenuController

+ (instancetype)shared {
    static ZNRuntimeMenuController *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [[ZNRuntimeMenuController alloc] init]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;

    _categories = @[@"首页", @"玩家", @"战斗", @"移动", @"其他", @"设置"];
    _categorySymbols = @[@"house.fill", @"person.fill", @"bolt.fill", @"location.north.fill", @"square.grid.2x2.fill", @"gearshape.fill"];
    _sidebarButtons = [NSMutableArray array];

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud objectForKey:kZNAutoSnapKey] == nil) [ud setBool:YES forKey:kZNAutoSnapKey];
    if ([ud objectForKey:kZNRememberPositionKey] == nil) [ud setBool:YES forKey:kZNRememberPositionKey];
    if ([ud objectForKey:kZNThemeModeKey] == nil) [ud setInteger:ZNThemeModeObsidian forKey:kZNThemeModeKey];
    if ([ud objectForKey:kZNMenuAlphaKey] == nil) [ud setDouble:0.88 forKey:kZNMenuAlphaKey];

    _autoSnap = [ud boolForKey:kZNAutoSnapKey];
    _rememberPosition = [ud boolForKey:kZNRememberPositionKey];
    _themeMode = (ZNThemeMode)[ud integerForKey:kZNThemeModeKey];
    if (_themeMode < ZNThemeModeSystem || _themeMode > ZNThemeModeMatcha) _themeMode = ZNThemeModeObsidian;
    _menuAlpha = ZNClamp([ud doubleForKey:kZNMenuAlphaKey], 0.55, 1.0);
    _theme = [ZNTheme themeForMode:_themeMode interfaceStyle:UIUserInterfaceStyleDark];
    _lastInterfaceStyle = UIUserInterfaceStyleUnspecified;
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

- (UIUserInterfaceStyle)currentInterfaceStyle {
    if (@available(iOS 13.0, *)) {
        UIUserInterfaceStyle style = self.hostWindow.traitCollection.userInterfaceStyle;
        if (style == UIUserInterfaceStyleUnspecified) style = UIScreen.mainScreen.traitCollection.userInterfaceStyle;
        if (style == UIUserInterfaceStyleUnspecified) style = UIUserInterfaceStyleDark;
        return style;
    }
    return UIUserInterfaceStyleDark;
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
    CGSize size = self.panel.bounds.size;
    CGFloat minX = safe.left + kZNMargin + size.width * 0.5;
    CGFloat maxX = CGRectGetWidth(bounds) - safe.right - kZNMargin - size.width * 0.5;
    CGFloat minY = safe.top + kZNMargin + size.height * 0.5;
    CGFloat maxY = CGRectGetHeight(bounds) - safe.bottom - kZNMargin - size.height * 0.5;
    return CGPointMake(ZNClamp(center.x, minX, maxX), ZNClamp(center.y, minY, maxY));
}

- (CGSize)preferredPanelSizeForWindow:(UIWindow *)window {
    CGRect bounds = window.bounds;
    UIEdgeInsets safe = window.safeAreaInsets;
    CGFloat w = CGRectGetWidth(bounds) - safe.left - safe.right;
    CGFloat h = CGRectGetHeight(bounds) - safe.top - safe.bottom;
    BOOL landscape = w >= h;
    BOOL padLike = MAX(w, h) >= 900.0 && MIN(w, h) >= 600.0;
    CGFloat panelW, panelH;
    if (padLike) {
        panelW = MIN(680.0, w - 28.0);
        panelH = MIN(460.0, h - 28.0);
    } else if (landscape) {
        panelW = MIN(620.0, MAX(430.0, w * 0.72));
        panelH = MIN(400.0, MAX(310.0, h * 0.82));
    } else {
        panelW = MIN(520.0, MAX(310.0, w - 28.0));
        panelH = MIN(560.0, MAX(380.0, h * 0.70));
    }
    panelW = MIN(panelW, MAX(290.0, w - kZNMargin * 2.0));
    panelH = MIN(panelH, MAX(310.0, h - kZNMargin * 2.0));
    return CGSizeMake(panelW, panelH);
}

- (CGFloat)sidebarWidthForPanelWidth:(CGFloat)panelW {
    return panelW < 450.0 ? 102.0 : 122.0;
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

- (void)clearThemeDecorationLayers {
    NSArray<CALayer *> *layers = [self.panel.layer.sublayers copy];
    for (CALayer *layer in layers) {
        if ([layer.name hasPrefix:@"ZNThemeDecoration"]) [layer removeFromSuperlayer];
    }
}

- (void)installThemeDecorationLayers {
    [self clearThemeDecorationLayers];
    if (!self.panel) return;

    CGRect b = self.panel.bounds;
    if (self.theme.neonAppearance) {
        CAGradientLayer *gradient = [CAGradientLayer layer];
        gradient.name = @"ZNThemeDecoration.NeonBorder";
        gradient.frame = b;
        gradient.colors = @[(id)self.theme.accent2Color.CGColor, (id)self.theme.accentColor.CGColor, (id)self.theme.accent2Color.CGColor];
        gradient.startPoint = CGPointMake(0.0, 0.2);
        gradient.endPoint = CGPointMake(1.0, 0.8);

        CAShapeLayer *mask = [CAShapeLayer layer];
        mask.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(b, 1.0, 1.0) cornerRadius:16.0].CGPath;
        mask.fillColor = UIColor.clearColor.CGColor;
        mask.strokeColor = UIColor.whiteColor.CGColor;
        mask.lineWidth = 2.0;
        gradient.mask = mask;
        [self.panel.layer addSublayer:gradient];
    }

    if (self.theme.mechanicalAppearance) {
        CAGradientLayer *topGlow = [CAGradientLayer layer];
        topGlow.name = @"ZNThemeDecoration.MechanicalTop";
        topGlow.frame = CGRectMake(0, 0, b.size.width, kZNHeaderHeight);
        topGlow.colors = @[(id)[self.theme.accentColor colorWithAlphaComponent:0.03].CGColor,
                           (id)[self.theme.accentColor colorWithAlphaComponent:0.16].CGColor,
                           (id)[self.theme.accentColor colorWithAlphaComponent:0.02].CGColor];
        topGlow.startPoint = CGPointMake(0, 0.5);
        topGlow.endPoint = CGPointMake(1, 0.5);
        [self.panel.layer insertSublayer:topGlow atIndex:0];

        for (NSInteger i = 0; i < 4; i++) {
            CAShapeLayer *bolt = [CAShapeLayer layer];
            bolt.name = [NSString stringWithFormat:@"ZNThemeDecoration.Bolt%ld", (long)i];
            CGFloat x = (i % 2 == 0) ? 12.0 : b.size.width - 18.0;
            CGFloat y = (i < 2) ? 10.0 : b.size.height - 16.0;
            bolt.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(x, y, 6, 6)].CGPath;
            bolt.fillColor = [self.theme.accentColor colorWithAlphaComponent:0.34].CGColor;
            bolt.strokeColor = [self.theme.accentColor colorWithAlphaComponent:0.70].CGColor;
            bolt.lineWidth = 0.8;
            [self.panel.layer addSublayer:bolt];
        }
    }
}

- (void)applyThemeToChrome {
    if (!self.uiReady) return;
    self.theme = [ZNTheme themeForMode:self.themeMode interfaceStyle:[self currentInterfaceStyle]];
    self.lastInterfaceStyle = [self currentInterfaceStyle];

    self.panel.backgroundColor = self.theme.panelColor;
    self.panel.alpha = self.menuAlpha;
    self.panel.layer.borderColor = self.theme.borderColor.CGColor;
    self.panel.layer.borderWidth = self.theme.neonAppearance ? 0.8 : 1.0;
    self.panel.layer.shadowColor = self.theme.shadowColor.CGColor;
    self.panel.layer.shadowOpacity = self.theme.neonAppearance ? 0.75 : 0.42;
    self.panel.layer.shadowRadius = self.theme.neonAppearance ? 18.0 : 12.0;
    self.panel.layer.shadowOffset = CGSizeMake(0, 5);

    self.headerView.backgroundColor = self.theme.headerColor;
    self.sidebarView.backgroundColor = self.theme.sidebarColor;
    self.contentScroll.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = UIColor.clearColor;
    self.footerView.backgroundColor = self.theme.footerColor;

    NSMutableAttributedString *title = [[NSMutableAttributedString alloc] initWithString:@"ZONOE PATCH"
                                                                              attributes:@{NSForegroundColorAttributeName:self.theme.primaryTextColor,
                                                                                           NSFontAttributeName:[UIFont systemFontOfSize:17 weight:UIFontWeightHeavy]}];
    if (self.theme.neonAppearance) {
        [title addAttribute:NSForegroundColorAttributeName value:self.theme.accentColor range:NSMakeRange(6, 5)];
    }
    self.titleLabel.attributedText = title;
    self.subtitleLabel.textColor = self.theme.secondaryTextColor;
    self.readyLabel.textColor = self.theme.primaryTextColor;
    self.readyDot.backgroundColor = self.theme.mechanicalAppearance ? self.theme.accentColor : [UIColor colorWithRed:0.28 green:0.86 blue:0.45 alpha:1.0];
    self.footerLabel.textColor = self.theme.secondaryTextColor;

    NSArray<UIButton *> *headerButtons = @[self.themeButton, self.minimizeButton, self.closeButton];
    for (UIButton *button in headerButtons) {
        button.backgroundColor = self.theme.controlColor;
        button.tintColor = self.theme.primaryTextColor;
        [button setTitleColor:self.theme.primaryTextColor forState:UIControlStateNormal];
        button.layer.borderColor = self.theme.borderColor.CGColor;
        button.layer.borderWidth = 1.0;
        button.layer.cornerRadius = 10.0;
        button.layer.shadowOpacity = 0.0;
    }
    self.themeButton.tintColor = self.theme.accentColor;
    if (self.theme.neonAppearance || self.theme.mechanicalAppearance) {
        self.themeButton.layer.shadowColor = self.theme.accentColor.CGColor;
        self.themeButton.layer.shadowOpacity = 0.65;
        self.themeButton.layer.shadowRadius = 8.0;
        self.themeButton.layer.shadowOffset = CGSizeZero;
    }

    self.floatButton.backgroundColor = self.theme.floatColor;
    self.floatButton.layer.borderColor = self.theme.accentColor.CGColor;
    self.floatButton.layer.borderWidth = self.theme.neonAppearance ? 2.0 : 1.5;
    self.floatButton.layer.shadowColor = self.theme.shadowColor.CGColor;
    self.floatButton.layer.shadowOpacity = self.theme.neonAppearance ? 0.85 : 0.48;
    self.floatButton.layer.shadowRadius = self.theme.neonAppearance ? 11.0 : 7.0;
    self.floatButton.layer.shadowOffset = CGSizeZero;
    [self.floatButton setTitleColor:self.theme.lightAppearance ? UIColor.whiteColor : self.theme.primaryTextColor forState:UIControlStateNormal];

    [self updateSidebarSelection];
    [self rebuildThemePopover];
    [self installThemeDecorationLayers];
    [self renderCurrentPage];
}

- (UIView *)cardWithHeight:(CGFloat)height y:(CGFloat)y width:(CGFloat)width {
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(12, y, MAX(0, width - 24), height)];
    card.backgroundColor = self.theme.cardColor;
    card.layer.cornerRadius = 11.0;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = self.theme.borderColor.CGColor;
    if (self.theme.neonAppearance) {
        card.layer.shadowColor = self.theme.accent2Color.CGColor;
        card.layer.shadowOpacity = 0.12;
        card.layer.shadowRadius = 7.0;
        card.layer.shadowOffset = CGSizeZero;
    } else if (self.theme.mechanicalAppearance) {
        card.layer.shadowColor = self.theme.accentColor.CGColor;
        card.layer.shadowOpacity = 0.10;
        card.layer.shadowRadius = 4.0;
        card.layer.shadowOffset = CGSizeZero;
    }
    return card;
}

- (void)addSectionTitle:(NSString *)title subtitle:(NSString *)subtitle y:(CGFloat *)y width:(CGFloat)width {
    UILabel *t = [self labelWithText:title font:[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold] color:self.theme.primaryTextColor];
    t.frame = CGRectMake(12, *y, MAX(80, width - 24), 24);
    [self.contentView addSubview:t];
    *y += 26;
    if (subtitle.length) {
        UILabel *s = [self labelWithText:subtitle font:[UIFont systemFontOfSize:11.5] color:self.theme.secondaryTextColor];
        s.frame = CGRectMake(12, *y, MAX(80, width - 24), 34);
        [self.contentView addSubview:s];
        *y += 40;
    }
}

- (UISwitch *)addSwitchCardTitle:(NSString *)title subtitle:(NSString *)subtitle y:(CGFloat *)y width:(CGFloat)width selector:(SEL)selector on:(BOOL)on {
    UIView *card = [self cardWithHeight:72 y:*y width:width];
    UILabel *t = [self labelWithText:title font:[UIFont systemFontOfSize:14.5 weight:UIFontWeightMedium] color:self.theme.primaryTextColor];
    t.frame = CGRectMake(14, 11, MAX(80, card.bounds.size.width - 92), 22);
    [card addSubview:t];
    UILabel *s = [self labelWithText:subtitle font:[UIFont systemFontOfSize:10.5] color:self.theme.secondaryTextColor];
    s.frame = CGRectMake(14, 35, MAX(80, card.bounds.size.width - 92), 27);
    [card addSubview:s];
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
    sw.on = on;
    sw.onTintColor = self.theme.accentColor;
    sw.tintColor = self.theme.trackColor;
    CGSize swSize = sw.bounds.size;
    sw.center = CGPointMake(card.bounds.size.width - 14 - swSize.width * 0.5, card.bounds.size.height * 0.5);
    [sw addTarget:self action:selector forControlEvents:UIControlEventValueChanged];
    [card addSubview:sw];
    [self.contentView addSubview:card];
    *y += 82;
    return sw;
}

- (void)addCompositePatchCardTitle:(NSString *)title
                       startValue:(CGFloat)startValue
                      defaultValue:(CGFloat)defaultValue
                               min:(CGFloat)minValue
                               max:(CGFloat)maxValue
                                 y:(CGFloat *)y
                             width:(CGFloat)width {
    UIView *card = [self cardWithHeight:88 y:*y width:width];

    UILabel *t = [self labelWithText:title font:[UIFont systemFontOfSize:14.5 weight:UIFontWeightSemibold] color:self.theme.primaryTextColor];
    t.frame = CGRectMake(14, 10, MAX(80, card.bounds.size.width - 92), 24);
    [card addSubview:t];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
    sw.onTintColor = self.theme.accentColor;
    sw.tintColor = self.theme.trackColor;
    sw.on = NO;
    CGSize swSize = sw.bounds.size;
    sw.center = CGPointMake(card.bounds.size.width - 14 - swSize.width * 0.5, 22.0);
    [sw addTarget:self action:@selector(dummySwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:sw];

    UILabel *value = [self labelWithText:[NSString stringWithFormat:@"%.1f", startValue]
                                    font:[UIFont monospacedDigitSystemFontOfSize:12.5 weight:UIFontWeightSemibold]
                                   color:self.theme.primaryTextColor];
    value.tag = 6201;
    value.textAlignment = NSTextAlignmentCenter;
    value.backgroundColor = self.theme.controlColor;
    value.layer.cornerRadius = 7.0;
    value.layer.masksToBounds = YES;
    value.layer.borderWidth = 1.0;
    value.layer.borderColor = self.theme.borderColor.CGColor;
    value.frame = CGRectMake(14, 46, 64, 30);
    [card addSubview:value];

    CGFloat resetW = MIN(88.0, MAX(72.0, card.bounds.size.width * 0.22));
    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
    reset.frame = CGRectMake(card.bounds.size.width - 14 - resetW, 46, resetW, 30);
    reset.backgroundColor = self.theme.controlColor;
    reset.layer.cornerRadius = 7.0;
    reset.layer.borderWidth = 1.0;
    reset.layer.borderColor = self.theme.borderColor.CGColor;
    [reset setTitle:@"恢复默认" forState:UIControlStateNormal];
    [reset setTitleColor:self.theme.primaryTextColor forState:UIControlStateNormal];
    reset.titleLabel.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightMedium];
    reset.accessibilityValue = [NSString stringWithFormat:@"%.4f", defaultValue];
    [reset addTarget:self action:@selector(dummyCompositeReset:) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:reset];

    CGFloat sliderX = CGRectGetMaxX(value.frame) + 10.0;
    CGFloat sliderRight = CGRectGetMinX(reset.frame) - 10.0;
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(sliderX, 46, MAX(60.0, sliderRight - sliderX), 30)];
    slider.tag = 6202;
    slider.minimumValue = minValue;
    slider.maximumValue = maxValue;
    slider.value = startValue;
    slider.minimumTrackTintColor = self.theme.accentColor;
    slider.maximumTrackTintColor = self.theme.trackColor;
    slider.thumbTintColor = self.theme.lightAppearance ? UIColor.whiteColor : self.theme.primaryTextColor;
    [slider addTarget:self action:@selector(dummyCompositeSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:slider];

    [self.contentView addSubview:card];
    *y += 98;
}

- (void)addThemeSummaryCardAtY:(CGFloat *)y width:(CGFloat)width {
    UIView *card = [self cardWithHeight:82 y:*y width:width];
    UIImageView *icon = [[UIImageView alloc] initWithImage:ZNSymbol(@"paintpalette.fill", 18, UIImageSymbolWeightSemibold)];
    icon.tintColor = self.theme.accentColor;
    icon.backgroundColor = self.theme.controlColor;
    icon.contentMode = UIViewContentModeCenter;
    icon.layer.cornerRadius = 9.0;
    icon.frame = CGRectMake(14, 13, 50, 50);
    [card addSubview:icon];

    UILabel *label = [self labelWithText:@"当前主题" font:[UIFont systemFontOfSize:11 weight:UIFontWeightMedium] color:self.theme.secondaryTextColor];
    label.frame = CGRectMake(76, 10, card.bounds.size.width - 116, 18);
    [card addSubview:label];

    UILabel *name = [self labelWithText:[ZNTheme nameForMode:self.themeMode] font:[UIFont systemFontOfSize:16 weight:UIFontWeightBold] color:self.theme.primaryTextColor];
    name.frame = CGRectMake(76, 28, card.bounds.size.width - 116, 23);
    [card addSubview:name];

    UILabel *caption = [self labelWithText:@"共 6 种主题风格（包含 跟随系统）" font:[UIFont systemFontOfSize:10.5] color:self.theme.secondaryTextColor];
    caption.frame = CGRectMake(76, 51, card.bounds.size.width - 116, 18);
    [card addSubview:caption];

    UIImageView *chevron = [[UIImageView alloc] initWithImage:ZNSymbol(@"chevron.right", 12, UIImageSymbolWeightSemibold)];
    chevron.tintColor = self.theme.secondaryTextColor;
    chevron.frame = CGRectMake(card.bounds.size.width - 28, 33, 10, 16);
    [card addSubview:chevron];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(themeSummaryTapped:)];
    [card addGestureRecognizer:tap];
    [self.contentView addSubview:card];
    *y += 92;
}

- (void)addMenuTransparencyCardAtY:(CGFloat *)y width:(CGFloat)width {
    UIView *card = [self cardWithHeight:72 y:*y width:width];
    UILabel *t = [self labelWithText:@"菜单透明度" font:[UIFont systemFontOfSize:14.5 weight:UIFontWeightMedium] color:self.theme.primaryTextColor];
    t.frame = CGRectMake(14, 10, 96, 22);
    [card addSubview:t];

    UILabel *value = [self labelWithText:[NSString stringWithFormat:@"%.0f%%", self.menuAlpha * 100.0]
                                    font:[UIFont monospacedDigitSystemFontOfSize:11.5 weight:UIFontWeightSemibold]
                                   color:self.theme.primaryTextColor];
    value.tag = 6401;
    value.textAlignment = NSTextAlignmentRight;
    value.frame = CGRectMake(card.bounds.size.width - 55, 10, 41, 22);
    [card addSubview:value];

    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(14, 36, card.bounds.size.width - 28, 28)];
    slider.minimumValue = 0.55f;
    slider.maximumValue = 1.0f;
    slider.value = self.menuAlpha;
    slider.minimumTrackTintColor = self.theme.accentColor;
    slider.maximumTrackTintColor = self.theme.trackColor;
    slider.thumbTintColor = self.theme.lightAppearance ? UIColor.whiteColor : self.theme.primaryTextColor;
    [slider addTarget:self action:@selector(menuAlphaChanged:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:slider];

    [self.contentView addSubview:card];
    *y += 82;
}

- (void)addActionCardTitle:(NSString *)title subtitle:(NSString *)subtitle buttonTitle:(NSString *)buttonTitle y:(CGFloat *)y width:(CGFloat)width selector:(SEL)selector {
    UIView *card = [self cardWithHeight:78 y:*y width:width];
    UILabel *t = [self labelWithText:title font:[UIFont systemFontOfSize:14.5 weight:UIFontWeightMedium] color:self.theme.primaryTextColor];
    t.frame = CGRectMake(14, 10, MAX(80, card.bounds.size.width - 146), 22);
    [card addSubview:t];
    UILabel *s = [self labelWithText:subtitle font:[UIFont systemFontOfSize:10.5] color:self.theme.secondaryTextColor];
    s.frame = CGRectMake(14, 34, MAX(80, card.bounds.size.width - 146), 30);
    [card addSubview:s];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(card.bounds.size.width - 128, 22, 114, 36);
    button.backgroundColor = self.theme.controlColor;
    button.layer.cornerRadius = 8.0;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = self.theme.borderColor.CGColor;
    [button setTitle:buttonTitle forState:UIControlStateNormal];
    [button setTitleColor:self.theme.primaryTextColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightMedium];
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:button];

    [self.contentView addSubview:card];
    *y += 88;
}

- (void)renderCurrentPage {
    if (!self.contentView) return;
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    if (width <= 0) return;
    CGFloat y = 14.0;
    NSString *category = self.categories[self.selectedCategory];

    if ([category isEqualToString:@"首页"]) {
        [self addSectionTitle:@"Runtime 状态" subtitle:@"Zonoe Runtime Patch Menu v0.2 UI · 当前仍为界面/交互测试基线。" y:&y width:width];
        UIView *card = [self cardWithHeight:176 y:y width:width];
        NSArray *rows = @[
            @[@"状态", @"Ready · UI ONLY"],
            @[@"版本", kZNMenuVersion],
            @[@"主题", [ZNTheme nameForMode:self.themeMode]],
            @[@"设备", [NSString stringWithFormat:@"iOS %@ · %@", UIDevice.currentDevice.systemVersion, ZNOrientationText(self.hostWindow.bounds.size)]],
            @[@"Patch", @"0 Enabled · 0 Unsupported"]
        ];
        CGFloat rowY = 10;
        for (NSArray *row in rows) {
            UILabel *l = [self labelWithText:row[0] font:[UIFont systemFontOfSize:11.5 weight:UIFontWeightMedium] color:self.theme.secondaryTextColor];
            l.frame = CGRectMake(14, rowY, 68, 24);
            [card addSubview:l];
            UILabel *r = [self labelWithText:row[1] font:[UIFont monospacedSystemFontOfSize:10.7 weight:UIFontWeightRegular] color:self.theme.primaryTextColor];
            r.textAlignment = NSTextAlignmentRight;
            r.frame = CGRectMake(86, rowY, card.bounds.size.width - 100, 24);
            [card addSubview:r];
            rowY += 31;
        }
        [self.contentView addSubview:card];
        y += 186;
    } else if ([category isEqualToString:@"玩家"]) {
        [self addSectionTitle:@"玩家" subtitle:@"开关型功能占位，后续直接绑定 PatchManager 状态。" y:&y width:width];
        [self addSwitchCardTitle:@"无敌（UI 测试）" subtitle:@"当前仅改变菜单状态，不修改游戏。" y:&y width:width selector:@selector(dummySwitchChanged:) on:NO];
        [self addSwitchCardTitle:@"无限资源（UI 测试）" subtitle:@"后续接真实 Runtime Patch。" y:&y width:width selector:@selector(dummySwitchChanged:) on:NO];
    } else if ([category isEqualToString:@"战斗"]) {
        [self addSectionTitle:@"战斗" subtitle:@"数值类功能统一使用：标题 + 开关 / 数值框 + Slider + 恢复默认。" y:&y width:width];
        [self addCompositePatchCardTitle:@"伤害倍率" startValue:5.0 defaultValue:1.0 min:1.0 max:20.0 y:&y width:width];
        [self addCompositePatchCardTitle:@"攻击速度" startValue:2.0 defaultValue:1.0 min:1.0 max:5.0 y:&y width:width];
    } else if ([category isEqualToString:@"移动"]) {
        [self addSectionTitle:@"移动" subtitle:@"按你确认的组合布局制作，不再把 Slider 单独拆成一个功能块。" y:&y width:width];
        [self addCompositePatchCardTitle:@"移速修改" startValue:2.5 defaultValue:1.0 min:1.0 max:5.0 y:&y width:width];
        [self addCompositePatchCardTitle:@"跳跃高度" startValue:2.0 defaultValue:1.0 min:1.0 max:5.0 y:&y width:width];
    } else if ([category isEqualToString:@"其他"]) {
        [self addSectionTitle:@"其他" subtitle:@"一次性动作与工具入口。" y:&y width:width];
        [self addActionCardTitle:@"一次性动作（UI 测试）" subtitle:@"点击仅输出日志。" buttonTitle:@"执行测试  ›" y:&y width:width selector:@selector(dummyButtonTapped:)];
    } else {
        [self addSectionTitle:@"界面设置" subtitle:@"主题与基础显示设置" y:&y width:width];
        [self addThemeSummaryCardAtY:&y width:width];
        [self addSwitchCardTitle:@"悬浮球自动贴边" subtitle:@"拖动结束后自动吸附到最近的左右边缘" y:&y width:width selector:@selector(autoSnapChanged:) on:self.autoSnap];
        [self addSwitchCardTitle:@"记住界面位置" subtitle:@"保存悬浮球与菜单面板最后位置" y:&y width:width selector:@selector(rememberPositionChanged:) on:self.rememberPosition];
        [self addMenuTransparencyCardAtY:&y width:width];
        [self addActionCardTitle:@"开发者测试" subtitle:@"用于功能调试与验证" buttonTitle:@"进入测试页  ›" y:&y width:width selector:@selector(dummyButtonTapped:)];
    }

    y += 14;
    CGRect frame = self.contentView.frame;
    frame.size.height = MAX(CGRectGetHeight(self.contentScroll.bounds), y);
    self.contentView.frame = frame;
    self.contentScroll.contentSize = CGSizeMake(CGRectGetWidth(self.contentScroll.bounds), frame.size.height);
}

- (void)updateSidebarSelection {
    for (NSInteger i = 0; i < self.sidebarButtons.count; i++) {
        UIButton *button = self.sidebarButtons[i];
        BOOL selected = (i == self.selectedCategory);
        button.backgroundColor = selected ? self.theme.selectedColor : UIColor.clearColor;
        [button setTitleColor:selected ? self.theme.primaryTextColor : self.theme.secondaryTextColor forState:UIControlStateNormal];
        button.tintColor = selected ? self.theme.accentColor : self.theme.secondaryTextColor;
        button.layer.borderWidth = selected ? 1.0 : 0.0;
        button.layer.borderColor = selected ? [self.theme.accentColor colorWithAlphaComponent:0.38].CGColor : UIColor.clearColor.CGColor;
        button.layer.shadowOpacity = 0.0;
        UIView *accent = [button viewWithTag:3900];
        accent.backgroundColor = self.theme.accentColor;
        accent.hidden = !selected;
        if (selected && (self.theme.neonAppearance || self.theme.mechanicalAppearance)) {
            button.layer.shadowColor = self.theme.accentColor.CGColor;
            button.layer.shadowOpacity = self.theme.neonAppearance ? 0.34 : 0.20;
            button.layer.shadowRadius = self.theme.neonAppearance ? 8.0 : 5.0;
            button.layer.shadowOffset = CGSizeZero;
        }
    }
}

- (void)layoutSidebarButtons {
    CGFloat width = CGRectGetWidth(self.sidebarView.bounds);
    CGFloat y = 10.0;
    CGFloat buttonH = 40.0;
    for (UIButton *button in self.sidebarButtons) {
        button.frame = CGRectMake(7, y, MAX(0, width - 14), buttonH);
        UIView *accent = [button viewWithTag:3900];
        accent.frame = CGRectMake(0, 6, 3, buttonH - 12);
        y += buttonH + 5;
    }
}

- (void)layoutThemePopover {
    if (!self.themePopover || !self.panel) return;
    CGFloat width = 210.0;
    CGFloat x = CGRectGetWidth(self.panel.bounds) - width - 54.0;
    x = MAX(8.0, x);
    self.themePopover.frame = CGRectMake(x, 48.0, width, 246.0);
    CGFloat rowY = 8.0;
    for (UIView *row in self.themePopover.subviews) {
        row.frame = CGRectMake(7, rowY, width - 14, 36.0);
        UILabel *dot = [row viewWithTag:7101];
        dot.frame = CGRectMake(7, 9, 18, 18);
        UILabel *check = [row viewWithTag:7102];
        check.frame = CGRectMake(row.bounds.size.width - 28, 7, 20, 22);
        UIButton *button = [row viewWithTag:7103];
        button.frame = row.bounds;
        button.contentEdgeInsets = UIEdgeInsetsMake(0, 32, 0, 30);
        rowY += 38.0;
    }
}

- (void)rebuildThemePopover {
    if (!self.themePopover) return;
    [self.themePopover.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    self.themePopover.backgroundColor = self.theme.popoverColor;
    self.themePopover.layer.cornerRadius = 12.0;
    self.themePopover.layer.borderWidth = 1.0;
    self.themePopover.layer.borderColor = self.theme.borderColor.CGColor;
    self.themePopover.layer.shadowColor = self.theme.shadowColor.CGColor;
    self.themePopover.layer.shadowOpacity = 0.48;
    self.themePopover.layer.shadowRadius = 12.0;
    self.themePopover.layer.shadowOffset = CGSizeMake(0, 5);

    NSArray<NSString *> *names = [ZNTheme themeNames];
    for (NSInteger i = 0; i < names.count; i++) {
        BOOL selected = (i == self.themeMode);
        UIView *row = [[UIView alloc] initWithFrame:CGRectZero];
        row.backgroundColor = selected ? self.theme.selectedColor : UIColor.clearColor;
        row.layer.cornerRadius = 8.0;
        if (selected) {
            row.layer.borderWidth = 1.0;
            row.layer.borderColor = [self.theme.accentColor colorWithAlphaComponent:0.42].CGColor;
        }

        UILabel *dot = [[UILabel alloc] initWithFrame:CGRectZero];
        dot.tag = 7101;
        dot.backgroundColor = [ZNTheme indicatorColorForMode:(ZNThemeMode)i];
        dot.layer.cornerRadius = 9.0;
        dot.layer.masksToBounds = YES;
        [row addSubview:dot];

        UILabel *check = [self labelWithText:selected ? @"✓" : @"" font:[UIFont systemFontOfSize:15 weight:UIFontWeightBold] color:self.theme.accentColor];
        check.tag = 7102;
        check.textAlignment = NSTextAlignmentCenter;
        [row addSubview:check];

        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tag = 7103;
        button.accessibilityIdentifier = [NSString stringWithFormat:@"%ld", (long)i];
        [button setTitle:names[i] forState:UIControlStateNormal];
        [button setTitleColor:self.theme.primaryTextColor forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:12.5 weight:selected ? UIFontWeightSemibold : UIFontWeightRegular];
        button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        [button addTarget:self action:@selector(themeRowTapped:) forControlEvents:UIControlEventTouchUpInside];
        [row addSubview:button];
        [self.themePopover addSubview:row];
    }
    [self layoutThemePopover];
}

- (void)layoutPanelContents {
    CGFloat panelW = CGRectGetWidth(self.panel.bounds);
    CGFloat panelH = CGRectGetHeight(self.panel.bounds);
    CGFloat sidebarW = [self sidebarWidthForPanelWidth:panelW];

    self.headerView.frame = CGRectMake(0, 0, panelW, kZNHeaderHeight);
    self.titleLabel.frame = CGRectMake(15, 6, MAX(120, panelW - 250), 22);
    self.subtitleLabel.frame = CGRectMake(15, 28, MAX(120, panelW - 250), 17);

    self.readyDot.frame = CGRectMake(panelW - 244, 21, 9, 9);
    self.readyLabel.frame = CGRectMake(panelW - 230, 10, 48, 30);
    self.themeButton.frame = CGRectMake(panelW - 178, 7, 42, 38);
    self.minimizeButton.frame = CGRectMake(panelW - 130, 7, 42, 38);
    self.closeButton.frame = CGRectMake(panelW - 82, 7, 42, 38);

    CGFloat bodyH = MAX(0, panelH - kZNHeaderHeight - kZNFooterHeight);
    self.sidebarView.frame = CGRectMake(0, kZNHeaderHeight, sidebarW, bodyH);
    self.contentScroll.frame = CGRectMake(sidebarW, kZNHeaderHeight, MAX(0, panelW - sidebarW), bodyH);
    self.contentView.frame = CGRectMake(0, 0, CGRectGetWidth(self.contentScroll.bounds), MAX(bodyH, self.contentView.frame.size.height));
    self.footerView.frame = CGRectMake(0, panelH - kZNFooterHeight, panelW, kZNFooterHeight);
    self.footerLabel.frame = CGRectMake(12, 0, panelW - 24, kZNFooterHeight);

    [self layoutSidebarButtons];
    [self layoutThemePopover];
    [self installThemeDecorationLayers];
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

    [self layoutPanelContents];
    self.lastHostBounds = bounds;
    self.lastSafeInsets = safe;
}

- (void)makeUI:(UIWindow *)window {
    if (self.uiReady || !window) return;
    self.hostWindow = window;
    self.theme = [ZNTheme themeForMode:self.themeMode interfaceStyle:[self currentInterfaceStyle]];

    UIButton *floatButton = [UIButton buttonWithType:UIButtonTypeCustom];
    floatButton.bounds = CGRectMake(0, 0, kZNFloatSize, kZNFloatSize);
    floatButton.layer.cornerRadius = kZNFloatSize * 0.5;
    [floatButton setTitle:@"ZN" forState:UIControlStateNormal];
    floatButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [floatButton addTarget:self action:@selector(togglePanel:) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *buttonPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panButton:)];
    buttonPan.cancelsTouchesInView = NO;
    [floatButton addGestureRecognizer:buttonPan];
    self.floatButton = floatButton;

    UIView *panel = [[UIView alloc] initWithFrame:CGRectZero];
    panel.layer.cornerRadius = 16.0;
    panel.layer.masksToBounds = NO;
    self.panel = panel;

    UIView *header = [[UIView alloc] initWithFrame:CGRectZero];
    header.layer.cornerRadius = 16.0;
    header.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    self.headerView = header;
    [panel addSubview:header];

    UIPanGestureRecognizer *panelPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panPanel:)];
    panelPan.cancelsTouchesInView = NO;
    [header addGestureRecognizer:panelPan];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel = title;
    [header addSubview:title];

    UILabel *subtitle = [self labelWithText:@"Runtime Patch Menu" font:[UIFont systemFontOfSize:10.5 weight:UIFontWeightRegular] color:self.theme.secondaryTextColor];
    self.subtitleLabel = subtitle;
    [header addSubview:subtitle];

    UIView *readyDot = [[UIView alloc] initWithFrame:CGRectZero];
    readyDot.layer.cornerRadius = 4.5;
    self.readyDot = readyDot;
    [header addSubview:readyDot];

    UILabel *ready = [self labelWithText:@"Ready" font:[UIFont systemFontOfSize:11.5 weight:UIFontWeightMedium] color:self.theme.primaryTextColor];
    self.readyLabel = ready;
    [header addSubview:ready];

    UIButton *themeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [themeButton setImage:ZNSymbol(@"paintpalette.fill", 15, UIImageSymbolWeightSemibold) forState:UIControlStateNormal];
    [themeButton addTarget:self action:@selector(themeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    self.themeButton = themeButton;
    [header addSubview:themeButton];

    UIButton *minimize = [UIButton buttonWithType:UIButtonTypeSystem];
    [minimize setTitle:@"—" forState:UIControlStateNormal];
    minimize.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [minimize addTarget:self action:@selector(minimizeTapped:) forControlEvents:UIControlEventTouchUpInside];
    self.minimizeButton = minimize;
    [header addSubview:minimize];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"×" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightLight];
    [close addTarget:self action:@selector(closeTapped:) forControlEvents:UIControlEventTouchUpInside];
    self.closeButton = close;
    [header addSubview:close];

    UIView *sidebar = [[UIView alloc] initWithFrame:CGRectZero];
    self.sidebarView = sidebar;
    [panel addSubview:sidebar];

    for (NSInteger i = 0; i < self.categories.count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.tag = 3000 + i;
        button.layer.cornerRadius = 9.0;
        button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        button.contentEdgeInsets = UIEdgeInsetsMake(0, 11, 0, 6);
        [button setTitle:[NSString stringWithFormat:@"  %@", self.categories[i]] forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        [button setImage:ZNSymbol(self.categorySymbols[i], 14, UIImageSymbolWeightSemibold) forState:UIControlStateNormal];
        [button addTarget:self action:@selector(sidebarTapped:) forControlEvents:UIControlEventTouchUpInside];
        UIView *accent = [[UIView alloc] initWithFrame:CGRectZero];
        accent.tag = 3900;
        accent.layer.cornerRadius = 1.5;
        accent.userInteractionEnabled = NO;
        [button addSubview:accent];
        [sidebar addSubview:button];
        [self.sidebarButtons addObject:button];
    }

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    scroll.showsVerticalScrollIndicator = YES;
    scroll.alwaysBounceVertical = NO;
    self.contentScroll = scroll;
    [panel addSubview:scroll];

    UIView *content = [[UIView alloc] initWithFrame:CGRectZero];
    self.contentView = content;
    [scroll addSubview:content];

    UIView *footer = [[UIView alloc] initWithFrame:CGRectZero];
    self.footerView = footer;
    [panel addSubview:footer];

    UILabel *footerLabel = [self labelWithText:@"" font:[UIFont monospacedSystemFontOfSize:9.5 weight:UIFontWeightRegular] color:self.theme.secondaryTextColor];
    self.footerLabel = footerLabel;
    [footer addSubview:footerLabel];

    UIView *popover = [[UIView alloc] initWithFrame:CGRectZero];
    popover.hidden = YES;
    self.themePopover = popover;
    [panel addSubview:popover];

    panel.hidden = YES;
    [window addSubview:floatButton];
    [window addSubview:panel];

    self.uiReady = YES;
    [self layoutForWindow:window initial:YES];
    [self applyThemeToChrome];
    self.footerLabel.text = [NSString stringWithFormat:@"UnityFramework    Runtime 0.2    iOS %@", UIDevice.currentDevice.systemVersion];
    NSLog(@"[ZonoePatch v0.2.1] UI ready theme=%@", [ZNTheme nameForMode:self.themeMode]);
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
    [self applyThemeToChrome];
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

    UIUserInterfaceStyle style = [self currentInterfaceStyle];
    if (self.themeMode == ZNThemeModeSystem && style != self.lastInterfaceStyle) {
        [self applyThemeToChrome];
    }

    [window bringSubviewToFront:self.panel];
    [window bringSubviewToFront:self.floatButton];
    [self.panel bringSubviewToFront:self.themePopover];
}

- (void)start {
    if (self.timer) {
        self.floatButton.hidden = NO;
        return;
    }
    [self tick:nil];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    NSLog(@"[ZonoePatch v0.2.1] bootstrap version=%@", kZNMenuVersion);
}

- (void)show {
    if (!self.uiReady) {
        [self tick:nil];
        if (!self.uiReady) return;
    }
    self.floatButton.hidden = NO;
    self.panel.hidden = NO;
    [self.hostWindow bringSubviewToFront:self.panel];
    [self.hostWindow bringSubviewToFront:self.floatButton];
}

- (void)hide {
    self.themePopover.hidden = YES;
    self.panel.hidden = YES;
}

- (BOOL)isVisible {
    return self.uiReady && !self.panel.hidden;
}

- (void)togglePanel:(id)sender {
    (void)sender;
    self.panel.hidden = !self.panel.hidden;
    self.themePopover.hidden = YES;
    if (!self.panel.hidden) {
        [self.hostWindow bringSubviewToFront:self.panel];
        [self.hostWindow bringSubviewToFront:self.floatButton];
    }
}

- (void)minimizeTapped:(id)sender {
    (void)sender;
    [self hide];
}

- (void)closeTapped:(id)sender {
    (void)sender;
    self.themePopover.hidden = YES;
    self.panel.hidden = YES;
    self.floatButton.hidden = YES;
}

- (void)themeButtonTapped:(id)sender {
    (void)sender;
    self.themePopover.hidden = !self.themePopover.hidden;
    if (!self.themePopover.hidden) {
        [self rebuildThemePopover];
        [self.panel bringSubviewToFront:self.themePopover];
    }
}

- (void)themeSummaryTapped:(UITapGestureRecognizer *)gesture {
    (void)gesture;
    self.themePopover.hidden = NO;
    [self rebuildThemePopover];
    [self.panel bringSubviewToFront:self.themePopover];
}

- (void)themeRowTapped:(UIButton *)sender {
    NSInteger index = sender.accessibilityIdentifier.integerValue;
    if (index < ZNThemeModeSystem || index > ZNThemeModeMatcha) return;
    self.themeMode = (ZNThemeMode)index;
    [[NSUserDefaults standardUserDefaults] setInteger:self.themeMode forKey:kZNThemeModeKey];
    self.themePopover.hidden = YES;
    [self applyThemeToChrome];
    NSLog(@"[ZonoePatch v0.2.1] theme=%@", [ZNTheme nameForMode:self.themeMode]);
}

- (void)sidebarTapped:(UIButton *)sender {
    NSInteger index = sender.tag - 3000;
    if (index < 0 || index >= self.categories.count) return;
    self.selectedCategory = index;
    self.themePopover.hidden = YES;
    [self updateSidebarSelection];
    self.contentScroll.contentOffset = CGPointZero;
    [self renderCurrentPage];
}

- (void)dummySwitchChanged:(UISwitch *)sender {
    NSLog(@"[ZonoePatch v0.2.1] dummy switch=%@", sender.isOn ? @"ON" : @"OFF");
}

- (void)dummyCompositeSliderChanged:(UISlider *)slider {
    UIView *card = slider.superview;
    UILabel *value = [card viewWithTag:6201];
    value.text = [NSString stringWithFormat:@"%.1f", slider.value];
}

- (void)dummyCompositeReset:(UIButton *)sender {
    UIView *card = sender.superview;
    UISlider *slider = [card viewWithTag:6202];
    CGFloat defaultValue = sender.accessibilityValue.doubleValue;
    slider.value = defaultValue;
    [self dummyCompositeSliderChanged:slider];
    NSLog(@"[ZonoePatch v0.2.1] composite reset=%.2f", defaultValue);
}

- (void)dummyButtonTapped:(UIButton *)sender {
    (void)sender;
    NSLog(@"[ZonoePatch v0.2.1] dummy action tapped");
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

- (void)menuAlphaChanged:(UISlider *)slider {
    self.menuAlpha = ZNClamp(slider.value, 0.55, 1.0);
    self.panel.alpha = self.menuAlpha;
    [[NSUserDefaults standardUserDefaults] setDouble:self.menuAlpha forKey:kZNMenuAlphaKey];
    UILabel *value = [slider.superview viewWithTag:6401];
    value.text = [NSString stringWithFormat:@"%.0f%%", self.menuAlpha * 100.0];
}

- (void)snapFloatButtonAnimated:(BOOL)animated {
    UIWindow *window = self.hostWindow;
    if (!window) return;
    CGRect bounds = window.bounds;
    UIEdgeInsets safe = window.safeAreaInsets;
    CGFloat half = kZNFloatSize * 0.5;
    CGFloat leftX = safe.left + kZNMargin + half;
    CGFloat rightX = CGRectGetWidth(bounds) - safe.right - kZNMargin - half;
    CGPoint center = [self clampedButtonCenter:self.floatButton.center inWindow:window];
    center.x = center.x < CGRectGetMidX(bounds) ? leftX : rightX;
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
    return "0.2.1-ui";
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
        NSLog(@"[ZonoePatch v0.2.1] dylib loaded");
        ZonoePatchStart();
    }
}
