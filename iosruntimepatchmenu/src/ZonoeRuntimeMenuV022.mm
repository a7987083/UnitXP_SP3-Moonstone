#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <stdint.h>

#import "ZNTheme.h"

static NSString * const kZNMenuVersion = @"0.2.2-ui";
static NSString * const kZNFloatPositionKey = @"ZonoePatch.FloatCenter";
static NSString * const kZNPanelPositionKey = @"ZonoePatch.PanelCenter";
static NSString * const kZNThemeModeKey = @"ZonoePatch.ThemeMode";
static NSString * const kZNCompactModeKey = @"ZonoePatch.CompactMode";
static NSString * const kZNMenuAlphaKey = @"ZonoePatch.MenuAlpha";
static const CGFloat kZNFloatSize = 52.0;
static const CGFloat kZNMargin = 10.0;
static const CGFloat kZNHeaderH = 52.0;
static const CGFloat kZNFooterH = 28.0;

static CGFloat ZNClamp(CGFloat v, CGFloat lo, CGFloat hi) {
    if (hi < lo) return lo;
    return MIN(MAX(v, lo), hi);
}

static UIImage *ZNSymbol(NSString *name, CGFloat size, UIImageSymbolWeight weight) {
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:size weight:weight];
        return [[UIImage systemImageNamed:name withConfiguration:cfg] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    return nil;
}

@interface ZNRuntimeMenuControllerV022 : NSObject
@property(nonatomic,strong) UIButton *floatButton;
@property(nonatomic,strong) UIView *panel;
@property(nonatomic,strong) UIView *headerView;
@property(nonatomic,strong) UILabel *titleLabel;
@property(nonatomic,strong) UILabel *subtitleLabel;
@property(nonatomic,strong) UIView *readyDot;
@property(nonatomic,strong) UILabel *readyLabel;
@property(nonatomic,strong) UIButton *themeButton;
@property(nonatomic,strong) UIButton *modeButton;
@property(nonatomic,strong) UIButton *closeButton;
@property(nonatomic,strong) UIView *sidebarView;
@property(nonatomic,strong) UIScrollView *contentScroll;
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIView *footerView;
@property(nonatomic,strong) UILabel *footerLabel;
@property(nonatomic,strong) UIView *themePopover;
@property(nonatomic,strong) NSMutableArray<UIButton *> *sidebarButtons;
@property(nonatomic,copy) NSArray<NSString *> *categories;
@property(nonatomic,copy) NSArray<NSString *> *categorySymbols;
@property(nonatomic,assign) NSInteger selectedCategory;
@property(nonatomic,weak) UIWindow *hostWindow;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,assign) CGRect lastBounds;
@property(nonatomic,assign) UIEdgeInsets lastInsets;
@property(nonatomic,assign) BOOL uiReady;
@property(nonatomic,assign) BOOL compactMode;
@property(nonatomic,assign) ZNThemeMode themeMode;
@property(nonatomic,strong) ZNTheme *theme;
@property(nonatomic,assign) CGFloat menuAlpha;
@end

@implementation ZNRuntimeMenuControllerV022

+ (instancetype)shared {
    static ZNRuntimeMenuControllerV022 *s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ s = [ZNRuntimeMenuControllerV022 new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _categories = @[@"首页", @"玩家", @"战斗", @"移动", @"其他", @"设置"];
    _categorySymbols = @[@"house.fill", @"person.fill", @"bolt.fill", @"location.north.fill", @"square.grid.2x2.fill", @"gearshape.fill"];
    _sidebarButtons = [NSMutableArray array];
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    if ([ud objectForKey:kZNThemeModeKey] == nil) [ud setInteger:ZNThemeModeObsidian forKey:kZNThemeModeKey];
    if ([ud objectForKey:kZNCompactModeKey] == nil) [ud setBool:NO forKey:kZNCompactModeKey];
    if ([ud objectForKey:kZNMenuAlphaKey] == nil) [ud setDouble:0.88 forKey:kZNMenuAlphaKey];
    _themeMode = (ZNThemeMode)[ud integerForKey:kZNThemeModeKey];
    if (_themeMode < ZNThemeModeSystem || _themeMode > ZNThemeModeMatcha) _themeMode = ZNThemeModeObsidian;
    _compactMode = [ud boolForKey:kZNCompactModeKey];
    _menuAlpha = ZNClamp([ud doubleForKey:kZNMenuAlphaKey], 0.55, 1.0);
    _theme = [ZNTheme themeForMode:_themeMode interfaceStyle:UIUserInterfaceStyleDark];
    return self;
}

- (UIWindow *)currentWindow {
    UIApplication *app = UIApplication.sharedApplication;
    if (@available(iOS 13.0, *)) {
        UIWindow *fallback = nil;
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            if (scene.activationState != UISceneActivationStateForegroundActive && scene.activationState != UISceneActivationStateForegroundInactive) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.hidden || w.alpha <= 0.01) continue;
                if (w.isKeyWindow) return w;
                if (!fallback && w.windowLevel == UIWindowLevelNormal && w.rootViewController) fallback = w;
            }
        }
        if (fallback) return fallback;
    }
    if (app.keyWindow && !app.keyWindow.hidden) return app.keyWindow;
    for (UIWindow *w in app.windows.reverseObjectEnumerator) {
        if (!w.hidden && w.windowLevel == UIWindowLevelNormal && w.rootViewController) return w;
    }
    return app.windows.lastObject;
}

- (UIUserInterfaceStyle)interfaceStyle {
    if (@available(iOS 13.0, *)) {
        UIUserInterfaceStyle s = self.hostWindow.traitCollection.userInterfaceStyle;
        return s == UIUserInterfaceStyleLight ? UIUserInterfaceStyleLight : UIUserInterfaceStyleDark;
    }
    return UIUserInterfaceStyleDark;
}

- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color {
    UILabel *l = [UILabel new];
    l.text = text;
    l.font = [UIFont systemFontOfSize:size weight:weight];
    l.textColor = color;
    l.numberOfLines = 1;
    return l;
}

- (CGPoint)clampFloat:(CGPoint)c window:(UIWindow *)w {
    UIEdgeInsets s = w.safeAreaInsets;
    CGFloat h = kZNFloatSize * 0.5;
    return CGPointMake(ZNClamp(c.x, s.left + kZNMargin + h, CGRectGetWidth(w.bounds) - s.right - kZNMargin - h),
                       ZNClamp(c.y, s.top + kZNMargin + h, CGRectGetHeight(w.bounds) - s.bottom - kZNMargin - h));
}

- (CGPoint)clampPanel:(CGPoint)c window:(UIWindow *)w {
    UIEdgeInsets s = w.safeAreaInsets;
    CGSize z = self.panel.bounds.size;
    return CGPointMake(ZNClamp(c.x, s.left + kZNMargin + z.width * 0.5, CGRectGetWidth(w.bounds) - s.right - kZNMargin - z.width * 0.5),
                       ZNClamp(c.y, s.top + kZNMargin + z.height * 0.5, CGRectGetHeight(w.bounds) - s.bottom - kZNMargin - z.height * 0.5));
}

- (CGSize)fullSizeForWindow:(UIWindow *)w {
    UIEdgeInsets s = w.safeAreaInsets;
    CGFloat aw = CGRectGetWidth(w.bounds) - s.left - s.right;
    CGFloat ah = CGRectGetHeight(w.bounds) - s.top - s.bottom;
    BOOL landscape = aw >= ah;
    CGFloat pw = landscape ? MIN(620.0, MAX(430.0, aw * 0.72)) : MIN(520.0, MAX(310.0, aw - 28.0));
    CGFloat ph = landscape ? MIN(400.0, MAX(310.0, ah * 0.82)) : MIN(560.0, MAX(380.0, ah * 0.70));
    return CGSizeMake(MIN(pw, aw - 20.0), MIN(ph, ah - 20.0));
}

- (CGSize)compactSizeForWindow:(UIWindow *)w {
    UIEdgeInsets s = w.safeAreaInsets;
    CGFloat aw = CGRectGetWidth(w.bounds) - s.left - s.right;
    CGFloat ah = CGRectGetHeight(w.bounds) - s.top - s.bottom;
    CGFloat pw = MIN(330.0, MAX(286.0, aw - 20.0));
    CGFloat ph = MIN(286.0, MAX(236.0, ah - 20.0));
    return CGSizeMake(pw, ph);
}

- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact {
    CGFloat inset = compact ? 7.0 : 12.0;
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(inset, y, MAX(0, w - inset * 2.0), h)];
    v.backgroundColor = self.theme.cardColor;
    v.layer.cornerRadius = compact ? 8.0 : 11.0;
    v.layer.borderWidth = 1.0;
    v.layer.borderColor = self.theme.borderColor.CGColor;
    if (self.theme.neonAppearance) {
        v.layer.shadowColor = self.theme.accent2Color.CGColor;
        v.layer.shadowOpacity = compact ? 0.16 : 0.12;
        v.layer.shadowRadius = compact ? 5.0 : 7.0;
        v.layer.shadowOffset = CGSizeZero;
    }
    return v;
}

- (UISwitch *)switchForCard:(UIView *)card on:(BOOL)on compact:(BOOL)compact {
    UISwitch *sw = [UISwitch new];
    sw.on = on;
    sw.onTintColor = self.theme.accentColor;
    sw.tintColor = self.theme.trackColor;
    sw.transform = compact ? CGAffineTransformMakeScale(0.72, 0.72) : CGAffineTransformIdentity;
    [sw addTarget:self action:@selector(dummySwitch:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:sw];
    return sw;
}

- (void)addFullComposite:(NSString *)name value:(CGFloat)value min:(CGFloat)min max:(CGFloat)max y:(CGFloat *)y width:(CGFloat)width {
    UIView *card = [self cardAtY:*y height:82 width:width compact:NO];
    UILabel *t = [self label:name size:14.0 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    t.frame = CGRectMake(14, 9, 92, 22);
    [card addSubview:t];

    UILabel *val = [self label:[NSString stringWithFormat:@"[ %.1fx ]", value] size:12.0 weight:UIFontWeightSemibold color:self.theme.accentColor];
    val.tag = 6201;
    val.frame = CGRectMake(105, 9, 74, 22);
    [card addSubview:val];

    UISwitch *sw = [self switchForCard:card on:NO compact:NO];
    CGSize ss = sw.bounds.size;
    sw.center = CGPointMake(card.bounds.size.width - 14 - ss.width * 0.5, 20);

    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(14, 43, card.bounds.size.width - 28, 26)];
    slider.tag = 6202;
    slider.minimumValue = min;
    slider.maximumValue = max;
    slider.value = value;
    slider.minimumTrackTintColor = self.theme.accentColor;
    slider.maximumTrackTintColor = self.theme.trackColor;
    slider.thumbTintColor = UIColor.whiteColor;
    [slider addTarget:self action:@selector(compositeSlider:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:slider];
    [self.contentView addSubview:card];
    *y += 92;
}

- (void)addFullSwitch:(NSString *)name subtitle:(NSString *)subtitle y:(CGFloat *)y width:(CGFloat)width {
    UIView *card = [self cardAtY:*y height:66 width:width compact:NO];
    UILabel *t = [self label:name size:14.0 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    t.frame = CGRectMake(14, 9, MAX(90, card.bounds.size.width - 90), 22);
    [card addSubview:t];
    UILabel *s = [self label:subtitle size:10.5 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    s.frame = CGRectMake(14, 33, MAX(90, card.bounds.size.width - 90), 20);
    [card addSubview:s];
    UISwitch *sw = [self switchForCard:card on:NO compact:NO];
    CGSize ss = sw.bounds.size;
    sw.center = CGPointMake(card.bounds.size.width - 14 - ss.width * 0.5, card.bounds.size.height * 0.5);
    [self.contentView addSubview:card];
    *y += 76;
}

- (void)addCompactComposite:(NSString *)name value:(CGFloat)value min:(CGFloat)min max:(CGFloat)max y:(CGFloat *)y width:(CGFloat)width {
    UIView *card = [self cardAtY:*y height:52 width:width compact:YES];
    UILabel *t = [self label:name size:11.5 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    t.frame = CGRectMake(9, 5, 58, 20);
    [card addSubview:t];

    UILabel *val = [self label:[NSString stringWithFormat:@"[%.1fx]", value] size:10.0 weight:UIFontWeightSemibold color:self.theme.accentColor];
    val.tag = 7201;
    val.textAlignment = NSTextAlignmentCenter;
    val.frame = CGRectMake(64, 5, 52, 20);
    [card addSubview:val];

    UISwitch *sw = [self switchForCard:card on:NO compact:YES];
    sw.center = CGPointMake(card.bounds.size.width - 25, 15);

    CGFloat sliderX = 9.0;
    CGFloat sliderRight = CGRectGetMinX(sw.frame) - 5.0;
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(sliderX, 26, MAX(90.0, sliderRight - sliderX), 20)];
    slider.tag = 7202;
    slider.minimumValue = min;
    slider.maximumValue = max;
    slider.value = value;
    slider.minimumTrackTintColor = self.theme.accentColor;
    slider.maximumTrackTintColor = self.theme.trackColor;
    slider.thumbTintColor = UIColor.whiteColor;
    [slider addTarget:self action:@selector(compactSlider:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:slider];
    [self.contentView addSubview:card];
    *y += 58;
}

- (void)addCompactSwitch:(NSString *)name y:(CGFloat *)y width:(CGFloat)width {
    UIView *card = [self cardAtY:*y height:38 width:width compact:YES];
    UILabel *t = [self label:name size:11.5 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    t.frame = CGRectMake(9, 8, 150, 20);
    [card addSubview:t];
    UISwitch *sw = [self switchForCard:card on:NO compact:YES];
    sw.center = CGPointMake(card.bounds.size.width - 25, card.bounds.size.height * 0.5);
    [self.contentView addSubview:card];
    *y += 44;
}

- (void)addSection:(NSString *)title subtitle:(NSString *)subtitle y:(CGFloat *)y width:(CGFloat)width {
    UILabel *t = [self label:title size:16.0 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    t.frame = CGRectMake(12, *y, width - 24, 22);
    [self.contentView addSubview:t];
    *y += 24;
    if (subtitle.length) {
        UILabel *s = [self label:subtitle size:10.5 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        s.frame = CGRectMake(12, *y, width - 24, 20);
        [self.contentView addSubview:s];
        *y += 24;
    }
}

- (void)addThemeCardY:(CGFloat *)y width:(CGFloat)width {
    UIView *card = [self cardAtY:*y height:66 width:width compact:NO];
    UILabel *t = [self label:@"当前主题" size:11 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];
    t.frame = CGRectMake(14, 9, 80, 18);
    [card addSubview:t];
    UILabel *n = [self label:[ZNTheme nameForMode:self.themeMode] size:15 weight:UIFontWeightBold color:self.theme.primaryTextColor];
    n.frame = CGRectMake(14, 27, 150, 24);
    [card addSubview:n];
    UILabel *r = [self label:@"点击右上角调色板切换" size:10.0 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    r.textAlignment = NSTextAlignmentRight;
    r.frame = CGRectMake(card.bounds.size.width - 170, 22, 156, 22);
    [card addSubview:r];
    [self.contentView addSubview:card];
    *y += 76;
}

- (void)addAlphaCardY:(CGFloat *)y width:(CGFloat)width {
    UIView *card = [self cardAtY:*y height:70 width:width compact:NO];
    UILabel *t = [self label:@"菜单透明度" size:13.5 weight:UIFontWeightMedium color:self.theme.primaryTextColor];
    t.frame = CGRectMake(14, 8, 110, 20);
    [card addSubview:t];
    UILabel *v = [self label:[NSString stringWithFormat:@"%.0f%%", self.menuAlpha * 100] size:10.5 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    v.tag = 6401;
    v.textAlignment = NSTextAlignmentRight;
    v.frame = CGRectMake(card.bounds.size.width - 54, 8, 40, 20);
    [card addSubview:v];
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(14, 34, card.bounds.size.width - 28, 24)];
    slider.minimumValue = 0.55;
    slider.maximumValue = 1.0;
    slider.value = self.menuAlpha;
    slider.minimumTrackTintColor = self.theme.accentColor;
    slider.maximumTrackTintColor = self.theme.trackColor;
    slider.thumbTintColor = UIColor.whiteColor;
    [slider addTarget:self action:@selector(alphaSlider:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:slider];
    [self.contentView addSubview:card];
    *y += 80;
}

- (void)renderFullPage {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat y = 12.0;
    NSString *cat = self.categories[self.selectedCategory];
    if ([cat isEqualToString:@"首页"]) {
        [self addSection:@"Runtime 状态" subtitle:@"V0.2.2 UI · Compact Mode 基线" y:&y width:width];
        [self addFullSwitch:@"UI 测试开关" subtitle:@"当前不执行真实 Patch" y:&y width:width];
    } else if ([cat isEqualToString:@"玩家"]) {
        [self addSection:@"玩家" subtitle:@"角色与能力相关修改" y:&y width:width];
        [self addFullSwitch:@"无敌" subtitle:@"当前仅改变界面状态" y:&y width:width];
        [self addFullComposite:@"伤害倍率" value:5.0 min:1 max:20 y:&y width:width];
    } else if ([cat isEqualToString:@"战斗"]) {
        [self addSection:@"战斗" subtitle:@"数值类功能统一使用组合 Slider" y:&y width:width];
        [self addFullComposite:@"伤害倍率" value:5.0 min:1 max:20 y:&y width:width];
        [self addFullComposite:@"攻速修改" value:1.8 min:1 max:5 y:&y width:width];
    } else if ([cat isEqualToString:@"移动"]) {
        [self addSection:@"移动" subtitle:@"功能名 + 当前值 + Slider + 开关" y:&y width:width];
        [self addFullComposite:@"移速修改" value:2.5 min:1 max:5 y:&y width:width];
        [self addFullComposite:@"跳跃高度" value:1.5 min:1 max:5 y:&y width:width];
    } else if ([cat isEqualToString:@"其他"]) {
        [self addSection:@"其他" subtitle:@"后续扩展功能" y:&y width:width];
        [self addFullSwitch:@"测试功能" subtitle:@"占位控件" y:&y width:width];
    } else {
        [self addSection:@"界面设置" subtitle:@"主题与基础显示设置" y:&y width:width];
        [self addThemeCardY:&y width:width];
        [self addAlphaCardY:&y width:width];
    }
    CGRect f = self.contentView.frame;
    f.size.height = MAX(CGRectGetHeight(self.contentScroll.bounds), y + 8);
    self.contentView.frame = f;
    self.contentScroll.contentSize = f.size;
}

- (void)renderCompactPage {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat y = 7.0;
    [self addCompactSwitch:@"无敌" y:&y width:width];
    [self addCompactComposite:@"移速" value:2.5 min:1 max:5 y:&y width:width];
    [self addCompactComposite:@"伤害" value:5.0 min:1 max:20 y:&y width:width];
    [self addCompactComposite:@"跳跃" value:1.5 min:1 max:5 y:&y width:width];
    CGRect f = self.contentView.frame;
    f.size.height = MAX(CGRectGetHeight(self.contentScroll.bounds), y + 4);
    self.contentView.frame = f;
    self.contentScroll.contentSize = f.size;
}

- (void)renderPage {
    if (!self.contentView) return;
    if (self.compactMode) [self renderCompactPage];
    else [self renderFullPage];
}

- (void)applyTheme {
    if (!self.uiReady) return;
    self.theme = [ZNTheme themeForMode:self.themeMode interfaceStyle:[self interfaceStyle]];
    self.panel.backgroundColor = self.theme.panelColor;
    self.panel.alpha = self.menuAlpha;
    self.panel.layer.borderColor = self.theme.borderColor.CGColor;
    self.panel.layer.borderWidth = self.theme.neonAppearance ? 1.2 : 1.0;
    self.panel.layer.shadowColor = self.theme.shadowColor.CGColor;
    self.panel.layer.shadowOpacity = self.theme.neonAppearance ? 0.72 : 0.38;
    self.panel.layer.shadowRadius = self.theme.neonAppearance ? 16 : 10;
    self.headerView.backgroundColor = self.theme.headerColor;
    self.sidebarView.backgroundColor = self.theme.sidebarColor;
    self.footerView.backgroundColor = self.theme.footerColor;
    self.titleLabel.textColor = self.theme.primaryTextColor;
    self.subtitleLabel.textColor = self.theme.secondaryTextColor;
    self.readyLabel.textColor = self.theme.primaryTextColor;
    self.readyDot.backgroundColor = self.theme.mechanicalAppearance ? self.theme.accentColor : [UIColor colorWithRed:0.25 green:0.86 blue:0.43 alpha:1];
    self.footerLabel.textColor = self.theme.secondaryTextColor;
    for (UIButton *b in @[self.themeButton,self.modeButton,self.closeButton]) {
        b.backgroundColor = self.theme.controlColor;
        b.tintColor = self.theme.primaryTextColor;
        [b setTitleColor:self.theme.primaryTextColor forState:UIControlStateNormal];
        b.layer.cornerRadius = 9;
        b.layer.borderWidth = 1;
        b.layer.borderColor = self.theme.borderColor.CGColor;
    }
    self.themeButton.tintColor = self.theme.accentColor;
    self.floatButton.backgroundColor = self.theme.floatColor;
    self.floatButton.layer.borderColor = self.theme.accentColor.CGColor;
    self.floatButton.layer.borderWidth = self.theme.neonAppearance ? 2 : 1.5;
    [self.floatButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self updateSidebar];
    [self rebuildPopover];
    [self renderPage];
}

- (void)updateSidebar {
    for (NSInteger i=0;i<self.sidebarButtons.count;i++) {
        UIButton *b = self.sidebarButtons[i];
        BOOL sel = i == self.selectedCategory;
        b.backgroundColor = sel ? self.theme.selectedColor : UIColor.clearColor;
        b.tintColor = sel ? self.theme.accentColor : self.theme.secondaryTextColor;
        [b setTitleColor:sel ? self.theme.primaryTextColor : self.theme.secondaryTextColor forState:UIControlStateNormal];
    }
}

- (void)layoutSidebar {
    CGFloat y = 8;
    CGFloat w = CGRectGetWidth(self.sidebarView.bounds);
    for (UIButton *b in self.sidebarButtons) {
        b.frame = CGRectMake(7,y,w-14,38);
        y += 43;
    }
}

- (void)rebuildPopover {
    if (!self.themePopover) return;
    [self.themePopover.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    self.themePopover.backgroundColor = self.theme.popoverColor;
    self.themePopover.layer.cornerRadius = 11;
    self.themePopover.layer.borderWidth = 1;
    self.themePopover.layer.borderColor = self.theme.borderColor.CGColor;
    NSArray *names = [ZNTheme themeNames];
    CGFloat y = 6;
    for (NSInteger i=0;i<names.count;i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.tag = 8000+i;
        b.frame = CGRectMake(6,y,176,32);
        b.layer.cornerRadius = 7;
        b.backgroundColor = i == self.themeMode ? self.theme.selectedColor : UIColor.clearColor;
        [b setTitle:[NSString stringWithFormat:@"  %@%@", names[i], i==self.themeMode?@"   ✓":@""] forState:UIControlStateNormal];
        [b setTitleColor:self.theme.primaryTextColor forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:11.5 weight:i==self.themeMode?UIFontWeightSemibold:UIFontWeightRegular];
        b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        [b addTarget:self action:@selector(themeRow:) forControlEvents:UIControlEventTouchUpInside];
        [self.themePopover addSubview:b];
        y += 34;
    }
}

- (void)layoutPanel {
    CGFloat w = CGRectGetWidth(self.panel.bounds);
    CGFloat h = CGRectGetHeight(self.panel.bounds);
    self.headerView.frame = CGRectMake(0,0,w,kZNHeaderH);

    if (self.compactMode) {
        self.titleLabel.text = @"ZN";
        self.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightHeavy];
        self.titleLabel.frame = CGRectMake(12,8,44,20);
        self.subtitleLabel.text = @"Compact";
        self.subtitleLabel.font = [UIFont systemFontOfSize:9.5 weight:UIFontWeightRegular];
        self.subtitleLabel.frame = CGRectMake(12,28,55,15);
        self.readyDot.hidden = YES;
        self.readyLabel.hidden = YES;
        self.themeButton.hidden = YES;
        self.modeButton.hidden = NO;
        self.closeButton.hidden = NO;
        self.modeButton.frame = CGRectMake(w-84,8,34,36);
        self.closeButton.frame = CGRectMake(w-44,8,34,36);
        [self.modeButton setTitle:@"□" forState:UIControlStateNormal];
        self.modeButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        self.sidebarView.hidden = YES;
        self.footerView.hidden = YES;
        self.contentScroll.frame = CGRectMake(0,kZNHeaderH,w,h-kZNHeaderH);
    } else {
        self.titleLabel.text = @"ZONOE PATCH";
        self.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightHeavy];
        self.titleLabel.frame = CGRectMake(15,6,MAX(120,w-245),22);
        self.subtitleLabel.text = @"Runtime Patch Menu";
        self.subtitleLabel.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightRegular];
        self.subtitleLabel.frame = CGRectMake(15,28,MAX(120,w-245),17);
        self.readyDot.hidden = NO;
        self.readyLabel.hidden = NO;
        self.themeButton.hidden = NO;
        self.modeButton.hidden = NO;
        self.closeButton.hidden = NO;
        CGFloat right = 8.0;
        self.closeButton.frame = CGRectMake(w-right-42,7,42,38);
        self.modeButton.frame = CGRectMake(CGRectGetMinX(self.closeButton.frame)-48,7,42,38);
        self.themeButton.frame = CGRectMake(CGRectGetMinX(self.modeButton.frame)-48,7,42,38);
        [self.modeButton setTitle:@"—" forState:UIControlStateNormal];
        self.modeButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        self.readyLabel.frame = CGRectMake(CGRectGetMinX(self.themeButton.frame)-58,11,48,28);
        self.readyDot.frame = CGRectMake(CGRectGetMinX(self.readyLabel.frame)-13,21,8,8);
        self.sidebarView.hidden = NO;
        self.footerView.hidden = NO;
        CGFloat sidebarW = w < 450 ? 100 : 120;
        CGFloat bodyH = h-kZNHeaderH-kZNFooterH;
        self.sidebarView.frame = CGRectMake(0,kZNHeaderH,sidebarW,bodyH);
        self.contentScroll.frame = CGRectMake(sidebarW,kZNHeaderH,w-sidebarW,bodyH);
        self.footerView.frame = CGRectMake(0,h-kZNFooterH,w,kZNFooterH);
        self.footerLabel.frame = CGRectMake(12,0,w-24,kZNFooterH);
        [self layoutSidebar];
    }

    self.contentView.frame = CGRectMake(0,0,CGRectGetWidth(self.contentScroll.bounds),MAX(CGRectGetHeight(self.contentScroll.bounds),self.contentView.frame.size.height));
    self.themePopover.frame = CGRectMake(MAX(8,w-196),48,188,216);
    [self renderPage];
}

- (void)layoutForWindow:(UIWindow *)window initial:(BOOL)initial {
    if (!window || !self.uiReady) return;
    CGPoint old = self.panel.center;
    CGSize size = self.compactMode ? [self compactSizeForWindow:window] : [self fullSizeForWindow:window];
    self.panel.bounds = CGRectMake(0,0,size.width,size.height);
    if (initial) {
        UIEdgeInsets s = window.safeAreaInsets;
        CGPoint df = CGPointMake(CGRectGetWidth(window.bounds)-s.right-kZNMargin-kZNFloatSize*0.5,CGRectGetMidY(window.bounds));
        CGPoint dp = CGPointMake(CGRectGetMidX(window.bounds),CGRectGetMidY(window.bounds));
        NSString *fs = [NSUserDefaults.standardUserDefaults stringForKey:kZNFloatPositionKey];
        NSString *ps = [NSUserDefaults.standardUserDefaults stringForKey:kZNPanelPositionKey];
        self.floatButton.center = [self clampFloat:fs.length?CGPointFromString(fs):df window:window];
        self.panel.center = [self clampPanel:ps.length?CGPointFromString(ps):dp window:window];
    } else {
        self.floatButton.center = [self clampFloat:self.floatButton.center window:window];
        self.panel.center = [self clampPanel:old window:window];
    }
    [self layoutPanel];
    self.lastBounds = window.bounds;
    self.lastInsets = window.safeAreaInsets;
}

- (void)makeUI:(UIWindow *)window {
    if (self.uiReady || !window) return;
    self.hostWindow = window;
    self.theme = [ZNTheme themeForMode:self.themeMode interfaceStyle:[self interfaceStyle]];

    self.floatButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatButton.bounds = CGRectMake(0,0,kZNFloatSize,kZNFloatSize);
    self.floatButton.layer.cornerRadius = kZNFloatSize*0.5;
    [self.floatButton setTitle:@"ZN" forState:UIControlStateNormal];
    self.floatButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [self.floatButton addTarget:self action:@selector(togglePanel:) forControlEvents:UIControlEventTouchUpInside];
    [self.floatButton addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panFloat:)]];

    self.panel = [UIView new];
    self.panel.layer.cornerRadius = 15;
    self.panel.layer.masksToBounds = NO;

    self.headerView = [UIView new];
    self.headerView.layer.cornerRadius = 15;
    self.headerView.layer.maskedCorners = kCALayerMinXMinYCorner|kCALayerMaxXMinYCorner;
    [self.headerView addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panPanel:)]];
    [self.panel addSubview:self.headerView];

    self.titleLabel = [UILabel new];
    [self.headerView addSubview:self.titleLabel];
    self.subtitleLabel = [UILabel new];
    [self.headerView addSubview:self.subtitleLabel];
    self.readyDot = [UIView new]; self.readyDot.layer.cornerRadius = 4; [self.headerView addSubview:self.readyDot];
    self.readyLabel = [self label:@"Ready" size:11 weight:UIFontWeightMedium color:self.theme.primaryTextColor]; [self.headerView addSubview:self.readyLabel];

    self.themeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.themeButton setImage:ZNSymbol(@"paintpalette.fill",15,UIImageSymbolWeightSemibold) forState:UIControlStateNormal];
    [self.themeButton addTarget:self action:@selector(themeTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.headerView addSubview:self.themeButton];

    self.modeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.modeButton addTarget:self action:@selector(modeTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.headerView addSubview:self.modeButton];

    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.closeButton setTitle:@"×" forState:UIControlStateNormal];
    self.closeButton.titleLabel.font = [UIFont systemFontOfSize:23 weight:UIFontWeightLight];
    [self.closeButton addTarget:self action:@selector(closeTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.headerView addSubview:self.closeButton];

    self.sidebarView = [UIView new];
    [self.panel addSubview:self.sidebarView];
    for (NSInteger i=0;i<self.categories.count;i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.tag = 3000+i;
        b.layer.cornerRadius = 8;
        b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        b.contentEdgeInsets = UIEdgeInsetsMake(0,10,0,4);
        [b setImage:ZNSymbol(self.categorySymbols[i],13,UIImageSymbolWeightSemibold) forState:UIControlStateNormal];
        [b setTitle:[NSString stringWithFormat:@"  %@",self.categories[i]] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightMedium];
        [b addTarget:self action:@selector(categoryTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.sidebarView addSubview:b]; [self.sidebarButtons addObject:b];
    }

    self.contentScroll = [UIScrollView new];
    self.contentScroll.showsVerticalScrollIndicator = YES;
    [self.panel addSubview:self.contentScroll];
    self.contentView = [UIView new];
    [self.contentScroll addSubview:self.contentView];

    self.footerView = [UIView new];
    [self.panel addSubview:self.footerView];
    self.footerLabel = [self label:@"" size:9.2 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    [self.footerView addSubview:self.footerLabel];

    self.themePopover = [UIView new];
    self.themePopover.hidden = YES;
    [self.panel addSubview:self.themePopover];

    self.panel.hidden = YES;
    [window addSubview:self.floatButton];
    [window addSubview:self.panel];
    self.uiReady = YES;
    [self layoutForWindow:window initial:YES];
    [self applyTheme];
    self.footerLabel.text = [NSString stringWithFormat:@"UnityFramework    Runtime 0.2.2    iOS %@",UIDevice.currentDevice.systemVersion];
    NSLog(@"[ZonoePatch v0.2.2] UI ready compact=%d theme=%@",self.compactMode,[ZNTheme nameForMode:self.themeMode]);
}

- (void)attach:(UIWindow *)window {
    if (!window || !self.uiReady) return;
    [self.floatButton removeFromSuperview]; [self.panel removeFromSuperview];
    [window addSubview:self.floatButton]; [window addSubview:self.panel];
    self.hostWindow = window;
    [self layoutForWindow:window initial:NO];
    [self applyTheme];
}

- (void)tick:(NSTimer *)timer {
    (void)timer;
    UIWindow *w = [self currentWindow]; if (!w) return;
    if (!self.uiReady) { [self makeUI:w]; return; }
    if (self.hostWindow != w || self.panel.superview != w || self.floatButton.superview != w) [self attach:w];
    if (!CGRectEqualToRect(self.lastBounds,w.bounds) || !UIEdgeInsetsEqualToEdgeInsets(self.lastInsets,w.safeAreaInsets)) [self layoutForWindow:w initial:NO];
    [w bringSubviewToFront:self.panel]; [w bringSubviewToFront:self.floatButton]; [self.panel bringSubviewToFront:self.themePopover];
}

- (void)start {
    if (!self.timer) {
        [self tick:nil];
        self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    }
    self.floatButton.hidden = NO;
}

- (void)show {
    if (!self.uiReady) [self tick:nil];
    if (!self.uiReady) return;
    self.floatButton.hidden = NO;
    self.panel.hidden = NO;
}

- (void)hide { self.themePopover.hidden = YES; self.panel.hidden = YES; }
- (BOOL)isVisible { return self.uiReady && !self.panel.hidden; }

- (void)togglePanel:(id)sender { (void)sender; self.panel.hidden = !self.panel.hidden; self.themePopover.hidden = YES; }

- (void)modeTapped:(id)sender {
    (void)sender;
    self.compactMode = !self.compactMode;
    [NSUserDefaults.standardUserDefaults setBool:self.compactMode forKey:kZNCompactModeKey];
    self.themePopover.hidden = YES;
    [self layoutForWindow:self.hostWindow initial:NO];
    [self applyTheme];
    NSLog(@"[ZonoePatch v0.2.2] compact=%d",self.compactMode);
}

- (void)closeTapped:(id)sender {
    (void)sender;
    self.themePopover.hidden = YES;
    self.panel.hidden = YES;
    self.floatButton.hidden = NO;
}

- (void)themeTapped:(id)sender {
    (void)sender;
    if (self.compactMode) return;
    self.themePopover.hidden = !self.themePopover.hidden;
    if (!self.themePopover.hidden) { [self rebuildPopover]; [self.panel bringSubviewToFront:self.themePopover]; }
}

- (void)themeRow:(UIButton *)sender {
    NSInteger idx = sender.tag - 8000;
    if (idx < ZNThemeModeSystem || idx > ZNThemeModeMatcha) return;
    self.themeMode = (ZNThemeMode)idx;
    [NSUserDefaults.standardUserDefaults setInteger:self.themeMode forKey:kZNThemeModeKey];
    self.themePopover.hidden = YES;
    [self applyTheme];
}

- (void)categoryTapped:(UIButton *)sender {
    NSInteger idx = sender.tag - 3000;
    if (idx < 0 || idx >= self.categories.count) return;
    self.selectedCategory = idx;
    self.contentScroll.contentOffset = CGPointZero;
    [self updateSidebar]; [self renderPage];
}

- (void)dummySwitch:(UISwitch *)sender { NSLog(@"[ZonoePatch v0.2.2] switch=%@",sender.isOn?@"ON":@"OFF"); }

- (void)compositeSlider:(UISlider *)slider {
    UILabel *v = [slider.superview viewWithTag:6201];
    v.text = [NSString stringWithFormat:@"[ %.1fx ]",slider.value];
}

- (void)compactSlider:(UISlider *)slider {
    UILabel *v = [slider.superview viewWithTag:7201];
    v.text = [NSString stringWithFormat:@"[%.1fx]",slider.value];
}

- (void)alphaSlider:(UISlider *)slider {
    self.menuAlpha = ZNClamp(slider.value,0.55,1.0);
    self.panel.alpha = self.menuAlpha;
    [NSUserDefaults.standardUserDefaults setDouble:self.menuAlpha forKey:kZNMenuAlphaKey];
    UILabel *v = [slider.superview viewWithTag:6401];
    v.text = [NSString stringWithFormat:@"%.0f%%",self.menuAlpha*100];
}

- (void)panFloat:(UIPanGestureRecognizer *)g {
    CGPoint tr = [g translationInView:self.hostWindow];
    CGPoint c = self.floatButton.center; c.x += tr.x; c.y += tr.y;
    self.floatButton.center = [self clampFloat:c window:self.hostWindow];
    [g setTranslation:CGPointZero inView:self.hostWindow];
    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled)
        [NSUserDefaults.standardUserDefaults setObject:NSStringFromCGPoint(self.floatButton.center) forKey:kZNFloatPositionKey];
}

- (void)panPanel:(UIPanGestureRecognizer *)g {
    CGPoint tr = [g translationInView:self.hostWindow];
    CGPoint c = self.panel.center; c.x += tr.x; c.y += tr.y;
    self.panel.center = [self clampPanel:c window:self.hostWindow];
    [g setTranslation:CGPointZero inView:self.hostWindow];
    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled)
        [NSUserDefaults.standardUserDefaults setObject:NSStringFromCGPoint(self.panel.center) forKey:kZNPanelPositionKey];
}

@end

extern "C" __attribute__((visibility("default"))) uint32_t ZonoePatchGetAPIVersion(void) { return 1; }
extern "C" __attribute__((visibility("default"))) const char *ZonoePatchGetVersion(void) { return "0.2.2-ui"; }
extern "C" __attribute__((visibility("default"))) void ZonoePatchStart(void) { dispatch_async(dispatch_get_main_queue(), ^{ [[ZNRuntimeMenuControllerV022 shared] start]; }); }
extern "C" __attribute__((visibility("default"))) void ZonoePatchShow(void) { dispatch_async(dispatch_get_main_queue(), ^{ [[ZNRuntimeMenuControllerV022 shared] show]; }); }
extern "C" __attribute__((visibility("default"))) void ZonoePatchHide(void) { dispatch_async(dispatch_get_main_queue(), ^{ [[ZNRuntimeMenuControllerV022 shared] hide]; }); }
extern "C" __attribute__((visibility("default"))) bool ZonoePatchIsVisible(void) {
    __block BOOL v = NO;
    if (NSThread.isMainThread) return [[ZNRuntimeMenuControllerV022 shared] isVisible];
    dispatch_sync(dispatch_get_main_queue(), ^{ v = [[ZNRuntimeMenuControllerV022 shared] isVisible]; });
    return v;
}

__attribute__((constructor)) static void ZNRuntimeMenuBootstrapV022(void) {
    @autoreleasepool {
        NSLog(@"[ZonoePatch v0.2.2] dylib loaded");
        ZonoePatchStart();
    }
}
