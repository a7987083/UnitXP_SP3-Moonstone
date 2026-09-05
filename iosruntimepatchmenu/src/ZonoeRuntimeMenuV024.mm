#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <stdint.h>

#import "ZNTheme.h"

static NSString * const kZNMenuVersion = @"0.2.4-ui";
static NSString * const kZNFloatPositionKey = @"ZonoePatch.FloatCenter";
static NSString * const kZNPanelPositionKey = @"ZonoePatch.PanelCenter";
static NSString * const kZNThemeModeKey = @"ZonoePatch.ThemeMode";
static NSString * const kZNCompactModeKey = @"ZonoePatch.CompactMode";
static NSString * const kZNMenuAlphaKey = @"ZonoePatch.MenuAlpha";
static NSString * const kZNSelectedCategoryKey = @"ZonoePatch.SelectedCategory";
static NSString * const kZNAutoSnapKey = @"ZonoePatch.AutoSnap";
static NSString * const kZNRememberPositionKey = @"ZonoePatch.RememberPosition";

static NSString * const kZNFeatureUITest = @"ui_test";
static NSString * const kZNFeatureInvincible = @"invincible";
static NSString * const kZNFeatureSpeed = @"speed";
static NSString * const kZNFeatureDamage = @"damage";
static NSString * const kZNFeatureJump = @"jump";
static NSString * const kZNFeatureAttackSpeed = @"attack_speed";
static NSString * const kZNFeatureOtherTest = @"other_test";

static const CGFloat kZNFloatSize = 52.0;
static const CGFloat kZNMargin = 10.0;
static const CGFloat kZNHeaderH = 48.0;
static const CGFloat kZNFooterH = 24.0;
static const CGFloat kZNCompactSwitchScale = 0.72;
static const NSInteger kZNThemeCategoryIndex = 6;

static CGFloat ZNClamp(CGFloat v, CGFloat lo, CGFloat hi) {
    if (hi < lo) return lo;
    return MIN(MAX(v, lo), hi);
}

static NSString *ZNEnabledKey(NSString *featureID) {
    return [NSString stringWithFormat:@"ZonoePatch.Feature.%@.Enabled", featureID];
}

static NSString *ZNValueKey(NSString *featureID) {
    return [NSString stringWithFormat:@"ZonoePatch.Feature.%@.Value", featureID];
}

static UIImage *ZNSymbol(NSString *name, CGFloat size, UIImageSymbolWeight weight) {
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:size weight:weight];
        return [[UIImage systemImageNamed:name withConfiguration:cfg] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    return nil;
}

@interface ZNRuntimeMenuControllerV024 : NSObject
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
@property(nonatomic,strong) NSMutableArray<UIButton *> *sidebarButtons;
@property(nonatomic,copy) NSArray<NSString *> *categories;
@property(nonatomic,copy) NSArray<NSString *> *categorySymbols;
@property(nonatomic,assign) NSInteger selectedCategory;
@property(nonatomic,weak) UIWindow *hostWindow;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,assign) CGRect lastBounds;
@property(nonatomic,assign) UIEdgeInsets lastInsets;
@property(nonatomic,assign) UIUserInterfaceStyle lastStyle;
@property(nonatomic,assign) BOOL uiReady;
@property(nonatomic,assign) BOOL compactMode;
@property(nonatomic,assign) BOOL autoSnap;
@property(nonatomic,assign) BOOL rememberPosition;
@property(nonatomic,assign) ZNThemeMode themeMode;
@property(nonatomic,strong) ZNTheme *theme;
@property(nonatomic,assign) CGFloat menuAlpha;
@end

@implementation ZNRuntimeMenuControllerV024

+ (instancetype)shared {
    static ZNRuntimeMenuControllerV024 *s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ s = [ZNRuntimeMenuControllerV024 new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;

    _categories = @[@"首页", @"玩家", @"战斗", @"移动", @"其他", @"设置", @"主题"];
    _categorySymbols = @[@"house.fill", @"person.fill", @"bolt.fill", @"location.north.fill", @"square.grid.2x2.fill", @"gearshape.fill", @"paintpalette.fill"];
    _sidebarButtons = [NSMutableArray array];

    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    [ud registerDefaults:@{
        kZNThemeModeKey: @(ZNThemeModeObsidian),
        kZNCompactModeKey: @NO,
        kZNMenuAlphaKey: @0.88,
        kZNSelectedCategoryKey: @0,
        kZNAutoSnapKey: @YES,
        kZNRememberPositionKey: @YES,
        ZNEnabledKey(kZNFeatureUITest): @NO,
        ZNEnabledKey(kZNFeatureInvincible): @NO,
        ZNEnabledKey(kZNFeatureSpeed): @NO,
        ZNEnabledKey(kZNFeatureDamage): @NO,
        ZNEnabledKey(kZNFeatureJump): @NO,
        ZNEnabledKey(kZNFeatureAttackSpeed): @NO,
        ZNEnabledKey(kZNFeatureOtherTest): @NO,
        ZNValueKey(kZNFeatureSpeed): @2.5,
        ZNValueKey(kZNFeatureDamage): @5.0,
        ZNValueKey(kZNFeatureJump): @1.5,
        ZNValueKey(kZNFeatureAttackSpeed): @1.8,
    }];

    _themeMode = (ZNThemeMode)[ud integerForKey:kZNThemeModeKey];
    if (_themeMode < ZNThemeModeSystem || _themeMode >= ZNThemeModeCount) _themeMode = ZNThemeModeObsidian;
    _compactMode = [ud boolForKey:kZNCompactModeKey];
    _menuAlpha = ZNClamp([ud doubleForKey:kZNMenuAlphaKey], 0.55, 1.0);
    _selectedCategory = [ud integerForKey:kZNSelectedCategoryKey];
    if (_selectedCategory < 0 || _selectedCategory >= _categories.count) _selectedCategory = 0;
    _autoSnap = [ud boolForKey:kZNAutoSnapKey];
    _rememberPosition = [ud boolForKey:kZNRememberPositionKey];
    _theme = [ZNTheme themeForMode:_themeMode interfaceStyle:UIUserInterfaceStyleDark];
    _lastStyle = UIUserInterfaceStyleUnspecified;
    return self;
}

- (BOOL)enabledForFeature:(NSString *)featureID {
    return [NSUserDefaults.standardUserDefaults boolForKey:ZNEnabledKey(featureID)];
}

- (void)setFeature:(NSString *)featureID enabled:(BOOL)enabled {
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:ZNEnabledKey(featureID)];
}

- (CGFloat)valueForFeature:(NSString *)featureID fallback:(CGFloat)fallback {
    id obj = [NSUserDefaults.standardUserDefaults objectForKey:ZNValueKey(featureID)];
    return obj ? [NSUserDefaults.standardUserDefaults doubleForKey:ZNValueKey(featureID)] : fallback;
}

- (void)setFeature:(NSString *)featureID value:(CGFloat)value {
    [NSUserDefaults.standardUserDefaults setDouble:value forKey:ZNValueKey(featureID)];
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
        if (s == UIUserInterfaceStyleUnspecified) s = UIScreen.mainScreen.traitCollection.userInterfaceStyle;
        return s == UIUserInterfaceStyleLight ? UIUserInterfaceStyleLight : UIUserInterfaceStyleDark;
    }
    return UIUserInterfaceStyleDark;
}

- (UIFont *)menuFont:(CGFloat)size weight:(UIFontWeight)weight {
    switch (self.theme.decorationStyle) {
        case ZNThemeDecorationTerminal:
        case ZNThemeDecorationArcade:
            return [UIFont fontWithName:@"Menlo-Bold" size:size] ?: [UIFont systemFontOfSize:size weight:weight];
        case ZNThemeDecorationParchment:
        case ZNThemeDecorationWood:
        case ZNThemeDecorationGothic:
            return [UIFont fontWithName:@"Georgia-Bold" size:size] ?: [UIFont systemFontOfSize:size weight:weight];
        default:
            return [UIFont systemFontOfSize:size weight:weight];
    }
}

- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color {
    UILabel *l = [UILabel new];
    l.text = text;
    l.font = [self menuFont:size weight:weight];
    l.textColor = color;
    l.numberOfLines = 1;
    return l;
}

- (CGPoint)clampFloat:(CGPoint)c window:(UIWindow *)w {
    UIEdgeInsets s = w.safeAreaInsets;
    CGFloat h = kZNFloatSize * 0.5;
    return CGPointMake(ZNClamp(c.x, s.left+kZNMargin+h, CGRectGetWidth(w.bounds)-s.right-kZNMargin-h),
                       ZNClamp(c.y, s.top+kZNMargin+h, CGRectGetHeight(w.bounds)-s.bottom-kZNMargin-h));
}

- (CGPoint)clampPanel:(CGPoint)c window:(UIWindow *)w {
    UIEdgeInsets s = w.safeAreaInsets;
    CGSize z = self.panel.bounds.size;
    return CGPointMake(ZNClamp(c.x, s.left+kZNMargin+z.width*0.5, CGRectGetWidth(w.bounds)-s.right-kZNMargin-z.width*0.5),
                       ZNClamp(c.y, s.top+kZNMargin+z.height*0.5, CGRectGetHeight(w.bounds)-s.bottom-kZNMargin-z.height*0.5));
}

- (CGSize)fullSizeForWindow:(UIWindow *)w {
    UIEdgeInsets s = w.safeAreaInsets;
    CGFloat aw = CGRectGetWidth(w.bounds)-s.left-s.right;
    CGFloat ah = CGRectGetHeight(w.bounds)-s.top-s.bottom;
    BOOL landscape = aw >= ah;
    CGFloat pw = landscape ? MIN(620.0, MAX(430.0, aw*0.72)) : MIN(520.0, MAX(310.0, aw-28.0));
    CGFloat desired = 340.0;
    switch (self.selectedCategory) {
        case 0: desired = 340.0; break;
        case 1: desired = 370.0; break;
        case 2:
        case 3: desired = 390.0; break;
        case 4: desired = 340.0; break;
        case 5: desired = 415.0; break;
        case 6: desired = landscape ? 410.0 : 430.0; break;
        default: break;
    }
    CGFloat maxH = MAX(300.0, ah-20.0);
    return CGSizeMake(MIN(pw, aw-20.0), MIN(desired, maxH));
}

- (CGSize)compactSizeForWindow:(UIWindow *)w {
    UIEdgeInsets s = w.safeAreaInsets;
    CGFloat aw = CGRectGetWidth(w.bounds)-s.left-s.right;
    CGFloat ah = CGRectGetHeight(w.bounds)-s.top-s.bottom;
    return CGSizeMake(MIN(330.0, MAX(286.0, aw-20.0)), MIN(286.0, MAX(244.0, ah-20.0)));
}

- (void)clearDecorations {
    NSArray<CALayer *> *layers = [self.panel.layer.sublayers copy];
    for (CALayer *layer in layers) if ([layer.name hasPrefix:@"ZNDecor"]) [layer removeFromSuperlayer];
}

- (void)applyDecorations {
    [self clearDecorations];
    self.panel.layer.cornerRadius = 14.0;
    self.panel.layer.borderWidth = self.theme.neonAppearance ? 1.5 : 1.0;
    self.headerView.layer.cornerRadius = 14.0;

    ZNThemeDecorationStyle style = self.theme.decorationStyle;
    if (style == ZNThemeDecorationMechanical || style == ZNThemeDecorationSteam || style == ZNThemeDecorationPolar || style == ZNThemeDecorationLava) {
        self.panel.layer.cornerRadius = 7.0;
        self.panel.layer.borderWidth = 2.0;
    } else if (style == ZNThemeDecorationTerminal || style == ZNThemeDecorationBlueprint || style == ZNThemeDecorationArcade) {
        self.panel.layer.cornerRadius = 3.0;
    } else if (style == ZNThemeDecorationGlass || style == ZNThemeDecorationCandy) {
        self.panel.layer.cornerRadius = 20.0;
    }

    if (style == ZNThemeDecorationNeonCircuit || style == ZNThemeDecorationBlueprint || style == ZNThemeDecorationTerminal || style == ZNThemeDecorationMedical || style == ZNThemeDecorationSpace || style == ZNThemeDecorationSonar || style == ZNThemeDecorationArcade) {
        for (NSInteger i=0;i<5;i++) {
            CALayer *line = [CALayer layer];
            line.name = [NSString stringWithFormat:@"ZNDecorLine%ld",(long)i];
            line.backgroundColor = [self.theme.accent2Color colorWithAlphaComponent:0.12].CGColor;
            line.frame = CGRectMake(0, 78+i*54, CGRectGetWidth(self.panel.bounds), 0.5);
            [self.panel.layer insertSublayer:line atIndex:0];
        }
    }
}

- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact {
    CGFloat inset = compact ? 7.0 : 10.0;
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(inset,y,MAX(0,w-inset*2),h)];
    v.backgroundColor = self.theme.cardColor;
    v.layer.cornerRadius = compact ? 8.0 : ((self.theme.decorationStyle==ZNThemeDecorationMechanical||self.theme.decorationStyle==ZNThemeDecorationSteam)?5.0:10.0);
    v.layer.borderWidth = self.theme.neonAppearance ? 1.2 : 1.0;
    v.layer.borderColor = self.theme.borderColor.CGColor;
    if (self.theme.neonAppearance) {
        v.layer.shadowColor = self.theme.accent2Color.CGColor;
        v.layer.shadowOpacity = compact ? 0.15 : 0.12;
        v.layer.shadowRadius = 5.0;
        v.layer.shadowOffset = CGSizeZero;
    }
    return v;
}

- (UISwitch *)switchForCard:(UIView *)card featureID:(NSString *)featureID compact:(BOOL)compact {
    UISwitch *sw = [UISwitch new];
    sw.on = [self enabledForFeature:featureID];
    sw.accessibilityIdentifier = featureID;
    sw.onTintColor = self.theme.accentColor;
    sw.tintColor = self.theme.trackColor;
    sw.transform = compact ? CGAffineTransformMakeScale(kZNCompactSwitchScale,kZNCompactSwitchScale) : CGAffineTransformIdentity;
    [sw addTarget:self action:@selector(featureSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [card addSubview:sw];
    return sw;
}

- (void)placeCompactSwitch:(UISwitch *)sw inCard:(UIView *)card centerY:(CGFloat)centerY {
    CGFloat visualW = sw.bounds.size.width*kZNCompactSwitchScale;
    sw.center = CGPointMake(card.bounds.size.width-9.0-visualW*0.5,centerY);
}

- (void)addFullComposite:(NSString *)name featureID:(NSString *)featureID fallback:(CGFloat)fallback min:(CGFloat)min max:(CGFloat)max y:(CGFloat *)y width:(CGFloat)width {
    CGFloat value = ZNClamp([self valueForFeature:featureID fallback:fallback],min,max);
    UIView *card = [self cardAtY:*y height:76 width:width compact:NO];
    UILabel *t = [self label:name size:13.5 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    t.frame = CGRectMake(13,7,92,22); [card addSubview:t];
    UILabel *val = [self label:[NSString stringWithFormat:@"[ %.1fx ]",value] size:11.5 weight:UIFontWeightSemibold color:self.theme.accentColor];
    val.tag=6201; val.frame=CGRectMake(103,7,74,22); [card addSubview:val];
    UISwitch *sw = [self switchForCard:card featureID:featureID compact:NO];
    CGSize ss=sw.bounds.size; sw.center=CGPointMake(card.bounds.size.width-13-ss.width*0.5,18.5);
    CGFloat sx=13.0, sr=CGRectGetMinX(sw.frame)-11.0;
    UISlider *slider=[[UISlider alloc] initWithFrame:CGRectMake(sx,39,MAX(100.0,sr-sx),25)];
    slider.tag=6202; slider.accessibilityIdentifier=featureID; slider.minimumValue=min; slider.maximumValue=max; slider.value=value;
    slider.minimumTrackTintColor=self.theme.accentColor; slider.maximumTrackTintColor=self.theme.trackColor; slider.thumbTintColor=UIColor.whiteColor;
    [slider addTarget:self action:@selector(featureSliderChanged:) forControlEvents:UIControlEventValueChanged]; [card addSubview:slider];
    [self.contentView addSubview:card]; *y += 84;
}

- (void)addFullSwitch:(NSString *)name subtitle:(NSString *)subtitle featureID:(NSString *)featureID y:(CGFloat *)y width:(CGFloat)width {
    UIView *card=[self cardAtY:*y height:60 width:width compact:NO];
    UILabel *t=[self label:name size:13.5 weight:UIFontWeightSemibold color:self.theme.primaryTextColor]; t.frame=CGRectMake(13,7,MAX(90,card.bounds.size.width-90),22); [card addSubview:t];
    UILabel *s=[self label:subtitle size:10 weight:UIFontWeightRegular color:self.theme.secondaryTextColor]; s.frame=CGRectMake(13,30,MAX(90,card.bounds.size.width-90),18); [card addSubview:s];
    UISwitch *sw=[self switchForCard:card featureID:featureID compact:NO]; CGSize ss=sw.bounds.size; sw.center=CGPointMake(card.bounds.size.width-13-ss.width*0.5,card.bounds.size.height*0.5);
    [self.contentView addSubview:card]; *y += 68;
}

- (void)addCompactComposite:(NSString *)name featureID:(NSString *)featureID fallback:(CGFloat)fallback min:(CGFloat)min max:(CGFloat)max y:(CGFloat *)y width:(CGFloat)width {
    CGFloat value=ZNClamp([self valueForFeature:featureID fallback:fallback],min,max);
    UIView *card=[self cardAtY:*y height:54 width:width compact:YES];
    UILabel *t=[self label:name size:11.5 weight:UIFontWeightSemibold color:self.theme.primaryTextColor]; t.frame=CGRectMake(9,5,58,20); [card addSubview:t];
    UILabel *val=[self label:[NSString stringWithFormat:@"[%.1fx]",value] size:10 weight:UIFontWeightSemibold color:self.theme.accentColor]; val.tag=7201; val.textAlignment=NSTextAlignmentCenter; val.frame=CGRectMake(64,5,54,20); [card addSubview:val];
    UISwitch *sw=[self switchForCard:card featureID:featureID compact:YES]; [self placeCompactSwitch:sw inCard:card centerY:15.5];
    CGFloat visualW=sw.bounds.size.width*kZNCompactSwitchScale; CGFloat sx=9.0; CGFloat sr=card.bounds.size.width-9.0-visualW-12.0;
    UISlider *slider=[[UISlider alloc] initWithFrame:CGRectMake(sx,28,MAX(92.0,sr-sx),20)]; slider.tag=7202; slider.accessibilityIdentifier=featureID; slider.minimumValue=min; slider.maximumValue=max; slider.value=value;
    slider.minimumTrackTintColor=self.theme.accentColor; slider.maximumTrackTintColor=self.theme.trackColor; slider.thumbTintColor=UIColor.whiteColor; [slider addTarget:self action:@selector(featureSliderChanged:) forControlEvents:UIControlEventValueChanged]; [card addSubview:slider];
    [self.contentView addSubview:card]; *y += 60;
}

- (void)addCompactSwitch:(NSString *)name featureID:(NSString *)featureID y:(CGFloat *)y width:(CGFloat)width {
    UIView *card=[self cardAtY:*y height:40 width:width compact:YES]; UILabel *t=[self label:name size:11.5 weight:UIFontWeightSemibold color:self.theme.primaryTextColor]; t.frame=CGRectMake(9,10,150,20); [card addSubview:t];
    UISwitch *sw=[self switchForCard:card featureID:featureID compact:YES]; [self placeCompactSwitch:sw inCard:card centerY:20.0]; [self.contentView addSubview:card]; *y += 46;
}

- (void)addSection:(NSString *)title subtitle:(NSString *)subtitle y:(CGFloat *)y width:(CGFloat)width {
    UILabel *t=[self label:title size:15.5 weight:UIFontWeightSemibold color:self.theme.primaryTextColor]; t.frame=CGRectMake(10,*y,width-20,21); [self.contentView addSubview:t]; *y += 22;
    if (subtitle.length) { UILabel *s=[self label:subtitle size:10 weight:UIFontWeightRegular color:self.theme.secondaryTextColor]; s.frame=CGRectMake(10,*y,width-20,18); [self.contentView addSubview:s]; *y += 21; }
}

- (void)addAlphaCardY:(CGFloat *)y width:(CGFloat)width {
    UIView *card=[self cardAtY:*y height:66 width:width compact:NO]; UILabel *t=[self label:@"菜单透明度" size:13 weight:UIFontWeightMedium color:self.theme.primaryTextColor]; t.frame=CGRectMake(13,7,110,20); [card addSubview:t];
    UILabel *v=[self label:[NSString stringWithFormat:@"%.0f%%",self.menuAlpha*100] size:10.5 weight:UIFontWeightSemibold color:self.theme.primaryTextColor]; v.tag=6401; v.textAlignment=NSTextAlignmentRight; v.frame=CGRectMake(card.bounds.size.width-53,7,40,20); [card addSubview:v];
    UISlider *slider=[[UISlider alloc] initWithFrame:CGRectMake(13,31,card.bounds.size.width-26,24)]; slider.minimumValue=0.55; slider.maximumValue=1.0; slider.value=self.menuAlpha; slider.minimumTrackTintColor=self.theme.accentColor; slider.maximumTrackTintColor=self.theme.trackColor; slider.thumbTintColor=UIColor.whiteColor; [slider addTarget:self action:@selector(alphaSliderChanged:) forControlEvents:UIControlEventValueChanged]; [card addSubview:slider]; [self.contentView addSubview:card]; *y += 74;
}

- (void)addSettingSwitch:(NSString *)name subtitle:(NSString *)subtitle on:(BOOL)on selector:(SEL)selector y:(CGFloat *)y width:(CGFloat)width {
    UIView *card=[self cardAtY:*y height:60 width:width compact:NO]; UILabel *t=[self label:name size:13 weight:UIFontWeightMedium color:self.theme.primaryTextColor]; t.frame=CGRectMake(13,7,MAX(90,card.bounds.size.width-90),20); [card addSubview:t]; UILabel *s=[self label:subtitle size:9.8 weight:UIFontWeightRegular color:self.theme.secondaryTextColor]; s.frame=CGRectMake(13,30,MAX(90,card.bounds.size.width-90),18); [card addSubview:s];
    UISwitch *sw=[UISwitch new]; sw.on=on; sw.onTintColor=self.theme.accentColor; sw.center=CGPointMake(card.bounds.size.width-13-sw.bounds.size.width*0.5,card.bounds.size.height*0.5); [sw addTarget:self action:selector forControlEvents:UIControlEventValueChanged]; [card addSubview:sw]; [self.contentView addSubview:card]; *y += 68;
}

- (NSInteger)themeColumnsForWidth:(CGFloat)width {
    BOOL pad = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad;
    BOOL landscape = self.hostWindow && CGRectGetWidth(self.hostWindow.bounds) >= CGRectGetHeight(self.hostWindow.bounds);
    return (pad || landscape || width >= 370.0) ? 4 : 3;
}

- (void)addThemeGridY:(CGFloat *)y width:(CGFloat)width {
    NSArray<NSString *> *names=[ZNTheme themeNames]; NSInteger cols=[self themeColumnsForWidth:width]; CGFloat gap=7.0; CGFloat left=10.0; CGFloat usable=width-left*2-gap*(cols-1); CGFloat cellW=floor(usable/cols); CGFloat cellH=58.0;
    for (NSInteger i=0;i<names.count;i++) {
        NSInteger row=i/cols, col=i%cols; CGFloat x=left+col*(cellW+gap); CGFloat cy=*y+row*(cellH+gap);
        UIButton *b=[UIButton buttonWithType:UIButtonTypeCustom]; b.tag=8000+i; b.frame=CGRectMake(x,cy,cellW,cellH); b.layer.cornerRadius=9; b.layer.borderWidth=(i==self.themeMode)?2.0:1.0; b.layer.borderColor=(i==self.themeMode?self.theme.accentColor:self.theme.borderColor).CGColor; b.backgroundColor=(i==self.themeMode)?self.theme.selectedColor:self.theme.cardColor; [b addTarget:self action:@selector(themeGridTapped:) forControlEvents:UIControlEventTouchUpInside];
        ZNTheme *p=[ZNTheme themeForMode:(ZNThemeMode)i interfaceStyle:[self interfaceStyle]];
        CGFloat dot=9.0; NSArray<UIColor *> *cs=@[p.panelColor,p.accentColor,p.accent2Color];
        for (NSInteger d=0;d<3;d++) { UIView *v=[[UIView alloc] initWithFrame:CGRectMake(8+d*(dot+4),8,dot,dot)]; v.layer.cornerRadius=dot*0.5; v.backgroundColor=cs[d]; v.layer.borderWidth=0.5; v.layer.borderColor=p.borderColor.CGColor; v.userInteractionEnabled=NO; [b addSubview:v]; }
        UILabel *n=[self label:names[i] size:9.6 weight:(i==self.themeMode?UIFontWeightSemibold:UIFontWeightMedium) color:self.theme.primaryTextColor]; n.textAlignment=NSTextAlignmentCenter; n.frame=CGRectMake(3,29,cellW-6,19); n.adjustsFontSizeToFitWidth=YES; n.minimumScaleFactor=0.75; n.userInteractionEnabled=NO; [b addSubview:n];
        if (i==self.themeMode) { UILabel *check=[self label:@"✓" size:10 weight:UIFontWeightBold color:self.theme.accentColor]; check.textAlignment=NSTextAlignmentRight; check.frame=CGRectMake(cellW-22,5,14,14); check.userInteractionEnabled=NO; [b addSubview:check]; }
        [self.contentView addSubview:b];
    }
    NSInteger rows=(names.count+cols-1)/cols; *y += rows*(cellH+gap);
}

- (void)renderFullPage {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)]; CGFloat width=CGRectGetWidth(self.contentView.bounds); CGFloat y=9.0; NSString *cat=self.categories[self.selectedCategory];
    if ([cat isEqualToString:@"首页"]) {
        [self addSection:@"Runtime 状态" subtitle:@"V0.2.4 UI · 页面高度已自适应" y:&y width:width];
        [self addFullSwitch:@"UI 测试开关" subtitle:@"当前不执行真实 Patch" featureID:kZNFeatureUITest y:&y width:width];
    } else if ([cat isEqualToString:@"玩家"]) {
        [self addSection:@"玩家" subtitle:@"角色与能力相关修改" y:&y width:width]; [self addFullSwitch:@"无敌" subtitle:@"当前仅改变界面状态" featureID:kZNFeatureInvincible y:&y width:width]; [self addFullComposite:@"伤害倍率" featureID:kZNFeatureDamage fallback:5 min:1 max:20 y:&y width:width];
    } else if ([cat isEqualToString:@"战斗"]) {
        [self addSection:@"战斗" subtitle:@"数值类功能统一使用组合 Slider" y:&y width:width]; [self addFullComposite:@"伤害倍率" featureID:kZNFeatureDamage fallback:5 min:1 max:20 y:&y width:width]; [self addFullComposite:@"攻速修改" featureID:kZNFeatureAttackSpeed fallback:1.8 min:1 max:5 y:&y width:width];
    } else if ([cat isEqualToString:@"移动"]) {
        [self addSection:@"移动" subtitle:@"功能名 + 当前值 + Slider + 开关" y:&y width:width]; [self addFullComposite:@"移速修改" featureID:kZNFeatureSpeed fallback:2.5 min:1 max:5 y:&y width:width]; [self addFullComposite:@"跳跃高度" featureID:kZNFeatureJump fallback:1.5 min:1 max:5 y:&y width:width];
    } else if ([cat isEqualToString:@"其他"]) {
        [self addSection:@"其他" subtitle:@"后续扩展功能" y:&y width:width]; [self addFullSwitch:@"测试功能" subtitle:@"占位控件" featureID:kZNFeatureOtherTest y:&y width:width];
    } else if ([cat isEqualToString:@"设置"]) {
        [self addSection:@"界面设置" subtitle:@"透明度与行为设置均持久化" y:&y width:width]; [self addAlphaCardY:&y width:width]; [self addSettingSwitch:@"悬浮球自动贴边" subtitle:@"拖动结束后自动吸附左右边缘" on:self.autoSnap selector:@selector(autoSnapChanged:) y:&y width:width]; [self addSettingSwitch:@"记住界面位置" subtitle:@"保存悬浮球与菜单最后位置" on:self.rememberPosition selector:@selector(rememberPositionChanged:) y:&y width:width];
    } else {
        [self addSection:@"主题" subtitle:[NSString stringWithFormat:@"20 种外观 · 当前：%@",[ZNTheme nameForMode:self.themeMode]] y:&y width:width]; [self addThemeGridY:&y width:width];
    }
    CGRect f=self.contentView.frame; f.size.height=MAX(CGRectGetHeight(self.contentScroll.bounds),y+6); self.contentView.frame=f; self.contentScroll.contentSize=f.size;
}

- (void)renderCompactPage {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)]; CGFloat width=CGRectGetWidth(self.contentView.bounds), y=7.0;
    [self addCompactSwitch:@"无敌" featureID:kZNFeatureInvincible y:&y width:width]; [self addCompactComposite:@"移速" featureID:kZNFeatureSpeed fallback:2.5 min:1 max:5 y:&y width:width]; [self addCompactComposite:@"伤害" featureID:kZNFeatureDamage fallback:5 min:1 max:20 y:&y width:width]; [self addCompactComposite:@"跳跃" featureID:kZNFeatureJump fallback:1.5 min:1 max:5 y:&y width:width];
    CGRect f=self.contentView.frame; f.size.height=MAX(CGRectGetHeight(self.contentScroll.bounds),y+4); self.contentView.frame=f; self.contentScroll.contentSize=f.size;
}

- (void)renderPage { if (!self.contentView) return; self.compactMode ? [self renderCompactPage] : [self renderFullPage]; }

- (void)updateSidebar {
    for (NSInteger i=0;i<self.sidebarButtons.count;i++) { UIButton *b=self.sidebarButtons[i]; BOOL sel=i==self.selectedCategory; b.backgroundColor=sel?self.theme.selectedColor:UIColor.clearColor; b.tintColor=sel?self.theme.accentColor:self.theme.secondaryTextColor; [b setTitleColor:sel?self.theme.primaryTextColor:self.theme.secondaryTextColor forState:UIControlStateNormal]; b.titleLabel.font=[self menuFont:11.0 weight:(sel?UIFontWeightSemibold:UIFontWeightMedium)]; }
}

- (void)layoutSidebar {
    CGFloat y=6,w=CGRectGetWidth(self.sidebarView.bounds); for (UIButton *b in self.sidebarButtons) { b.frame=CGRectMake(6,y,w-12,31); y+=34; }
}

- (void)applyTheme {
    if (!self.uiReady) return; self.theme=[ZNTheme themeForMode:self.themeMode interfaceStyle:[self interfaceStyle]]; self.lastStyle=[self interfaceStyle];
    self.panel.backgroundColor=self.theme.panelColor; self.panel.alpha=self.menuAlpha; self.panel.layer.borderColor=self.theme.borderColor.CGColor; self.panel.layer.shadowColor=self.theme.shadowColor.CGColor; self.panel.layer.shadowOpacity=self.theme.neonAppearance?0.65:0.32; self.panel.layer.shadowRadius=self.theme.neonAppearance?15:9; self.panel.layer.shadowOffset=CGSizeZero;
    self.headerView.backgroundColor=self.theme.headerColor; self.sidebarView.backgroundColor=self.theme.sidebarColor; self.footerView.backgroundColor=self.theme.footerColor; self.titleLabel.textColor=self.theme.primaryTextColor; self.subtitleLabel.textColor=self.theme.secondaryTextColor; self.readyLabel.textColor=self.theme.primaryTextColor; self.readyDot.backgroundColor=self.theme.mechanicalAppearance?self.theme.accentColor:[UIColor colorWithRed:0.25 green:0.86 blue:0.43 alpha:1]; self.footerLabel.textColor=self.theme.secondaryTextColor;
    self.titleLabel.font=[self menuFont:(self.compactMode?15:16.5) weight:UIFontWeightHeavy]; self.subtitleLabel.font=[self menuFont:(self.compactMode?9.2:10.2) weight:UIFontWeightRegular];
    for (UIButton *b in @[self.themeButton,self.modeButton,self.closeButton]) { b.backgroundColor=self.theme.controlColor; b.tintColor=self.theme.primaryTextColor; [b setTitleColor:self.theme.primaryTextColor forState:UIControlStateNormal]; b.layer.cornerRadius=(self.theme.decorationStyle==ZNThemeDecorationMechanical||self.theme.decorationStyle==ZNThemeDecorationSteam)?5:8; b.layer.borderWidth=1; b.layer.borderColor=self.theme.borderColor.CGColor; }
    self.themeButton.tintColor=self.theme.accentColor; self.floatButton.backgroundColor=self.theme.floatColor; self.floatButton.layer.borderColor=self.theme.accentColor.CGColor; self.floatButton.layer.borderWidth=self.theme.neonAppearance?2:1.5; [self.floatButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; [self applyDecorations]; [self updateSidebar]; [self renderPage];
}

- (void)layoutPanel {
    CGFloat w=CGRectGetWidth(self.panel.bounds), h=CGRectGetHeight(self.panel.bounds); self.headerView.frame=CGRectMake(0,0,w,kZNHeaderH);
    if (self.compactMode) {
        self.titleLabel.text=@"ZN"; self.titleLabel.frame=CGRectMake(12,6,44,20); self.subtitleLabel.text=@"Compact"; self.subtitleLabel.frame=CGRectMake(12,25,55,15); self.readyDot.hidden=YES; self.readyLabel.hidden=YES; self.themeButton.hidden=YES; self.modeButton.hidden=NO; self.closeButton.hidden=NO; CGFloat right=6; self.closeButton.frame=CGRectMake(w-right-34,6,34,34); self.modeButton.frame=CGRectMake(CGRectGetMinX(self.closeButton.frame)-40,6,34,34); [self.modeButton setTitle:@"□" forState:UIControlStateNormal]; self.modeButton.titleLabel.font=[self menuFont:15 weight:UIFontWeightSemibold]; self.sidebarView.hidden=YES; self.footerView.hidden=YES; self.contentScroll.frame=CGRectMake(0,kZNHeaderH,w,h-kZNHeaderH);
    } else {
        self.titleLabel.text=@"ZONOE PATCH"; self.titleLabel.frame=CGRectMake(14,4,MAX(118,w-238),21); self.subtitleLabel.text=@"Runtime Patch Menu"; self.subtitleLabel.frame=CGRectMake(14,24,MAX(118,w-238),16); self.readyDot.hidden=NO; self.readyLabel.hidden=NO; self.themeButton.hidden=NO; self.modeButton.hidden=NO; self.closeButton.hidden=NO;
        CGFloat right=5; self.closeButton.frame=CGRectMake(w-right-38,5,38,36); self.modeButton.frame=CGRectMake(CGRectGetMinX(self.closeButton.frame)-44,5,38,36); self.themeButton.frame=CGRectMake(CGRectGetMinX(self.modeButton.frame)-44,5,38,36); [self.modeButton setTitle:@"—" forState:UIControlStateNormal]; self.modeButton.titleLabel.font=[self menuFont:15.5 weight:UIFontWeightSemibold]; self.readyLabel.frame=CGRectMake(CGRectGetMinX(self.themeButton.frame)-54,9,45,25); self.readyDot.frame=CGRectMake(CGRectGetMinX(self.readyLabel.frame)-12,18,8,8);
        self.sidebarView.hidden=NO; self.footerView.hidden=NO; CGFloat sidebarW=w<450?94:112; CGFloat bodyH=h-kZNHeaderH-kZNFooterH; self.sidebarView.frame=CGRectMake(0,kZNHeaderH,sidebarW,bodyH); self.contentScroll.frame=CGRectMake(sidebarW,kZNHeaderH,w-sidebarW,bodyH); self.footerView.frame=CGRectMake(0,h-kZNFooterH,w,kZNFooterH); self.footerLabel.frame=CGRectMake(10,0,w-20,kZNFooterH); [self layoutSidebar];
    }
    self.contentView.frame=CGRectMake(0,0,CGRectGetWidth(self.contentScroll.bounds),MAX(CGRectGetHeight(self.contentScroll.bounds),self.contentView.frame.size.height)); [self renderPage];
}

- (void)layoutForWindow:(UIWindow *)window initial:(BOOL)initial {
    if (!window || !self.uiReady) return; CGPoint old=self.panel.center; CGSize size=self.compactMode?[self compactSizeForWindow:window]:[self fullSizeForWindow:window]; self.panel.bounds=CGRectMake(0,0,size.width,size.height);
    if (initial) { UIEdgeInsets s=window.safeAreaInsets; CGPoint df=CGPointMake(CGRectGetWidth(window.bounds)-s.right-kZNMargin-kZNFloatSize*0.5,CGRectGetMidY(window.bounds)); CGPoint dp=CGPointMake(CGRectGetMidX(window.bounds),CGRectGetMidY(window.bounds)); NSString *fs=self.rememberPosition?[NSUserDefaults.standardUserDefaults stringForKey:kZNFloatPositionKey]:nil; NSString *ps=self.rememberPosition?[NSUserDefaults.standardUserDefaults stringForKey:kZNPanelPositionKey]:nil; self.floatButton.center=[self clampFloat:fs.length?CGPointFromString(fs):df window:window]; self.panel.center=[self clampPanel:ps.length?CGPointFromString(ps):dp window:window]; }
    else { self.floatButton.center=[self clampFloat:self.floatButton.center window:window]; self.panel.center=[self clampPanel:old window:window]; }
    [self layoutPanel]; self.lastBounds=window.bounds; self.lastInsets=window.safeAreaInsets;
}

- (void)makeUI:(UIWindow *)window {
    if (self.uiReady || !window) return; self.hostWindow=window; self.theme=[ZNTheme themeForMode:self.themeMode interfaceStyle:[self interfaceStyle]];
    self.floatButton=[UIButton buttonWithType:UIButtonTypeCustom]; self.floatButton.bounds=CGRectMake(0,0,kZNFloatSize,kZNFloatSize); self.floatButton.layer.cornerRadius=kZNFloatSize*0.5; [self.floatButton setTitle:@"ZN" forState:UIControlStateNormal]; self.floatButton.titleLabel.font=[UIFont systemFontOfSize:14 weight:UIFontWeightBold]; [self.floatButton addTarget:self action:@selector(togglePanel:) forControlEvents:UIControlEventTouchUpInside]; [self.floatButton addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panFloat:)]];
    self.panel=[UIView new]; self.panel.layer.masksToBounds=NO; self.headerView=[UIView new]; self.headerView.layer.maskedCorners=kCALayerMinXMinYCorner|kCALayerMaxXMinYCorner; [self.headerView addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panPanel:)]]; [self.panel addSubview:self.headerView];
    self.titleLabel=[UILabel new]; [self.headerView addSubview:self.titleLabel]; self.subtitleLabel=[UILabel new]; [self.headerView addSubview:self.subtitleLabel]; self.readyDot=[UIView new]; self.readyDot.layer.cornerRadius=4; [self.headerView addSubview:self.readyDot]; self.readyLabel=[self label:@"Ready" size:10.5 weight:UIFontWeightMedium color:self.theme.primaryTextColor]; [self.headerView addSubview:self.readyLabel];
    self.themeButton=[UIButton buttonWithType:UIButtonTypeSystem]; [self.themeButton setImage:ZNSymbol(@"paintpalette.fill",14,UIImageSymbolWeightSemibold) forState:UIControlStateNormal]; [self.themeButton addTarget:self action:@selector(themeTapped:) forControlEvents:UIControlEventTouchUpInside]; [self.headerView addSubview:self.themeButton];
    self.modeButton=[UIButton buttonWithType:UIButtonTypeSystem]; [self.modeButton addTarget:self action:@selector(modeTapped:) forControlEvents:UIControlEventTouchUpInside]; [self.headerView addSubview:self.modeButton]; self.closeButton=[UIButton buttonWithType:UIButtonTypeSystem]; [self.closeButton setTitle:@"×" forState:UIControlStateNormal]; self.closeButton.titleLabel.font=[UIFont systemFontOfSize:22 weight:UIFontWeightLight]; [self.closeButton addTarget:self action:@selector(closeTapped:) forControlEvents:UIControlEventTouchUpInside]; [self.headerView addSubview:self.closeButton];
    self.sidebarView=[UIView new]; [self.panel addSubview:self.sidebarView]; for (NSInteger i=0;i<self.categories.count;i++) { UIButton *b=[UIButton buttonWithType:UIButtonTypeCustom]; b.tag=3000+i; b.layer.cornerRadius=7; b.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft; b.contentEdgeInsets=UIEdgeInsetsMake(0,8,0,3); [b setImage:ZNSymbol(self.categorySymbols[i],12.5,UIImageSymbolWeightSemibold) forState:UIControlStateNormal]; [b setTitle:[NSString stringWithFormat:@"  %@",self.categories[i]] forState:UIControlStateNormal]; [b addTarget:self action:@selector(categoryTapped:) forControlEvents:UIControlEventTouchUpInside]; [self.sidebarView addSubview:b]; [self.sidebarButtons addObject:b]; }
    self.contentScroll=[UIScrollView new]; self.contentScroll.showsVerticalScrollIndicator=YES; [self.panel addSubview:self.contentScroll]; self.contentView=[UIView new]; [self.contentScroll addSubview:self.contentView]; self.footerView=[UIView new]; [self.panel addSubview:self.footerView]; self.footerLabel=[self label:@"" size:8.8 weight:UIFontWeightRegular color:self.theme.secondaryTextColor]; [self.footerView addSubview:self.footerLabel];
    self.panel.hidden=YES; [window addSubview:self.floatButton]; [window addSubview:self.panel]; self.uiReady=YES; [self layoutForWindow:window initial:YES]; [self applyTheme]; self.footerLabel.text=[NSString stringWithFormat:@"UnityFramework    Runtime 0.2.4    iOS %@",UIDevice.currentDevice.systemVersion]; NSLog(@"[ZonoePatch v0.2.4] UI ready compact=%d theme=%@ category=%ld",self.compactMode,[ZNTheme nameForMode:self.themeMode],(long)self.selectedCategory);
}

- (void)attach:(UIWindow *)window { if (!window||!self.uiReady) return; [self.floatButton removeFromSuperview]; [self.panel removeFromSuperview]; [window addSubview:self.floatButton]; [window addSubview:self.panel]; self.hostWindow=window; [self layoutForWindow:window initial:NO]; [self applyTheme]; }
- (void)tick:(NSTimer *)timer { (void)timer; UIWindow *w=[self currentWindow]; if(!w)return; if(!self.uiReady){[self makeUI:w];return;} if(self.hostWindow!=w||self.panel.superview!=w||self.floatButton.superview!=w)[self attach:w]; if(!CGRectEqualToRect(self.lastBounds,w.bounds)||!UIEdgeInsetsEqualToEdgeInsets(self.lastInsets,w.safeAreaInsets))[self layoutForWindow:w initial:NO]; if(self.themeMode==ZNThemeModeSystem&&[self interfaceStyle]!=self.lastStyle)[self applyTheme]; [w bringSubviewToFront:self.panel]; [w bringSubviewToFront:self.floatButton]; }
- (void)start { if(!self.timer){[self tick:nil]; self.timer=[NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(tick:) userInfo:nil repeats:YES];} self.floatButton.hidden=NO; }
- (void)show { if(!self.uiReady)[self tick:nil]; if(!self.uiReady)return; self.floatButton.hidden=NO; self.panel.hidden=NO; }
- (void)hide { self.panel.hidden=YES; }
- (BOOL)isVisible { return self.uiReady&&!self.panel.hidden; }
- (void)togglePanel:(id)sender { (void)sender; self.panel.hidden=!self.panel.hidden; }

- (void)modeTapped:(id)sender { (void)sender; self.compactMode=!self.compactMode; [NSUserDefaults.standardUserDefaults setBool:self.compactMode forKey:kZNCompactModeKey]; [self layoutForWindow:self.hostWindow initial:NO]; [self applyTheme]; }
- (void)closeTapped:(id)sender { (void)sender; self.panel.hidden=YES; self.floatButton.hidden=NO; }
- (void)themeTapped:(id)sender { (void)sender; if(self.compactMode)return; self.selectedCategory=kZNThemeCategoryIndex; [NSUserDefaults.standardUserDefaults setInteger:self.selectedCategory forKey:kZNSelectedCategoryKey]; self.contentScroll.contentOffset=CGPointZero; [self layoutForWindow:self.hostWindow initial:NO]; [self updateSidebar]; [self renderPage]; }
- (void)themeGridTapped:(UIButton *)sender { NSInteger idx=sender.tag-8000; if(idx<ZNThemeModeSystem||idx>=ZNThemeModeCount)return; self.themeMode=(ZNThemeMode)idx; [NSUserDefaults.standardUserDefaults setInteger:self.themeMode forKey:kZNThemeModeKey]; [self applyTheme]; }
- (void)categoryTapped:(UIButton *)sender { NSInteger idx=sender.tag-3000; if(idx<0||idx>=self.categories.count)return; self.selectedCategory=idx; [NSUserDefaults.standardUserDefaults setInteger:idx forKey:kZNSelectedCategoryKey]; self.contentScroll.contentOffset=CGPointZero; [self layoutForWindow:self.hostWindow initial:NO]; [self updateSidebar]; [self renderPage]; }
- (void)featureSwitchChanged:(UISwitch *)sender { NSString *fid=sender.accessibilityIdentifier; if(fid.length)[self setFeature:fid enabled:sender.isOn]; }
- (void)featureSliderChanged:(UISlider *)slider { NSString *fid=slider.accessibilityIdentifier; if(!fid.length)return; [self setFeature:fid value:slider.value]; UILabel *a=[slider.superview viewWithTag:6201]; UILabel *b=[slider.superview viewWithTag:7201]; if(a)a.text=[NSString stringWithFormat:@"[ %.1fx ]",slider.value]; if(b)b.text=[NSString stringWithFormat:@"[%.1fx]",slider.value]; }
- (void)alphaSliderChanged:(UISlider *)slider { self.menuAlpha=ZNClamp(slider.value,0.55,1.0); self.panel.alpha=self.menuAlpha; [NSUserDefaults.standardUserDefaults setDouble:self.menuAlpha forKey:kZNMenuAlphaKey]; UILabel *v=[slider.superview viewWithTag:6401]; if(v)v.text=[NSString stringWithFormat:@"%.0f%%",self.menuAlpha*100]; }
- (void)autoSnapChanged:(UISwitch *)sender { self.autoSnap=sender.isOn; [NSUserDefaults.standardUserDefaults setBool:self.autoSnap forKey:kZNAutoSnapKey]; }
- (void)rememberPositionChanged:(UISwitch *)sender { self.rememberPosition=sender.isOn; [NSUserDefaults.standardUserDefaults setBool:self.rememberPosition forKey:kZNRememberPositionKey]; if(!self.rememberPosition){[NSUserDefaults.standardUserDefaults removeObjectForKey:kZNFloatPositionKey];[NSUserDefaults.standardUserDefaults removeObjectForKey:kZNPanelPositionKey];} }

- (void)panFloat:(UIPanGestureRecognizer *)g {
    CGPoint tr=[g translationInView:self.hostWindow], c=self.floatButton.center; c.x+=tr.x; c.y+=tr.y; self.floatButton.center=[self clampFloat:c window:self.hostWindow]; [g setTranslation:CGPointZero inView:self.hostWindow];
    if(g.state==UIGestureRecognizerStateEnded||g.state==UIGestureRecognizerStateCancelled){ if(self.autoSnap){UIEdgeInsets s=self.hostWindow.safeAreaInsets;CGFloat h=kZNFloatSize*0.5;CGFloat left=s.left+kZNMargin+h,right=CGRectGetWidth(self.hostWindow.bounds)-s.right-kZNMargin-h;CGPoint target=self.floatButton.center;target.x=(target.x<CGRectGetMidX(self.hostWindow.bounds))?left:right;[UIView animateWithDuration:0.18 animations:^{self.floatButton.center=target;} completion:^(BOOL finished){(void)finished;if(self.rememberPosition)[NSUserDefaults.standardUserDefaults setObject:NSStringFromCGPoint(self.floatButton.center) forKey:kZNFloatPositionKey];}];} else if(self.rememberPosition)[NSUserDefaults.standardUserDefaults setObject:NSStringFromCGPoint(self.floatButton.center) forKey:kZNFloatPositionKey]; }
}
- (void)panPanel:(UIPanGestureRecognizer *)g { CGPoint tr=[g translationInView:self.hostWindow],c=self.panel.center;c.x+=tr.x;c.y+=tr.y;self.panel.center=[self clampPanel:c window:self.hostWindow];[g setTranslation:CGPointZero inView:self.hostWindow];if((g.state==UIGestureRecognizerStateEnded||g.state==UIGestureRecognizerStateCancelled)&&self.rememberPosition)[NSUserDefaults.standardUserDefaults setObject:NSStringFromCGPoint(self.panel.center) forKey:kZNPanelPositionKey]; }

@end

extern "C" __attribute__((visibility("default"))) uint32_t ZonoePatchGetAPIVersion(void){return 1;}
extern "C" __attribute__((visibility("default"))) const char *ZonoePatchGetVersion(void){return "0.2.4-ui";}
extern "C" __attribute__((visibility("default"))) void ZonoePatchStart(void){dispatch_async(dispatch_get_main_queue(),^{[[ZNRuntimeMenuControllerV024 shared] start];});}
extern "C" __attribute__((visibility("default"))) void ZonoePatchShow(void){dispatch_async(dispatch_get_main_queue(),^{[[ZNRuntimeMenuControllerV024 shared] show];});}
extern "C" __attribute__((visibility("default"))) void ZonoePatchHide(void){dispatch_async(dispatch_get_main_queue(),^{[[ZNRuntimeMenuControllerV024 shared] hide];});}
extern "C" __attribute__((visibility("default"))) bool ZonoePatchIsVisible(void){__block BOOL v=NO;if(NSThread.isMainThread)return [[ZNRuntimeMenuControllerV024 shared] isVisible];dispatch_sync(dispatch_get_main_queue(),^{v=[[ZNRuntimeMenuControllerV024 shared] isVisible];});return v;}

__attribute__((constructor)) static void ZNRuntimeMenuBootstrapV024(void){@autoreleasepool{NSLog(@"[ZonoePatch v0.2.4] dylib loaded");ZonoePatchStart();}}
