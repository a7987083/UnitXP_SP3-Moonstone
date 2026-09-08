// Zonoe Runtime Patch Menu — consolidated current source
// v0.5.0 source consolidation baseline
// Historical V0xx menu sources are retained by Git history only; this file is
// the sole compiled menu/UI source. ZNDeveloperGate provides permission state
// only and never owns sidebar/UI definitions.

// BEGIN inlined ZonoeRuntimeMenuV048.mm
// BEGIN inlined ZonoeRuntimeMenuV045.mm
// BEGIN inlined ZonoeRuntimeMenuV044.mm
// BEGIN inlined ZonoeRuntimeMenuV043.mm
// BEGIN inlined ZonoeRuntimeMenuV042.mm
// BEGIN inlined ZonoeRuntimeMenuV0402.mm
// BEGIN inlined ZonoeRuntimeMenuV0401.mm
// BEGIN inlined ZonoeRuntimeMenuV040.mm
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "ZNPatchCore.h"
#import "ZNDeveloperGate.h"
#import "ZNIL2CPPResolver.h"

static void ZNInstallV040Swizzles(void);

__attribute__((constructor(101))) static void ZNRuntimeCoreBootstrapV040(void) {
    @autoreleasepool {
        [ZNPatchManager sharedManager];
        [[ZNDeveloperGate sharedGate] refresh];
        [[ZNIL2CPPResolver sharedResolver] refresh];
        ZNInstallV040Swizzles();
        [[ZNRuntimeLogger sharedLogger] log:@"Runtime Patch Menu 0.5.0 consolidated bootstrap（Stock iOS / No JIT）"];
    }
}

// v0.2.4 visual primitives remain embedded as the immutable visual baseline. v0.5 only layers runtime core,
// developer diagnostics and resolver state over it.
#define ZNRuntimeMenuControllerV024 ZNRuntimeMenuControllerV040
#define ZonoePatchGetAPIVersion ZonoePatchGetAPIVersionBaselineV024
#define ZonoePatchGetVersion ZonoePatchGetVersionBaselineV024
#define ZonoePatchStart ZonoePatchStartBaselineV024
#define ZonoePatchShow ZonoePatchShowBaselineV024
#define ZonoePatchHide ZonoePatchHideBaselineV024
#define ZonoePatchIsVisible ZonoePatchIsVisibleBaselineV024
#define ZNRuntimeMenuBootstrapV024 ZNRuntimeMenuBootstrapBaselineV024
// BEGIN inlined ZonoeRuntimeMenuV024.mm
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
- (void)themeTapped:(id)sender { (void)sender; if(self.compactMode)return; NSInteger idx=[self.categories indexOfObject:@"主题"]; if(idx==NSNotFound)return; self.selectedCategory=idx; [NSUserDefaults.standardUserDefaults setInteger:self.selectedCategory forKey:kZNSelectedCategoryKey]; self.contentScroll.contentOffset=CGPointZero; [self layoutForWindow:self.hostWindow initial:NO]; [self updateSidebar]; [self renderPage]; }
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
// END inlined ZonoeRuntimeMenuV024.mm
#undef ZNRuntimeMenuControllerV024
#undef ZonoePatchGetAPIVersion
#undef ZonoePatchGetVersion
#undef ZonoePatchStart
#undef ZonoePatchShow
#undef ZonoePatchHide
#undef ZonoePatchIsVisible
#undef ZNRuntimeMenuBootstrapV024

@interface ZNRuntimeMenuControllerV040 (V040Private)
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIFont *)menuFont:(CGFloat)size weight:(UIFontWeight)weight;
- (void)addSection:(NSString *)title subtitle:(NSString *)subtitle y:(CGFloat *)y width:(CGFloat)width;
- (void)layoutSidebar;
- (void)updateSidebar;
- (void)renderPage;
@end

@interface ZNRuntimeMenuControllerV040 (V040)
- (instancetype)zn40_init;
- (BOOL)zn40_enabledForFeature:(NSString *)featureID;
- (void)zn40_setFeature:(NSString *)featureID enabled:(BOOL)enabled;
- (CGFloat)zn40_valueForFeature:(NSString *)featureID fallback:(CGFloat)fallback;
- (void)zn40_setFeature:(NSString *)featureID value:(CGFloat)value;
- (void)zn40_renderFullPage;
- (CGSize)zn40_fullSizeForWindow:(UIWindow *)window;
- (void)zn40_tick:(NSTimer *)timer;
- (void)zn40_makeUI:(UIWindow *)window;
- (void)zn40_togglePanel:(id)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (V040)

- (instancetype)zn40_init {
    id obj = [self zn40_init];
    if (!obj) return nil;
    [ZNPatchManager sharedManager];
    [[ZNDeveloperGate sharedGate] refresh];
    [self zn40_refreshDeveloperCategories:NO];
    return obj;
}

- (BOOL)zn40_enabledForFeature:(NSString *)featureID {
    return [[ZNPatchManager sharedManager] enabledForFeature:featureID];
}

- (void)zn40_setFeature:(NSString *)featureID enabled:(BOOL)enabled {
    [[ZNPatchManager sharedManager] setFeature:featureID enabled:enabled];
}

- (CGFloat)zn40_valueForFeature:(NSString *)featureID fallback:(CGFloat)fallback {
    return (CGFloat)[[ZNPatchManager sharedManager] valueForFeature:featureID fallback:fallback];
}

- (void)zn40_setFeature:(NSString *)featureID value:(CGFloat)value {
    [[ZNPatchManager sharedManager] setFeature:featureID value:value];
}

- (NSArray<NSString *> *)zn40_baseCategories {
    NSMutableArray<NSString *> *items = [NSMutableArray arrayWithObject:@"功能"];
    if ([ZNDeveloperGate sharedGate].otherAuthorized) [items addObject:@"其他"];
    [items addObjectsFromArray:@[@"设置", @"主题"]];
    return items;
}

- (NSArray<NSString *> *)zn40_baseSymbols {
    NSMutableArray<NSString *> *items = [NSMutableArray arrayWithObject:@"switch.2"];
    if ([ZNDeveloperGate sharedGate].otherAuthorized) [items addObject:@"square.grid.2x2.fill"];
    [items addObjectsFromArray:@[@"gearshape.fill", @"paintpalette.fill"]];
    return items;
}

- (void)zn40_refreshDeveloperCategories:(BOOL)force {
    ZNDeveloperGate *gate = [ZNDeveloperGate sharedGate];
    NSMutableArray<NSString *> *cats = [[self zn40_baseCategories] mutableCopy];
    NSMutableArray<NSString *> *symbols = [[self zn40_baseSymbols] mutableCopy];
    if (gate.authorized) {
        [cats addObject:@"诊断"];
        [symbols addObject:@"stethoscope"];
        [cats addObject:@"Debug"];
        [symbols addObject:@"ladybug.fill"];
    }
    if (!force && [self.categories isEqualToArray:cats]) return;

    NSString *oldCategory = (self.selectedCategory >= 0 && self.selectedCategory < self.categories.count) ? self.categories[self.selectedCategory] : @"功能";
    self.categories = cats;
    self.categorySymbols = symbols;
    NSInteger newIndex = [cats indexOfObject:oldCategory];
    if (newIndex == NSNotFound) newIndex = 0;
    self.selectedCategory = newIndex;
    [NSUserDefaults.standardUserDefaults setInteger:self.selectedCategory forKey:@"ZonoePatch.SelectedCategory"];

    if (!self.uiReady || !self.sidebarView) return;
    for (UIButton *button in [self.sidebarButtons copy]) [button removeFromSuperview];
    [self.sidebarButtons removeAllObjects];
    for (NSInteger i=0; i<self.categories.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.tag = 3000+i;
        b.layer.cornerRadius = 7;
        b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        b.contentEdgeInsets = UIEdgeInsetsMake(0,8,0,3);
        [b setImage:ZNSymbol(self.categorySymbols[i],12.5,UIImageSymbolWeightSemibold) forState:UIControlStateNormal];
        [b setTitle:[NSString stringWithFormat:@"  %@",self.categories[i]] forState:UIControlStateNormal];
        [b addTarget:self action:@selector(categoryTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.sidebarView addSubview:b];
        [self.sidebarButtons addObject:b];
    }
    [self layoutSidebar];
    [self updateSidebar];
    [self renderPage];
}

- (void)zn40_updateSubtitle {
    if (!self.uiReady || !self.subtitleLabel) return;
    NSString *value = [ZNDeveloperGate sharedGate].observedUDID ?: @"";
    self.subtitleLabel.text = value.length ? value : @"";
    self.subtitleLabel.adjustsFontSizeToFitWidth = YES;
    self.subtitleLabel.minimumScaleFactor = 0.42;
    self.subtitleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
}

- (void)zn40_makeUI:(UIWindow *)window {
    [self zn40_makeUI:window];
    [self zn40_refreshDeveloperCategories:YES];
    [self zn40_updateSubtitle];
    self.footerLabel.text = [NSString stringWithFormat:@"PatchCore 0.4.0    No JIT    iOS %@", UIDevice.currentDevice.systemVersion];
}

- (void)zn40_tick:(NSTimer *)timer {
    [self zn40_tick:timer];
    [[ZNDeveloperGate sharedGate] refresh];
    [self zn40_refreshDeveloperCategories:NO];
    [self zn40_updateSubtitle];
    if (self.uiReady) self.footerLabel.text = [NSString stringWithFormat:@"PatchCore 0.4.0    No JIT    iOS %@", UIDevice.currentDevice.systemVersion];
}

- (void)zn40_togglePanel:(id)sender {
    [[ZNDeveloperGate sharedGate] refresh];
    [self zn40_refreshDeveloperCategories:NO];
    [self zn40_togglePanel:sender];
    [self zn40_updateSubtitle];
}

- (CGSize)zn40_fullSizeForWindow:(UIWindow *)window {
    CGSize size = [self zn40_fullSizeForWindow:window];
    NSString *cat = (self.selectedCategory >= 0 && self.selectedCategory < self.categories.count) ? self.categories[self.selectedCategory] : @"";
    if ([cat isEqualToString:@"诊断"] || [cat isEqualToString:@"Debug"]) {
        UIEdgeInsets insets = window.safeAreaInsets;
        CGFloat available = CGRectGetHeight(window.bounds)-insets.top-insets.bottom-20.0;
        size.height = MIN(MAX(size.height, 470.0), MAX(300.0, available));
    }
    return size;
}

- (void)zn40_updateContentHeight:(CGFloat)y {
    CGRect frame = self.contentView.frame;
    frame.size.height = MAX(CGRectGetHeight(self.contentScroll.bounds), y+8.0);
    self.contentView.frame = frame;
    self.contentScroll.contentSize = frame.size;
}

- (void)zn40_addInfoCard:(NSString *)title lines:(NSArray<NSString *> *)lines y:(CGFloat *)y width:(CGFloat)width {
    CGFloat lineH = 17.0;
    CGFloat h = 30.0 + lineH*lines.count + 8.0;
    UIView *card = [self cardAtY:*y height:h width:width compact:NO];
    UILabel *t = [self label:title size:12.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    t.frame = CGRectMake(13,7,card.bounds.size.width-26,19);
    [card addSubview:t];
    CGFloat ly = 28.0;
    for (NSString *line in lines) {
        UILabel *l = [self label:line size:9.8 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        l.frame = CGRectMake(13,ly,card.bounds.size.width-26,lineH);
        l.adjustsFontSizeToFitWidth = YES;
        l.minimumScaleFactor = 0.65;
        [card addSubview:l];
        ly += lineH;
    }
    [self.contentView addSubview:card];
    *y += h+8.0;
}

- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = frame;
    b.backgroundColor = self.theme.controlColor;
    b.tintColor = self.theme.accentColor;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:self.theme.primaryTextColor forState:UIControlStateNormal];
    b.titleLabel.font = [self menuFont:10.5 weight:UIFontWeightSemibold];
    b.layer.cornerRadius = 8;
    b.layer.borderWidth = 1;
    b.layer.borderColor = self.theme.borderColor.CGColor;
    [b addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)zn40_addActionCardY:(CGFloat *)y width:(CGFloat)width titles:(NSArray<NSString *> *)titles selectors:(NSArray<NSString *> *)selectors {
    UIView *card = [self cardAtY:*y height:54 width:width compact:NO];
    CGFloat gap = 8.0;
    CGFloat inner = card.bounds.size.width-26.0;
    CGFloat bw = (inner-gap*(titles.count-1))/MAX((CGFloat)titles.count,1.0);
    for (NSInteger i=0; i<titles.count; i++) {
        CGRect f = CGRectMake(13+i*(bw+gap),10,bw,34);
        [card addSubview:[self zn40_button:titles[i] selector:NSSelectorFromString(selectors[i]) frame:f]];
    }
    [self.contentView addSubview:card];
    *y += 62.0;
}

- (void)zn40_replaceHomeVersionText {
    for (UIView *view in self.contentView.subviews) {
        if (![view isKindOfClass:UILabel.class]) continue;
        UILabel *label = (UILabel *)view;
        if ([label.text hasPrefix:@"V0.2.4 UI"]) label.text = @"V0.4.0 Runtime Foundation · No JIT";
    }
}

- (NSArray<NSString *> *)zn40_nonEmptyLines:(NSString *)text {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) if (line.length) [out addObject:line];
    return out;
}

- (void)zn40_renderDiagnostics {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width = CGRectGetWidth(self.contentView.bounds), y = 9.0;
    ZNDeveloperGate *gate = [ZNDeveloperGate sharedGate];
    ZNPatchManager *pm = [ZNPatchManager sharedManager];
    NSDictionary *counts = pm.stateCounts;
    NSDictionary *main = [ZNModuleManager sharedManager].mainExecutable;
    NSDictionary *unity = [ZNModuleManager sharedManager].unityFramework;
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"未知";
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"未知";

    [self addSection:@"运行时诊断" subtitle:@"v0.4.0 Foundation · Stock iOS / 未越狱 / No JIT" y:&y width:width];
    [self zn40_addInfoCard:@"运行环境" lines:@[
        @"状态：基础层已就绪",
        @"核心版本：0.4.0-runtime-foundation    API：2",
        [NSString stringWithFormat:@"Bundle：%@    App：%@",bundle,version],
        [NSString stringWithFormat:@"系统：iOS %@",UIDevice.currentDevice.systemVersion],
        @"JIT：不依赖    越狱：不依赖"
    ] y:&y width:width];

    NSString *mainLine = main ? [NSString stringWithFormat:@"主程序：%@    base=0x%llx",main[@"name"],[main[@"base"] unsignedLongLongValue]] : @"主程序：未找到";
    NSString *unityLine = unity ? [NSString stringWithFormat:@"UnityFramework：已加载    base=0x%llx",[unity[@"base"] unsignedLongLongValue]] : @"UnityFramework：未加载";
    [self zn40_addInfoCard:@"模块解析" lines:@[mainLine,unityLine,[NSString stringWithFormat:@"已加载镜像：%lu",(unsigned long)[ZNModuleManager sharedManager].loadedImages.count],[NSString stringWithFormat:@"模块代数：%llu",[ZNModuleManager sharedManager].moduleGeneration]] y:&y width:width];

    [self zn40_addInfoCard:@"开发者标记" lines:@[
        [NSString stringWithFormat:@"状态：%@",gate.authorized?@"已启用":@"未启用"],
        [NSString stringWithFormat:@"来源：%@",gate.sourceDescription],
        [NSString stringWithFormat:@"文件：%@",gate.markerPath.length?gate.markerPath:@"未找到"],
        [NSString stringWithFormat:@"附加值：%@",gate.observedUDID.length?[gate maskedUDID:gate.observedUDID]:@"空白（允许）"],
        @"外部 UDID 获取：已禁用"
    ] y:&y width:width];

    [self zn40_addInfoCard:@"Feature / Action" lines:@[
        [NSString stringWithFormat:@"Feature：%@    Action：%lu",counts[@"registered"],(unsigned long)pm.actionCount],
        [NSString stringWithFormat:@"已启用：%@    已关闭：%@",counts[@"enabled"],counts[@"disabled"]],
        [NSString stringWithFormat:@"等待模块：%@    不支持：%@    失败：%@",counts[@"waiting"],counts[@"unsupported"],counts[@"failed"]],
        @"执行器：Foundation（本版本只建立模型与解析，不写真实 Patch）"
    ] y:&y width:width];

    [self zn40_addInfoCard:@"IL2CPP Resolver" lines:[self zn40_nonEmptyLines:[[ZNIL2CPPResolver sharedResolver] diagnosticReport]] y:&y width:width];
    [self zn40_addActionCardY:&y width:width titles:@[@"刷新目标解析",@"复制诊断信息"] selectors:@[@"zn40_refreshTargets:",@"zn40_copyDiagnostics:"]];
    [self zn40_addActionCardY:&y width:width titles:@[@"重新检测标记",@"运行基础自检"] selectors:@[@"zn40_validateMarker:",@"zn40_selfTest:"]];
    [self zn40_updateContentHeight:y];
}

- (void)zn40_renderDebug {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width = CGRectGetWidth(self.contentView.bounds), y = 9.0;
    ZNDeveloperGate *gate = [ZNDeveloperGate sharedGate];
    [self addSection:@"Debug" subtitle:@"Feature / Action / 模块 / IL2CPP / 最近日志" y:&y width:width];

    [self zn40_addInfoCard:@"标记状态" lines:@[
        [NSString stringWithFormat:@"标记文件：%@",gate.markerPath.length?gate.markerPath:@"未找到"],
        [NSString stringWithFormat:@"第一行 g：%@",gate.authorized?@"有效":@"无效"],
        [NSString stringWithFormat:@"第二行附加值：%@",gate.observedUDID.length?@"已提供":@"未提供"],
        @"Host Bridge：已禁用",
        @"Local Ticket：已禁用"
    ] y:&y width:width];

    NSMutableArray<NSString *> *featureLines = [NSMutableArray array];
    for (ZNPatchDescriptor *d in [ZNPatchManager sharedManager].allDescriptors) {
        [featureLines addObject:[NSString stringWithFormat:@"%@ · %@ · %@ · value=%.2f · actions=%lu",d.identifier,ZNStringForPatchState(d.state),ZNStringForControlType(d.controlType),d.value,(unsigned long)d.actions.count]];
    }
    [self zn40_addInfoCard:@"Feature 描述" lines:featureLines y:&y width:width];

    NSArray<NSString *> *logs = [[ZNRuntimeLogger sharedLogger] recentLines:10];
    if (!logs.count) logs = @[@"暂无运行日志"];
    [self zn40_addInfoCard:@"最近日志" lines:logs y:&y width:width];
    [self zn40_addActionCardY:&y width:width titles:@[@"刷新目标解析",@"清空日志"] selectors:@[@"zn40_refreshTargets:",@"zn40_clearLogs:"]];
    [self zn40_updateContentHeight:y];
}

- (void)zn40_renderFullPage {
    NSString *cat = (self.selectedCategory >= 0 && self.selectedCategory < self.categories.count) ? self.categories[self.selectedCategory] : @"";
    if ([cat isEqualToString:@"诊断"]) { [self zn40_renderDiagnostics]; return; }
    if ([cat isEqualToString:@"Debug"]) { [self zn40_renderDebug]; return; }
    [self zn40_renderFullPage];
}

- (NSString *)zn40_fullReport {
    NSMutableString *report = [NSMutableString string];
    [report appendString:[[ZNPatchManager sharedManager] diagnosticReport]];
    [report appendString:@"\n"];
    [report appendString:[[ZNDeveloperGate sharedGate] diagnosticReport]];
    NSArray *logs = [[ZNRuntimeLogger sharedLogger] recentLines:20];
    if (logs.count) {
        [report appendString:@"\n最近日志:\n"];
        [report appendString:[logs componentsJoinedByString:@"\n"]];
        [report appendString:@"\n"];
    }
    return report;
}

- (void)zn40_refreshTargets:(id)sender {
    (void)sender;
    [[ZNPatchManager sharedManager] refreshResolution];
    [self renderPage];
}

- (void)zn40_copyDiagnostics:(id)sender {
    (void)sender;
    UIPasteboard.generalPasteboard.string = [self zn40_fullReport];
    [[ZNRuntimeLogger sharedLogger] log:@"诊断信息已复制"];
    [self renderPage];
}

- (void)zn40_validateMarker:(id)sender {
    (void)sender;
    [[ZNDeveloperGate sharedGate] requestZonoeValidation];
    [self zn40_refreshDeveloperCategories:NO];
    [self renderPage];
}

- (void)zn40_selfTest:(id)sender {
    (void)sender;
    [[ZNPatchManager sharedManager] runSelfTest];
    [self renderPage];
}

- (void)zn40_clearLogs:(id)sender {
    (void)sender;
    [[ZNRuntimeLogger sharedLogger] clear];
    [[ZNRuntimeLogger sharedLogger] log:@"日志已清空"];
    [self renderPage];
}
@end

static void ZNSwapInstanceMethodV040(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a,b);
}

static void ZNInstallV040Swizzles(void) {
    Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
    if (!cls) return;
    ZNSwapInstanceMethodV040(cls,@selector(init),@selector(zn40_init));
    ZNSwapInstanceMethodV040(cls,@selector(enabledForFeature:),@selector(zn40_enabledForFeature:));
    ZNSwapInstanceMethodV040(cls,@selector(setFeature:enabled:),@selector(zn40_setFeature:enabled:));
    ZNSwapInstanceMethodV040(cls,@selector(valueForFeature:fallback:),@selector(zn40_valueForFeature:fallback:));
    ZNSwapInstanceMethodV040(cls,@selector(setFeature:value:),@selector(zn40_setFeature:value:));
    ZNSwapInstanceMethodV040(cls,@selector(renderFullPage),@selector(zn40_renderFullPage));
    ZNSwapInstanceMethodV040(cls,@selector(fullSizeForWindow:),@selector(zn40_fullSizeForWindow:));
    ZNSwapInstanceMethodV040(cls,@selector(tick:),@selector(zn40_tick:));
    ZNSwapInstanceMethodV040(cls,@selector(makeUI:),@selector(zn40_makeUI:));
    ZNSwapInstanceMethodV040(cls,@selector(togglePanel:),@selector(zn40_togglePanel:));
}

extern "C" __attribute__((visibility("default"))) uint32_t ZonoePatchGetAPIVersion(void) { return 2; }
extern "C" __attribute__((visibility("default"))) const char *ZonoePatchGetVersion(void) { return "0.5.0-menu-consolidated"; }
extern "C" __attribute__((visibility("default"))) void ZonoePatchStart(void) {
    [[ZNDeveloperGate sharedGate] refresh];
    [ZNPatchManager sharedManager];
    [[ZNIL2CPPResolver sharedResolver] refresh];
    ZonoePatchStartBaselineV024();
}
extern "C" __attribute__((visibility("default"))) void ZonoePatchShow(void) { ZonoePatchShowBaselineV024(); }
extern "C" __attribute__((visibility("default"))) void ZonoePatchHide(void) { ZonoePatchHideBaselineV024(); }
extern "C" __attribute__((visibility("default"))) bool ZonoePatchIsVisible(void) { return ZonoePatchIsVisibleBaselineV024(); }
// END inlined ZonoeRuntimeMenuV040.mm

// v0.4.0a UI hotfix layer.
// Keep the v0.4.0 runtime foundation unchanged and patch only navigation/touch behavior.

@interface ZNRuntimeMenuControllerV040 (V0401)
- (void)zn401_makeUI:(UIWindow *)window;
- (void)zn401_themeTapped:(id)sender;
- (CGSize)zn401_fullSizeForWindow:(UIWindow *)window;
- (UIButton *)zn401_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
@end

@implementation ZNRuntimeMenuControllerV040 (V0401)


- (void)zn401_makeUI:(UIWindow *)window {
    [self zn401_makeUI:window];
    // UIScrollView defaults to delayed content touches. That makes the diagnostic
    // buttons look as if they only react after a press-and-hold. Disable the delay
    // so a normal tap highlights and dispatches immediately.
    self.contentScroll.delaysContentTouches = NO;
    self.contentScroll.canCancelContentTouches = YES;
}

- (void)zn401_themeTapped:(id)sender {
    (void)sender;
    if (self.compactMode) return;
    NSInteger idx = [self.categories indexOfObject:@"主题"];
    if (idx == NSNotFound) return;
    self.selectedCategory = idx;
    [NSUserDefaults.standardUserDefaults setInteger:idx forKey:@"ZonoePatch.SelectedCategory"];
    self.contentScroll.contentOffset = CGPointZero;
    [self layoutForWindow:self.hostWindow initial:NO];
    [self updateSidebar];
    [self renderPage];
}

- (CGSize)zn401_fullSizeForWindow:(UIWindow *)window {
    CGSize size = [self zn401_fullSizeForWindow:window];
    NSString *cat = (self.selectedCategory >= 0 && self.selectedCategory < self.categories.count) ? self.categories[self.selectedCategory] : @"";
    CGFloat desired = size.height;
    if ([cat isEqualToString:@"其他"]) desired = 340.0;
    else if ([cat isEqualToString:@"设置"]) desired = 415.0;
    else if ([cat isEqualToString:@"主题"]) {
        BOOL landscape = CGRectGetWidth(window.bounds) >= CGRectGetHeight(window.bounds);
        desired = landscape ? 410.0 : 430.0;
    } else if ([cat isEqualToString:@"诊断"] || [cat isEqualToString:@"Debug"]) {
        desired = MAX(desired, 470.0);
    }
    UIEdgeInsets insets = window.safeAreaInsets;
    CGFloat available = MAX(300.0, CGRectGetHeight(window.bounds)-insets.top-insets.bottom-20.0);
    size.height = MIN(desired, available);
    return size;
}

- (UIButton *)zn401_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame {
    UIButton *button = [self zn401_button:title selector:selector frame:frame];
    button.showsTouchWhenHighlighted = YES;
    button.exclusiveTouch = YES;
    return button;
}

@end

static void ZNSwapInstanceMethodV0401(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

__attribute__((constructor(102))) static void ZNInstallV0401UIFixes(void) {
    @autoreleasepool {
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNSwapInstanceMethodV0401(cls, @selector(makeUI:), @selector(zn401_makeUI:));
        ZNSwapInstanceMethodV0401(cls, @selector(themeTapped:), @selector(zn401_themeTapped:));
        ZNSwapInstanceMethodV0401(cls, @selector(fullSizeForWindow:), @selector(zn401_fullSizeForWindow:));
        ZNSwapInstanceMethodV0401(cls, @selector(zn40_button:selector:frame:), @selector(zn401_button:selector:frame:));
        [[ZNRuntimeLogger sharedLogger] log:@"UI touch/theme fixes installed; sidebar ownership remains centralized in ZonoeRuntimeMenu.mm"];
    }
}
// END inlined ZonoeRuntimeMenuV0401.mm

// v0.4.0b touch-policy scope fix.
// Diagnostic/Debug pages keep immediate button response; all other pages restore
// UIScrollView's delayed-touch behavior so theme grids and sliders scroll normally.

@interface ZNRuntimeMenuControllerV040 (V0402)
- (void)zn402_applyTouchPolicy;
- (void)zn402_makeUI:(UIWindow *)window;
- (void)zn402_renderPage;
@end

@implementation ZNRuntimeMenuControllerV040 (V0402)

- (void)zn402_applyTouchPolicy {
    NSString *cat = (self.selectedCategory >= 0 && self.selectedCategory < self.categories.count)
        ? self.categories[self.selectedCategory]
        : @"";
    BOOL developerPage = [cat isEqualToString:@"诊断"] || [cat isEqualToString:@"Debug"];

    // Developer pages: buttons should highlight/dispatch immediately.
    // Normal pages (especially 主题): restore UIScrollView's gesture arbitration.
    self.contentScroll.delaysContentTouches = !developerPage;
    self.contentScroll.canCancelContentTouches = YES;
}

- (void)zn402_makeUI:(UIWindow *)window {
    [self zn402_makeUI:window];
    [self zn402_applyTouchPolicy];
}

- (void)zn402_renderPage {
    [self zn402_applyTouchPolicy];
    [self zn402_renderPage];
}

@end

static void ZNSwapInstanceMethodV0402(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

__attribute__((constructor(103))) static void ZNInstallV0402TouchPolicyFix(void) {
    @autoreleasepool {
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNSwapInstanceMethodV0402(cls, @selector(makeUI:), @selector(zn402_makeUI:));
        ZNSwapInstanceMethodV0402(cls, @selector(renderPage), @selector(zn402_renderPage));
        [[ZNRuntimeLogger sharedLogger] log:@"v0.4.0b touch policy installed：诊断/Debug 即时触摸，其余页面恢复滚动优先"];
    }
}
// END inlined ZonoeRuntimeMenuV0402.mm
#import "ZNExecutablePageProbe.h"

// v0.4.2 UI/diagnostics layer:
// - diagnostic/debug info rows wrap instead of shrinking/truncating
// - the existing self-test button also runs the real __TEXT RX->RW->RX probe

@interface ZNRuntimeMenuControllerV040 (V042)
- (void)zn42_addInfoCard:(NSString *)title lines:(NSArray<NSString *> *)lines y:(CGFloat *)y width:(CGFloat)width;
- (void)zn42_selfTest:(id)sender;
- (void)zn42_makeUI:(UIWindow *)window;
@end

@implementation ZNRuntimeMenuControllerV040 (V042)

- (void)zn42_addInfoCard:(NSString *)title lines:(NSArray<NSString *> *)lines y:(CGFloat *)y width:(CGFloat)width {
    CGFloat cardWidth = MAX(0.0, width - 20.0);
    CGFloat textWidth = MAX(20.0, cardWidth - 26.0);
    UIFont *font = [self menuFont:9.8 weight:UIFontWeightRegular];
    NSMutableArray<NSNumber *> *heights = [NSMutableArray arrayWithCapacity:lines.count];
    CGFloat bodyHeight = 0.0;

    for (NSString *line in lines) {
        CGRect r = [line boundingRectWithSize:CGSizeMake(textWidth, CGFLOAT_MAX)
                                      options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                   attributes:@{NSFontAttributeName:font}
                                      context:nil];
        CGFloat h = MAX(17.0, ceil(CGRectGetHeight(r)) + 3.0);
        [heights addObject:@(h)];
        bodyHeight += h;
    }

    CGFloat h = 30.0 + bodyHeight + 8.0;
    UIView *card = [self cardAtY:*y height:h width:width compact:NO];
    UILabel *t = [self label:title size:12.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    t.frame = CGRectMake(13,7,card.bounds.size.width-26,19);
    [card addSubview:t];

    CGFloat ly = 28.0;
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *line = lines[i];
        CGFloat lineHeight = heights[i].doubleValue;
        UILabel *l = [self label:line size:9.8 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        l.frame = CGRectMake(13, ly, card.bounds.size.width-26, lineHeight);
        l.numberOfLines = 0;
        l.lineBreakMode = NSLineBreakByWordWrapping;
        l.adjustsFontSizeToFitWidth = NO;
        [card addSubview:l];
        ly += lineHeight;
    }

    [self.contentView addSubview:card];
    *y += h + 8.0;
}

- (void)zn42_selfTest:(id)sender {
    [self zn42_selfTest:sender];
    CFAbsoluteTime begin = CFAbsoluteTimeGetCurrent();
    BOOL supported = [[ZNExecutablePageProbe sharedProbe] runProbe];
    double totalMs = (CFAbsoluteTimeGetCurrent() - begin) * 1000.0;
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[probe][%@] __TEXT RX→RW→RX %@ total=%.2fms detail=%@",
                                         NSThread.isMainThread?@"main":@"bg",
                                         supported?@"PASS":@"UNSUPPORTED/FAIL",
                                         totalMs,
                                         [ZNExecutablePageProbe sharedProbe].lastResult ?: @""]];
    [self renderPage];
}

- (void)zn42_makeUI:(UIWindow *)window {
    [self zn42_makeUI:window];
    self.footerLabel.text = [NSString stringWithFormat:@"PatchCore 0.4.2    No JIT    iOS %@", UIDevice.currentDevice.systemVersion];
}

@end

static void ZNSwapInstanceMethodV042(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

__attribute__((constructor(105))) static void ZNInstallV042MenuDiagnostics(void) {
    @autoreleasepool {
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNSwapInstanceMethodV042(cls, @selector(zn40_addInfoCard:lines:y:width:), @selector(zn42_addInfoCard:lines:y:width:));
        ZNSwapInstanceMethodV042(cls, @selector(zn40_selfTest:), @selector(zn42_selfTest:));
        ZNSwapInstanceMethodV042(cls, @selector(makeUI:), @selector(zn42_makeUI:));
        [[ZNRuntimeLogger sharedLogger] log:@"[bootstrap][main] v0.4.2 diagnostics UI installed: wrap=ON executableProbe=ON"];
    }
}
// END inlined ZonoeRuntimeMenuV042.mm
#import "ZNPatchRuntimeValidator.h"

// v0.4.3 developer runtime-validation layer.
// The production target remains stock iOS / No-JIT. This page is a developer
// verification tool for the user's capable test device: it captures live OFF
// bytes, applies one temporary code patch, verifies it, and restores exactly.

static UIViewController *ZN43TopController(UIWindow *window) {
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if ([vc isKindOfClass:UINavigationController.class]) vc = ((UINavigationController *)vc).visibleViewController ?: vc;
    if ([vc isKindOfClass:UITabBarController.class]) vc = ((UITabBarController *)vc).selectedViewController ?: vc;
    return vc;
}

static NSString *ZN43HexString(NSData *data) {
    if (!data.length) return @"";
    const uint8_t *p = (const uint8_t *)data.bytes;
    NSMutableString *s = [NSMutableString stringWithCapacity:data.length * 2];
    for (NSUInteger i = 0; i < data.length; i++) [s appendFormat:@"%02X", p[i]];
    return s;
}

// Methods implemented by the included v0.4.0/v0.4.2 layers. Keep these in a
// declaration-only category so Clang does not treat them as missing V043 methods.
@interface ZNRuntimeMenuControllerV040 (V043BaseMethods)
- (void)zn40_addInfoCard:(NSString *)title lines:(NSArray<NSString *> *)lines y:(CGFloat *)y width:(CGFloat)width;
- (void)zn40_addActionCardY:(CGFloat *)y width:(CGFloat)width titles:(NSArray<NSString *> *)titles selectors:(NSArray<NSString *> *)selectors;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)addSection:(NSString *)title subtitle:(NSString *)subtitle y:(CGFloat *)y width:(CGFloat)width;
- (void)renderPage;
@end

@interface ZNRuntimeMenuControllerV040 (V043)
- (void)zn43_renderDebug;
- (void)zn43_makeUI:(UIWindow *)window;
- (void)zn43_tick:(NSTimer *)timer;
- (void)zn43_configureRuntimePatch:(id)sender;
- (void)zn43_validateRuntimePatch:(id)sender;
- (void)zn43_applyRuntimePatch:(id)sender;
- (void)zn43_restoreRuntimePatch:(id)sender;
- (void)zn43_copyRuntimeValidation:(id)sender;
- (void)zn43_clearRuntimeValidation:(id)sender;
- (void)zn43_showMessage:(NSString *)title body:(NSString *)body;
@end

@implementation ZNRuntimeMenuControllerV040 (V043)

- (void)zn43_renderDebug {
    [self zn43_renderDebug];

    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat y = MAX(CGRectGetHeight(self.contentView.frame), CGRectGetHeight(self.contentScroll.bounds)) + 4.0;
    ZNPatchRuntimeValidator *validator = [ZNPatchRuntimeValidator sharedValidator];

    [self addSection:@"Patch 实机验证"
            subtitle:@"开发者工具 · target + offset + patch · Live Original · 临时应用 / 精确恢复"
                   y:&y
               width:width];
    [self zn40_addInfoCard:@"当前验证会话" lines:[validator diagnosticLines] y:&y width:width];
    [self zn40_addActionCardY:&y width:width
                        titles:@[@"配置 Patch", @"读取 / 验证"]
                     selectors:@[@"zn43_configureRuntimePatch:", @"zn43_validateRuntimePatch:"]];
    [self zn40_addActionCardY:&y width:width
                        titles:@[@"临时应用", @"恢复原始"]
                     selectors:@[@"zn43_applyRuntimePatch:", @"zn43_restoreRuntimePatch:"]];
    [self zn40_addActionCardY:&y width:width
                        titles:@[@"复制验证报告", @"清除会话"]
                     selectors:@[@"zn43_copyRuntimeValidation:", @"zn43_clearRuntimeValidation:"]];
    [self zn40_updateContentHeight:y];
}

- (void)zn43_makeUI:(UIWindow *)window {
    [self zn43_makeUI:window];
    self.footerLabel.text = [NSString stringWithFormat:@"PatchCore 0.4.3    Runtime Validation    iOS %@", UIDevice.currentDevice.systemVersion];
}

- (void)zn43_tick:(NSTimer *)timer {
    [self zn43_tick:timer];
    if (self.uiReady) self.footerLabel.text = [NSString stringWithFormat:@"PatchCore 0.4.3    Runtime Validation    iOS %@", UIDevice.currentDevice.systemVersion];
}

- (void)zn43_showMessage:(NSString *)title body:(NSString *)body {
    UIViewController *presenter = ZN43TopController(self.hostWindow ?: UIApplication.sharedApplication.keyWindow);
    if (!presenter) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title ?: @"Patch 验证"
                                                                   message:body ?: @""
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

- (void)zn43_configureRuntimePatch:(id)sender {
    (void)sender;
    ZNPatchRuntimeValidator *validator = [ZNPatchRuntimeValidator sharedValidator];
    if (validator.isApplied) {
        [self zn43_showMessage:@"无法重新配置" body:@"当前临时 Patch 尚未恢复。请先点击“恢复原始”。"];
        return;
    }

    UIViewController *presenter = ZN43TopController(self.hostWindow ?: UIApplication.sharedApplication.keyWindow);
    if (!presenter) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"配置运行时 Patch"
                                                                   message:@"只使用 target + offset + patch。JSON original 不参与验证，OFF 基线从当前原版进程现场读取。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Target，例如 UnityFramework";
        field.text = validator.target.length ? validator.target : @"UnityFramework";
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Offset，例如 0x92AAF88";
        field.text = validator.isConfigured ? [NSString stringWithFormat:@"0x%llX", validator.rva] : @"";
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Patch HEX，例如 02020014";
        field.text = validator.patchBytes.length ? ZN43HexString(validator.patchBytes) : @"";
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *error = nil;
        BOOL ok = [validator configureTarget:alert.textFields[0].text ?: @""
                                offsetString:alert.textFields[1].text ?: @""
                                    patchHex:alert.textFields[2].text ?: @""
                                       error:&error];
        if (!ok) {
            [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[runtime-validate] 配置失败：%@", error ?: @"未知错误"]];
            [weakSelf zn43_showMessage:@"配置失败" body:error ?: @"未知错误"];
        }
        [weakSelf renderPage];
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

- (void)zn43_validateRuntimePatch:(id)sender {
    (void)sender;
    NSString *error = nil;
    BOOL ok = [[ZNPatchRuntimeValidator sharedValidator] validate:&error];
    if (!ok) [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[runtime-validate] 读取验证失败：%@", error ?: @"未知错误"]];
    [self renderPage];
    if (!ok) [self zn43_showMessage:@"验证失败" body:error ?: @"未知错误"];
}

- (void)zn43_applyRuntimePatch:(id)sender {
    (void)sender;
    NSString *error = nil;
    BOOL ok = [[ZNPatchRuntimeValidator sharedValidator] applyTemporary:&error];
    [self renderPage];
    [self zn43_showMessage:ok ? @"临时应用成功" : @"临时应用失败"
                       body:ok ? [ZNPatchRuntimeValidator sharedValidator].lastResult : (error ?: @"未知错误")];
}

- (void)zn43_restoreRuntimePatch:(id)sender {
    (void)sender;
    NSString *error = nil;
    BOOL ok = [[ZNPatchRuntimeValidator sharedValidator] restoreOriginal:&error];
    [self renderPage];
    [self zn43_showMessage:ok ? @"恢复成功" : @"恢复失败"
                       body:ok ? [ZNPatchRuntimeValidator sharedValidator].lastResult : (error ?: @"未知错误")];
}

- (void)zn43_copyRuntimeValidation:(id)sender {
    (void)sender;
    UIPasteboard.generalPasteboard.string = [[ZNPatchRuntimeValidator sharedValidator] diagnosticReport];
    [[ZNRuntimeLogger sharedLogger] log:@"[runtime-validate] 验证报告已复制"];
    [self renderPage];
}

- (void)zn43_clearRuntimeValidation:(id)sender {
    (void)sender;
    ZNPatchRuntimeValidator *validator = [ZNPatchRuntimeValidator sharedValidator];
    if (validator.isApplied) {
        [self zn43_showMessage:@"无法清除" body:@"当前临时 Patch 尚未恢复。请先恢复原始字节。"];
        return;
    }
    [validator clearSession];
    [[ZNRuntimeLogger sharedLogger] log:@"[runtime-validate] 验证会话已清除"];
    [self renderPage];
}

@end

static void ZNSwapInstanceMethodV043(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

__attribute__((constructor(106))) static void ZNInstallV043RuntimeValidation(void) {
    @autoreleasepool {
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNSwapInstanceMethodV043(cls, @selector(zn40_renderDebug), @selector(zn43_renderDebug));
        ZNSwapInstanceMethodV043(cls, @selector(makeUI:), @selector(zn43_makeUI:));
        ZNSwapInstanceMethodV043(cls, @selector(tick:), @selector(zn43_tick:));
        [[ZNRuntimeLogger sharedLogger] log:@"[bootstrap][main] v0.4.3 runtime validation installed: live-original / temporary-apply / verified-restore"];
    }
}
// END inlined ZonoeRuntimeMenuV043.mm
#import "ZNBinaryPatchWorkspace.h"
#import "ZNStaticBinaryBuilder.h"
#import "ZNStaticDispatchRuntime.h"

// v0.4.4 developer binary-builder layer.
// `其他` is q-gated by ZNDeveloperGate. No system configuration alerts are
// used here: target/offset/enabled are edited inline, Original is live-captured.

@interface ZNRuntimeMenuControllerV040 (V044Base)
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIFont *)menuFont:(CGFloat)size weight:(UIFontWeight)weight;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)addSection:(NSString *)title subtitle:(NSString *)subtitle y:(CGFloat *)y width:(CGFloat)width;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)renderPage;
@end

@interface ZNRuntimeMenuControllerV040 (V044)
- (void)zn44_renderFullPage;
- (CGSize)zn44_fullSizeForWindow:(UIWindow *)window;
- (void)zn44_makeUI:(UIWindow *)window;
- (void)zn44_tick:(NSTimer *)timer;
- (void)zn44_renderOther;
- (void)zn44_fieldChanged:(UITextField *)field;
- (void)zn44_endEditing:(UITextField *)field;
- (void)zn44_importJSON:(id)sender;
- (void)zn44_jsonTapped:(UIButton *)sender;
- (void)zn44_addOffset:(id)sender;
- (void)zn44_validateAll:(id)sender;
- (void)zn44_applyAll:(id)sender;
- (void)zn44_restoreAll:(id)sender;
- (void)zn44_buildBinary:(id)sender;
- (void)zn44_toggleStatic:(UIButton *)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (V044)

- (UITextField *)zn44_field:(CGRect)frame text:(NSString *)text placeholder:(NSString *)placeholder tag:(NSInteger)tag enabled:(BOOL)enabled {
    UITextField *f=[[UITextField alloc] initWithFrame:frame];
    f.tag=tag; f.text=text?:@""; f.placeholder=placeholder; f.enabled=enabled;
    f.textColor=self.theme.primaryTextColor; f.backgroundColor=self.theme.controlColor;
    f.font=[self menuFont:10.5 weight:UIFontWeightMedium]; f.keyboardType=UIKeyboardTypeASCIICapable;
    f.autocorrectionType=UITextAutocorrectionTypeNo; f.autocapitalizationType=UITextAutocapitalizationTypeNone;
    f.returnKeyType=UIReturnKeyDone; f.clearButtonMode=UITextFieldViewModeWhileEditing;
    f.layer.cornerRadius=7; f.layer.borderWidth=1; f.layer.borderColor=self.theme.borderColor.CGColor;
    UIView *pad=[[UIView alloc] initWithFrame:CGRectMake(0,0,8,1)]; f.leftView=pad; f.leftViewMode=UITextFieldViewModeAlways;
    [f addTarget:self action:@selector(zn44_fieldChanged:) forControlEvents:UIControlEventEditingChanged];
    [f addTarget:self action:@selector(zn44_endEditing:) forControlEvents:UIControlEventEditingDidEndOnExit];
    return f;
}

- (void)zn44_renderFullPage {
    NSString *cat=(self.selectedCategory>=0&&self.selectedCategory<self.categories.count)?self.categories[self.selectedCategory]:@"";
    if([cat isEqualToString:@"其他"]){[self zn44_renderOther];return;}
    [self zn44_renderFullPage];
}

- (CGSize)zn44_fullSizeForWindow:(UIWindow *)window {
    CGSize size=[self zn44_fullSizeForWindow:window];
    NSString *cat=(self.selectedCategory>=0&&self.selectedCategory<self.categories.count)?self.categories[self.selectedCategory]:@"";
    if([cat isEqualToString:@"其他"]){UIEdgeInsets insets=window.safeAreaInsets;CGFloat avail=CGRectGetHeight(window.bounds)-insets.top-insets.bottom-20;size.height=MIN(MAX(size.height,500.0),MAX(320.0,avail));}
    return size;
}

- (void)zn44_makeUI:(UIWindow *)window {
    [self zn44_makeUI:window];
    self.footerLabel.text=[NSString stringWithFormat:@"PatchCore 0.4.4    Binary Builder    iOS %@",UIDevice.currentDevice.systemVersion];
}
- (void)zn44_tick:(NSTimer *)timer {
    [self zn44_tick:timer]; if(self.uiReady)self.footerLabel.text=[NSString stringWithFormat:@"PatchCore 0.4.4    Binary Builder    iOS %@",UIDevice.currentDevice.systemVersion];
}

- (void)zn44_renderOther {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width=CGRectGetWidth(self.contentView.bounds),y=9.0; ZNBinaryPatchWorkspace *ws=[ZNBinaryPatchWorkspace sharedWorkspace]; [ws ensureDefaultRows];
    BOOL locked=ws.hasAnyApplied||ws.isBuilding;
    [self addSection:@"二进制生成" subtitle:@"q 开发者工具 · Inline Patch Editor · Universal JSON · Static Dispatch / No-JIT" y:&y width:width];

    UIView *targetCard=[self cardAtY:y height:58 width:width compact:NO];
    UILabel *tl=[self label:@"二进制" size:11.5 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];tl.frame=CGRectMake(13,7,56,18);[targetCard addSubview:tl];
    CGFloat buttonW=76; UITextField *target=[self zn44_field:CGRectMake(68,7,targetCard.bounds.size.width-68-buttonW-20,34) text:ws.defaultTarget placeholder:@"默认主程序，可输入" tag:440000 enabled:!locked];[targetCard addSubview:target];
    UIButton *import=[self zn40_button:ws.showJSONFiles?@"收起 JSON":@"导入 JSON" selector:@selector(zn44_importJSON:) frame:CGRectMake(targetCard.bounds.size.width-buttonW-9,7,buttonW,34)];import.enabled=!locked;[targetCard addSubview:import];
    UILabel *hint=[self label:@"target 可为主程序 / UnityFramework / framework / dylib 名称" size:8.7 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];hint.frame=CGRectMake(13,42,targetCard.bounds.size.width-26,13);[targetCard addSubview:hint];
    [self.contentView addSubview:targetCard];y+=66;

    if(ws.showJSONFiles){
        NSUInteger shown=ws.jsonFiles.count;CGFloat h=34+shown*34;UIView *list=[self cardAtY:y height:h width:width compact:NO];
        UILabel *t=[self label:[NSString stringWithFormat:@"Application Support JSON · %lu",(unsigned long)ws.jsonFiles.count] size:11.0 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];t.frame=CGRectMake(13,7,list.bounds.size.width-26,18);[list addSubview:t];
        for(NSUInteger i=0;i<shown;i++){NSString *p=ws.jsonFiles[i];UIButton *b=[self zn40_button:p.lastPathComponent selector:@selector(zn44_jsonTapped:) frame:CGRectMake(13,29+i*34,list.bounds.size.width-26,28)];b.tag=446000+i;b.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;b.titleLabel.lineBreakMode=NSLineBreakByTruncatingMiddle;[list addSubview:b];}
        [self.contentView addSubview:list];y+=h+8;
    }

    for(NSUInteger i=0;i<ws.rows.count;i++){
        ZNBinaryPatchRow *r=ws.rows[i];CGFloat h=92;UIView *card=[self cardAtY:y height:h width:width compact:NO];
        NSString *rowTitle=[NSString stringWithFormat:@"#%lu",(unsigned long)i+1];if(r.explicitTarget&&r.target.length)rowTitle=[rowTitle stringByAppendingFormat:@" · %@",r.target];if(r.title.length)rowTitle=[rowTitle stringByAppendingFormat:@" · %@",r.title];
        UILabel *head=[self label:rowTitle size:10.2 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];head.frame=CGRectMake(13,5,card.bounds.size.width-26,15);head.lineBreakMode=NSLineBreakByTruncatingMiddle;[card addSubview:head];
        UILabel *ol=[self label:@"Offset" size:9.0 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];ol.frame=CGRectMake(13,23,48,28);[card addSubview:ol];UITextField *of=[self zn44_field:CGRectMake(58,22,card.bounds.size.width-71,29) text:r.offsetText placeholder:@"0x..." tag:441000+i enabled:!locked];[card addSubview:of];
        UILabel *el=[self label:@"Enabled" size:9.0 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];el.frame=CGRectMake(13,53,48,28);[card addSubview:el];UITextField *ef=[self zn44_field:CGRectMake(58,52,card.bounds.size.width-71,29) text:r.enabledText placeholder:@"ARM64 HEX" tag:442000+i enabled:!locked];ef.autocapitalizationType=UITextAutocapitalizationTypeAllCharacters;[card addSubview:ef];
        NSString *orig=r.originalHex.length?r.originalHex:@"-";NSString *line=[NSString stringWithFormat:@"Original  %@",orig];if(r.statusText.length)line=[line stringByAppendingFormat:@"   %@",r.statusText];UILabel *st=[self label:line size:8.3 weight:UIFontWeightRegular color:r.conflict?UIColor.systemOrangeColor:self.theme.secondaryTextColor];st.frame=CGRectMake(13,80,card.bounds.size.width-26,11);st.lineBreakMode=NSLineBreakByTruncatingMiddle;[card addSubview:st];
        [self.contentView addSubview:card];y+=h+6;
    }

    UIView *addCard=[self cardAtY:y height:48 width:width compact:NO];UIButton *add=[self zn40_button:@"＋ 增加 Offset" selector:@selector(zn44_addOffset:) frame:CGRectMake(13,7,addCard.bounds.size.width-26,34)];add.enabled=!locked;[addCard addSubview:add];[self.contentView addSubview:addCard];y+=56;

    UIView *summary=[self cardAtY:y height:44 width:width compact:NO];UILabel *sl=[self label:[NSString stringWithFormat:@"已填写 %lu / %lu · 已验证 %lu%@",(unsigned long)ws.filledCount,(unsigned long)ws.rows.count,(unsigned long)ws.validatedCount,ws.hasAnyApplied?@" · Runtime 已应用":(ws.isBuilding?@" · 正在生成…":@"")] size:10.2 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];sl.frame=CGRectMake(13,6,summary.bounds.size.width-26,16);[summary addSubview:sl];UILabel *ss=[self label:ws.lastStatus?:@"" size:8.6 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];ss.frame=CGRectMake(13,23,summary.bounds.size.width-26,15);ss.lineBreakMode=NSLineBreakByTruncatingMiddle;[summary addSubview:ss];[self.contentView addSubview:summary];y+=52;

    UIView *a1=[self cardAtY:y height:52 width:width compact:NO];CGFloat gap=8,inner=a1.bounds.size.width-26,bw=(inner-gap)/2;UIButton *v=[self zn40_button:@"读取验证" selector:@selector(zn44_validateAll:) frame:CGRectMake(13,9,bw,34)];UIButton *ap=[self zn40_button:@"临时应用" selector:@selector(zn44_applyAll:) frame:CGRectMake(13+bw+gap,9,bw,34)];v.enabled=!ws.isBuilding&&!ws.hasAnyApplied;ap.enabled=!ws.isBuilding&&!ws.hasAnyApplied;[a1 addSubview:v];[a1 addSubview:ap];[self.contentView addSubview:a1];y+=60;
    UIView *a2=[self cardAtY:y height:52 width:width compact:NO];UIButton *rs=[self zn40_button:@"恢复全部" selector:@selector(zn44_restoreAll:) frame:CGRectMake(13,9,bw,34)];UIButton *build=[self zn40_button:ws.isBuilding?@"正在生成…":@"生成新二进制" selector:@selector(zn44_buildBinary:) frame:CGRectMake(13+bw+gap,9,bw,34)];rs.enabled=!ws.isBuilding&&ws.hasAnyApplied;build.enabled=!ws.isBuilding&&!ws.hasAnyApplied&&ws.validatedCount==ws.filledCount&&ws.filledCount>0;[a2 addSubview:rs];[a2 addSubview:build];[self.contentView addSubview:a2];y+=60;

    if(ws.lastOutputPaths.count){NSMutableArray *lines=[NSMutableArray array];for(NSUInteger i=0;i<MIN((NSUInteger)4,ws.lastOutputPaths.count);i++){NSString *p=ws.lastOutputPaths[i];[lines addObject:[p hasPrefix:NSHomeDirectory()]?[p substringFromIndex:NSHomeDirectory().length]:p];}[self zn40_addInfoCard:@"最近输出" lines:lines y:&y width:width];}

    // Runtime ON/OFF switches intentionally live only in the single `功能`
    // category (v0.4.5). `其他` remains builder/import/validation only.
    [self zn40_updateContentHeight:y];
}

- (void)zn44_fieldChanged:(UITextField *)f {
    ZNBinaryPatchWorkspace *ws=[ZNBinaryPatchWorkspace sharedWorkspace];if(f.tag==440000){[ws updateDefaultTarget:f.text?:@""];return;}if(f.tag>=441000&&f.tag<442000){[ws updateOffset:f.text?:@"" row:(NSUInteger)(f.tag-441000)];return;}if(f.tag>=442000&&f.tag<443000){[ws updateEnabled:f.text?:@"" row:(NSUInteger)(f.tag-442000)];return;}
}
- (void)zn44_endEditing:(UITextField *)field {(void)field;[self.hostWindow endEditing:YES];}
- (void)zn44_importJSON:(id)sender {(void)sender;ZNBinaryPatchWorkspace *ws=[ZNBinaryPatchWorkspace sharedWorkspace];if(ws.showJSONFiles)ws.showJSONFiles=NO;else{[ws refreshJSONFiles];ws.showJSONFiles=YES;}[self renderPage];}
- (void)zn44_jsonTapped:(UIButton *)sender {ZNBinaryPatchWorkspace *ws=[ZNBinaryPatchWorkspace sharedWorkspace];NSUInteger i=(NSUInteger)(sender.tag-446000);if(i>=ws.jsonFiles.count)return;NSString *e=nil;if(![ws importJSONAtPath:ws.jsonFiles[i] error:&e])ws.lastStatus=[NSString stringWithFormat:@"导入失败：%@",e?:@"未知错误"];[self renderPage];}
- (void)zn44_addOffset:(id)sender {(void)sender;[[ZNBinaryPatchWorkspace sharedWorkspace] addEmptyRow];[self renderPage];}
- (void)zn44_validateAll:(id)sender {(void)sender;[self.hostWindow endEditing:YES];ZNBinaryPatchWorkspace *ws=[ZNBinaryPatchWorkspace sharedWorkspace];NSString *e=nil;[ws validateAll:&e];if(e.length&&![ws.lastStatus containsString:e])[[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[builder] validate: %@",e]];[self renderPage];}
- (void)zn44_applyAll:(id)sender {(void)sender;[self.hostWindow endEditing:YES];ZNBinaryPatchWorkspace *ws=[ZNBinaryPatchWorkspace sharedWorkspace];NSString *e=nil;if(![ws applyAll:&e]&&e.length)[[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[builder] apply: %@",e]];[self renderPage];}
- (void)zn44_restoreAll:(id)sender {(void)sender;ZNBinaryPatchWorkspace *ws=[ZNBinaryPatchWorkspace sharedWorkspace];NSString *e=nil;if(![ws restoreAll:&e]&&e.length)[[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[builder] restore: %@",e]];[self renderPage];}
- (void)zn44_buildBinary:(id)sender {(void)sender;[self.hostWindow endEditing:YES];ZNBinaryPatchWorkspace *ws=[ZNBinaryPatchWorkspace sharedWorkspace];if(ws.isBuilding)return;if(ws.hasAnyApplied){ws.lastStatus=@"生成前必须先恢复 Runtime Patch";[self renderPage];return;}ws.building=YES;ws.lastStatus=@"正在生成：验证 Mach-O / 安全 gap / relocation…";[self renderPage];__weak typeof(self) weakSelf=self;dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSArray *paths=nil;NSString *report=nil,*error=nil;BOOL ok=[ZNStaticBinaryBuilder buildWorkspace:ws outputs:&paths report:&report error:&error];dispatch_async(dispatch_get_main_queue(),^{ws.building=NO;if(ok)[ws setBuildOutputs:paths status:report?:@"生成成功"];else[ws setBuildOutputs:@[] status:[NSString stringWithFormat:@"生成失败：%@",error?:@"未知错误"]];[weakSelf renderPage];});});}
- (void)zn44_toggleStatic:(UIButton *)sender {ZNStaticDispatchRuntime *rt=[ZNStaticDispatchRuntime sharedRuntime];NSUInteger i=(NSUInteger)(sender.tag-447000);if(i>=rt.records.count)return;ZNStaticPatchRecord *r=rt.records[i];NSString *e=nil;if(![rt setEnabled:!r.enabled forRecord:r error:&e])[[ZNBinaryPatchWorkspace sharedWorkspace] setBuildOutputs:[ZNBinaryPatchWorkspace sharedWorkspace].lastOutputPaths status:[NSString stringWithFormat:@"Static Dispatch 切换失败：%@",e?:@"未知错误"]];[self renderPage];}
@end

static void ZNSwapV044(Class cls,SEL a,SEL b){Method x=class_getInstanceMethod(cls,a),y=class_getInstanceMethod(cls,b);if(x&&y)method_exchangeImplementations(x,y);}
__attribute__((constructor(110))) static void ZNInstallV044BinaryBuilder(void){@autoreleasepool{Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040");if(!cls)return;ZNSwapV044(cls,@selector(renderFullPage),@selector(zn44_renderFullPage));ZNSwapV044(cls,@selector(fullSizeForWindow:),@selector(zn44_fullSizeForWindow:));ZNSwapV044(cls,@selector(makeUI:),@selector(zn44_makeUI:));ZNSwapV044(cls,@selector(tick:),@selector(zn44_tick:));[[ZNRuntimeLogger sharedLogger] log:@"[bootstrap][main] v0.4.4 embedded patch editor / universal JSON / static binary builder installed"];}}
// END inlined ZonoeRuntimeMenuV044.mm
#import "ZNDeveloperGate.h"
#import "ZNStaticDispatchRuntime.h"
#import "ZNPatchCore.h"

// v0.4.6 UI cleanup + marker-sibling JSON scan release.
// Public runtime Patch UI is intentionally reduced to one `功能` category.
// `其他` remains q-gated for the developer Binary Builder; g still controls
// Diagnostics + Debug. All generated Static Dispatch records are shown in 功能.

@interface ZNRuntimeMenuControllerV040 (V045Base)
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)addSection:(NSString *)title subtitle:(NSString *)subtitle y:(CGFloat *)y width:(CGFloat)width;
- (void)zn40_addInfoCard:(NSString *)title lines:(NSArray<NSString *> *)lines y:(CGFloat *)y width:(CGFloat)width;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)layoutForWindow:(UIWindow *)window initial:(BOOL)initial;
- (void)updateSidebar;
- (void)renderPage;
@end

@interface ZNRuntimeMenuControllerV040 (V045)
- (void)zn45_renderFullPage;
- (void)zn45_renderCompactPage;
- (void)zn45_renderFeaturePage;
- (CGSize)zn45_fullSizeForWindow:(UIWindow *)window;
- (void)zn45_themeTapped:(id)sender;
- (void)zn45_makeUI:(UIWindow *)window;
- (void)zn45_tick:(NSTimer *)timer;
@end

@implementation ZNRuntimeMenuControllerV040 (V045)


- (void)zn45_renderFeaturePage {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width=CGRectGetWidth(self.contentView.bounds),y=9.0;
    ZNStaticDispatchRuntime *runtime=[ZNStaticDispatchRuntime sharedRuntime];
    [runtime refresh];

    [self addSection:@"功能" subtitle:@"所有 Runtime Patch 统一显示在这里" y:&y width:width];
    if (!runtime.records.count) {
        [self zn40_addInfoCard:@"暂无 Patch" lines:@[
            @"当前安装包没有检测到 Static Dispatch Patch。",
            @"开发者可在“其他”中导入 JSON、验证并生成新二进制后重新签名安装。"
        ] y:&y width:width];
        [self zn40_updateContentHeight:y];
        return;
    }

    for (NSUInteger i=0;i<runtime.records.count;i++) {
        ZNStaticPatchRecord *r=runtime.records[i];
        UIView *card=[self cardAtY:y height:52 width:width compact:NO];
        NSString *title=r.title.length?r.title:[NSString stringWithFormat:@"Patch #%u",r.patchID];
        UILabel *name=[self label:title size:11.2 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
        name.frame=CGRectMake(13,6,card.bounds.size.width-96,18);
        name.lineBreakMode=NSLineBreakByTruncatingMiddle;
        [card addSubview:name];
        UILabel *detail=[self label:[NSString stringWithFormat:@"%@ + 0x%llX · ID %u",r.target,r.siteRVA,r.patchID] size:8.5 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        detail.frame=CGRectMake(13,27,card.bounds.size.width-96,16);
        detail.lineBreakMode=NSLineBreakByTruncatingMiddle;
        [card addSubview:detail];
        UIButton *toggle=[self zn40_button:r.enabled?@"ON":@"OFF" selector:@selector(zn44_toggleStatic:) frame:CGRectMake(card.bounds.size.width-72,9,60,34)];
        toggle.tag=447000+i;
        [card addSubview:toggle];
        [self.contentView addSubview:card];
        y+=58;
    }
    [self zn40_updateContentHeight:y];
}

- (void)zn45_renderFullPage {
    NSString *cat=(self.selectedCategory>=0&&self.selectedCategory<self.categories.count)?self.categories[self.selectedCategory]:@"";
    if ([cat isEqualToString:@"功能"]) { [self zn45_renderFeaturePage]; return; }
    [self zn45_renderFullPage];
}

- (void)zn45_renderCompactPage {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width=CGRectGetWidth(self.contentView.bounds),y=7.0;
    ZNStaticDispatchRuntime *runtime=[ZNStaticDispatchRuntime sharedRuntime];
    [runtime refresh];
    if (!runtime.records.count) {
        UIView *card=[self cardAtY:y height:44 width:width compact:YES];
        UILabel *label=[self label:@"暂无 Runtime Patch" size:11.0 weight:UIFontWeightSemibold color:self.theme.secondaryTextColor];
        label.frame=CGRectMake(9,11,card.bounds.size.width-18,20);
        [card addSubview:label];
        [self.contentView addSubview:card];
        y+=50;
    } else {
        for (NSUInteger i=0;i<runtime.records.count;i++) {
            ZNStaticPatchRecord *r=runtime.records[i];
            UIView *card=[self cardAtY:y height:42 width:width compact:YES];
            NSString *title=r.title.length?r.title:[NSString stringWithFormat:@"Patch #%u",r.patchID];
            UILabel *label=[self label:title size:10.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
            label.frame=CGRectMake(9,10,card.bounds.size.width-80,20);
            label.lineBreakMode=NSLineBreakByTruncatingMiddle;
            [card addSubview:label];
            UIButton *toggle=[self zn40_button:r.enabled?@"ON":@"OFF" selector:@selector(zn44_toggleStatic:) frame:CGRectMake(card.bounds.size.width-65,7,56,28)];
            toggle.tag=447000+i;
            [card addSubview:toggle];
            [self.contentView addSubview:card];
            y+=48;
        }
    }
    [self zn40_updateContentHeight:y];
}

- (CGSize)zn45_fullSizeForWindow:(UIWindow *)window {
    CGSize size=[self zn45_fullSizeForWindow:window];
    NSString *cat=(self.selectedCategory>=0&&self.selectedCategory<self.categories.count)?self.categories[self.selectedCategory]:@"";
    UIEdgeInsets insets=window.safeAreaInsets;
    CGFloat available=CGRectGetHeight(window.bounds)-insets.top-insets.bottom-20.0;
    if ([cat isEqualToString:@"功能"]) size.height=MIN(MAX(size.height,390.0),MAX(300.0,available));
    if ([cat isEqualToString:@"主题"]) size.height=MIN(MAX(size.height,430.0),MAX(300.0,available));
    return size;
}

- (void)zn45_themeTapped:(id)sender {
    (void)sender;
    if (self.compactMode) return;
    NSInteger idx=[self.categories indexOfObject:@"主题"];
    if (idx==NSNotFound) return;
    self.selectedCategory=idx;
    [NSUserDefaults.standardUserDefaults setInteger:idx forKey:@"ZonoePatch.SelectedCategory"];
    self.contentScroll.contentOffset=CGPointZero;
    [self layoutForWindow:self.hostWindow initial:NO];
    [self updateSidebar];
    [self renderPage];
}

- (void)zn45_makeUI:(UIWindow *)window {
    [self zn45_makeUI:window];
    self.footerLabel.text=[NSString stringWithFormat:@"PatchCore 0.4.6    Function + Binary Builder    iOS %@",UIDevice.currentDevice.systemVersion];
}

- (void)zn45_tick:(NSTimer *)timer {
    [self zn45_tick:timer];
    if (self.uiReady) self.footerLabel.text=[NSString stringWithFormat:@"PatchCore 0.4.6    Function + Binary Builder    iOS %@",UIDevice.currentDevice.systemVersion];
}

@end

static void ZNSwapV045(Class cls,SEL a,SEL b){
    Method x=class_getInstanceMethod(cls,a),y=class_getInstanceMethod(cls,b);
    if(x&&y) method_exchangeImplementations(x,y);
}

__attribute__((constructor(111))) static void ZNInstallV045FunctionUI(void){
    @autoreleasepool {
        Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if(!cls) return;
        ZNSwapV045(cls,@selector(renderFullPage),@selector(zn45_renderFullPage));
        ZNSwapV045(cls,@selector(renderCompactPage),@selector(zn45_renderCompactPage));
        ZNSwapV045(cls,@selector(fullSizeForWindow:),@selector(zn45_fullSizeForWindow:));
        ZNSwapV045(cls,@selector(themeTapped:),@selector(zn45_themeTapped:));
        ZNSwapV045(cls,@selector(makeUI:),@selector(zn45_makeUI:));
        ZNSwapV045(cls,@selector(tick:),@selector(zn45_tick:));
        [[ZNRuntimeLogger sharedLogger] log:@"[bootstrap][main] Function page installed; sidebar ownership centralized; q=Other, g=Diagnostics/Debug"];
    }
}
// END inlined ZonoeRuntimeMenuV045.mm
#import "ZNBinaryPatchWorkspace.h"
#import "ZNPatchJSONImporter.h"

// v0.4.8 JSON import layer.
// Primary path: scan only the immediate directory that contains developer file
// `1`, regardless of JSON filename. If exactly one JSON contains recognizable
// Patch entries, import it automatically. Manual document picker remains a
// fallback and reads the selected URL through coordinated security-scoped I/O.

static UIViewController *ZN48TopViewController(UIViewController *vc) {
    if (!vc) return nil;
    UIViewController *presented=vc.presentedViewController;
    if (presented && !presented.isBeingDismissed) return ZN48TopViewController(presented);
    if ([vc isKindOfClass:UINavigationController.class]) {
        UIViewController *top=((UINavigationController *)vc).visibleViewController;
        return top?ZN48TopViewController(top):vc;
    }
    if ([vc isKindOfClass:UITabBarController.class]) {
        UIViewController *sel=((UITabBarController *)vc).selectedViewController;
        return sel?ZN48TopViewController(sel):vc;
    }
    if ([vc isKindOfClass:UISplitViewController.class]) {
        UIViewController *last=((UISplitViewController *)vc).viewControllers.lastObject;
        return last?ZN48TopViewController(last):vc;
    }
    return vc;
}

static void ZN48RelabelJSONList(UIView *view) {
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *l=(UILabel *)view;
        if ([l.text hasPrefix:@"Application Support JSON"]) {
            l.text=[l.text stringByReplacingOccurrencesOfString:@"Application Support JSON" withString:@"与 1 同目录 JSON"];
        }
    }
    for (UIView *sub in view.subviews) ZN48RelabelJSONList(sub);
}

@interface ZNRuntimeMenuControllerV040 (V048) <UIDocumentPickerDelegate>
- (void)zn48_importJSON:(id)sender;
- (void)zn48_presentManualPicker;
- (void)zn48_renderOther;
- (void)zn48_makeUI:(UIWindow *)window;
- (void)zn48_tick:(NSTimer *)timer;
@end

@implementation ZNRuntimeMenuControllerV040 (V048)

- (void)zn48_presentManualPicker {
    NSArray<NSString *> *types=@[@"public.json",@"public.text",@"public.data"];
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initWithDocumentTypes:types inMode:UIDocumentPickerModeOpen];
    picker.delegate=(id<UIDocumentPickerDelegate>)self;
    picker.allowsMultipleSelection=NO;
    picker.modalPresentationStyle=UIModalPresentationFormSheet;

    UIWindow *window=self.hostWindow;
    if (!window) window=UIApplication.sharedApplication.keyWindow;
    UIViewController *presenter=ZN48TopViewController(window.rootViewController);
    if (!presenter) {
        ZNBinaryPatchWorkspace *ws=[ZNBinaryPatchWorkspace sharedWorkspace];
        ws.lastStatus=@"手动导入失败：找不到可用于弹出文件选择器的 ViewController";
        [self renderPage];
        return;
    }
    [presenter presentViewController:picker animated:YES completion:nil];
}

- (void)zn48_importJSON:(id)sender {
    (void)sender;
    ZNBinaryPatchWorkspace *ws=[ZNBinaryPatchWorkspace sharedWorkspace];
    if (ws.hasAnyApplied || ws.isBuilding) return;
    [self.hostWindow endEditing:YES];

    if (ws.showJSONFiles) {
        ws.showJSONFiles=NO;
        [self renderPage];
        return;
    }

    [ws refreshJSONFiles];
    NSArray<NSString *> *all=ws.jsonFiles;
    NSMutableArray<NSString *> *valid=[NSMutableArray array];
    NSMutableArray<NSString *> *invalid=[NSMutableArray array];

    for (NSString *path in all) {
        NSString *probeError=nil;
        NSArray *items=[ZNPatchJSONImporter importFile:path error:&probeError];
        if (items.count) [valid addObject:path];
        else [invalid addObject:[NSString stringWithFormat:@"%@：%@",path.lastPathComponent,probeError?:@"非 Patch JSON"]];
    }

    if (valid.count==1) {
        NSString *path=valid.firstObject;
        NSString *importError=nil;
        if ([ws importJSONAtPath:path error:&importError]) {
            ws.lastStatus=[NSString stringWithFormat:@"自动导入成功：%@ · Patch %lu · 同目录 JSON %lu",path.lastPathComponent,(unsigned long)ws.filledCount,(unsigned long)all.count];
        } else {
            ws.lastStatus=[NSString stringWithFormat:@"自动导入失败：%@",importError?:@"未知错误"];
        }
        ws.showJSONFiles=NO;
        [self renderPage];
        return;
    }

    if (valid.count>1) {
        ws.showJSONFiles=YES;
        ws.lastStatus=[NSString stringWithFormat:@"与 1 同目录发现 %lu 个 JSON，其中 %lu 个可识别 Patch；请选择",(unsigned long)all.count,(unsigned long)valid.count];
        [self renderPage];
        ZN48RelabelJSONList(self.contentView);
        return;
    }

    ws.showJSONFiles=NO;
    NSString *discovery=[ZNPatchJSONImporter discoveryStatus];
    if (all.count) {
        NSString *detail=invalid.firstObject?:@"没有可识别的 Patch JSON";
        ws.lastStatus=[NSString stringWithFormat:@"%@ · 未识别 Patch JSON · %@ · 打开手动选择",discovery,detail];
    } else {
        ws.lastStatus=[NSString stringWithFormat:@"%@ · 打开手动选择",discovery];
    }
    [self renderPage];
    [self zn48_presentManualPicker];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    NSURL *url=urls.firstObject;
    ZNBinaryPatchWorkspace *ws=[ZNBinaryPatchWorkspace sharedWorkspace];
    if (!url) {
        ws.lastStatus=@"手动导入失败：没有选择文件";
        [self renderPage];
        return;
    }

    NSString *name=url.lastPathComponent?:@"";
    if (![[name.pathExtension lowercaseString] isEqualToString:@"json"]) {
        ws.lastStatus=[NSString stringWithFormat:@"手动导入失败：%@ 不是 JSON 文件",name.length?name:@"所选文件"];
        [self renderPage];
        return;
    }

    BOOL scoped=[url startAccessingSecurityScopedResource];
    __block NSData *data=nil;
    __block NSError *readError=nil;
    NSError *coordError=nil;
    NSFileCoordinator *coordinator=[[NSFileCoordinator alloc] initWithFilePresenter:nil];
    [coordinator coordinateReadingItemAtURL:url options:0 error:&coordError byAccessor:^(NSURL *newURL) {
        data=[NSData dataWithContentsOfURL:newURL options:0 error:&readError];
    }];
    if (scoped) [url stopAccessingSecurityScopedResource];

    if (!data.length) {
        NSError *e=readError?:coordError;
        ws.lastStatus=[NSString stringWithFormat:@"手动导入失败：文件读取失败 · %@",e.localizedDescription?:@"未知错误"];
        [self renderPage];
        return;
    }

    NSString *tmp=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"znpatch-%@.json",NSUUID.UUID.UUIDString]];
    NSError *writeError=nil;
    if (![data writeToFile:tmp options:NSDataWritingAtomic error:&writeError]) {
        ws.lastStatus=[NSString stringWithFormat:@"手动导入失败：临时文件写入失败 · %@",writeError.localizedDescription?:@"未知错误"];
        [self renderPage];
        return;
    }

    NSString *importError=nil;
    BOOL ok=[ws importJSONAtPath:tmp error:&importError];
    [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
    if (ok) {
        ws.lastStatus=[NSString stringWithFormat:@"手动导入成功：%@ · Patch %lu",name,(unsigned long)ws.filledCount];
    } else {
        ws.lastStatus=[NSString stringWithFormat:@"手动导入失败：%@",importError?:@"未知错误"];
    }
    ws.showJSONFiles=NO;
    [self renderPage];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    (void)controller;
}

- (void)zn48_renderOther {
    [self zn48_renderOther];
    ZN48RelabelJSONList(self.contentView);
}

- (void)zn48_makeUI:(UIWindow *)window {
    [self zn48_makeUI:window];
    self.footerLabel.text=[NSString stringWithFormat:@"PatchCore 0.4.8    Marker-Sibling Auto JSON + Manual Fallback    iOS %@",UIDevice.currentDevice.systemVersion];
}

- (void)zn48_tick:(NSTimer *)timer {
    [self zn48_tick:timer];
    if (self.uiReady) self.footerLabel.text=[NSString stringWithFormat:@"PatchCore 0.4.8    Marker-Sibling Auto JSON + Manual Fallback    iOS %@",UIDevice.currentDevice.systemVersion];
}

@end

static void ZNSwapV048(Class cls,SEL a,SEL b){
    Method x=class_getInstanceMethod(cls,a),y=class_getInstanceMethod(cls,b);
    if(x&&y) method_exchangeImplementations(x,y);
}

__attribute__((constructor(113))) static void ZNInstallV048JSONImport(void){
    @autoreleasepool {
        Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if(!cls) return;
        ZNSwapV048(cls,@selector(zn44_importJSON:),@selector(zn48_importJSON:));
        ZNSwapV048(cls,@selector(zn44_renderOther),@selector(zn48_renderOther));
        ZNSwapV048(cls,@selector(makeUI:),@selector(zn48_makeUI:));
        ZNSwapV048(cls,@selector(tick:),@selector(zn48_tick:));
        [[ZNRuntimeLogger sharedLogger] log:@"[bootstrap][main] v0.4.8 marker-sibling auto JSON import + coordinated manual fallback installed"];
    }
}
// END inlined ZonoeRuntimeMenuV048.mm
#import "ZNSharedSiteProbe.h"

// v0.4.9 Shared-Site Probe.
// Developer-only instrumentation for the known EarntoDieRogue sample. It hooks
// the patch object's -setActive: entry and records the shared UnityFramework
// site before / after each Posters(5) or Prestige(10) transition. This is a
// diagnostic probe only; it does not write target executable memory.

@interface ZNRuntimeMenuControllerV040 (V049)
- (void)zn49_renderDebug;
- (void)zn49_makeUI:(UIWindow *)window;
- (void)zn49_tick:(NSTimer *)timer;
- (void)zn49_toggleSharedSiteProbe:(id)sender;
- (void)zn49_snapshotSharedSiteProbe:(id)sender;
- (void)zn49_clearSharedSiteProbe:(id)sender;
- (void)zn49_copySharedSiteProbe:(id)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (V049)

- (void)zn49_renderDebug {
    [self zn49_renderDebug];

    CGFloat width=CGRectGetWidth(self.contentView.bounds);
    CGFloat y=MAX(CGRectGetHeight(self.contentView.frame),CGRectGetHeight(self.contentScroll.bounds))+4.0;
    ZNSharedSiteProbe *probe=[ZNSharedSiteProbe sharedProbe];

    [self addSection:@"Shared-Site Probe"
            subtitle:@"开发者专项探针 · MdhpNuX -setActive: · Posters(5) / Prestige(10) · 只读共享地址"
                   y:&y
               width:width];
    [self zn40_addInfoCard:@"0x2E25904 专项状态" lines:[probe diagnosticLines] y:&y width:width];

    NSString *toggleTitle=probe.isLoggingEnabled?@"暂停 Probe":@"启用 Probe";
    [self zn40_addActionCardY:&y width:width
                        titles:@[toggleTitle,@"记录当前状态"]
                     selectors:@[@"zn49_toggleSharedSiteProbe:",@"zn49_snapshotSharedSiteProbe:"]];
    [self zn40_addActionCardY:&y width:width
                        titles:@[@"清除 Probe 日志",@"复制 Probe 日志"]
                     selectors:@[@"zn49_clearSharedSiteProbe:",@"zn49_copySharedSiteProbe:"]];
    [self zn40_updateContentHeight:y];
}

- (void)zn49_toggleSharedSiteProbe:(id)sender {
    (void)sender;
    ZNSharedSiteProbe *probe=[ZNSharedSiteProbe sharedProbe];
    if (!probe.isInstalled || !probe.isLoggingEnabled) {
        NSString *error=nil;
        BOOL ok=[probe installAndEnable:&error];
        if (!ok) [self zn43_showMessage:@"Probe 启用失败" body:error?:@"未知错误"];
    } else {
        [probe setLoggingEnabled:NO];
    }
    [self renderPage];
}

- (void)zn49_snapshotSharedSiteProbe:(id)sender {
    (void)sender;
    ZNSharedSiteProbe *probe=[ZNSharedSiteProbe sharedProbe];
    if (!probe.isInstalled) {
        NSString *error=nil;
        if (![probe installAndEnable:&error]) {
            [self zn43_showMessage:@"Probe 未安装" body:error?:@"未知错误"];
            [self renderPage];
            return;
        }
    }
    [probe captureCurrentStateWithLabel:@"manual"];
    [self renderPage];
}

- (void)zn49_clearSharedSiteProbe:(id)sender {
    (void)sender;
    [[ZNSharedSiteProbe sharedProbe] clearLog];
    [self renderPage];
}

- (void)zn49_copySharedSiteProbe:(id)sender {
    (void)sender;
    ZNSharedSiteProbe *probe=[ZNSharedSiteProbe sharedProbe];
    UIPasteboard.generalPasteboard.string=[probe logText];
    [[ZNRuntimeLogger sharedLogger] log:@"[SSP] Probe 日志已复制"];
    [self renderPage];
}

- (void)zn49_makeUI:(UIWindow *)window {
    [self zn49_makeUI:window];
    self.footerLabel.text=[NSString stringWithFormat:@"PatchCore 0.5.0    Consolidated Menu + Shared-Site Probe    iOS %@",UIDevice.currentDevice.systemVersion];
}

- (void)zn49_tick:(NSTimer *)timer {
    [self zn49_tick:timer];
    if (self.uiReady) self.footerLabel.text=[NSString stringWithFormat:@"PatchCore 0.5.0    Consolidated Menu + Shared-Site Probe    iOS %@",UIDevice.currentDevice.systemVersion];
}

@end

static void ZNSwapV049(Class cls,SEL a,SEL b) {
    Method x=class_getInstanceMethod(cls,a),y=class_getInstanceMethod(cls,b);
    if (x&&y) method_exchangeImplementations(x,y);
}

__attribute__((constructor(114))) static void ZNInstallV049SharedSiteProbeUI(void) {
    @autoreleasepool {
        Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNSwapV049(cls,@selector(zn40_renderDebug),@selector(zn49_renderDebug));
        ZNSwapV049(cls,@selector(makeUI:),@selector(zn49_makeUI:));
        ZNSwapV049(cls,@selector(tick:),@selector(zn49_tick:));
        [[ZNRuntimeLogger sharedLogger] log:@"[bootstrap][main] v0.5.0 consolidated menu + shared-site probe installed"];
    }
}
