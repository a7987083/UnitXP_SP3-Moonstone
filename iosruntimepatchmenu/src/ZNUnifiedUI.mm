// ZNUnifiedUI.mm
// Single UI owner for Runtime Patch Menu.
// Consolidated from baseline b72c2a271c703e494397f680c327a26a6cf275f5 without intentional behavior changes.
// UI drawing, layout and UIKit interaction handlers live in this translation unit.


#pragma mark - BEGIN ZonoeRuntimeMenu.mm
#line 1 "ZonoeRuntimeMenu.mm"
#import "ZNBinaryPatchWorkspace.h"
// Zonoe Runtime Patch Menu — consolidated current source
// v0.5.5 full deferred bootstrap
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
#import "ZNDeferredBootstrap.h"

static void ZNInstallV040Swizzles(void);

static void ZNRuntimeCoreBootstrapV040(void) {
    @autoreleasepool {
        [ZNPatchManager sharedManager];
        [[ZNDeveloperGate sharedGate] refresh];
        [[ZNIL2CPPResolver sharedResolver] refresh];
        ZNInstallV040Swizzles();
        [[ZNRuntimeLogger sharedLogger] log:@"Runtime Patch Menu 0.5.5 deferred bootstrap（Stock iOS / No JIT）"];
    }
}

// Current visual primitives originate from the stable UI core; v0.5.3 installs the active runtime layers in one explicit order,
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

static NSString * const kZNMenuVersion = @"0.5.6.2-ui-core";
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

static uint32_t ZonoePatchGetAPIVersion(void){return 1;}
static const char *ZonoePatchGetVersion(void){return "0.5.6-ui-core";}
static void ZonoePatchStart(void){dispatch_async(dispatch_get_main_queue(),^{[[ZNRuntimeMenuControllerV024 shared] start];});}
static void ZonoePatchShow(void){dispatch_async(dispatch_get_main_queue(),^{[[ZNRuntimeMenuControllerV024 shared] show];});}
static void ZonoePatchHide(void){dispatch_async(dispatch_get_main_queue(),^{[[ZNRuntimeMenuControllerV024 shared] hide];});}
static bool ZonoePatchIsVisible(void){__block BOOL v=NO;if(NSThread.isMainThread)return [[ZNRuntimeMenuControllerV024 shared] isVisible];dispatch_sync(dispatch_get_main_queue(),^{v=[[ZNRuntimeMenuControllerV024 shared] isVisible];});return v;}

static void ZNRuntimeMenuBootstrapV024(void){@autoreleasepool{NSLog(@"[ZonoPatch] ui-core loaded");ZonoePatchStart();}}
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
    self.footerLabel.text = [NSString stringWithFormat:@"PatchCore 0.5.6    No JIT    iOS %@", UIDevice.currentDevice.systemVersion];
}

- (void)zn40_tick:(NSTimer *)timer {
    [self zn40_tick:timer];
    [[ZNDeveloperGate sharedGate] refresh];
    [self zn40_refreshDeveloperCategories:NO];
    [self zn40_updateSubtitle];
    if (self.uiReady) self.footerLabel.text = [NSString stringWithFormat:@"PatchCore 0.5.6    No JIT    iOS %@", UIDevice.currentDevice.systemVersion];
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
extern "C" __attribute__((visibility("default"))) const char *ZonoePatchGetVersion(void) { return "0.5.6-ui-consolidated"; }
extern "C" __attribute__((visibility("default"))) void ZonoePatchStart(void) {
    if (!ZNDeferredBootstrapIsActivated()) return;
    [[ZNDeveloperGate sharedGate] refresh];
    [ZNPatchManager sharedManager];
    [[ZNIL2CPPResolver sharedResolver] refresh];
    ZonoePatchStartBaselineV024();
}
extern "C" __attribute__((visibility("default"))) void ZonoePatchShow(void) {
    if (!ZNDeferredBootstrapIsActivated()) return;
    ZonoePatchShowBaselineV024();
}
extern "C" __attribute__((visibility("default"))) void ZonoePatchHide(void) {
    if (!ZNDeferredBootstrapIsActivated()) return;
    ZonoePatchHideBaselineV024();
}
extern "C" __attribute__((visibility("default"))) bool ZonoePatchIsVisible(void) {
    return ZNDeferredBootstrapIsActivated() && ZonoePatchIsVisibleBaselineV024();
}
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

static void ZNInstallV0401UIFixes(void) {
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

static void ZNInstallV0402TouchPolicyFix(void) {
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
    self.footerLabel.text = [NSString stringWithFormat:@"PatchCore 0.5.6    No JIT    iOS %@", UIDevice.currentDevice.systemVersion];
}

@end

static void ZNSwapInstanceMethodV042(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

static void ZNInstallV042MenuDiagnostics(void) {
    @autoreleasepool {
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNSwapInstanceMethodV042(cls, @selector(zn40_addInfoCard:lines:y:width:), @selector(zn42_addInfoCard:lines:y:width:));
        ZNSwapInstanceMethodV042(cls, @selector(zn40_selfTest:), @selector(zn42_selfTest:));
        ZNSwapInstanceMethodV042(cls, @selector(makeUI:), @selector(zn42_makeUI:));
        [[ZNRuntimeLogger sharedLogger] log:@"[bootstrap][ui-layer] diagnostics diagnostics UI installed: wrap=ON executableProbe=ON"];
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
    self.footerLabel.text = [NSString stringWithFormat:@"PatchCore 0.5.6    Runtime Validation    iOS %@", UIDevice.currentDevice.systemVersion];
}

- (void)zn43_tick:(NSTimer *)timer {
    [self zn43_tick:timer];
    if (self.uiReady) self.footerLabel.text = [NSString stringWithFormat:@"PatchCore 0.5.6    Runtime Validation    iOS %@", UIDevice.currentDevice.systemVersion];
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
    ZNBinaryPatchWorkspace *workspace=[ZNBinaryPatchWorkspace sharedWorkspace];
    NSString *globalTarget=[workspace.defaultTarget ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    BOOL autoTarget=!globalTarget.length||[globalTarget caseInsensitiveCompare:@"自动"]==NSOrderedSame||[globalTarget caseInsensitiveCompare:@"auto"]==NSOrderedSame;
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Target，例如 UnityFramework";
        field.text = autoTarget ? (validator.target.length ? validator.target : @"UnityFramework") : globalTarget;
        field.enabled = autoTarget;
        field.textColor = autoTarget ? UIColor.labelColor : UIColor.secondaryLabelColor;
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
        NSString *effectiveTarget=autoTarget?(alert.textFields[0].text?:@""):globalTarget;
        BOOL ok = [validator configureTarget:effectiveTarget
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

static void ZNInstallV043RuntimeValidation(void) {
    @autoreleasepool {
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNSwapInstanceMethodV043(cls, @selector(zn40_renderDebug), @selector(zn43_renderDebug));
        ZNSwapInstanceMethodV043(cls, @selector(makeUI:), @selector(zn43_makeUI:));
        ZNSwapInstanceMethodV043(cls, @selector(tick:), @selector(zn43_tick:));
        [[ZNRuntimeLogger sharedLogger] log:@"[bootstrap][ui-layer] runtime validation runtime validation installed: live-original / temporary-apply / verified-restore"];
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
    self.footerLabel.text=[NSString stringWithFormat:@"PatchCore 0.5.6    Binary Builder    iOS %@",UIDevice.currentDevice.systemVersion];
}
- (void)zn44_tick:(NSTimer *)timer {
    [self zn44_tick:timer]; if(self.uiReady)self.footerLabel.text=[NSString stringWithFormat:@"PatchCore 0.5.6    Binary Builder    iOS %@",UIDevice.currentDevice.systemVersion];
}

- (void)zn44_renderOther {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width=CGRectGetWidth(self.contentView.bounds),y=9.0; ZNBinaryPatchWorkspace *ws=[ZNBinaryPatchWorkspace sharedWorkspace]; [ws ensureDefaultRows];
    BOOL locked=ws.hasAnyApplied||ws.isBuilding;
    [self addSection:@"二进制生成" subtitle:@"q 开发者工具 · Inline Patch Editor · Universal JSON · Static Dispatch / No-JIT" y:&y width:width];

    UIView *targetCard=[self cardAtY:y height:58 width:width compact:NO];
    UILabel *tl=[self label:@"全局 Target" size:11.5 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];tl.frame=CGRectMake(13,7,56,18);[targetCard addSubview:tl];
    CGFloat buttonW=76; UITextField *target=[self zn44_field:CGRectMake(68,7,targetCard.bounds.size.width-68-buttonW-20,34) text:ws.defaultTarget placeholder:@"自动 / UnityFramework" tag:440000 enabled:!locked];[targetCard addSubview:target];
    UIButton *import=[self zn40_button:ws.showJSONFiles?@"收起 JSON":@"导入 JSON" selector:@selector(zn44_importJSON:) frame:CGRectMake(targetCard.bounds.size.width-buttonW-9,7,buttonW,34)];import.enabled=!locked;[targetCard addSubview:import];
    UILabel *hint=[self label:@"自动=允许 JSON/诊断自行选择；填写模块名=所有路径强制使用该 Target" size:8.7 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];hint.frame=CGRectMake(13,42,targetCard.bounds.size.width-26,13);[targetCard addSubview:hint];
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
static dispatch_queue_t ZN44PatchExecutionQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue=dispatch_queue_create("com.zonoe.patch.workspace.execution", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

- (void)zn44_applyAll:(id)sender {
    (void)sender;
    [self.hostWindow endEditing:YES];
    ZNBinaryPatchWorkspace *ws=[ZNBinaryPatchWorkspace sharedWorkspace];
    if(ws.isBuilding)return;

    ws.building=YES;
    ws.lastStatus=@"正在应用 Runtime Patch…";
    [self renderPage];

    __weak typeof(self) weakSelf=self;
    dispatch_async(ZN44PatchExecutionQueue(), ^{
        @autoreleasepool {
            NSString *e=nil;
            BOOL ok=[ws applyAll:&e];
            dispatch_async(dispatch_get_main_queue(), ^{
                ws.building=NO;
                if(!ok&&e.length){
                    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[builder] apply: %@",e]];
                    if(!ws.lastStatus.length||[ws.lastStatus isEqualToString:@"正在应用 Runtime Patch…"])
                        ws.lastStatus=[NSString stringWithFormat:@"应用失败：%@",e];
                }
                [weakSelf renderPage];
            });
        }
    });
}

- (void)zn44_restoreAll:(id)sender {
    (void)sender;
    [self.hostWindow endEditing:YES];
    ZNBinaryPatchWorkspace *ws=[ZNBinaryPatchWorkspace sharedWorkspace];
    if(ws.isBuilding)return;

    ws.building=YES;
    ws.lastStatus=@"正在恢复 Runtime Patch…";
    [self renderPage];

    __weak typeof(self) weakSelf=self;
    dispatch_async(ZN44PatchExecutionQueue(), ^{
        @autoreleasepool {
            NSString *e=nil;
            BOOL ok=[ws restoreAll:&e];
            dispatch_async(dispatch_get_main_queue(), ^{
                ws.building=NO;
                if(!ok&&e.length){
                    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[builder] restore: %@",e]];
                    if(!ws.lastStatus.length||[ws.lastStatus isEqualToString:@"正在恢复 Runtime Patch…"])
                        ws.lastStatus=[NSString stringWithFormat:@"恢复失败：%@",e];
                }
                [weakSelf renderPage];
            });
        }
    });
}
- (void)zn44_buildBinary:(id)sender {(void)sender;[self.hostWindow endEditing:YES];ZNBinaryPatchWorkspace *ws=[ZNBinaryPatchWorkspace sharedWorkspace];if(ws.isBuilding)return;if(ws.hasAnyApplied){ws.lastStatus=@"生成前必须先恢复 Runtime Patch";[self renderPage];return;}ws.building=YES;ws.lastStatus=@"正在生成：验证 Mach-O / 安全 gap / relocation…";[self renderPage];__weak typeof(self) weakSelf=self;dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSArray *paths=nil;NSString *report=nil,*error=nil;BOOL ok=[ZNStaticBinaryBuilder buildWorkspace:ws outputs:&paths report:&report error:&error];dispatch_async(dispatch_get_main_queue(),^{ws.building=NO;if(ok)[ws setBuildOutputs:paths status:report?:@"生成成功"];else[ws setBuildOutputs:@[] status:[NSString stringWithFormat:@"生成失败：%@",error?:@"未知错误"]];[weakSelf renderPage];});});}
- (void)zn44_toggleStatic:(UIButton *)sender {ZNStaticDispatchRuntime *rt=[ZNStaticDispatchRuntime sharedRuntime];NSUInteger i=(NSUInteger)(sender.tag-447000);if(i>=rt.records.count)return;ZNStaticPatchRecord *r=rt.records[i];NSString *e=nil;if(![rt setEnabled:!r.enabled forRecord:r error:&e])[[ZNBinaryPatchWorkspace sharedWorkspace] setBuildOutputs:[ZNBinaryPatchWorkspace sharedWorkspace].lastOutputPaths status:[NSString stringWithFormat:@"Static Dispatch 切换失败：%@",e?:@"未知错误"]];[self renderPage];}
@end

static void ZNSwapV044(Class cls,SEL a,SEL b){Method x=class_getInstanceMethod(cls,a),y=class_getInstanceMethod(cls,b);if(x&&y)method_exchangeImplementations(x,y);}
static void ZNInstallV044BinaryBuilder(void){@autoreleasepool{Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040");if(!cls)return;ZNSwapV044(cls,@selector(renderFullPage),@selector(zn44_renderFullPage));ZNSwapV044(cls,@selector(fullSizeForWindow:),@selector(zn44_fullSizeForWindow:));ZNSwapV044(cls,@selector(makeUI:),@selector(zn44_makeUI:));ZNSwapV044(cls,@selector(tick:),@selector(zn44_tick:));[[ZNRuntimeLogger sharedLogger] log:@"[bootstrap][ui-layer] binary builder embedded patch editor / universal JSON / static binary builder installed"];}}
// END inlined ZonoeRuntimeMenuV044.mm

// v0.5.3: legacy V045 Feature/Compact renderer removed.
// ZNFeatureGroupUI is the sole public Feature renderer.
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
    self.footerLabel.text=[NSString stringWithFormat:@"PatchCore 0.5.6    Marker-Sibling Auto JSON + Manual Fallback    iOS %@",UIDevice.currentDevice.systemVersion];
}

- (void)zn48_tick:(NSTimer *)timer {
    [self zn48_tick:timer];
    if (self.uiReady) self.footerLabel.text=[NSString stringWithFormat:@"PatchCore 0.5.6    Marker-Sibling Auto JSON + Manual Fallback    iOS %@",UIDevice.currentDevice.systemVersion];
}

@end

static void ZNSwapV048(Class cls,SEL a,SEL b){
    Method x=class_getInstanceMethod(cls,a),y=class_getInstanceMethod(cls,b);
    if(x&&y) method_exchangeImplementations(x,y);
}

static void ZNInstallV048JSONImport(void){
    @autoreleasepool {
        Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if(!cls) return;
        ZNSwapV048(cls,@selector(zn44_importJSON:),@selector(zn48_importJSON:));
        ZNSwapV048(cls,@selector(zn44_renderOther),@selector(zn48_renderOther));
        ZNSwapV048(cls,@selector(makeUI:),@selector(zn48_makeUI:));
        ZNSwapV048(cls,@selector(tick:),@selector(zn48_tick:));
        [[ZNRuntimeLogger sharedLogger] log:@"[bootstrap][ui-layer] JSON import marker-sibling auto JSON import + coordinated manual fallback installed"];
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
    self.footerLabel.text=[NSString stringWithFormat:@"PatchCore 0.5.6    Consolidated Menu + Shared-Site Probe    iOS %@",UIDevice.currentDevice.systemVersion];
}

- (void)zn49_tick:(NSTimer *)timer {
    [self zn49_tick:timer];
    if (self.uiReady) self.footerLabel.text=[NSString stringWithFormat:@"PatchCore 0.5.6    Consolidated Menu + Shared-Site Probe    iOS %@",UIDevice.currentDevice.systemVersion];
}

@end

static void ZNSwapV049(Class cls,SEL a,SEL b) {
    Method x=class_getInstanceMethod(cls,a),y=class_getInstanceMethod(cls,b);
    if (x&&y) method_exchangeImplementations(x,y);
}

static void ZNInstallV049SharedSiteProbeUI(void) {
    @autoreleasepool {
        Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNSwapV049(cls,@selector(zn40_renderDebug),@selector(zn49_renderDebug));
        ZNSwapV049(cls,@selector(makeUI:),@selector(zn49_makeUI:));
        ZNSwapV049(cls,@selector(tick:),@selector(zn49_tick:));
        [[ZNRuntimeLogger sharedLogger] log:@"[bootstrap][main] v0.5.0 consolidated menu + shared-site probe installed"];
    }
}

// v0.5.5 current UI layer. One swizzle set owns active menu behavior instead of
// chaining V040/V0401/V0402/V042/V043/V044/V045/V048/V049 wrappers.
@interface ZNRuntimeMenuControllerV040 (V053Current)
- (instancetype)zn53_init;
- (void)zn53_makeUI:(UIWindow *)window;
- (void)zn53_tick:(NSTimer *)timer;
- (void)zn53_togglePanel:(id)sender;
- (void)zn53_renderPage;
- (void)zn53_renderFullPage;
- (void)zn53_renderDebug;
- (CGSize)zn53_fullSizeForWindow:(UIWindow *)window;
- (void)zn53_themeTapped:(id)sender;
- (UIButton *)zn53_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)zn53_addInfoCard:(NSString *)title lines:(NSArray<NSString *> *)lines y:(CGFloat *)y width:(CGFloat)width;
- (void)zn53_selfTest:(id)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (V053Current)

- (instancetype)zn53_init {
    id obj = [self zn53_init];
    if (!obj) return nil;
    [ZNPatchManager sharedManager];
    [[ZNDeveloperGate sharedGate] refresh];
    [self zn40_refreshDeveloperCategories:NO];
    return obj;
}

- (void)zn53_applyTouchPolicy {
    NSString *cat = (self.selectedCategory >= 0 && self.selectedCategory < self.categories.count)
        ? self.categories[self.selectedCategory] : @"";
    BOOL immediatePage = self.compactMode ||
                         [cat isEqualToString:@"功能"] ||
                         [cat isEqualToString:@"诊断"] ||
                         [cat isEqualToString:@"Debug"];

    // M6.3: Feature controls must dispatch on a normal tap. Keep cancellation
    // enabled so UIScrollView can still take ownership once the user drags.
    self.contentScroll.delaysContentTouches = !immediatePage;
    self.contentScroll.canCancelContentTouches = YES;
}

- (void)zn53_makeUI:(UIWindow *)window {
    [self zn53_makeUI:window];
    [self zn40_refreshDeveloperCategories:YES];
    [self zn40_updateSubtitle];
    [self zn53_applyTouchPolicy];
    self.footerLabel.text = [NSString stringWithFormat:@"PatchCore 0.5.6    Current UI    iOS %@", UIDevice.currentDevice.systemVersion];
}

- (void)zn53_tick:(NSTimer *)timer {
    [self zn53_tick:timer];
    // Developer authorization is a process-start snapshot in v0.5.2+; no
    // marker re-read or category mutation occurs on the periodic UI tick.
    [self zn40_updateSubtitle];
    if (self.uiReady) self.footerLabel.text = [NSString stringWithFormat:@"PatchCore 0.5.6    Current UI    iOS %@", UIDevice.currentDevice.systemVersion];
}

- (void)zn53_togglePanel:(id)sender {
    [self zn53_togglePanel:sender];
    [self zn40_updateSubtitle];
}

- (void)zn53_renderPage {
    [self zn53_renderPage];

    // Legacy V0402 is inside the historical render chain and may restore
    // delaysContentTouches=YES for normal pages. Apply the current policy last
    // so Feature/compact surfaces keep immediate touch semantics.
    [self zn53_applyTouchPolicy];
}

- (void)zn53_renderDebug {
    [self zn40_renderDebug];

    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat y = MAX(CGRectGetHeight(self.contentView.frame), CGRectGetHeight(self.contentScroll.bounds)) + 4.0;
    ZNPatchRuntimeValidator *validator = [ZNPatchRuntimeValidator sharedValidator];

    [self addSection:@"Patch 实机验证"
            subtitle:@"开发者工具 · target + offset + patch · Live Original · 临时应用 / 精确恢复"
                   y:&y width:width];
    [self zn40_addInfoCard:@"当前验证会话" lines:[validator diagnosticLines] y:&y width:width];
    [self zn40_addActionCardY:&y width:width titles:@[@"配置 Patch", @"读取 / 验证"] selectors:@[@"zn43_configureRuntimePatch:", @"zn43_validateRuntimePatch:"]];
    [self zn40_addActionCardY:&y width:width titles:@[@"临时应用", @"恢复原始"] selectors:@[@"zn43_applyRuntimePatch:", @"zn43_restoreRuntimePatch:"]];
    [self zn40_addActionCardY:&y width:width titles:@[@"复制验证报告", @"清除会话"] selectors:@[@"zn43_copyRuntimeValidation:", @"zn43_clearRuntimeValidation:"]];
    [self zn40_updateContentHeight:y];

    y = MAX(CGRectGetHeight(self.contentView.frame), CGRectGetHeight(self.contentScroll.bounds)) + 4.0;
    ZNSharedSiteProbe *probe = [ZNSharedSiteProbe sharedProbe];
    [self addSection:@"Shared-Site Probe"
            subtitle:@"开发者专项探针 · MdhpNuX -setActive: · Posters(5) / Prestige(10) · 只读共享地址"
                   y:&y width:width];
    [self zn40_addInfoCard:@"0x2E25904 专项状态" lines:[probe diagnosticLines] y:&y width:width];
    NSString *toggleTitle = probe.isLoggingEnabled ? @"暂停 Probe" : @"启用 Probe";
    [self zn40_addActionCardY:&y width:width titles:@[toggleTitle, @"记录当前状态"] selectors:@[@"zn49_toggleSharedSiteProbe:", @"zn49_snapshotSharedSiteProbe:"]];
    [self zn40_addActionCardY:&y width:width titles:@[@"清除 Probe 日志", @"复制 Probe 日志"] selectors:@[@"zn49_clearSharedSiteProbe:", @"zn49_copySharedSiteProbe:"]];
    [self zn40_updateContentHeight:y];
}

- (void)zn53_renderFullPage {
    NSString *cat = (self.selectedCategory >= 0 && self.selectedCategory < self.categories.count)
        ? self.categories[self.selectedCategory] : @"";
    if ([cat isEqualToString:@"诊断"]) { [self zn40_renderDiagnostics]; return; }
    if ([cat isEqualToString:@"Debug"]) { [self zn53_renderDebug]; return; }
    if ([cat isEqualToString:@"其他"]) { [self zn44_renderOther]; return; }
    [self zn53_renderFullPage];
}

- (CGSize)zn53_fullSizeForWindow:(UIWindow *)window {
    CGSize size = [self zn53_fullSizeForWindow:window];
    NSString *cat = (self.selectedCategory >= 0 && self.selectedCategory < self.categories.count)
        ? self.categories[self.selectedCategory] : @"";
    CGFloat desired = size.height;
    if ([cat isEqualToString:@"功能"]) desired = MAX(desired, 390.0);
    else if ([cat isEqualToString:@"其他"]) desired = MAX(desired, 500.0);
    else if ([cat isEqualToString:@"设置"]) desired = MAX(desired, 415.0);
    else if ([cat isEqualToString:@"主题"]) {
        BOOL landscape = CGRectGetWidth(window.bounds) >= CGRectGetHeight(window.bounds);
        desired = MAX(desired, landscape ? 410.0 : 430.0);
    } else if ([cat isEqualToString:@"诊断"] || [cat isEqualToString:@"Debug"]) {
        desired = MAX(desired, 470.0);
    }
    UIEdgeInsets insets = window.safeAreaInsets;
    CGFloat available = MAX(300.0, CGRectGetHeight(window.bounds)-insets.top-insets.bottom-20.0);
    size.height = MIN(desired, available);
    return size;
}

- (void)zn53_themeTapped:(id)sender {
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

- (UIButton *)zn53_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame {
    UIButton *button = [self zn53_button:title selector:selector frame:frame];
    button.showsTouchWhenHighlighted = YES;
    button.exclusiveTouch = YES;
    return button;
}

- (void)zn53_addInfoCard:(NSString *)title lines:(NSArray<NSString *> *)lines y:(CGFloat *)y width:(CGFloat)width {
    CGFloat cardWidth = MAX(0.0, width - 20.0);
    CGFloat textWidth = MAX(20.0, cardWidth - 26.0);
    UIFont *font = [self menuFont:9.8 weight:UIFontWeightRegular];
    NSMutableArray<NSNumber *> *heights = [NSMutableArray arrayWithCapacity:lines.count];
    CGFloat bodyHeight = 0.0;
    for (NSString *line in lines) {
        CGRect r = [line boundingRectWithSize:CGSizeMake(textWidth, CGFLOAT_MAX)
                                      options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                   attributes:@{NSFontAttributeName:font} context:nil];
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
    for (NSUInteger i=0; i<lines.count; i++) {
        UILabel *l = [self label:lines[i] size:9.8 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        CGFloat lineHeight = heights[i].doubleValue;
        l.frame = CGRectMake(13,ly,card.bounds.size.width-26,lineHeight);
        l.numberOfLines = 0;
        l.lineBreakMode = NSLineBreakByWordWrapping;
        l.adjustsFontSizeToFitWidth = NO;
        [card addSubview:l];
        ly += lineHeight;
    }
    [self.contentView addSubview:card];
    *y += h + 8.0;
}

- (void)zn53_selfTest:(id)sender {
    [self zn53_selfTest:sender];
    CFAbsoluteTime begin = CFAbsoluteTimeGetCurrent();
    BOOL supported = [[ZNExecutablePageProbe sharedProbe] runProbe];
    double totalMs = (CFAbsoluteTimeGetCurrent() - begin) * 1000.0;
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[probe][%@] __TEXT RX→RW→RX %@ total=%.2fms detail=%@",
        NSThread.isMainThread?@"main":@"bg", supported?@"PASS":@"UNSUPPORTED/FAIL", totalMs,
        [ZNExecutablePageProbe sharedProbe].lastResult ?: @""]];
    [self renderPage];
}

@end

static void ZNSwapV053(Class cls, SEL a, SEL b) {
    Method x = class_getInstanceMethod(cls,a), y = class_getInstanceMethod(cls,b);
    if (x && y) method_exchangeImplementations(x,y);
}

static void ZNInstallV053CurrentUI(void) {
    Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
    if (!cls) return;
    ZNSwapV053(cls,@selector(init),@selector(zn53_init));
    ZNSwapV053(cls,@selector(enabledForFeature:),@selector(zn40_enabledForFeature:));
    ZNSwapV053(cls,@selector(setFeature:enabled:),@selector(zn40_setFeature:enabled:));
    ZNSwapV053(cls,@selector(valueForFeature:fallback:),@selector(zn40_valueForFeature:fallback:));
    ZNSwapV053(cls,@selector(setFeature:value:),@selector(zn40_setFeature:value:));
    ZNSwapV053(cls,@selector(makeUI:),@selector(zn53_makeUI:));
    ZNSwapV053(cls,@selector(tick:),@selector(zn53_tick:));
    ZNSwapV053(cls,@selector(togglePanel:),@selector(zn53_togglePanel:));
    ZNSwapV053(cls,@selector(renderPage),@selector(zn53_renderPage));
    ZNSwapV053(cls,@selector(renderFullPage),@selector(zn53_renderFullPage));
    ZNSwapV053(cls,@selector(fullSizeForWindow:),@selector(zn53_fullSizeForWindow:));
    ZNSwapV053(cls,@selector(themeTapped:),@selector(zn53_themeTapped:));
    ZNSwapV053(cls,@selector(zn40_button:selector:frame:),@selector(zn53_button:selector:frame:));
    ZNSwapV053(cls,@selector(zn40_addInfoCard:lines:y:width:),@selector(zn53_addInfoCard:lines:y:width:));
    ZNSwapV053(cls,@selector(zn40_selfTest:),@selector(zn53_selfTest:));
    ZNSwapV053(cls,@selector(zn44_importJSON:),@selector(zn48_importJSON:));
}

extern "C" void ZNInstallRuntimeMenuV055Deferred(void) {
    @autoreleasepool {
        [ZNPatchManager sharedManager];
        [[ZNDeveloperGate sharedGate] refresh];
        [[ZNIL2CPPResolver sharedResolver] refresh];
        ZNInstallV053CurrentUI();
        [[ZNRuntimeLogger sharedLogger] log:@"[bootstrap][deferred] v0.5.6 current UI installed after first launcher tap"];
    }
}

#pragma mark - END ZonoeRuntimeMenu.mm


#pragma mark - BEGIN ZNDeferredBootstrap.mm
#line 1 "ZNDeferredBootstrap.mm"
#import "ZNDeferredBootstrap.h"
#import <UIKit/UIKit.h>
#import <atomic>

extern "C" void ZNInstallSharedSiteExecutionProbeV3Deferred(void);
extern "C" void ZNInstallPublicCompactLayoutDeferred(void);
extern "C" void ZNInstallRuntimeExecutorV041Deferred(void);
extern "C" void ZNInstallRuntimeDiagnosticsV042Deferred(void);
extern "C" void ZNPrepareStaticDispatchRuntimeDeferred(void);
extern "C" void ZNInstallRuntimeMenuV055Deferred(void);
extern "C" void ZNInstallFeatureGroupUIDeferred(void);
extern "C" void ZNInstallPublicCompactDefaultsDeferred(void);
extern "C" void ZNInstallIL2CPPNamedOffsetWorkspaceDeferred(void);
extern "C" void ZNInstallFeatureBuilderUIDeferred(void);
extern "C" void ZNInstallRuntimeMethodCallBuilderUIDeferred(void);
extern "C" void ZNInstallMethodFinderUnifiedUIDeferred(void);
extern "C" void ZNInstallM630HardCutUIDeferred(void);

extern "C" void ZonoePatchStart(void);
extern "C" void ZonoePatchShow(void);

typedef NS_ENUM(int, ZNDeferredState) {
    ZNDeferredStateCold = 0,
    ZNDeferredStateLoading = 1,
    ZNDeferredStateReady = 2,
    ZNDeferredStateFailed = 3,
};

static std::atomic<int> gZNDeferredState{ZNDeferredStateCold};
static NSString * const kZNDeferredFloatPositionKey = @"ZonoePatch.FloatCenter";
static const CGFloat kZNDeferredFloatSize = 52.0;
static const CGFloat kZNDeferredMargin = 10.0;

static void ZNRunActivationStage(NSString *name, void (^block)(void)) {
    (void)name;
    block();
}

extern "C" BOOL ZNDeferredBootstrapIsActivated(void) {
    int state = gZNDeferredState.load(std::memory_order_acquire);
    return state == ZNDeferredStateLoading || state == ZNDeferredStateReady;
}

extern "C" BOOL ZNDeferredBootstrapIsReady(void) {
    return gZNDeferredState.load(std::memory_order_acquire) == ZNDeferredStateReady;
}

static UIWindow *ZNDeferredCurrentWindow(void) {
    UIApplication *app = UIApplication.sharedApplication;
    if (@available(iOS 13.0, *)) {
        UIWindow *fallback = nil;
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            if (scene.activationState != UISceneActivationStateForegroundActive &&
                scene.activationState != UISceneActivationStateForegroundInactive) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.hidden || window.alpha <= 0.01) continue;
                if (window.isKeyWindow) return window;
                if (!fallback && window.windowLevel == UIWindowLevelNormal && window.rootViewController) fallback = window;
            }
        }
        if (fallback) return fallback;
    }
    if (app.keyWindow && !app.keyWindow.hidden) return app.keyWindow;
    for (UIWindow *window in app.windows.reverseObjectEnumerator) {
        if (!window.hidden && window.windowLevel == UIWindowLevelNormal && window.rootViewController) return window;
    }
    return nil;
}

@interface ZNDeferredLauncher : NSObject
@property(nonatomic,strong) UIButton *button;
@property(nonatomic,weak) UIWindow *hostWindow;
- (void)installIfPossible;
@end

@implementation ZNDeferredLauncher

+ (instancetype)sharedLauncher {
    static ZNDeferredLauncher *launcher;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ launcher = [ZNDeferredLauncher new]; });
    return launcher;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(zn_windowChanged:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [nc addObserver:self selector:@selector(zn_windowChanged:) name:UIWindowDidBecomeKeyNotification object:nil];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)zn_windowChanged:(NSNotification *)note {
    (void)note;
    [self installIfPossible];
}

- (CGPoint)zn_clamp:(CGPoint)center window:(UIWindow *)window {
    UIEdgeInsets safe = window.safeAreaInsets;
    CGFloat half = kZNDeferredFloatSize * 0.5;
    CGFloat left = safe.left + kZNDeferredMargin + half;
    CGFloat right = CGRectGetWidth(window.bounds) - safe.right - kZNDeferredMargin - half;
    CGFloat top = safe.top + kZNDeferredMargin + half;
    CGFloat bottom = CGRectGetHeight(window.bounds) - safe.bottom - kZNDeferredMargin - half;
    center.x = MIN(MAX(center.x, left), MAX(left, right));
    center.y = MIN(MAX(center.y, top), MAX(top, bottom));
    return center;
}

- (void)installIfPossible {
    if (gZNDeferredState.load(std::memory_order_acquire) == ZNDeferredStateReady) return;
    UIWindow *window = ZNDeferredCurrentWindow();
    if (!window) return;

    if (!self.button) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.bounds = CGRectMake(0, 0, kZNDeferredFloatSize, kZNDeferredFloatSize);
        button.layer.cornerRadius = kZNDeferredFloatSize * 0.5;
        button.layer.borderWidth = 1.5;
        button.layer.borderColor = [UIColor colorWithRed:0.42 green:0.55 blue:1.0 alpha:1.0].CGColor;
        button.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.92];
        [button setTitle:@"ZN" forState:UIControlStateNormal];
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
        button.layer.shadowColor = UIColor.blackColor.CGColor;
        button.layer.shadowOpacity = 0.28;
        button.layer.shadowRadius = 8.0;
        button.layer.shadowOffset = CGSizeZero;
        [button addTarget:self action:@selector(zn_activate:) forControlEvents:UIControlEventTouchUpInside];
        [button addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(zn_pan:)]];
        self.button = button;
    }

    if (self.button.superview != window) {
        [self.button removeFromSuperview];
        self.hostWindow = window;
        NSString *stored = [NSUserDefaults.standardUserDefaults stringForKey:kZNDeferredFloatPositionKey];
        UIEdgeInsets safe = window.safeAreaInsets;
        CGPoint fallback = CGPointMake(CGRectGetWidth(window.bounds) - safe.right - kZNDeferredMargin - kZNDeferredFloatSize * 0.5,
                                       CGRectGetMidY(window.bounds));
        self.button.center = [self zn_clamp:(stored.length ? CGPointFromString(stored) : fallback) window:window];
        [window addSubview:self.button];
    }
    [window bringSubviewToFront:self.button];
}

- (void)zn_pan:(UIPanGestureRecognizer *)gesture {
    if (gZNDeferredState.load(std::memory_order_acquire) != ZNDeferredStateCold) return;
    UIWindow *window = self.hostWindow;
    if (!window) return;
    CGPoint translation = [gesture translationInView:window];
    CGPoint center = self.button.center;
    center.x += translation.x;
    center.y += translation.y;
    self.button.center = [self zn_clamp:center window:window];
    [gesture setTranslation:CGPointZero inView:window];
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        [NSUserDefaults.standardUserDefaults setObject:NSStringFromCGPoint(self.button.center) forKey:kZNDeferredFloatPositionKey];
    }
}

- (void)zn_markFailed:(NSException *)exception {
    gZNDeferredState.store(ZNDeferredStateFailed, std::memory_order_release);
    self.button.enabled = NO;
    self.button.alpha = 1.0;
    [self.button setTitle:@"!" forState:UIControlStateNormal];
    NSLog(@"[ZonoPatch] v0.5.7 deferred activation failed: %@", exception.reason ?: @"unknown exception");
}

- (void)zn_finishActivation {
    @try {
        ZNRunActivationStage(@"RuntimeMenu", ^{ ZNInstallRuntimeMenuV055Deferred(); });
        ZNRunActivationStage(@"FeatureGroupUI", ^{ ZNInstallFeatureGroupUIDeferred(); });
        ZNRunActivationStage(@"PublicCompactDefaults", ^{ ZNInstallPublicCompactDefaultsDeferred(); });
        ZNRunActivationStage(@"IL2CPPNamedOffsetWorkspace", ^{ ZNInstallIL2CPPNamedOffsetWorkspaceDeferred(); });
        ZNRunActivationStage(@"FeatureBuilderUI", ^{ ZNInstallFeatureBuilderUIDeferred(); });
        ZNRunActivationStage(@"RuntimeMethodBuilderUI", ^{ ZNInstallRuntimeMethodCallBuilderUIDeferred(); });
        ZNRunActivationStage(@"MethodFinderUnifiedUI", ^{ ZNInstallMethodFinderUnifiedUIDeferred(); });
        ZNRunActivationStage(@"M630HardCutUI", ^{ ZNInstallM630HardCutUIDeferred(); });

        gZNDeferredState.store(ZNDeferredStateReady, std::memory_order_release);
        ZNRunActivationStage(@"ZonoePatchStart", ^{ ZonoePatchStart(); });
        ZNRunActivationStage(@"ZonoePatchShow", ^{ ZonoePatchShow(); });

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.button removeFromSuperview];
            self.button = nil;
            self.hostWindow = nil;
        });
    } @catch (NSException *exception) {
        [self zn_markFailed:exception];
    }
}

- (void)zn_beginActivation {
    @try {
        // Old +load-era wrappers, then former constructor priorities 104/106/109.
        ZNRunActivationStage(@"SharedSiteExecutionProbeV3", ^{ ZNInstallSharedSiteExecutionProbeV3Deferred(); });
        ZNRunActivationStage(@"PublicCompactLayout", ^{ ZNInstallPublicCompactLayoutDeferred(); });
        ZNRunActivationStage(@"RuntimeExecutorV041", ^{ ZNInstallRuntimeExecutorV041Deferred(); });
        ZNRunActivationStage(@"RuntimeDiagnosticsV042", ^{ ZNInstallRuntimeDiagnosticsV042Deferred(); });
        ZNRunActivationStage(@"StaticDispatchPrepare", ^{ ZNPrepareStaticDispatchRuntimeDeferred(); });

        // Static Dispatch historically waits 350 ms before refresh. Keep that
        // stage behavior. This continuation is queued later on the same main
        // queue, so the refresh must finish before the menu is revealed.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self zn_finishActivation];
        });
    } @catch (NSException *exception) {
        [self zn_markFailed:exception];
    }
}

- (void)zn_activate:(id)sender {
    (void)sender;
    int expected = ZNDeferredStateCold;
    if (!gZNDeferredState.compare_exchange_strong(expected,
                                                   ZNDeferredStateLoading,
                                                   std::memory_order_acq_rel)) {
        return;
    }

    self.button.enabled = NO;
    self.button.alpha = 0.78;
    [self.button setTitle:@"…" forState:UIControlStateNormal];

    // One UI beat makes the loading state visible before the original startup
    // chain begins. The menu appears only after all deferred stages complete.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self zn_beginActivation];
    });
}

@end

// The only v0.5.7 load-time constructor. It owns the cold launcher only and
// intentionally does not touch DeveloperGate, PatchManager, Resolver, Static
// Dispatch, Builder, Diagnostics, Probe, Feature UI, or the menu controller.
__attribute__((constructor(200))) static void ZNDeferredColdLauncherBootstrap(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[ZNDeferredLauncher sharedLauncher] installIfPossible];
    });
}

#pragma mark - END ZNDeferredBootstrap.mm


#pragma mark - BEGIN ZNRuntimeMenuModalShell.mm
#line 1 "ZNRuntimeMenuModalShell.mm"
#import "ZNRuntimeMenuModalShell.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface ZNModalPassthroughView : UIView
@property(nonatomic,weak) UIView *panel;
@end

@implementation ZNModalPassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self) return nil;
    return hit;
}
@end

@interface ZNRuntimeMenuModalViewController : UIViewController
@property(nonatomic,strong) UIView *menuPanel;
@end

@implementation ZNRuntimeMenuModalViewController
- (instancetype)initWithPanel:(UIView *)panel {
    self = [super initWithNibName:nil bundle:nil];
    if (!self) return nil;
    _menuPanel = panel;
    self.modalPresentationStyle = UIModalPresentationOverFullScreen;
    return self;
}

- (void)loadView {
    ZNModalPassthroughView *root = [ZNModalPassthroughView new];
    root.backgroundColor = UIColor.clearColor;
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    root.panel = self.menuPanel;
    self.view = root;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.menuPanel.superview != self.view) {
        [self.menuPanel removeFromSuperview];
        [self.view addSubview:self.menuPanel];
    }
    self.menuPanel.hidden = NO;
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    // Keep the visual tree owned by the runtime menu object, not by a dismissed
    // controller. A fresh modal shell is used on the next presentation.
    [self.menuPanel removeFromSuperview];
}
@end

static const void *kZNModalControllerKey = &kZNModalControllerKey;
static const void *kZNModalPresentingKey = &kZNModalPresentingKey;

static UIViewController *ZNModalTopController(UIViewController *vc) {
    if (!vc) return nil;
    UIViewController *presented = vc.presentedViewController;
    if (presented && !presented.isBeingDismissed) return ZNModalTopController(presented);
    if ([vc isKindOfClass:UINavigationController.class]) {
        UIViewController *top = ((UINavigationController *)vc).visibleViewController;
        return top ? ZNModalTopController(top) : vc;
    }
    if ([vc isKindOfClass:UITabBarController.class]) {
        UIViewController *selected = ((UITabBarController *)vc).selectedViewController;
        return selected ? ZNModalTopController(selected) : vc;
    }
    if ([vc isKindOfClass:UISplitViewController.class]) {
        UIViewController *last = ((UISplitViewController *)vc).viewControllers.lastObject;
        return last ? ZNModalTopController(last) : vc;
    }
    return vc;
}

static BOOL ZNModalIsPresented(id owner) {
    ZNRuntimeMenuModalViewController *modal = objc_getAssociatedObject(owner, kZNModalControllerKey);
    if (!modal) return NO;
    return modal.presentingViewController != nil || modal.isBeingPresented || [objc_getAssociatedObject(owner, kZNModalPresentingKey) boolValue];
}

@interface ZNRuntimeMenuControllerV040 (ZNRuntimeMenuModalShell)
- (void)znmodal_makeUI:(UIWindow *)window;
- (void)znmodal_attach:(UIWindow *)window;
- (void)znmodal_tick:(NSTimer *)timer;
- (void)znmodal_show;
- (void)znmodal_hide;
- (BOOL)znmodal_isVisible;
- (void)znmodal_togglePanel:(id)sender;
- (void)znmodal_closeTapped:(id)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNRuntimeMenuModalShell)

- (void)znmodal_makeUI:(UIWindow *)window {
    [self znmodal_makeUI:window];
    // The legacy builder creates the complete visual tree correctly. Only move
    // the panel out of UIWindow ownership; the floating button stays untouched.
    if (self.panel.superview == window) [self.panel removeFromSuperview];
    self.panel.hidden = YES;
}

- (void)znmodal_attach:(UIWindow *)window {
    if (!window || !self.uiReady) return;
    if (self.floatButton.superview != window) {
        [self.floatButton removeFromSuperview];
        [window addSubview:self.floatButton];
    }
    self.hostWindow = window;
    [self layoutForWindow:window initial:NO];
    [self applyTheme];
    if (!ZNModalIsPresented(self) && self.panel.superview == window) [self.panel removeFromSuperview];
}

- (void)znmodal_tick:(NSTimer *)timer {
    (void)timer;
    // While the menu is presented, keep its presentation/window relationship
    // stable. System text services may temporarily change key-window state.
    BOOL menuPresented = ZNModalIsPresented(self);
    UIWindow *window = menuPresented ? self.hostWindow : [self currentWindow];
    if (!window) return;

    if (!self.uiReady) {
        [self makeUI:window];
        return;
    }

    if (!menuPresented && (self.hostWindow != window || self.floatButton.superview != window)) {
        [self attach:window];
    }

    UIWindow *layoutWindow = self.hostWindow ?: window;
    if (layoutWindow && (!CGRectEqualToRect(self.lastBounds, layoutWindow.bounds) ||
                         !UIEdgeInsetsEqualToEdgeInsets(self.lastInsets, layoutWindow.safeAreaInsets))) {
        [self layoutForWindow:layoutWindow initial:NO];
    }
    if (self.themeMode == ZNThemeModeSystem && [self interfaceStyle] != self.lastStyle) [self applyTheme];

    [self zn40_updateSubtitle];
    if (self.uiReady && self.footerLabel) {
        self.footerLabel.text = [NSString stringWithFormat:@"PatchCore 0.5.6    Current UI    iOS %@", UIDevice.currentDevice.systemVersion];
    }
    if (self.floatButton.superview == layoutWindow) [layoutWindow bringSubviewToFront:self.floatButton];
}

- (void)znmodal_show {
    if (!self.uiReady) [self tick:nil];
    if (!self.uiReady || ZNModalIsPresented(self)) return;

    UIWindow *window = self.hostWindow ?: [self currentWindow];
    if (!window || !window.rootViewController) return;
    if (self.floatButton.superview != window) [self attach:window];

    UIViewController *presenter = ZNModalTopController(window.rootViewController);
    if (!presenter || presenter.isBeingDismissed) return;

    ZNRuntimeMenuModalViewController *modal = [[ZNRuntimeMenuModalViewController alloc] initWithPanel:self.panel];
    modal.modalPresentationStyle = UIModalPresentationOverFullScreen;
    modal.view.backgroundColor = UIColor.clearColor;
    objc_setAssociatedObject(self, kZNModalControllerKey, modal, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kZNModalPresentingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    self.panel.hidden = NO;
    [presenter presentViewController:modal animated:NO completion:^{
        objc_setAssociatedObject(self, kZNModalPresentingKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (self.floatButton.superview == window) [window bringSubviewToFront:self.floatButton];
        [[ZNRuntimeLogger sharedLogger] log:@"[menu-modal] presented via UIModalPresentationOverFullScreen"];
    }];
}

- (void)znmodal_hide {
    ZNRuntimeMenuModalViewController *modal = objc_getAssociatedObject(self, kZNModalControllerKey);
    if (!modal) {
        self.panel.hidden = YES;
        [self.panel removeFromSuperview];
        return;
    }

    self.panel.hidden = YES;
    UIViewController *presenter = modal.presentingViewController;
    void (^finish)(void) = ^{
        [self.panel removeFromSuperview];
        objc_setAssociatedObject(self, kZNModalControllerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kZNModalPresentingKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        self.floatButton.hidden = NO;
        if (self.floatButton.superview == self.hostWindow) [self.hostWindow bringSubviewToFront:self.floatButton];
        [[ZNRuntimeLogger sharedLogger] log:@"[menu-modal] dismissed"];
    };

    if (presenter || modal.isBeingPresented) [modal dismissViewControllerAnimated:NO completion:finish];
    else finish();
}

- (BOOL)znmodal_isVisible {
    return self.uiReady && ZNModalIsPresented(self) && !self.panel.hidden;
}

- (void)znmodal_togglePanel:(id)sender {
    (void)sender;
    if ([self isVisible]) [self hide];
    else [self show];
    [self zn40_updateSubtitle];
}

- (void)znmodal_closeTapped:(id)sender {
    (void)sender;
    [self hide];
}

@end

static void ZNModalSwap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallRuntimeMenuModalShellDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNModalSwap(cls, @selector(makeUI:), @selector(znmodal_makeUI:));
        ZNModalSwap(cls, @selector(attach:), @selector(znmodal_attach:));
        ZNModalSwap(cls, @selector(tick:), @selector(znmodal_tick:));
        ZNModalSwap(cls, @selector(show), @selector(znmodal_show));
        ZNModalSwap(cls, @selector(hide), @selector(znmodal_hide));
        ZNModalSwap(cls, @selector(isVisible), @selector(znmodal_isVisible));
        ZNModalSwap(cls, @selector(togglePanel:), @selector(znmodal_togglePanel:));
        ZNModalSwap(cls, @selector(closeTapped:), @selector(znmodal_closeTapped:));
        [[ZNRuntimeLogger sharedLogger] log:@"[menu-modal] installed: floating button remains UIWindow overlay; menu panel uses presented UIViewController shell"];
    });
}

#pragma mark - END ZNRuntimeMenuModalShell.mm


#pragma mark - BEGIN ZNFeatureGroupUI.mm
#line 1 "ZNFeatureGroupUI.mm"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNTheme.h"
#import "ZNPatchCore.h"
#include <mach/mach_time.h>
#import "ZNStaticDispatchRuntime.h"
#import "ZNStaticPatchFormat.h"
#import "ZNFeatureMetadataCodec.h"
#import "ZNFeatureSnapshotProvider.h"

// Public Feature UI intentionally contains display name + switch only.
// Technical fields (Target/RVA/Original/Enabled/Shared Site/Owner/Variant) stay
// out of this page and remain available through diagnostics/debug facilities.
//
// New privacy builds resolve names from ZNF1 metadata embedded in each generated
// Static Dispatch entry. The old NSUserDefaults feature-name registry is no
// longer read or written because it exposed target/RVA -> display-name mapping.
//
// v0.5.2 consolidation: compact mode is always the Feature surface. It no longer
// depends on the expanded menu's selected category, so Theme/Settings -> compact
// cannot fall back to the historical per-Patch renderer.

@interface ZNStaticPatchRecord (ZNFeatureMetadataAccess)
@property(nonatomic,assign) ZN44StaticEntry *entry;
@end

static const NSInteger kZN50FeatureToggleTagBase = 450000;

static double ZN50PerfMilliseconds(uint64_t start, uint64_t end) {
    static mach_timebase_info_data_t tb = {0};
    if (!tb.denom) mach_timebase_info(&tb);
    return ((double)(end - start) * (double)tb.numer / (double)tb.denom) / 1000000.0;
}

typedef NS_ENUM(NSInteger, ZN50FeatureVisualState) {
    ZN50FeatureVisualStateOff = 0,
    ZN50FeatureVisualStateOn,
    ZN50FeatureVisualStateMixed,
};

@interface ZN50FeatureToggleControl : UIControl
@property(nonatomic,strong) ZNTheme *znTheme;
@property(nonatomic,assign) ZN50FeatureVisualState visualState;
@property(nonatomic,assign) BOOL compact;
@property(nonatomic,strong) UIView *knobView;
@property(nonatomic,strong) UILabel *markLabel;
- (instancetype)initWithFrame:(CGRect)frame
                        theme:(ZNTheme *)theme
                        state:(ZN50FeatureVisualState)state
                      compact:(BOOL)compact;
- (void)zn50_applyVisualState;
@end

@implementation ZN50FeatureToggleControl

- (instancetype)initWithFrame:(CGRect)frame
                        theme:(ZNTheme *)theme
                        state:(ZN50FeatureVisualState)state
                      compact:(BOOL)compact {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.znTheme = theme;
    self.visualState = state;
    self.compact = compact;
    self.clipsToBounds = NO;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.accessibilityLabel = @"功能开关";

    self.knobView = [UIView new];
    self.knobView.userInteractionEnabled = NO;
    [self addSubview:self.knobView];

    self.markLabel = [UILabel new];
    self.markLabel.userInteractionEnabled = NO;
    self.markLabel.textAlignment = NSTextAlignmentCenter;
    self.markLabel.font = [UIFont systemFontOfSize:(compact ? 12.0 : 13.0) weight:UIFontWeightBold];
    [self addSubview:self.markLabel];

    [self zn50_applyVisualState];
    return self;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.78 : 1.0;
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m6.3-probe] toggle beginTracking tag=%ld", (long)self.tag]];
    return [super beginTrackingWithTouch:touch withEvent:event];
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    return [super continueTrackingWithTouch:touch withEvent:event];
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m6.3-probe] toggle endTracking tag=%ld", (long)self.tag]];
    [super endTrackingWithTouch:touch withEvent:event];
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m6.3-probe] toggle cancelTracking tag=%ld", (long)self.tag]];
    [super cancelTrackingWithEvent:event];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = CGRectGetHeight(self.bounds);
    CGFloat w = CGRectGetWidth(self.bounds);
    CGFloat inset = self.compact ? 3.5 : 4.0;
    CGFloat knob = MAX(12.0, h - inset * 2.0);
    CGFloat knobX = inset;

    if (self.visualState == ZN50FeatureVisualStateOn) {
        knobX = w - inset - knob;
    } else if (self.visualState == ZN50FeatureVisualStateMixed) {
        knobX = (w - knob) * 0.5;
    }

    self.layer.cornerRadius = h * 0.5;
    self.knobView.frame = CGRectMake(knobX, inset, knob, knob);
    self.knobView.layer.cornerRadius = knob * 0.5;

    CGFloat markWidth = MAX(14.0, w - knob - inset * 3.0);
    if (self.visualState == ZN50FeatureVisualStateOn) {
        self.markLabel.frame = CGRectMake(inset, 0, markWidth, h);
    } else if (self.visualState == ZN50FeatureVisualStateMixed) {
        self.markLabel.frame = CGRectMake(inset, 0, markWidth, h);
    } else {
        self.markLabel.frame = CGRectZero;
    }
}

- (void)zn50_applyVisualState {
    ZNTheme *theme = self.znTheme;
    UIColor *knobColor = theme.lightAppearance
        ? [UIColor colorWithWhite:1.0 alpha:0.98]
        : [UIColor colorWithWhite:0.96 alpha:0.98];

    self.layer.borderWidth = 1.0;
    self.layer.shadowOffset = CGSizeZero;
    self.layer.shadowRadius = 4.5;
    self.knobView.backgroundColor = knobColor;
    self.knobView.layer.borderWidth = 0.7;
    self.knobView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.65].CGColor;
    self.knobView.layer.shadowColor = UIColor.blackColor.CGColor;
    self.knobView.layer.shadowOffset = CGSizeMake(0, 1.0);
    self.knobView.layer.shadowRadius = 1.8;
    self.knobView.layer.shadowOpacity = theme.lightAppearance ? 0.16 : 0.34;

    if (self.visualState == ZN50FeatureVisualStateOn) {
        self.backgroundColor = [theme.accentColor colorWithAlphaComponent:(theme.lightAppearance ? 0.16 : 0.15)];
        self.layer.borderColor = [theme.accentColor colorWithAlphaComponent:0.95].CGColor;
        self.layer.shadowColor = theme.accentColor.CGColor;
        self.layer.shadowOpacity = theme.neonAppearance ? 0.48 : 0.30;
        self.markLabel.hidden = NO;
        self.markLabel.text = @"✓";
        self.markLabel.textColor = theme.accentColor;
        self.accessibilityValue = @"开";
        self.accessibilityTraits = UIAccessibilityTraitButton | UIAccessibilityTraitSelected;
    } else if (self.visualState == ZN50FeatureVisualStateMixed) {
        UIColor *mixed = theme.accent2Color ?: theme.accentColor;
        self.backgroundColor = [mixed colorWithAlphaComponent:(theme.lightAppearance ? 0.12 : 0.10)];
        self.layer.borderColor = [mixed colorWithAlphaComponent:0.62].CGColor;
        self.layer.shadowColor = mixed.CGColor;
        self.layer.shadowOpacity = theme.neonAppearance ? 0.28 : 0.14;
        self.markLabel.hidden = NO;
        self.markLabel.text = @"•";
        self.markLabel.textColor = mixed;
        self.accessibilityValue = @"部分开启";
        self.accessibilityTraits = UIAccessibilityTraitButton;
    } else {
        self.backgroundColor = [theme.trackColor colorWithAlphaComponent:(theme.lightAppearance ? 0.42 : 0.58)];
        self.layer.borderColor = [theme.borderColor colorWithAlphaComponent:(theme.lightAppearance ? 0.62 : 0.78)].CGColor;
        self.layer.shadowColor = theme.shadowColor.CGColor;
        self.layer.shadowOpacity = 0.12;
        self.markLabel.hidden = YES;
        self.markLabel.text = @"";
        self.accessibilityValue = @"关";
        self.accessibilityTraits = UIAccessibilityTraitButton;
    }
    [self setNeedsLayout];
}

@end

static NSString *ZN50Trim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *ZN50FeaturePreferenceKey(uint64_t featureID) {
    if (!featureID) return nil;
    return [NSString stringWithFormat:@"zn.f.%016llx.enabled", featureID];
}

static NSDictionary<NSString *, id> *ZN50DisplayMetadata(ZNStaticPatchRecord *record) {
    NSDictionary<NSString *, id> *embedded = ZNFeatureMetadataDecodeEntry(record.entry);
    if (embedded) return embedded;

    NSString *title = ZN50Trim(record.title);
    NSString *group = ZN50Trim(record.group);
    if (!title.length || [title hasPrefix:@"Patch #"]) title = [NSString stringWithFormat:@"功能 #%u", record.patchID];
    if (!group.length) group = @"Imported";
    return @{
        @"featureID": @0,
        @"title": title,
        @"group": group,
        @"explicitGroup": @([group caseInsensitiveCompare:@"Imported"] != NSOrderedSame),
        @"source": @"legacy-entry"
    };
}

static NSArray<NSDictionary *> *ZN50FeatureGroups(NSArray<ZNStaticPatchRecord *> *records) {
    (void)records;
    return [[ZNFeatureSnapshotProvider sharedProvider] currentFeatures];
}

static BOOL ZN50AllEnabled(NSArray<ZNStaticPatchRecord *> *records) {
    if (!records.count) return NO;
    for (ZNStaticPatchRecord *record in records) if (!record.enabled) return NO;
    return YES;
}

static BOOL ZN50AnyEnabled(NSArray<ZNStaticPatchRecord *> *records) {
    for (ZNStaticPatchRecord *record in records) if (record.enabled) return YES;
    return NO;
}

static ZN50FeatureVisualState ZN50VisualState(NSArray<ZNStaticPatchRecord *> *records) {
    BOOL all = ZN50AllEnabled(records);
    BOOL any = ZN50AnyEnabled(records);
    if (all) return ZN50FeatureVisualStateOn;
    if (any) return ZN50FeatureVisualStateMixed;
    return ZN50FeatureVisualStateOff;
}

static BOOL ZN50SetFeatureEnabled(NSArray<ZNStaticPatchRecord *> *records, BOOL enabled, NSString **error) {
    uint64_t probeStart = mach_absolute_time();
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m6.3-probe] setFeature begin enabled=%d records=%lu", enabled, (unsigned long)records.count]];
    if (!records.count) {
        if (error) *error = @"Feature 没有 Patch";
        return NO;
    }

    ZNStaticDispatchRuntime *runtime = [ZNStaticDispatchRuntime sharedRuntime];
    NSMutableArray<ZNStaticPatchRecord *> *changed = [NSMutableArray array];
    NSMutableArray<NSNumber *> *previous = [NSMutableArray array];

    for (ZNStaticPatchRecord *record in records) {
        if (record.enabled == enabled) continue;
        BOOL old = record.enabled;
        NSString *localError = nil;
        if (![runtime setEnabled:enabled forRecord:record error:&localError]) {
            for (NSInteger i = (NSInteger)changed.count - 1; i >= 0; i--) {
                ZNStaticPatchRecord *rollbackRecord = changed[(NSUInteger)i];
                BOOL rollbackState = [previous[(NSUInteger)i] boolValue];
                NSString *ignored = nil;
                [runtime setEnabled:rollbackState forRecord:rollbackRecord error:&ignored];
            }
            if (error) {
                *error = [NSString stringWithFormat:@"%@+0x%llX：%@", record.target ?: @"target", record.siteRVA, localError ?: @"切换失败"];
            }
            return NO;
        }
        [changed addObject:record];
        [previous addObject:@(old)];
    }
    uint64_t probeEnd = mach_absolute_time();
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m6.3-probe] setFeature end enabled=%d records=%lu ms=%.3f", enabled, (unsigned long)records.count, ZN50PerfMilliseconds(probeStart, probeEnd)]];
    return YES;
}

static NSMutableSet<NSString *> *ZN50RestoredPreferenceKeys(void) {
    static NSMutableSet<NSString *> *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ keys = [NSMutableSet set]; });
    return keys;
}

static void ZN50RestorePersistedFeatureStates(NSArray<NSDictionary *> *features) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSMutableSet<NSString *> *restored = ZN50RestoredPreferenceKeys();

    for (NSDictionary *feature in features) {
        uint64_t featureID = [feature[@"featureID"] unsignedLongLongValue];
        NSString *key = ZN50FeaturePreferenceKey(featureID);
        if (!key.length || [restored containsObject:key]) continue;
        [restored addObject:key];

        id stored = [defaults objectForKey:key];
        if (![stored isKindOfClass:NSNumber.class]) continue;

        NSArray<ZNStaticPatchRecord *> *records = feature[@"records"];
        BOOL desired = [stored boolValue];
        BOOL currentAll = ZN50AllEnabled(records);
        BOOL currentAny = ZN50AnyEnabled(records);
        if ((desired && currentAll) || (!desired && !currentAny)) continue;

        NSString *restoreError = nil;
        if (!ZN50SetFeatureEnabled(records, desired, &restoreError)) {
            [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[feature-pref] restore failed id=%016llx: %@", featureID, restoreError ?: @"unknown"]];
        }
    }
}

static ZN50FeatureToggleControl *ZN50MakeToggle(ZNTheme *theme,
                                                NSArray<ZNStaticPatchRecord *> *records,
                                                CGRect frame,
                                                BOOL compact,
                                                id target,
                                                SEL action) {
    ZN50FeatureToggleControl *toggle = [[ZN50FeatureToggleControl alloc] initWithFrame:frame
                                                                                theme:theme
                                                                                state:ZN50VisualState(records)
                                                                              compact:compact];
    [toggle addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return toggle;
}

@interface ZNRuntimeMenuControllerV040 (ZNFeatureGroupUI)
- (void)zn50_renderFullPage;
- (void)zn50_renderCompactPage;
- (void)zn50_renderFeatureGroupsCompact;
- (void)zn50_renderFeatureGroupsFull;
- (void)zn50_toggleFeature:(UIControl *)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNFeatureGroupUI)

- (void)zn50_renderFullPage {
    NSString *category = (self.selectedCategory >= 0 && self.selectedCategory < (NSInteger)self.categories.count)
        ? self.categories[(NSUInteger)self.selectedCategory]
        : @"";
    if ([category isEqualToString:@"功能"]) {
        [self zn50_renderFeatureGroupsFull];
        return;
    }
    [self zn50_renderFullPage];
}

- (void)zn50_renderCompactPage {
    // Compact is always the public Feature surface. Keep selectedCategory intact
    // so expanding returns to the page the user had open before collapsing.
    [self zn50_renderFeatureGroupsCompact];
}

- (void)zn50_renderFeatureGroupsFull {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat y = 9.0;

    ZNStaticDispatchRuntime *runtime = [ZNStaticDispatchRuntime sharedRuntime];
    [runtime refresh];
    NSArray<NSDictionary *> *features = ZN50FeatureGroups(runtime.records);
    ZN50RestorePersistedFeatureStates(features);

    if (!features.count) {
        UIView *card = [self cardAtY:y height:46 width:width compact:NO];
        UILabel *label = [self label:@"暂无功能" size:11.0 weight:UIFontWeightSemibold color:self.theme.secondaryTextColor];
        label.frame = CGRectMake(13, 13, card.bounds.size.width - 26, 20);
        [card addSubview:label];
        [self.contentView addSubview:card];
        y += 54;
        [self zn40_updateContentHeight:y];
        return;
    }

    for (NSUInteger featureIndex = 0; featureIndex < features.count; featureIndex++) {
        NSDictionary *feature = features[featureIndex];
        NSString *title = feature[@"title"];
        NSArray<ZNStaticPatchRecord *> *records = feature[@"records"];

        UIView *card = [self cardAtY:y height:46 width:width compact:NO];
        UILabel *name = [self label:title ?: @"功能" size:11.4 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
        name.frame = CGRectMake(13, 13, card.bounds.size.width - 100, 20);
        name.lineBreakMode = NSLineBreakByTruncatingTail;
        [card addSubview:name];

        ZN50FeatureToggleControl *toggle = ZN50MakeToggle(self.theme,
                                                          records,
                                                          CGRectMake(card.bounds.size.width - 78, 8, 66, 30),
                                                          NO,
                                                          self,
                                                          @selector(zn50_toggleFeature:));
        toggle.tag = kZN50FeatureToggleTagBase + (NSInteger)featureIndex;
        toggle.accessibilityLabel = title.length ? title : @"功能开关";
        [card addSubview:toggle];
        [self.contentView addSubview:card];
        y += 52;
    }

    [self zn40_updateContentHeight:y];
}

- (void)zn50_renderFeatureGroupsCompact {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat y = 7.0;

    ZNStaticDispatchRuntime *runtime = [ZNStaticDispatchRuntime sharedRuntime];
    [runtime refresh];
    NSArray<NSDictionary *> *features = ZN50FeatureGroups(runtime.records);
    ZN50RestorePersistedFeatureStates(features);

    if (!features.count) {
        UIView *card = [self cardAtY:y height:40 width:width compact:YES];
        UILabel *label = [self label:@"暂无功能" size:10.7 weight:UIFontWeightSemibold color:self.theme.secondaryTextColor];
        label.frame = CGRectMake(9, 10, card.bounds.size.width - 18, 20);
        [card addSubview:label];
        [self.contentView addSubview:card];
        y += 46;
        [self zn40_updateContentHeight:y];
        return;
    }

    for (NSUInteger featureIndex = 0; featureIndex < features.count; featureIndex++) {
        NSDictionary *feature = features[featureIndex];
        NSString *title = feature[@"title"];
        NSArray<ZNStaticPatchRecord *> *records = feature[@"records"];

        UIView *card = [self cardAtY:y height:40 width:width compact:YES];
        UILabel *name = [self label:title ?: @"功能" size:10.7 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
        name.frame = CGRectMake(9, 10, card.bounds.size.width - 88, 20);
        name.lineBreakMode = NSLineBreakByTruncatingTail;
        [card addSubview:name];

        ZN50FeatureToggleControl *toggle = ZN50MakeToggle(self.theme,
                                                          records,
                                                          CGRectMake(card.bounds.size.width - 69, 6, 60, 28),
                                                          YES,
                                                          self,
                                                          @selector(zn50_toggleFeature:));
        toggle.tag = kZN50FeatureToggleTagBase + (NSInteger)featureIndex;
        toggle.accessibilityLabel = title.length ? title : @"功能开关";
        [card addSubview:toggle];
        [self.contentView addSubview:card];
        y += 46;
    }

    [self zn40_updateContentHeight:y];
}

- (void)zn50_toggleFeature:(UIControl *)sender {
    uint64_t handlerStart = mach_absolute_time();
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m6.3-probe] toggle handler ENTER tag=%ld", (long)sender.tag]];
    NSInteger index = sender.tag - kZN50FeatureToggleTagBase;
    if (index < 0) return;

    ZNStaticDispatchRuntime *runtime = [ZNStaticDispatchRuntime sharedRuntime];
    [runtime refresh];
    NSArray<NSDictionary *> *features = ZN50FeatureGroups(runtime.records);
    if ((NSUInteger)index >= features.count) return;

    NSDictionary *feature = features[(NSUInteger)index];
    NSArray<ZNStaticPatchRecord *> *records = feature[@"records"];
    BOOL desired = !ZN50AllEnabled(records);
    NSString *localError = nil;
    if (!ZN50SetFeatureEnabled(records, desired, &localError)) {
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[feature] toggle rollback: %@", localError ?: @"unknown"]];
        return;
    }

    uint64_t featureID = [feature[@"featureID"] unsignedLongLongValue];
    NSString *preferenceKey = ZN50FeaturePreferenceKey(featureID);
    if (preferenceKey.length) [NSUserDefaults.standardUserDefaults setBool:desired forKey:preferenceKey];
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[feature] %@ %@ (%lu patches)", desired ? @"ON" : @"OFF", feature[@"title"] ?: @"功能", (unsigned long)records.count]];

    // M6.3: the feature card already owns the live record objects. Reflect the
    // actual backend state in-place instead of destroying/rebuilding the page.
    // Shared-Site or rollback semantics are therefore preserved: the visual
    // state comes from records after setEnabled completes, not from optimism.
    if ([sender isKindOfClass:ZN50FeatureToggleControl.class]) {
        ZN50FeatureToggleControl *toggle = (ZN50FeatureToggleControl *)sender;
        toggle.visualState = ZN50VisualState(records);
        [toggle zn50_applyVisualState];
    }
    uint64_t handlerEnd = mach_absolute_time();
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m6.3-probe] toggle handler EXIT tag=%ld ms=%.3f", (long)sender.tag, ZN50PerfMilliseconds(handlerStart, handlerEnd)]];
}

@end

static void ZN50SwapInstanceMethod(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallFeatureGroupUIDeferred(void) {
    @autoreleasepool {
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZN50SwapInstanceMethod(cls, @selector(renderFullPage), @selector(zn50_renderFullPage));
        ZN50SwapInstanceMethod(cls, @selector(renderCompactPage), @selector(zn50_renderCompactPage));
        [[ZNRuntimeLogger sharedLogger] log:@"[bootstrap][main] v0.5.7 feature UI installed after first activation: ZNF1 feature renderer + themed toggle"];
    }
}

#pragma mark - END ZNFeatureGroupUI.mm


#pragma mark - BEGIN ZNFeatureRuntimeControlsV2.mm
#line 1 "ZNFeatureRuntimeControlsV2.mm"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <math.h>

#import "ZNFeatureControlModel.h"
#import "ZNFeatureMetadataCodec.h"
#import "ZNFeatureSnapshotProvider.h"
#import "ZNRangeControl.h"
#import "ZNStaticDispatchRuntime.h"
#import "ZNStaticPatchFormat.h"
#import "ZNTheme.h"
#import "ZNValueTypeModel.h"
#import "ZNPatchCore.h"

extern "C" void ZNM630RestorePersistedTypedValues(UIView *contentView);

static const NSInteger kZN65ToggleTagBase = 450000;
static const NSInteger kZN65NumberTagBase = 469000;
static const NSInteger kZN65ActionTagBase = 470000;
static const NSInteger kZN65SliderTagBase = 471000;
static const NSInteger kZN65NumberExecuteTagBase = 472000;

@interface ZNStaticPatchRecord (ZNFeatureRuntimeControlEntry)
@property(nonatomic,assign) ZN44StaticEntry *entry;
@end

static NSString *ZN65Trim(NSString *value) { return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; }
static NSDictionary<NSString *, id> *ZN65DisplayMetadata(ZNStaticPatchRecord *record) {
    NSDictionary *embedded = ZNFeatureMetadataDecodeEntry(record.entry); if (embedded) return embedded;
    NSString *title=ZN65Trim(record.title),*group=ZN65Trim(record.group); if(!title.length||[title hasPrefix:@"Patch #"])title=[NSString stringWithFormat:@"功能 #%u",record.patchID]; if(!group.length)group=@"Imported";
    return @{@"featureID":@0,@"title":title,@"group":group,@"explicitGroup":@([group caseInsensitiveCompare:@"Imported"]!=NSOrderedSame),@"controlType":@(ZNFeatureControlTypeSwitch),@"valueType":@(ZNValueTypeAuto)};
}
static NSArray<NSDictionary *> *ZN65FeatureGroups(void) {
    return [[ZNFeatureSnapshotProvider sharedProvider] currentFeatures];
}

static NSString *ZN65PreferenceKey(NSDictionary *feature,NSString *suffix){uint64_t featureID=[feature[@"featureID"] unsignedLongLongValue];NSString *identity=featureID?[NSString stringWithFormat:@"%016llx",featureID]:[feature[@"key"] description];return [NSString stringWithFormat:@"zn.fc.%@.%@",identity?:@"feature",suffix?:@"value"];}
static double ZN65StoredValue(NSDictionary *feature,double fallback){id stored=[NSUserDefaults.standardUserDefaults objectForKey:ZN65PreferenceKey(feature,@"value")];return [stored isKindOfClass:NSNumber.class]?[stored doubleValue]:fallback;}
static NSString *ZN65StoredText(NSDictionary *feature,NSString *fallback){id stored=[NSUserDefaults.standardUserDefaults objectForKey:ZN65PreferenceKey(feature,@"valueText")];return [stored isKindOfClass:NSString.class]&&[(NSString *)stored length]?(NSString *)stored:(fallback?:@"1");}
static NSDictionary *ZN65EventInfo(NSDictionary *feature,NSNumber *value,NSString *valueText){NSMutableDictionary *info=[@{@"featureID":feature[@"featureID"]?:@0,@"title":feature[@"title"]?:@"功能",@"controlType":feature[@"controlType"]?:@(ZNFeatureControlTypeSwitch),@"valueType":feature[@"valueType"]?:@(ZNValueTypeAuto),@"key":feature[@"key"]?:@""} mutableCopy];if(value)info[@"value"]=value;if(valueText.length)info[@"valueText"]=valueText;return info;}

static void ZN65StoreNumberText(NSDictionary *feature, NSString *text) {
    NSString *trim = ZN65Trim(text);
    if (!trim.length) trim = @"0";
    [NSUserDefaults.standardUserDefaults setObject:trim forKey:ZN65PreferenceKey(feature,@"valueText")];
    NSDecimalNumber *n = [NSDecimalNumber decimalNumberWithString:trim locale:@{NSLocaleDecimalSeparator:@"."}];
    if (![n isEqualToNumber:NSDecimalNumber.notANumber]) [NSUserDefaults.standardUserDefaults setDouble:n.doubleValue forKey:ZN65PreferenceKey(feature,@"value")];
}

@interface ZNRuntimeMenuControllerV040 (ZNFeatureRuntimeControlsV2)
- (void)zn65fc_renderFull;
- (void)zn65fc_renderCompact;
- (void)zn65fc_numberChanged:(UITextField *)field;
- (void)zn65fc_numberReturn:(UITextField *)field;
- (void)zn65fc_numberExecute:(UIButton *)button;
- (void)zn65fc_actionTapped:(UIButton *)button;
- (void)zn65fc_sliderCommitted:(ZNRangeControl *)slider;
@end
@implementation ZNRuntimeMenuControllerV040 (ZNFeatureRuntimeControlsV2)
- (void)zn65fc_decorateCompact:(BOOL)compact {
    NSArray *features=ZN65FeatureGroups();
    for(NSUInteger i=0;i<features.count;i++){
        NSDictionary *feature=features[i];
        ZNFeatureControlType type=(ZNFeatureControlType)[feature[@"controlType"] unsignedIntValue];
        if(type==ZNFeatureControlTypeSwitch)continue;
        UIView *old=[self.contentView viewWithTag:kZN65ToggleTagBase+(NSInteger)i],*card=old.superview;
        if(!old||!card)continue;
        CGRect oldFrame=old.frame;
        [old removeFromSuperview];
        ZNValueType valueType=(ZNValueType)[feature[@"valueType"] integerValue];

        if(type==ZNFeatureControlTypeNumber){
            CGFloat executeW=compact?46:52;
            CGFloat gap=4;
            CGFloat totalW=compact?118:136;
            CGFloat x=CGRectGetWidth(card.bounds)-totalW-(compact?7:10);
            UITextField *field=[[UITextField alloc]initWithFrame:CGRectMake(x,oldFrame.origin.y,totalW-executeW-gap,oldFrame.size.height)];
            field.tag=kZN65NumberTagBase+(NSInteger)i;
            double stored=ZN65StoredValue(feature,1);
            NSString *fallback=ZNValueTypeIsInteger(valueType)||valueType==ZNValueTypeAuto?[NSString stringWithFormat:@"%.0f",stored]:[NSString stringWithFormat:@"%.6g",stored];
            field.text=ZN65StoredText(feature,fallback);
            field.textAlignment=NSTextAlignmentCenter;
            field.keyboardType=UIKeyboardTypeNumbersAndPunctuation;
            field.returnKeyType=UIReturnKeyDone;
            field.textColor=self.theme.primaryTextColor;
            field.backgroundColor=[self.theme.controlColor colorWithAlphaComponent:.82];
            field.font=[UIFont systemFontOfSize:(compact?9:9.6) weight:UIFontWeightSemibold];
            field.layer.cornerRadius=7;field.layer.borderWidth=1;field.layer.borderColor=self.theme.borderColor.CGColor;
            [field addTarget:self action:@selector(zn65fc_numberChanged:) forControlEvents:UIControlEventEditingChanged|UIControlEventEditingDidEnd];
            [field addTarget:self action:@selector(zn65fc_numberReturn:) forControlEvents:UIControlEventEditingDidEndOnExit];
            field.accessibilityLabel=[NSString stringWithFormat:@"%@ 数值 %@",feature[@"title"]?:@"功能",ZNValueTypeName(valueType)];
            [card addSubview:field];
            UIButton *execute=[self zn40_button:@"执行" selector:@selector(zn65fc_numberExecute:) frame:CGRectMake(CGRectGetMaxX(field.frame)+gap,oldFrame.origin.y,executeW,oldFrame.size.height)];
            execute.tag=kZN65NumberExecuteTagBase+(NSInteger)i;
            execute.titleLabel.font=[UIFont systemFontOfSize:(compact?8.2:8.8) weight:UIFontWeightSemibold];
            [card addSubview:execute];
        }else if(type==ZNFeatureControlTypeButton){
            UIButton *button=[self zn40_button:@"执行" selector:@selector(zn65fc_actionTapped:) frame:oldFrame];button.tag=kZN65ActionTagBase+(NSInteger)i;[card addSubview:button];
        }else if(type==ZNFeatureControlTypeSlider){
            CGFloat width=compact?88:112;
            ZNRangeControl *slider=[[ZNRangeControl alloc]initWithFrame:CGRectMake(CGRectGetWidth(card.bounds)-width-(compact?7:10),oldFrame.origin.y,width,oldFrame.size.height)];
            slider.tag=kZN65SliderTagBase+(NSInteger)i;

            // M6.3 consolidation: absorb M5.8.5 authored range semantics here
            // instead of adding a second decorator swizzle.
            double max=[feature[@"sliderMax"] doubleValue];
            if(!isfinite(max)||max<=0.0)max=10.0;
            double stored=ZN65StoredValue(feature,0.0);
            if(!isfinite(stored))stored=0.0;
            slider.minimumValue=0.0;
            slider.maximumValue=max;
            slider.value=MAX(0.0,MIN(max,round(stored)));

            slider.minimumTrackTintColor=self.theme.accentColor;
            slider.maximumTrackTintColor=[self.theme.trackColor colorWithAlphaComponent:.75];
            slider.thumbTintColor=self.theme.primaryTextColor;
            [slider addTarget:self action:@selector(zn65fc_sliderCommitted:) forControlEvents:UIControlEventPrimaryActionTriggered];
            slider.accessibilityLabel=[NSString stringWithFormat:@"%@ 滑块 %@ 0-%.0f step 1",feature[@"title"]?:@"功能",ZNValueTypeName(valueType),max];
            [card addSubview:slider];
        }
    }

    // M6.3 consolidation: M5.9.0 typed-value restore is now a direct tail
    // stage of the single control decorator rather than another swizzle layer.
    ZNM630RestorePersistedTypedValues(self.contentView);
}
- (void)zn65fc_renderFull{[self zn65fc_renderFull];[self zn65fc_decorateCompact:NO];}
- (void)zn65fc_renderCompact{[self zn65fc_renderCompact];[self zn65fc_decorateCompact:YES];}

- (void)zn65fc_numberChanged:(UITextField *)field {
    NSInteger index=field.tag-kZN65NumberTagBase;
    NSArray *features=ZN65FeatureGroups();
    if(index<0||(NSUInteger)index>=features.count)return;
    NSDictionary *feature=features[(NSUInteger)index];
    ZN65StoreNumberText(feature,field.text);
}

- (void)zn65fc_numberReturn:(UITextField *)field {
    [self zn65fc_numberChanged:field];
    [field resignFirstResponder];
}

- (void)zn65fc_numberExecute:(UIButton *)button {
    NSInteger index=button.tag-kZN65NumberExecuteTagBase;
    NSArray *features=ZN65FeatureGroups();
    if(index<0||(NSUInteger)index>=features.count)return;
    NSDictionary *feature=features[(NSUInteger)index];
    NSString *text=ZN65StoredText(feature,@"0");
    [NSNotificationCenter.defaultCenter postNotificationName:ZNFeatureNumberValueDidChangeNotification object:self userInfo:ZN65EventInfo(feature,@(text.doubleValue),text)];
}

- (void)zn65fc_actionTapped:(UIButton *)button {
    NSInteger index=button.tag-kZN65ActionTagBase;
    NSArray *features=ZN65FeatureGroups();
    if(index<0||(NSUInteger)index>=features.count)return;
    NSDictionary *feature=features[(NSUInteger)index];
    [NSNotificationCenter.defaultCenter postNotificationName:ZNFeatureActionRequestedNotification object:self userInfo:ZN65EventInfo(feature,nil,nil)];
}

- (void)zn65fc_sliderCommitted:(ZNRangeControl *)slider {
    NSInteger index=slider.tag-kZN65SliderTagBase;
    NSArray *features=ZN65FeatureGroups();
    if(index<0||(NSUInteger)index>=features.count)return;
    NSDictionary *feature=features[(NSUInteger)index];
    double max=[feature[@"sliderMax"] doubleValue];
    if(!isfinite(max)||max<=0.0)max=10.0;
    double value=MAX(0.0,MIN(max,round(slider.value)));
    slider.value=value;
    NSString *text=[NSString stringWithFormat:@"%.0f",value];
    [NSUserDefaults.standardUserDefaults setDouble:value forKey:ZN65PreferenceKey(feature,@"value")];
    [NSUserDefaults.standardUserDefaults setObject:text forKey:ZN65PreferenceKey(feature,@"valueText")];
    [NSNotificationCenter.defaultCenter postNotificationName:ZNFeatureSliderValueDidChangeNotification object:self userInfo:ZN65EventInfo(feature,@(value),text)];
}
@end

extern "C" void ZNInstallFeatureRuntimeControlsV2Deferred(void){
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken,^{
        Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040");if(!cls)return;
        Method a=class_getInstanceMethod(cls,@selector(zn50_renderFeatureGroupsFull)),b=class_getInstanceMethod(cls,@selector(zn65fc_renderFull));if(a&&b)method_exchangeImplementations(a,b);
        Method c=class_getInstanceMethod(cls,@selector(zn50_renderFeatureGroupsCompact)),d=class_getInstanceMethod(cls,@selector(zn65fc_renderCompact));if(c&&d)method_exchangeImplementations(c,d);
        [[ZNRuntimeLogger sharedLogger]log:@"[m5.8.1-control] Static Number manual Execute; Slider standalone range/single release commit"];
    });
}

#pragma mark - END ZNFeatureRuntimeControlsV2.mm


#pragma mark - BEGIN ZNPublicCompactUI.mm
#line 1 "ZNPublicCompactUI.mm"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Public menu presentation policy for v0.5.6 Full Deferred Bootstrap.
// Keep the existing compact layout implementation and make it the default
// presentation after this migration. Users can still expand through the
// existing mode button; this only changes the post-upgrade default.

static NSString * const kZNPublicCompactMigrationKey = @"zonoe.public-compact-ui.v1";
static NSString * const kZNCompactModeDefaultsKey = @"ZonoePatch.CompactMode";
static NSString * const kZNSelectedCategoryDefaultsKey = @"ZonoePatch.SelectedCategory";
static NSString * const kZNLegacyFeatureNameRegistryDefaultsKey = @"zonoe.feature-name-registry.v1";

@implementation ZNRuntimeMenuControllerV040 (ZNPublicCompactUI)

- (void)znpublic_layoutPanel {
    [self znpublic_layoutPanel];
    if (self.compactMode) {
        self.subtitleLabel.text = @"0.5.6";
        self.subtitleLabel.alpha = 0.72;
    }
}

+ (void)znpublic_installLayoutDeferred {
    Method original = class_getInstanceMethod(self, @selector(layoutPanel));
    Method replacement = class_getInstanceMethod(self, @selector(znpublic_layoutPanel));
    if (original && replacement) method_exchangeImplementations(original, replacement);
}


@end

extern "C" void ZNInstallPublicCompactLayoutDeferred(void) {
    [ZNRuntimeMenuControllerV040 znpublic_installLayoutDeferred];
}

extern "C" void ZNInstallPublicCompactDefaultsDeferred(void) {
    @autoreleasepool {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;

        // The old v0.5 Privacy UI registry linked target/RVA/patchID directly to
        // title/group. New ZNF1 outputs do not depend on it, so remove it on
        // every launch and never recreate it.
        [defaults removeObjectForKey:kZNLegacyFeatureNameRegistryDefaultsKey];

        BOOL migrated = [defaults boolForKey:kZNPublicCompactMigrationKey];
        if (!migrated) {
            [defaults setBool:YES forKey:kZNCompactModeDefaultsKey];
            [defaults setInteger:0 forKey:kZNSelectedCategoryDefaultsKey];
            [defaults setBool:YES forKey:kZNPublicCompactMigrationKey];

            Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
            if (cls && [cls respondsToSelector:@selector(shared)]) {
                ZNRuntimeMenuControllerV040 *controller = [cls shared];
                controller.compactMode = YES;
                controller.selectedCategory = 0;
            }
        }

        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kZNLegacyFeatureNameRegistryDefaultsKey];
        NSLog(@"[ZonoPatch] v0.5.6 public compact UI installed after first activation; legacy feature-name registry purged");
    }
}

#pragma mark - END ZNPublicCompactUI.mm


#pragma mark - BEGIN ZNFeatureBuilderUI.mm
#line 1 "ZNFeatureBuilderUI.mm"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNFeatureControlModel.h"
#import "ZNRuntimeActionModel.h"
#import "ZNNativeHookAction.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

// ZonoPatch v0.5 Feature/Patch Builder UI.
//
// `其他` is the developer authoring surface:
//   Feature -> one or more Patch rows -> validate -> temporary test -> build.
// JSON is only an optional import source. Once built, Feature metadata and
// Static Dispatch records are embedded in the generated Mach-O and runtime no
// longer needs the JSON file.

static const void *kZN50BExpandedFeatureKeys = &kZN50BExpandedFeatureKeys;
static const NSInteger kZN50BExpandTagBase = 460000;
static const NSInteger kZN50BAddPatchTagBase = 461000;
static const NSInteger kZN50BRenameTagBase = 462000;
static const NSInteger kZN50BDescriptionTagBase = 463000;
static const NSInteger kZN50BSliderMaxTagBase = 932000;
static NSString * const kZN50BSliderMaxDefaultsPrefix = @"zonoe.m5.8.5.static-slider-max.v1";

static NSString *ZN50BTrim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *ZN50BFeatureKey(NSString *name) {
    return ZN50BTrim(name).lowercaseString;
}

static NSString *ZN50BSliderMaxDefaultsKey(NSString *featureName) {
    return [NSString stringWithFormat:@"%@.%@", kZN50BSliderMaxDefaultsPrefix, ZN50BTrim(featureName).lowercaseString];
}

static double ZN50BStoredSliderMax(NSString *featureName) {
    id value=[NSUserDefaults.standardUserDefaults objectForKey:ZN50BSliderMaxDefaultsKey(featureName)];
    return [value isKindOfClass:NSNumber.class]?[value doubleValue]:0.0;
}

static void ZN50BStoreSliderMax(NSString *featureName,double value) {
    NSString *key=ZN50BSliderMaxDefaultsKey(featureName);
    if(isfinite(value)&&value>0.0)[NSUserDefaults.standardUserDefaults setDouble:MIN(value,16383.0) forKey:key];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
}

static void ZN50BNormalizeImportedGroups(ZNBinaryPatchWorkspace *workspace) {
    for (ZNBinaryPatchRow *row in workspace.rows) {
        NSString *group = ZN50BTrim(row.group);
        NSString *title = ZN50BTrim(row.title);
        if ((!group.length || [group caseInsensitiveCompare:@"Imported"] == NSOrderedSame) && title.length) {
            // Legacy/universal JSON often has only a feature/title field. Make
            // that title the durable group name so Builder writes it into the
            // Static Dispatch table and runtime can expose one Feature switch.
            row.group = title;
        }
    }
}

static BOOL ZN50BRowVisible(ZNBinaryPatchRow *row) {
    if (row.offsetText.length || row.enabledText.length) return YES;
    NSString *group = ZN50BTrim(row.group);
    NSString *title = ZN50BTrim(row.title);
    if (group.length && [group caseInsensitiveCompare:@"Imported"] != NSOrderedSame) return YES;
    return title.length > 0;
}

static NSArray<NSDictionary *> *ZN50BFeatureGroups(ZNBinaryPatchWorkspace *workspace) {
    ZN50BNormalizeImportedGroups(workspace);
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray<ZNBinaryPatchRow *> *> *rowsByKey = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *nameByKey = [NSMutableDictionary dictionary];

    for (ZNBinaryPatchRow *row in workspace.rows) {
        if (!ZN50BRowVisible(row)) continue;
        NSString *name = ZN50BTrim(row.group);
        if (!name.length || [name caseInsensitiveCompare:@"Imported"] == NSOrderedSame) {
            name = ZN50BTrim(row.title);
        }
        if (!name.length) name = @"未命名功能";
        NSString *key = ZN50BFeatureKey(name);
        if (!rowsByKey[key]) {
            rowsByKey[key] = [NSMutableArray array];
            nameByKey[key] = name;
            [order addObject:key];
        }
        [rowsByKey[key] addObject:row];
    }

    NSMutableArray<NSDictionary *> *out = [NSMutableArray arrayWithCapacity:order.count];
    for (NSString *key in order) {
        [out addObject:@{
            @"key": key,
            @"name": nameByKey[key] ?: @"Feature",
            @"rows": [rowsByKey[key] copy] ?: @[],
        }];
    }
    return out;
}

static NSMutableSet<NSString *> *ZN50BExpandedKeys(ZNRuntimeMenuControllerV040 *controller) {
    NSMutableSet<NSString *> *set = objc_getAssociatedObject(controller, kZN50BExpandedFeatureKeys);
    if (!set) {
        set = [NSMutableSet set];
        objc_setAssociatedObject(controller, kZN50BExpandedFeatureKeys, set, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return set;
}

@implementation ZNBinaryPatchWorkspace (ZNFeatureEditing)

- (NSString *)addFeature {
    if (self.hasAnyApplied || self.isBuilding) {
        self.lastStatus = @"当前状态不可增加功能，请先恢复 Runtime Patch 或等待生成结束";
        return @"";
    }

    NSMutableSet<NSString *> *used = [NSMutableSet set];
    for (ZNBinaryPatchRow *row in self.rows) {
        NSString *group = ZN50BTrim(row.group);
        if (group.length && [group caseInsensitiveCompare:@"Imported"] != NSOrderedSame) {
            [used addObject:group.lowercaseString];
        }
    }

    NSUInteger serial = 1;
    NSString *name = nil;
    do {
        name = [NSString stringWithFormat:@"新功能 %lu", (unsigned long)serial++];
    } while ([used containsObject:name.lowercaseString]);

    ZNBinaryPatchRow *row = [ZNBinaryPatchRow new];
    row.group = name;
    row.title = @"Patch #1";
    row.statusText = @"待填写";
    [self.rows addObject:row];
    self.lastStatus = [NSString stringWithFormat:@"已增加功能：%@", name];
    return name;
}

- (void)addPatchToFeature:(NSString *)featureName {
    if (self.hasAnyApplied || self.isBuilding) {
        self.lastStatus = @"当前状态不可增加 Patch，请先恢复 Runtime Patch 或等待生成结束";
        return;
    }
    NSString *name = ZN50BTrim(featureName);
    if (!name.length) return;

    NSUInteger count = 0;
    for (ZNBinaryPatchRow *row in self.rows) {
        if ([ZN50BTrim(row.group) caseInsensitiveCompare:name] == NSOrderedSame) count++;
    }

    NSString *existingDescription=@"";
    for (ZNBinaryPatchRow *existing in self.rows) {
        if ([ZN50BTrim(existing.group) caseInsensitiveCompare:name] == NSOrderedSame && existing.featureDescription.length) {
            existingDescription=existing.featureDescription;
            break;
        }
    }

    ZNBinaryPatchRow *row = [ZNBinaryPatchRow new];
    row.group = name;
    row.title = [NSString stringWithFormat:@"Patch #%lu", (unsigned long)count + 1];
    row.featureDescription = existingDescription;
    row.statusText = @"待填写";
    [self.rows addObject:row];
    self.lastStatus = [NSString stringWithFormat:@"%@：已增加 Patch #%lu", name, (unsigned long)count + 1];
}

- (BOOL)renameFeature:(NSString *)oldName to:(NSString *)newName error:(NSString **)error {
    if (self.hasAnyApplied || self.isBuilding) {
        if (error) *error = @"当前状态不可重命名功能";
        return NO;
    }
    NSString *oldValue = ZN50BTrim(oldName);
    NSString *newValue = ZN50BTrim(newName);
    if (!newValue.length) {
        if (error) *error = @"功能名称不能为空";
        return NO;
    }
    if ([oldValue caseInsensitiveCompare:newValue] == NSOrderedSame) return YES;

    for (ZNBinaryPatchRow *row in self.rows) {
        NSString *group = ZN50BTrim(row.group);
        if ([group caseInsensitiveCompare:newValue] == NSOrderedSame &&
            [group caseInsensitiveCompare:oldValue] != NSOrderedSame) {
            if (error) *error = @"已存在同名功能，避免意外合并";
            return NO;
        }
    }

    BOOL changed = NO;
    for (ZNBinaryPatchRow *row in self.rows) {
        if ([ZN50BTrim(row.group) caseInsensitiveCompare:oldValue] == NSOrderedSame) {
            row.group = newValue;
            changed = YES;
        }
    }
    if (!changed) {
        if (error) *error = @"找不到要重命名的功能";
        return NO;
    }
    self.lastStatus = [NSString stringWithFormat:@"功能已重命名：%@ → %@", oldValue, newValue];
    return YES;
}

- (BOOL)setDescription:(NSString *)description forFeature:(NSString *)featureName error:(NSString **)error {
    if (self.hasAnyApplied || self.isBuilding) {
        if (error) *error=@"当前状态不可修改功能说明";
        return NO;
    }
    NSString *name=ZN50BTrim(featureName);
    NSString *desc=ZN50BTrim(description);
    BOOL changed=NO;
    for (ZNBinaryPatchRow *row in self.rows) {
        if ([ZN50BTrim(row.group) caseInsensitiveCompare:name] == NSOrderedSame) {
            row.featureDescription=desc ?: @"";
            changed=YES;
        }
    }
    if(!changed){
        if(error)*error=@"找不到对应功能";
        return NO;
    }
    self.lastStatus=desc.length?[NSString stringWithFormat:@"%@：说明已更新",name]:[NSString stringWithFormat:@"%@：说明已清空",name];
    return YES;
}

@end

@interface ZNRuntimeMenuControllerV040 (ZNFeatureBuilderUI)
- (void)zn50b_renderOther;
- (void)zn50b_expandFeature:(UIButton *)sender;
- (void)zn50b_addFeature:(id)sender;
- (void)zn50b_addPatch:(UIButton *)sender;
- (void)zn50b_featureNameEnd:(UITextField *)field;
- (void)zn50b_featureDescriptionEnd:(UITextField *)field;
- (void)zn50b_sliderMaxChanged:(UITextField *)field;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNFeatureBuilderUI)

- (void)zn50b_renderOther {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat y = 9.0;
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    [workspace ensureDefaultRows];
    ZN50BNormalizeImportedGroups(workspace);
    BOOL locked = workspace.hasAnyApplied || workspace.isBuilding;

    // Target + JSON import. JSON is authoring-time only; it is not a runtime dependency.
    UIView *targetCard = [self cardAtY:y height:56 width:width compact:NO];
    UILabel *binaryLabel = [self label:@"Target" size:11.2 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    binaryLabel.frame = CGRectMake(13, 11, 50, 32);
    [targetCard addSubview:binaryLabel];
    CGFloat importW = 78.0;
    UITextField *target = [self zn44_field:CGRectMake(65, 11, targetCard.bounds.size.width - 65 - importW - 18, 32)
                                        text:workspace.defaultTarget
                                 placeholder:@"自动 / UnityFramework"
                                         tag:440000
                                     enabled:!locked];
    [targetCard addSubview:target];
    UIButton *import = [self zn40_button:(workspace.showJSONFiles ? @"收起 JSON" : @"导入 JSON")
                                selector:@selector(zn44_importJSON:)
                                   frame:CGRectMake(targetCard.bounds.size.width - importW - 9, 11, importW, 32)];
    import.enabled = !locked;
    [targetCard addSubview:import];
    [self.contentView addSubview:targetCard];
    y += 64;

    if (workspace.showJSONFiles) {
        NSUInteger shown = workspace.jsonFiles.count;
        CGFloat h = 32.0 + shown * 34.0;
        UIView *jsonCard = [self cardAtY:y height:h width:width compact:NO];
        UILabel *title = [self label:[NSString stringWithFormat:@"与 1 同目录 JSON · %lu", (unsigned long)shown]
                                  size:10.5
                                weight:UIFontWeightSemibold
                                 color:self.theme.primaryTextColor];
        title.frame = CGRectMake(13, 7, jsonCard.bounds.size.width - 26, 17);
        [jsonCard addSubview:title];
        for (NSUInteger i = 0; i < shown; i++) {
            NSString *path = workspace.jsonFiles[i];
            UIButton *button = [self zn40_button:path.lastPathComponent
                                        selector:@selector(zn44_jsonTapped:)
                                           frame:CGRectMake(13, 27 + i * 34, jsonCard.bounds.size.width - 26, 28)];
            button.tag = 446000 + (NSInteger)i;
            button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
            button.titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
            [jsonCard addSubview:button];
        }
        [self.contentView addSubview:jsonCard];
        y += h + 8;
    }

    NSArray<NSDictionary *> *features = ZN50BFeatureGroups(workspace);
    NSMutableSet<NSString *> *expanded = ZN50BExpandedKeys(self);

    for (NSUInteger featureIndex = 0; featureIndex < features.count; featureIndex++) {
        NSDictionary *feature = features[featureIndex];
        NSString *key = feature[@"key"];
        NSString *name = feature[@"name"];
        NSArray<ZNBinaryPatchRow *> *rows = feature[@"rows"];
        BOOL isExpanded = [expanded containsObject:key];

        UIView *featureCard = [self cardAtY:y height:48 width:width compact:NO];
        UILabel *featureName = [self label:name size:11.2 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
        featureName.frame = CGRectMake(13, 8, featureCard.bounds.size.width - 142, 30);
        featureName.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [featureCard addSubview:featureName];

        NSString *countTitle = [NSString stringWithFormat:@"%lu Patch %@", (unsigned long)rows.count, isExpanded ? @"▲" : @"▼"];
        UIButton *expand = [self zn40_button:countTitle
                                    selector:@selector(zn50b_expandFeature:)
                                       frame:CGRectMake(featureCard.bounds.size.width - 124, 8, 112, 32)];
        expand.tag = kZN50BExpandTagBase + (NSInteger)featureIndex;
        [featureCard addSubview:expand];
        [self.contentView addSubview:featureCard];
        y += 54;

        if (!isExpanded) continue;

        // Feature name editor. Group name is what Builder persists for the
        // final runtime Feature switch.
        UIView *nameCard = [self cardAtY:y height:50 width:width compact:NO];
        UILabel *label = [self label:@"功能名" size:9.2 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];
        label.frame = CGRectMake(18, 9, 45, 30);
        [nameCard addSubview:label];
        UITextField *nameField = [[UITextField alloc] initWithFrame:CGRectMake(63, 9, nameCard.bounds.size.width - 78, 31)];
        nameField.tag = kZN50BRenameTagBase + (NSInteger)featureIndex;
        nameField.text = name;
        nameField.enabled = !locked;
        nameField.textColor = self.theme.primaryTextColor;
        nameField.backgroundColor = self.theme.controlColor;
        nameField.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightMedium];
        nameField.autocorrectionType = UITextAutocorrectionTypeNo;
        nameField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        nameField.returnKeyType = UIReturnKeyDone;
        nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
        nameField.layer.cornerRadius = 7;
        nameField.layer.borderWidth = 1;
        nameField.layer.borderColor = self.theme.borderColor.CGColor;
        UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 1)];
        nameField.leftView = pad;
        nameField.leftViewMode = UITextFieldViewModeAlways;
        [nameField addTarget:self action:@selector(zn50b_featureNameEnd:) forControlEvents:UIControlEventEditingDidEndOnExit | UIControlEventEditingDidEnd];
        [nameCard addSubview:nameField];
        [self.contentView addSubview:nameCard];
        y += 56;

        UIView *descriptionCard=[self cardAtY:y height:50 width:width compact:NO];
        UILabel *descriptionLabel=[self label:@"功能说明" size:9.2 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];
        descriptionLabel.frame=CGRectMake(18,9,52,30);
        [descriptionCard addSubview:descriptionLabel];
        UITextField *descriptionField=[[UITextField alloc] initWithFrame:CGRectMake(72,9,descriptionCard.bounds.size.width-87,31)];
        descriptionField.tag=kZN50BDescriptionTagBase+(NSInteger)featureIndex;
        NSString *featureDescription=rows.firstObject.featureDescription ?: @"";
        descriptionField.text=featureDescription;
        descriptionField.placeholder=@"例如：开启后保持体力不减少";
        descriptionField.enabled=!locked;
        descriptionField.textColor=self.theme.primaryTextColor;
        descriptionField.backgroundColor=self.theme.controlColor;
        descriptionField.font=[UIFont systemFontOfSize:9.8 weight:UIFontWeightRegular];
        descriptionField.autocorrectionType=UITextAutocorrectionTypeNo;
        descriptionField.returnKeyType=UIReturnKeyDone;
        descriptionField.clearButtonMode=UITextFieldViewModeWhileEditing;
        descriptionField.layer.cornerRadius=7;
        descriptionField.layer.borderWidth=1;
        descriptionField.layer.borderColor=self.theme.borderColor.CGColor;
        UIView *descriptionPad=[[UIView alloc] initWithFrame:CGRectMake(0,0,8,1)];
        descriptionField.leftView=descriptionPad;
        descriptionField.leftViewMode=UITextFieldViewModeAlways;
        [descriptionField addTarget:self action:@selector(zn50b_featureDescriptionEnd:) forControlEvents:UIControlEventEditingDidEndOnExit|UIControlEventEditingDidEnd];
        [descriptionCard addSubview:descriptionField];
        [self.contentView addSubview:descriptionCard];
        y += 56;

        for (NSUInteger patchIndex = 0; patchIndex < rows.count; patchIndex++) {
            ZNBinaryPatchRow *row = rows[patchIndex];
            NSUInteger globalIndex = [workspace.rows indexOfObjectIdenticalTo:row];
            if (globalIndex == NSNotFound) continue;
            UIView *patchCard = [self cardAtY:y height:94 width:width compact:NO];
            BOOL autoTarget=[workspace.defaultTarget caseInsensitiveCompare:@"自动"]==NSOrderedSame || [workspace.defaultTarget caseInsensitiveCompare:@"auto"]==NSOrderedSame;
            NSString *effectiveTarget = autoTarget ? ((row.explicitTarget&&row.target.length)?row.target:@"main") : workspace.defaultTarget;
            NSString *patchTitle = ZN50BTrim(row.title);
            if (!patchTitle.length || [patchTitle caseInsensitiveCompare:name] == NSOrderedSame) {
                patchTitle = [NSString stringWithFormat:@"Patch #%lu", (unsigned long)patchIndex + 1];
            }
            UILabel *head = [self label:[NSString stringWithFormat:@"#%lu · %@ · %@", (unsigned long)patchIndex + 1, effectiveTarget, patchTitle]
                                    size:9.8
                                  weight:UIFontWeightSemibold
                                   color:self.theme.primaryTextColor];
            head.frame = CGRectMake(18, 5, patchCard.bounds.size.width - 31, 16);
            head.lineBreakMode = NSLineBreakByTruncatingMiddle;
            [patchCard addSubview:head];

            UILabel *offsetLabel = [self label:@"Offset" size:9.0 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];
            offsetLabel.frame = CGRectMake(18, 24, 45, 28);
            [patchCard addSubview:offsetLabel];
            UITextField *offset = [self zn44_field:CGRectMake(63, 23, patchCard.bounds.size.width - 78, 29)
                                               text:row.offsetText
                                        placeholder:@"0x..."
                                                tag:441000 + (NSInteger)globalIndex
                                            enabled:!locked];
            [patchCard addSubview:offset];

            ZNFeatureControlType controlType = [workspace controlTypeForFeature:name];
            BOOL isNumber = controlType == ZNFeatureControlTypeNumber;
            BOOL isSlider = controlType == ZNFeatureControlTypeSlider;
            BOOL isValueControl = isNumber || isSlider;

            if (!isSlider) {
                // M6.2 input contract:
                //   Button/Switch -> Offset + Patch
                //   Number        -> Offset + ValueType; this field is only an
                //                    ephemeral test value and is never emitted as Patch.
                NSString *valueLabel = isNumber ? @"测试值" : @"Patch";
                NSString *placeholder = isNumber ? @"例如 1000" : @"ARM64 HEX";
                UILabel *enabledLabel = [self label:valueLabel size:9.0 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];
                enabledLabel.frame = CGRectMake(18, 54, 45, 28);
                [patchCard addSubview:enabledLabel];
                UITextField *enabled = [self zn44_field:CGRectMake(63, 53, patchCard.bounds.size.width - 78, 29)
                                                    text:row.enabledText
                                             placeholder:placeholder
                                                     tag:442000 + (NSInteger)globalIndex
                                                 enabled:!locked];
                if (isNumber) {
                    enabled.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
                    enabled.autocapitalizationType = UITextAutocapitalizationTypeNone;
                } else {
                    enabled.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
                }
                [patchCard addSubview:enabled];
            } else {
                UILabel *maxLabel=[self label:@"Max" size:9.0 weight:UIFontWeightMedium color:self.theme.secondaryTextColor];
                maxLabel.frame=CGRectMake(18,54,45,28);
                [patchCard addSubview:maxLabel];

                double sliderMax=ZN50BStoredSliderMax(name);
                UITextField *maxField=[self zn44_field:CGRectMake(63,53,patchCard.bounds.size.width-78,29)
                                                   text:(sliderMax>0.0?[NSString stringWithFormat:@"%.0f",sliderMax]:@"")
                                            placeholder:@"例如 100"
                                                    tag:kZN50BSliderMaxTagBase+(NSInteger)globalIndex
                                                enabled:!locked];
                maxField.keyboardType=UIKeyboardTypeNumberPad;
                maxField.autocorrectionType=UITextAutocorrectionTypeNo;
                maxField.accessibilityLabel=[NSString stringWithFormat:@"%@ Slider 最大值",name];
                [maxField addTarget:self action:@selector(zn50b_sliderMaxChanged:)
                   forControlEvents:UIControlEventEditingChanged|UIControlEventEditingDidEnd];
                [patchCard addSubview:maxField];
            }

            NSString *original = row.originalHex.length ? row.originalHex : @"-";
            NSString *status = row.statusText.length ? row.statusText : (isValueControl ? @"待应用" : @"待应用");
            UILabel *originalLine = [self label:[NSString stringWithFormat:@"Original  %@   %@", original, status]
                                            size:8.2
                                          weight:UIFontWeightRegular
                                           color:row.conflict ? UIColor.systemOrangeColor : self.theme.secondaryTextColor];
            originalLine.frame = CGRectMake(18, 82, patchCard.bounds.size.width - 31, 11);
            originalLine.lineBreakMode = NSLineBreakByTruncatingMiddle;
            [patchCard addSubview:originalLine];

            [self.contentView addSubview:patchCard];
            y += 100;
        }

        UIView *addPatchCard = [self cardAtY:y height:44 width:width compact:NO];
        UIButton *addPatch = [self zn40_button:@"＋ 增加 Patch"
                                      selector:@selector(zn50b_addPatch:)
                                         frame:CGRectMake(18, 6, addPatchCard.bounds.size.width - 36, 32)];
        addPatch.tag = kZN50BAddPatchTagBase + (NSInteger)featureIndex;
        addPatch.enabled = !locked;
        [addPatchCard addSubview:addPatch];
        [self.contentView addSubview:addPatchCard];
        y += 50;
    }

    UIView *addFeatureCard = [self cardAtY:y height:48 width:width compact:NO];
    UIButton *addFeature = [self zn40_button:@"＋ 增加功能"
                                    selector:@selector(zn50b_addFeature:)
                                       frame:CGRectMake(13, 7, addFeatureCard.bounds.size.width - 26, 34)];
    addFeature.enabled = !locked;
    [addFeatureCard addSubview:addFeature];
    [self.contentView addSubview:addFeatureCard];
    y += 56;

    CGFloat gap = 8.0;
    CGFloat inner = width - 26.0;
    CGFloat buttonW = (inner - gap) / 2.0;

    BOOL hasRawPatch=NO;
    for(ZNBinaryPatchRow *candidate in workspace.rows){
        if(!candidate.offsetText.length)continue;
        if(candidate.featureControlType==ZNFeatureControlTypeButton||candidate.featureControlType==ZNFeatureControlTypeSwitch){
            if(candidate.enabledText.length){hasRawPatch=YES;break;}
        }
    }

    // M6.3: Apply/Restore test raw Button/Switch only.
    // Number/Slider are configured here and exercised after binary generation.
    UIView *actions1 = [self cardAtY:y height:52 width:width compact:NO];
    UIButton *apply = [self zn40_button:@"应用" selector:@selector(zn44_applyAll:)
                                  frame:CGRectMake(13, 9, inner, 34)];
    apply.enabled = !workspace.isBuilding && !workspace.hasAnyApplied && hasRawPatch;
    [actions1 addSubview:apply];
    [self.contentView addSubview:actions1];
    y += 60;

    UIView *actions2 = [self cardAtY:y height:52 width:width compact:NO];
    UIButton *restore = [self zn40_button:@"恢复" selector:@selector(zn44_restoreAll:) frame:CGRectMake(13, 9, buttonW, 34)];
    UIButton *build = [self zn40_button:(workspace.isBuilding ? @"正在生成…" : @"生成新二进制")
                                   selector:@selector(zn44_buildBinary:)
                                      frame:CGRectMake(13 + buttonW + gap, 9, buttonW, 34)];
    restore.enabled = !workspace.isBuilding && workspace.hasAnyApplied;
    BOOL hasRuntimeAuthoring = [[ZNRuntimeActionStore sharedStore] actionsSnapshot].count > 0 ||
                               [[ZNNativeHookStore sharedStore] actionsSnapshot].count > 0;
    build.enabled = !workspace.isBuilding && !workspace.hasAnyApplied && (workspace.filledCount > 0 || hasRuntimeAuthoring);
    [actions2 addSubview:restore];
    [actions2 addSubview:build];
    [self.contentView addSubview:actions2];
    y += 60;

    if (workspace.lastStatus.length) {
        UIView *statusCard = [self cardAtY:y height:38 width:width compact:NO];
        UILabel *status = [self label:workspace.lastStatus size:8.6 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        status.frame = CGRectMake(13, 8, statusCard.bounds.size.width - 26, 22);
        status.numberOfLines = 2;
        status.lineBreakMode = NSLineBreakByTruncatingTail;
        [statusCard addSubview:status];
        [self.contentView addSubview:statusCard];
        y += 46;
    }

    if (workspace.lastOutputPaths.count) {
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        for (NSUInteger i = 0; i < MIN((NSUInteger)4, workspace.lastOutputPaths.count); i++) {
            NSString *path = workspace.lastOutputPaths[i];
            [lines addObject:[path hasPrefix:NSHomeDirectory()] ? [path substringFromIndex:NSHomeDirectory().length] : path];
        }
        [self zn40_addInfoCard:@"最近输出" lines:lines y:&y width:width];
    }

    [self zn40_updateContentHeight:y];
}

- (void)zn50b_expandFeature:(UIButton *)sender {
    NSInteger index = sender.tag - kZN50BExpandTagBase;
    if (index < 0) return;
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    NSArray<NSDictionary *> *features = ZN50BFeatureGroups(workspace);
    if ((NSUInteger)index >= features.count) return;
    NSString *key = features[(NSUInteger)index][@"key"];
    NSMutableSet<NSString *> *expanded = ZN50BExpandedKeys(self);
    if ([expanded containsObject:key]) [expanded removeObject:key];
    else [expanded addObject:key];
    [self renderPage];
}

- (void)zn50b_addFeature:(id)sender {
    (void)sender;
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    NSString *name = [workspace addFeature];
    if (name.length) [ZN50BExpandedKeys(self) addObject:ZN50BFeatureKey(name)];
    [self renderPage];
}

- (void)zn50b_addPatch:(UIButton *)sender {
    NSInteger index = sender.tag - kZN50BAddPatchTagBase;
    if (index < 0) return;
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    NSArray<NSDictionary *> *features = ZN50BFeatureGroups(workspace);
    if ((NSUInteger)index >= features.count) return;
    NSString *name = features[(NSUInteger)index][@"name"];
    [workspace addPatchToFeature:name];
    [ZN50BExpandedKeys(self) addObject:ZN50BFeatureKey(name)];
    [self renderPage];
}

- (void)zn50b_featureNameEnd:(UITextField *)field {
    NSInteger index = field.tag - kZN50BRenameTagBase;
    if (index < 0) return;
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    NSArray<NSDictionary *> *features = ZN50BFeatureGroups(workspace);
    if ((NSUInteger)index >= features.count) return;
    NSString *oldName = features[(NSUInteger)index][@"name"];
    NSString *newName = ZN50BTrim(field.text);
    NSString *error = nil;
    if ([workspace renameFeature:oldName to:newName error:&error]) {
        NSMutableSet<NSString *> *expanded = ZN50BExpandedKeys(self);
        [expanded removeObject:ZN50BFeatureKey(oldName)];
        [expanded addObject:ZN50BFeatureKey(newName)];
    } else {
        workspace.lastStatus = [NSString stringWithFormat:@"重命名失败：%@", error ?: @"未知错误"];
        field.text = oldName;
    }
    [self.hostWindow endEditing:YES];
    [self renderPage];
}

- (void)zn50b_sliderMaxChanged:(UITextField *)field {
    NSInteger globalIndex=field.tag-kZN50BSliderMaxTagBase;
    if(globalIndex<0)return;
    ZNBinaryPatchWorkspace *workspace=[ZNBinaryPatchWorkspace sharedWorkspace];
    if((NSUInteger)globalIndex>=workspace.rows.count)return;
    ZNBinaryPatchRow *row=workspace.rows[(NSUInteger)globalIndex];
    if(row.featureControlType!=ZNFeatureControlTypeSlider)return;

    NSString *name=ZN50BTrim(row.group);
    if(!name.length||[name caseInsensitiveCompare:@"Imported"]==NSOrderedSame)name=ZN50BTrim(row.title);
    if(!name.length)name=@"未命名功能";

    NSString *text=ZN50BTrim(field.text);
    NSDecimalNumber *number=[NSDecimalNumber decimalNumberWithString:text locale:@{NSLocaleDecimalSeparator:@"."}];
    double value=(![number isEqualToNumber:NSDecimalNumber.notANumber])?number.doubleValue:0.0;
    if(!isfinite(value)||value<=0.0)value=0.0;
    if(value>16383.0){
        value=16383.0;
        field.text=@"16383";
    }
    ZN50BStoreSliderMax(name,value);
    row.validated=NO;
    row.validator=nil;
    row.originalHex=@"";
}

- (void)zn50b_featureDescriptionEnd:(UITextField *)field {
    NSInteger index=field.tag-kZN50BDescriptionTagBase;
    if(index<0)return;
    ZNBinaryPatchWorkspace *workspace=[ZNBinaryPatchWorkspace sharedWorkspace];
    NSArray<NSDictionary *> *features=ZN50BFeatureGroups(workspace);
    if((NSUInteger)index>=features.count)return;
    NSString *name=features[(NSUInteger)index][@"name"]?:@"";
    NSString *error=nil;
    if(![workspace setDescription:field.text?:@"" forFeature:name error:&error]){
        workspace.lastStatus=[NSString stringWithFormat:@"说明保存失败：%@",error?:@"未知错误"];
    }
    [self.hostWindow endEditing:YES];
    [self renderPage];
}

@end

static void ZN50BSwapInstanceMethod(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallFeatureBuilderUIDeferred(void) {
    @autoreleasepool {
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZN50BSwapInstanceMethod(cls, @selector(zn44_renderOther), @selector(zn50b_renderOther));
        [[ZNRuntimeLogger sharedLogger] log:@"[bootstrap][main] v0.5 Feature Builder installed: Feature -> Patches -> validate/build; JSON optional"];
    }
}

#pragma mark - END ZNFeatureBuilderUI.mm


#pragma mark - BEGIN ZNFeatureBuilderControlsV2.mm
#line 1 "ZNFeatureBuilderControlsV2.mm"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNFeatureControlModel.h"
#import "ZNValueTypeModel.h"
#import "ZNTheme.h"

// M5.5.1 recovery baseline: keep the proven M5.4 Builder layout intact.
// Typed value selection is layered by M5.5 as a separate overlay instead of
// replacing the base Builder geometry.

static const NSInteger kZN64AddPatchTagBase = 461000;
static const NSInteger kZN64OffsetFieldTagBase = 441000;
static const NSInteger kZN64TypeTagBase = 466000;
static const NSInteger kZN64DeleteFeatureTagBase = 467000;
static const NSInteger kZN64DeletePatchTagBase = 468000;
static const NSInteger kZN64ValueTypeTagBase = 469000;

static NSString *ZN64Trim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL ZN64RowVisible(ZNBinaryPatchRow *row) {
    if (row.offsetText.length || row.enabledText.length) return YES;
    NSString *group = ZN64Trim(row.group);
    NSString *title = ZN64Trim(row.title);
    if (group.length && [group caseInsensitiveCompare:@"Imported"] != NSOrderedSame) return YES;
    return title.length > 0;
}

static NSArray<NSDictionary *> *ZN64FeatureGroups(ZNBinaryPatchWorkspace *workspace) {
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray<ZNBinaryPatchRow *> *> *rowsByKey = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *names = [NSMutableDictionary dictionary];

    for (ZNBinaryPatchRow *row in workspace.rows) {
        if (!ZN64RowVisible(row)) continue;
        NSString *name = ZN64Trim(row.group);
        if (!name.length || [name caseInsensitiveCompare:@"Imported"] == NSOrderedSame) name = ZN64Trim(row.title);
        if (!name.length) name = @"未命名功能";
        NSString *key = name.lowercaseString;
        if (!rowsByKey[key]) {
            rowsByKey[key] = [NSMutableArray array];
            names[key] = name;
            [order addObject:key];
        }
        [rowsByKey[key] addObject:row];
    }

    NSMutableArray *out = [NSMutableArray arrayWithCapacity:order.count];
    for (NSString *key in order) {
        [out addObject:@{
            @"key": key,
            @"name": names[key] ?: @"功能",
            @"rows": [rowsByKey[key] copy] ?: @[]
        }];
    }
    return out;
}

static UIButton *ZN64ButtonWithTag(UIView *root, NSInteger tag) {
    UIView *view = [root viewWithTag:tag];
    return [view isKindOfClass:UIButton.class] ? (UIButton *)view : nil;
}

static UITextField *ZN64FieldWithTag(UIView *root, NSInteger tag) {
    UIView *view = [root viewWithTag:tag];
    return [view isKindOfClass:UITextField.class] ? (UITextField *)view : nil;
}

@interface ZNRuntimeMenuControllerV040 (ZNFeatureBuilderControlsV2)
- (void)zn64fb_renderOther;
- (void)zn64fb_cycleType:(UIButton *)sender;
- (void)zn64fb_deleteFeature:(UIButton *)sender;
- (void)zn64fb_deletePatch:(UIButton *)sender;
- (void)zn64fb_cycleValueType:(UIButton *)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNFeatureBuilderControlsV2)

- (void)zn64fb_renderOther {
    [self zn64fb_renderOther];

    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    BOOL locked = workspace.hasAnyApplied || workspace.isBuilding;
    NSArray<NSDictionary *> *features = ZN64FeatureGroups(workspace);

    for (NSUInteger i = 0; i < features.count; i++) {
        UIButton *addPatch = ZN64ButtonWithTag(self.contentView, kZN64AddPatchTagBase + (NSInteger)i);
        UIView *card = addPatch.superview;
        if (!addPatch || !card) continue;

        CGFloat left = 10.0;
        CGFloat gap = 6.0;
        CGFloat inner = CGRectGetWidth(card.bounds) - left * 2.0;
        CGFloat w = (inner - gap * 2.0) / 3.0;
        addPatch.frame = CGRectMake(left, 6, w, 32);
        [addPatch setTitle:@"＋ Patch" forState:UIControlStateNormal];

        NSString *name = features[i][@"name"] ?: @"功能";
        ZNFeatureControlType type = [workspace controlTypeForFeature:name];
        UIButton *typeButton = [self zn40_button:[NSString stringWithFormat:@"类型 · %@", ZNFeatureControlTypeName(type)]
                                          selector:@selector(zn64fb_cycleType:)
                                             frame:CGRectMake(left + w + gap, 6, w, 32)];
        typeButton.tag = kZN64TypeTagBase + (NSInteger)i;
        typeButton.enabled = !locked;
        typeButton.titleLabel.adjustsFontSizeToFitWidth = YES;
        typeButton.titleLabel.minimumScaleFactor = 0.65;
        [card addSubview:typeButton];

        UIButton *deleteFeature = [self zn40_button:@"删除功能"
                                            selector:@selector(zn64fb_deleteFeature:)
                                               frame:CGRectMake(left + (w + gap) * 2.0, 6, w, 32)];
        deleteFeature.tag = kZN64DeleteFeatureTagBase + (NSInteger)i;
        deleteFeature.enabled = !locked;
        deleteFeature.titleLabel.adjustsFontSizeToFitWidth = YES;
        deleteFeature.titleLabel.minimumScaleFactor = 0.7;
        deleteFeature.backgroundColor = [UIColor.systemRedColor colorWithAlphaComponent:0.12];
        deleteFeature.layer.borderColor = [UIColor.systemRedColor colorWithAlphaComponent:0.72].CGColor;
        [card addSubview:deleteFeature];
    }

    for (NSUInteger globalIndex = 0; globalIndex < workspace.rows.count; globalIndex++) {
        UITextField *offset = ZN64FieldWithTag(self.contentView, kZN64OffsetFieldTagBase + (NSInteger)globalIndex);
        UIView *patchCard = offset.superview;
        if (!offset || !patchCard) continue;

        ZNBinaryPatchRow *row=workspace.rows[globalIndex];
        BOOL typed=(row.featureControlType==ZNFeatureControlTypeNumber||row.featureControlType==ZNFeatureControlTypeSlider);

        UIButton *deletePatch = [self zn40_button:@"删除"
                                          selector:@selector(zn64fb_deletePatch:)
                                             frame:CGRectMake(CGRectGetWidth(patchCard.bounds) - 58, 3, 45, 19)];
        deletePatch.tag = kZN64DeletePatchTagBase + (NSInteger)globalIndex;
        deletePatch.enabled = !locked;
        deletePatch.titleLabel.font = [UIFont systemFontOfSize:8.0 weight:UIFontWeightSemibold];
        deletePatch.backgroundColor = [UIColor.systemRedColor colorWithAlphaComponent:0.10];
        deletePatch.layer.borderColor = [UIColor.systemRedColor colorWithAlphaComponent:0.64].CGColor;
        [patchCard addSubview:deletePatch];

        if(typed){
            NSString *vt=row.featureValueType==ZNValueTypeAuto?@"未选":ZNValueTypeName(row.featureValueType);
            UIButton *valueType=[self zn40_button:[NSString stringWithFormat:@"ValueType · %@",vt]
                                          selector:@selector(zn64fb_cycleValueType:)
                                             frame:CGRectMake(CGRectGetWidth(patchCard.bounds)-160,3,94,19)];
            valueType.tag=kZN64ValueTypeTagBase+(NSInteger)globalIndex;
            valueType.enabled=!locked;
            valueType.titleLabel.font=[UIFont systemFontOfSize:7.7 weight:UIFontWeightSemibold];
            valueType.titleLabel.adjustsFontSizeToFitWidth=YES;
            valueType.titleLabel.minimumScaleFactor=.60;
            [patchCard addSubview:valueType];
        }

        for (UIView *child in patchCard.subviews) {
            if (![child isKindOfClass:UILabel.class]) continue;
            UILabel *label = (UILabel *)child;
            if (CGRectGetMinY(label.frame) <= 6.0 && CGRectGetMinX(label.frame) <= 20.0) {
                CGRect f = label.frame;
                f.size.width = MAX(40.0, CGRectGetWidth(patchCard.bounds) - CGRectGetMinX(f) - (typed ? 170.0 : 76.0));
                label.frame = f;
                break;
            }
        }
    }
}

- (void)zn64fb_cycleType:(UIButton *)sender {
    NSInteger index = sender.tag - kZN64TypeTagBase;
    if (index < 0) return;
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    NSArray<NSDictionary *> *features = ZN64FeatureGroups(workspace);
    if ((NSUInteger)index >= features.count) return;
    NSString *name = features[(NSUInteger)index][@"name"] ?: @"";
    ZNFeatureControlType current = [workspace controlTypeForFeature:name];
    ZNFeatureControlType next = (ZNFeatureControlType)(((uint32_t)current + 1u) % 4u);
    NSString *error = nil;
    if (![workspace setControlType:next forFeature:name error:&error]) {
        workspace.lastStatus = [NSString stringWithFormat:@"修改控件类型失败：%@", error ?: @"未知错误"];
    }
    [self renderPage];
}

- (void)zn64fb_cycleValueType:(UIButton *)sender {
    NSInteger globalIndex=sender.tag-kZN64ValueTypeTagBase;
    ZNBinaryPatchWorkspace *workspace=[ZNBinaryPatchWorkspace sharedWorkspace];
    if(globalIndex<0||(NSUInteger)globalIndex>=workspace.rows.count)return;
    ZNBinaryPatchRow *row=workspace.rows[(NSUInteger)globalIndex];
    if(row.featureControlType!=ZNFeatureControlTypeNumber&&row.featureControlType!=ZNFeatureControlTypeSlider)return;

    NSString *name=ZN64Trim(row.group);
    if(!name.length||[name caseInsensitiveCompare:@"Imported"]==NSOrderedSame)name=ZN64Trim(row.title);
    ZNValueType current=row.featureValueType;
    ZNValueType next=(current<ZNValueTypeI32||current>=ZNValueTypeF64)?ZNValueTypeI32:(ZNValueType)(current+1);
    NSString *error=nil;
    if(![workspace setValueType:next forFeature:name error:&error]){
        workspace.lastStatus=[NSString stringWithFormat:@"修改 ValueType 失败：%@",error?:@"未知错误"];
    }
    [self renderPage];
}

- (void)zn64fb_deleteFeature:(UIButton *)sender {
    NSInteger index = sender.tag - kZN64DeleteFeatureTagBase;
    if (index < 0) return;
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    NSArray<NSDictionary *> *features = ZN64FeatureGroups(workspace);
    if ((NSUInteger)index >= features.count) return;
    NSString *name = features[(NSUInteger)index][@"name"] ?: @"";
    NSString *error = nil;
    if (![workspace removeFeatureNamed:name error:&error]) {
        workspace.lastStatus = [NSString stringWithFormat:@"删除功能失败：%@", error ?: @"未知错误"];
    }
    [self renderPage];
}

- (void)zn64fb_deletePatch:(UIButton *)sender {
    NSInteger index = sender.tag - kZN64DeletePatchTagBase;
    if (index < 0) return;
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    NSString *error = nil;
    if (![workspace removePatchAtGlobalIndex:(NSUInteger)index error:&error]) {
        workspace.lastStatus = [NSString stringWithFormat:@"删除 Patch 失败：%@", error ?: @"未知错误"];
    }
    [self renderPage];
}

@end

extern "C" void ZNInstallFeatureBuilderControlsV2Deferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        Method original = class_getInstanceMethod(cls, @selector(zn50b_renderOther));
        Method replacement = class_getInstanceMethod(cls, @selector(zn64fb_renderOther));
        if (original && replacement) method_exchangeImplementations(original, replacement);
    });
}

#pragma mark - END ZNFeatureBuilderControlsV2.mm


#pragma mark - BEGIN ZNIL2CPPMethodFinderUI.mm
#line 1 "ZNIL2CPPMethodFinderUI.mm"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNIL2CPPHybridFinder.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

// v0.5.7 Method Finder UI.
// Developer authoring surface only. Search resolves runtime metadata/address
// information but never patches code itself. "加入 Builder" creates an empty
// Builder row that must still pass the existing Runtime Validator before apply
// or generated-binary build.

static const void *kZN57MFQueryKey = &kZN57MFQueryKey;
static const void *kZN57MFResultKey = &kZN57MFResultKey;
static const void *kZN57MFStatusKey = &kZN57MFStatusKey;
static const NSInteger kZN57MFQueryFieldTag = 571001;

static NSString *ZN57MFTrim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *ZN57MFHex(uint64_t value) {
    return [NSString stringWithFormat:@"0x%llX", (unsigned long long)value];
}

static NSString *ZN57MFShortName(NSDictionary *result) {
    NSString *method = result[@"method"] ?: @"Method";
    NSInteger argc = [result[@"argumentCount"] integerValue];
    return argc >= 0 ? [NSString stringWithFormat:@"%@/%ld", method, (long)argc] : method;
}

static NSString *ZN57MFFullCopyText(NSDictionary *result) {
    NSDictionary *stats = result[@"searchStats"] ?: @{};
    return [NSString stringWithFormat:
            @"%@\nModule: UnityFramework\nAssembly: %@\nNamespace: %@\nClass: %@\nMethod: %@\nRVA: %@\nPreferred/IDA VA: %@\nRuntime VA: %@\nMethodInfo: %@\nMethod Pointer: %@\nPointer Source: %@\nPointer Type: %@\nSearch: %@ · classes=%@ · %@ms",
            result[@"canonical"] ?: @"IL2CPP Method",
            result[@"assembly"] ?: @"",
            result[@"namespace"] ?: @"",
            result[@"class"] ?: @"",
            result[@"method"] ?: @"",
            result[@"rvaText"] ?: @"?",
            ZN57MFHex([result[@"preferredVA"] unsignedLongLongValue]),
            ZN57MFHex([result[@"runtimeVA"] unsignedLongLongValue]),
            ZN57MFHex([result[@"methodInfo"] unsignedLongLongValue]),
            ZN57MFHex([result[@"methodPointer"] unsignedLongLongValue]),
            result[@"pointerSource"] ?: @"?",
            result[@"pointerKind"] ?: @"?",
            result[@"searchMode"] ?: @"?",
            stats[@"classesScanned"] ?: @0,
            stats[@"elapsedMs"] ?: @0];
}

@interface ZNRuntimeMenuControllerV040 (ZNIL2CPPMethodFinderUI)
- (NSArray<NSString *> *)zn57mf_baseCategories;
- (NSArray<NSString *> *)zn57mf_baseSymbols;
- (void)zn57mf_renderFullPage;
- (CGSize)zn57mf_fullSizeForWindow:(UIWindow *)window;
- (void)zn57mf_renderFinder;
- (void)zn57mf_search:(id)sender;
- (void)zn57mf_queryChanged:(UITextField *)field;
- (void)zn57mf_copyResult:(id)sender;
- (void)zn57mf_addToBuilder:(id)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNIL2CPPMethodFinderUI)

- (NSString *)zn57mf_query {
    return objc_getAssociatedObject(self, kZN57MFQueryKey) ?: @"";
}

- (void)zn57mf_setQuery:(NSString *)value {
    objc_setAssociatedObject(self, kZN57MFQueryKey, ZN57MFTrim(value), OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (NSDictionary *)zn57mf_result {
    return objc_getAssociatedObject(self, kZN57MFResultKey);
}

- (void)zn57mf_setResult:(NSDictionary *)value {
    objc_setAssociatedObject(self, kZN57MFResultKey, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSString *)zn57mf_status {
    return objc_getAssociatedObject(self, kZN57MFStatusKey) ?: @"输入方法名，例如 gethp / GetMoney/0 / Game.Player::GetHP/0";
}

- (void)zn57mf_setStatus:(NSString *)value {
    objc_setAssociatedObject(self, kZN57MFStatusKey, value ?: @"", OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (NSArray<NSString *> *)zn57mf_baseCategories {
    NSArray<NSString *> *base = [self zn57mf_baseCategories];
    if ([base containsObject:@"方法查找"] || ![base containsObject:@"其他"]) return base;
    NSMutableArray<NSString *> *items = [base mutableCopy];
    NSUInteger other = [items indexOfObject:@"其他"];
    [items insertObject:@"方法查找" atIndex:MIN(other + 1, items.count)];
    return items;
}

- (NSArray<NSString *> *)zn57mf_baseSymbols {
    NSArray<NSString *> *base = [self zn57mf_baseSymbols];
    NSArray<NSString *> *cats = [self zn57mf_baseCategories];
    if (base.count == cats.count) return base;
    NSMutableArray<NSString *> *items = [base mutableCopy];
    NSUInteger finder = [cats indexOfObject:@"方法查找"];
    if (finder != NSNotFound && finder <= items.count) [items insertObject:@"magnifyingglass" atIndex:finder];
    return items;
}

- (CGSize)zn57mf_fullSizeForWindow:(UIWindow *)window {
    CGSize size = [self zn57mf_fullSizeForWindow:window];
    NSString *category = (self.selectedCategory >= 0 && self.selectedCategory < (NSInteger)self.categories.count)
        ? self.categories[(NSUInteger)self.selectedCategory]
        : @"";
    if ([category isEqualToString:@"方法查找"]) {
        UIEdgeInsets insets = window.safeAreaInsets;
        CGFloat available = MAX(300.0, CGRectGetHeight(window.bounds) - insets.top - insets.bottom - 20.0);
        size.height = MIN(MAX(size.height, 470.0), available);
    }
    return size;
}

- (void)zn57mf_renderFullPage {
    NSString *category = (self.selectedCategory >= 0 && self.selectedCategory < (NSInteger)self.categories.count)
        ? self.categories[(NSUInteger)self.selectedCategory]
        : @"";
    if ([category isEqualToString:@"方法查找"]) {
        [self zn57mf_renderFinder];
        return;
    }
    [self zn57mf_renderFullPage];
}

- (UITextField *)zn57mf_field:(CGRect)frame {
    UITextField *field = [[UITextField alloc] initWithFrame:frame];
    field.tag = kZN57MFQueryFieldTag;
    field.text = [self zn57mf_query];
    field.placeholder = @"gethp / Class::Method/0";
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
    [field addTarget:self action:@selector(zn57mf_queryChanged:) forControlEvents:UIControlEventEditingChanged];
    [field addTarget:self action:@selector(zn57mf_search:) forControlEvents:UIControlEventEditingDidEndOnExit];
    return field;
}

- (void)zn57mf_renderFinder {
    [self.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat y = 9.0;

    UIView *searchCard = [self cardAtY:y height:82 width:width compact:NO];
    UILabel *title = [self label:@"IL2CPP 方法查找" size:12.6 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    title.frame = CGRectMake(13, 8, searchCard.bounds.size.width - 26, 20);
    [searchCard addSubview:title];
    CGFloat buttonW = 68.0;
    UITextField *field = [self zn57mf_field:CGRectMake(13, 34, searchCard.bounds.size.width - 26 - buttonW - 7, 36)];
    [searchCard addSubview:field];
    UIButton *search = [self zn40_button:@"搜索" selector:@selector(zn57mf_search:) frame:CGRectMake(CGRectGetMaxX(field.frame) + 7, 34, buttonW, 36)];
    search.backgroundColor = [self.theme.accentColor colorWithAlphaComponent:0.20];
    search.layer.borderColor = self.theme.accentColor.CGColor;
    [searchCard addSubview:search];
    [self.contentView addSubview:searchCard];
    y += 90.0;

    UIView *hintCard = [self cardAtY:y height:54 width:width compact:NO];
    UILabel *hint = [self label:@"大小写不敏感精确匹配 · Assembly-CSharp 优先 · bounded streaming · 不建立全量索引"
                              size:8.9
                            weight:UIFontWeightRegular
                             color:self.theme.secondaryTextColor];
    hint.frame = CGRectMake(13, 8, hintCard.bounds.size.width - 26, 38);
    hint.numberOfLines = 2;
    hint.lineBreakMode = NSLineBreakByWordWrapping;
    [hintCard addSubview:hint];
    [self.contentView addSubview:hintCard];
    y += 62.0;

    NSDictionary *result = [self zn57mf_result];
    NSString *statusText = [self zn57mf_status];
    if (!result) {
        UIView *statusCard = [self cardAtY:y height:70 width:width compact:NO];
        UILabel *status = [self label:statusText size:9.5 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        status.frame = CGRectMake(13, 9, statusCard.bounds.size.width - 26, 52);
        status.numberOfLines = 3;
        status.lineBreakMode = NSLineBreakByWordWrapping;
        [statusCard addSubview:status];
        [self.contentView addSubview:statusCard];
        y += 78.0;
        [self zn40_updateContentHeight:y];
        return;
    }

    NSString *canonical = result[@"canonical"] ?: @"IL2CPP Method";
    UIView *methodCard = [self cardAtY:y height:76 width:width compact:NO];
    UILabel *methodTitle = [self label:canonical size:11.3 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    methodTitle.frame = CGRectMake(13, 8, methodCard.bounds.size.width - 26, 22);
    methodTitle.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [methodCard addSubview:methodTitle];
    UILabel *owner = [self label:[NSString stringWithFormat:@"%@ · %@%@%@",
                                  result[@"assembly"] ?: @"?",
                                  result[@"namespace"] ?: @"",
                                  [result[@"namespace"] length] ? @"." : @"",
                                  result[@"class"] ?: @""]
                              size:9.2 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    owner.frame = CGRectMake(13, 32, methodCard.bounds.size.width - 26, 17);
    owner.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [methodCard addSubview:owner];
    UILabel *source = [self label:[NSString stringWithFormat:@"%@ · %@", result[@"pointerKind"] ?: @"?", result[@"pointerSource"] ?: @"?"]
                               size:8.8 weight:UIFontWeightRegular color:self.theme.accentColor];
    source.frame = CGRectMake(13, 51, methodCard.bounds.size.width - 26, 16);
    [methodCard addSubview:source];
    [self.contentView addSubview:methodCard];
    y += 84.0;

    NSArray<NSString *> *addressLines = @[
        [NSString stringWithFormat:@"RVA / Offset      %@", result[@"rvaText"] ?: @"?"],
        [NSString stringWithFormat:@"Preferred / IDA   %@", ZN57MFHex([result[@"preferredVA"] unsignedLongLongValue])],
        [NSString stringWithFormat:@"Runtime VA        %@", ZN57MFHex([result[@"runtimeVA"] unsignedLongLongValue])],
        [NSString stringWithFormat:@"MethodInfo        %@", ZN57MFHex([result[@"methodInfo"] unsignedLongLongValue])],
        [NSString stringWithFormat:@"Method Pointer    %@", ZN57MFHex([result[@"methodPointer"] unsignedLongLongValue])],
    ];
    CGFloat addressH = 30.0 + 18.0 * addressLines.count + 8.0;
    UIView *addressCard = [self cardAtY:y height:addressH width:width compact:NO];
    UILabel *addressTitle = [self label:@"地址信息" size:11.0 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    addressTitle.frame = CGRectMake(13, 7, addressCard.bounds.size.width - 26, 18);
    [addressCard addSubview:addressTitle];
    CGFloat lineY = 29.0;
    for (NSString *line in addressLines) {
        UILabel *label = [self label:line size:9.2 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        label.frame = CGRectMake(13, lineY, addressCard.bounds.size.width - 26, 17);
        label.font = [UIFont monospacedDigitSystemFontOfSize:9.2 weight:UIFontWeightRegular];
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.70;
        [addressCard addSubview:label];
        lineY += 18.0;
    }
    [self.contentView addSubview:addressCard];
    y += addressH + 8.0;

    NSDictionary *stats = result[@"searchStats"] ?: @{};
    UIView *statsCard = [self cardAtY:y height:52 width:width compact:NO];
    UILabel *statsLabel = [self label:[NSString stringWithFormat:@"搜索：%@ · classes=%@ · %.1fms · candidates=%@",
                                      result[@"searchMode"] ?: @"?",
                                      stats[@"classesScanned"] ?: @0,
                                      [stats[@"elapsedMs"] doubleValue],
                                      stats[@"candidateCount"] ?: @1]
                                  size:8.8 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    statsLabel.frame = CGRectMake(13, 7, statsCard.bounds.size.width - 26, 38);
    statsLabel.numberOfLines = 2;
    [statsCard addSubview:statsLabel];
    [self.contentView addSubview:statsCard];
    y += 60.0;

    CGFloat gap = 8.0;
    CGFloat inner = width - 26.0;
    CGFloat bw = (inner - gap) / 2.0;
    UIView *actions = [self cardAtY:y height:52 width:width compact:NO];
    UIButton *copy = [self zn40_button:@"复制信息" selector:@selector(zn57mf_copyResult:) frame:CGRectMake(13, 9, bw, 34)];
    UIButton *builder = [self zn40_button:@"加入 Builder" selector:@selector(zn57mf_addToBuilder:) frame:CGRectMake(13 + bw + gap, 9, bw, 34)];
    builder.backgroundColor = [self.theme.accentColor colorWithAlphaComponent:0.20];
    builder.layer.borderColor = self.theme.accentColor.CGColor;
    [actions addSubview:copy];
    [actions addSubview:builder];
    [self.contentView addSubview:actions];
    y += 60.0;

    if (statusText.length) {
        UIView *statusCard = [self cardAtY:y height:48 width:width compact:NO];
        UILabel *status = [self label:statusText size:8.6 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        status.frame = CGRectMake(13, 6, statusCard.bounds.size.width - 26, 36);
        status.numberOfLines = 2;
        [statusCard addSubview:status];
        [self.contentView addSubview:statusCard];
        y += 56.0;
    }

    [self zn40_updateContentHeight:y];
}

- (void)zn57mf_queryChanged:(UITextField *)field {
    [self zn57mf_setQuery:field.text];
}

- (void)zn57mf_search:(id)sender {
    (void)sender;
    UITextField *field = (UITextField *)[self.contentView viewWithTag:kZN57MFQueryFieldTag];
    NSString *query = ZN57MFTrim(field.text.length ? field.text : [self zn57mf_query]);
    [self zn57mf_setQuery:query];
    [self.hostWindow endEditing:YES];
    if (!query.length) {
        [self zn57mf_setResult:nil];
        [self zn57mf_setStatus:@"请输入 IL2CPP 方法名"];
        [self renderPage];
        return;
    }

    CFAbsoluteTime began = CFAbsoluteTimeGetCurrent();
    NSString *searchError = nil;
    NSDictionary *result = [[ZNIL2CPPHybridFinder sharedFinder] resolveExpression:query error:&searchError];
    double elapsedMs = (CFAbsoluteTimeGetCurrent() - began) * 1000.0;
    [self zn57mf_setResult:result];
    if (result) {
        NSDictionary *stats = result[@"searchStats"] ?: @{};
        [self zn57mf_setStatus:[NSString stringWithFormat:@"找到 %@ · %@ · classes=%@ · %.1fms",
                                ZN57MFShortName(result),
                                result[@"searchMode"] ?: @"?",
                                stats[@"classesScanned"] ?: @0,
                                elapsedMs]];
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[method-finder] %@ -> %@ (%@, %.1fms)",
                                             query,
                                             result[@"rvaText"] ?: @"?",
                                             result[@"pointerKind"] ?: @"?",
                                             elapsedMs]];
    } else {
        [self zn57mf_setStatus:searchError ?: @"Method Finder 搜索失败"];
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[method-finder] %@ failed: %@", query, searchError ?: @"unknown"]];
    }
    [self renderPage];
}

- (void)zn57mf_copyResult:(id)sender {
    (void)sender;
    NSDictionary *result = [self zn57mf_result];
    if (!result) return;
    UIPasteboard.generalPasteboard.string = ZN57MFFullCopyText(result);
    [self zn57mf_setStatus:@"方法信息已复制"];
    [self renderPage];
}

- (void)zn57mf_addToBuilder:(id)sender {
    (void)sender;
    NSDictionary *result = [self zn57mf_result];
    NSString *query = [self zn57mf_query];
    if (!result || !query.length) return;

    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    if (workspace.hasAnyApplied || workspace.isBuilding) {
        [self zn57mf_setStatus:@"Builder 当前被 Runtime Patch/生成任务锁定，请先恢复或等待生成结束"];
        [self renderPage];
        return;
    }

    NSString *featureName = [workspace addFeature];
    if (!featureName.length || !workspace.rows.count) {
        [self zn57mf_setStatus:workspace.lastStatus.length ? workspace.lastStatus : @"无法创建 Builder 行"];
        [self renderPage];
        return;
    }

    ZNBinaryPatchRow *row = workspace.rows.lastObject;
    NSString *suggested = ZN57MFShortName(result);
    if (suggested.length) {
        NSString *renameError = nil;
        if (![workspace renameFeature:featureName to:suggested error:&renameError]) {
            (void)renameError;
        }
    }
    row.target = @"UnityFramework";
    row.explicitTarget = YES;
    row.offsetText = query;
    row.enabledText = @"";
    row.originalHex = @"";
    row.validated = NO;
    row.validator = nil;
    row.statusText = @"来自 Method Finder · 请填写 Patch 字节后执行读取验证";
    workspace.lastStatus = [NSString stringWithFormat:@"Method Finder 已加入 Builder：%@；尚未写入 Patch 字节", suggested.length ? suggested : query];

    NSInteger other = [self.categories indexOfObject:@"其他"];
    if (other != NSNotFound) {
        self.selectedCategory = other;
        [NSUserDefaults.standardUserDefaults setInteger:other forKey:@"ZonoePatch.SelectedCategory"];
    }
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[method-finder] added to Builder: %@", query]];
    [self renderPage];
}

@end

static void ZN57MFSwapInstanceMethod(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallIL2CPPMethodFinderUIDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZN57MFSwapInstanceMethod(cls, @selector(zn40_baseCategories), @selector(zn57mf_baseCategories));
        ZN57MFSwapInstanceMethod(cls, @selector(zn40_baseSymbols), @selector(zn57mf_baseSymbols));
        ZN57MFSwapInstanceMethod(cls, @selector(renderFullPage), @selector(zn57mf_renderFullPage));
        ZN57MFSwapInstanceMethod(cls, @selector(fullSizeForWindow:), @selector(zn57mf_fullSizeForWindow:));
        [[ZNRuntimeLogger sharedLogger] log:@"[bootstrap][main] v0.5.7 Method Finder UI installed: bounded search -> detail -> Builder"];
    });
}

#pragma mark - END ZNIL2CPPMethodFinderUI.mm


#pragma mark - BEGIN ZNIL2CPPMethodFinderMenuBinding.mm
#line 1 "ZNIL2CPPMethodFinderMenuBinding.mm"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "ZNDeveloperGate.h"
#import "ZNPatchCore.h"
extern "C" void ZNInstallIL2CPPMethodFinderSearchV2Deferred(void);extern "C" void ZNInstallIL2CPPMethodFinderZeroVMAddrFixDeferred(void);extern "C" void ZNInstallIL2CPPMethodFinderUXV2Deferred(void);extern "C" void ZNInstallIL2CPPMethodFinderV3Deferred(void);extern "C" void ZNInstallIL2CPPMethodFinderPatchBridgeV3Deferred(void);extern "C" void ZNInstallIL2CPPMethodFinderM2Deferred(void);extern "C" void ZNInstallIL2CPPMethodFinderM21CancelUXDeferred(void);extern "C" void ZNInstallIL2CPPMethodFinderM22StableCancelUXDeferred(void);extern "C" void ZNInstallIL2CPPABIDetailUIDeferred(void);extern "C" void ZNInstallFeatureBuilderControlsV2Deferred(void);extern "C" void ZNInstallFeatureRuntimeControlsV2Deferred(void);extern "C" void ZNInstallOffsetResolverV2Deferred(void);extern "C" void ZNInstallBinaryPatchWorkspaceAddressV2Deferred(void);extern "C" void ZNInstallRuntimeMenuModalShellDeferred(void);extern "C" void ZNInstallRuntimeMethodCallDeferred(void);extern "C" void ZNInstallM551AuthoringPersistenceDeferred(void);extern "C" void ZNInstallUXFixesV2Deferred(void);extern "C" void ZNInstallMethodFinderM43UIDeferred(void);extern "C" void ZNInstallMethodFinderM43PolishDeferred(void);extern "C" void ZNInstallInstanceSelectionV2UIDeferred(void);extern "C" void ZNInstallM441HotfixDeferred(void);extern "C" void ZNInstallM442SearchRestoreDeferred(void);extern "C" void ZNInstallM45AddressOwningMethodDeferred(void);extern "C" void ZNInstallM46SignatureExecutionDeferred(void);extern "C" void ZNInstallM46FullSignatureUIDeferred(void);extern "C" void ZNInstallM461PolishDeferred(void);extern "C" void ZNInstallM462InstanceSafetyDeferred(void);extern "C" void ZNInstallM462CandidateBindingUIDeferred(void);extern "C" void ZNInstallM47ReceiverCaptureUIDeferred(void);extern "C" void ZNInstallM47MultiArgInvokeDeferred(void);extern "C" void ZNInstallM47MultiArgUIDeferred(void);extern "C" void ZNInstallM47BuilderArgsUIDeferred(void);extern "C" void ZNInstallM47VersionUIDeferred(void);extern "C" void ZNInstallM48ReturnCaptureDeferred(void);extern "C" void ZNInstallM49GenericInvokeEditableArgsDeferred(void);extern "C" void ZNInstallM50ManagedReturnChainingDeferred(void);extern "C" void ZNInstallMethodFinderUnifiedUIDeferred(void);extern "C" void ZNInstallM51RuntimeArgControlsImmediateChainDeferred(void);extern "C" void ZNInstallM52ChainStoreV2Deferred(void);extern "C" void ZNInstallM52ImmediateChainV2Deferred(void);extern "C" void ZNInstallM52ChainExecuteButtonDeferred(void);extern "C" void ZNInstallM55TypedControlBindingDeferred(void);extern "C" void ZNInstallM56StaticValueCellBindingDeferred(void);extern "C" void ZNInstallM58UnifiedControlRuntimeDeferred(void);extern "C" void ZNInstallM584SchemeALayoutDeferred(void);extern "C" void ZNInstallM585UnifiedControlSemanticsDeferred(void);extern "C" void ZNInstallM585StaticRuntimeRangeDeferred(void);extern "C" void ZNInstallM590UnifiedActionModelDeferred(void);extern "C" void ZNInstallM591OffsetHookControlsDeferred(void);extern "C" void ZNInstallM592OffsetAuthoringPersistenceDeferred(void);extern "C" void ZNInstallM600UnifiedFeatureSurfaceDeferred(void);extern "C" void ZNInstallM610UnifiedFeatureModelDeferred(void);
@interface ZNRuntimeMenuControllerV040 (ZNIL2CPPMethodFinderMenuBinding)
- (NSArray<NSString *> *)zn58mfb_baseCategories;- (NSArray<NSString *> *)zn58mfb_baseSymbols;
@end
@implementation ZNRuntimeMenuControllerV040 (ZNIL2CPPMethodFinderMenuBinding)
- (NSArray<NSString *> *)zn58mfb_baseCategories {NSArray<NSString *> *base=[self zn58mfb_baseCategories];if([base containsObject:@"方法查找"]||![ZNDeveloperGate sharedGate].authorized)return base;NSMutableArray<NSString *> *items=[base mutableCopy];NSUInteger other=[items indexOfObject:@"其他"],settings=[items indexOfObject:@"设置"],insertion=items.count;if(other!=NSNotFound)insertion=MIN(other+1,items.count);else if(settings!=NSNotFound)insertion=settings;else if(items.count>0)insertion=1;[items insertObject:@"方法查找" atIndex:insertion];return items;}
- (NSArray<NSString *> *)zn58mfb_baseSymbols {NSArray<NSString *> *base=[self zn58mfb_baseSymbols],*categories=[self zn40_baseCategories];if(base.count==categories.count)return base;NSUInteger finder=[categories indexOfObject:@"方法查找"];if(finder==NSNotFound||finder>base.count)return base;NSMutableArray<NSString *> *symbols=[base mutableCopy];[symbols insertObject:@"magnifyingglass" atIndex:finder];return symbols;}
@end
extern "C" void ZNInstallIL2CPPMethodFinderMenuBindingDeferred(void) {static dispatch_once_t onceToken;dispatch_once(&onceToken,^{ZNInstallIL2CPPMethodFinderSearchV2Deferred();ZNInstallIL2CPPMethodFinderZeroVMAddrFixDeferred();Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040");if(!cls)return;Method a=class_getInstanceMethod(cls,@selector(zn40_baseCategories)),b=class_getInstanceMethod(cls,@selector(zn58mfb_baseCategories));if(a&&b)method_exchangeImplementations(a,b);Method c=class_getInstanceMethod(cls,@selector(zn40_baseSymbols)),d=class_getInstanceMethod(cls,@selector(zn58mfb_baseSymbols));if(c&&d)method_exchangeImplementations(c,d);ZNInstallIL2CPPMethodFinderUXV2Deferred();ZNInstallIL2CPPMethodFinderV3Deferred();ZNInstallIL2CPPMethodFinderPatchBridgeV3Deferred();ZNInstallIL2CPPMethodFinderM2Deferred();ZNInstallIL2CPPMethodFinderM21CancelUXDeferred();ZNInstallIL2CPPMethodFinderM22StableCancelUXDeferred();ZNInstallIL2CPPABIDetailUIDeferred();ZNInstallFeatureBuilderControlsV2Deferred();ZNInstallFeatureRuntimeControlsV2Deferred();ZNInstallOffsetResolverV2Deferred();ZNInstallBinaryPatchWorkspaceAddressV2Deferred();ZNInstallRuntimeMenuModalShellDeferred();ZNInstallRuntimeMethodCallDeferred();ZNInstallM551AuthoringPersistenceDeferred();ZNInstallUXFixesV2Deferred();ZNInstallMethodFinderM43UIDeferred();ZNInstallMethodFinderM43PolishDeferred();ZNInstallInstanceSelectionV2UIDeferred();ZNInstallM441HotfixDeferred();ZNInstallM442SearchRestoreDeferred();ZNInstallM45AddressOwningMethodDeferred();ZNInstallM46SignatureExecutionDeferred();ZNInstallM46FullSignatureUIDeferred();ZNInstallM461PolishDeferred();ZNInstallM462InstanceSafetyDeferred();ZNInstallM47MultiArgInvokeDeferred();ZNInstallM47MultiArgUIDeferred();ZNInstallM47BuilderArgsUIDeferred();ZNInstallM47VersionUIDeferred();ZNInstallM48ReturnCaptureDeferred();ZNInstallM49GenericInvokeEditableArgsDeferred();ZNInstallM50ManagedReturnChainingDeferred();ZNInstallMethodFinderUnifiedUIDeferred();ZNInstallM462CandidateBindingUIDeferred();ZNInstallM47ReceiverCaptureUIDeferred();ZNInstallM51RuntimeArgControlsImmediateChainDeferred();ZNInstallM52ChainStoreV2Deferred();ZNInstallM52ImmediateChainV2Deferred();ZNInstallM52ChainExecuteButtonDeferred();ZNInstallM55TypedControlBindingDeferred();ZNInstallM56StaticValueCellBindingDeferred();ZNInstallM58UnifiedControlRuntimeDeferred();ZNInstallM584SchemeALayoutDeferred();ZNInstallM585UnifiedControlSemanticsDeferred();ZNInstallM585StaticRuntimeRangeDeferred();ZNInstallM590UnifiedActionModelDeferred();ZNInstallM591OffsetHookControlsDeferred();ZNInstallM592OffsetAuthoringPersistenceDeferred();ZNInstallM600UnifiedFeatureSurfaceDeferred();ZNInstallM610UnifiedFeatureModelDeferred();[[ZNRuntimeLogger sharedLogger]log:@"[m6.1] Unified Feature Model installed: exact Offset controls converge to Runtime backend; Static fallback preserved"];});}
#pragma mark - END ZNIL2CPPMethodFinderMenuBinding.mm


#pragma mark - BEGIN ZNIL2CPPMethodFinderUXV2.mm
#line 1 "ZNIL2CPPMethodFinderUXV2.mm"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNTheme.h"

// Method Finder V2 presentation layer. The existing v0.5.7 UI remains the
// baseline; this deferred swizzle augments it after each render so the change is
// isolated from the sealed menu lifecycle and Builder transaction semantics.

static const void *kZN58UXCopyValueKey = &kZN58UXCopyValueKey;
static const void *kZN58UXCopyLabelKey = &kZN58UXCopyLabelKey;
static const NSInteger kZN58UXQueryFieldTag = 571001;

static NSString *ZN58UXHex(uint64_t value) {
    return [NSString stringWithFormat:@"0x%llX", (unsigned long long)value];
}

static NSArray<UIView *> *ZN58UXDescendants(UIView *root) {
    NSMutableArray<UIView *> *result = [NSMutableArray array];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIView *view = queue.lastObject;
        [queue removeLastObject];
        for (UIView *child in view.subviews) {
            [result addObject:child];
            [queue addObject:child];
        }
    }
    return result;
}

@interface ZNRuntimeMenuControllerV040 (ZNIL2CPPMethodFinderUXV2)
- (void)zn58ux_renderFinder;
- (void)zn58ux_copyAddress:(UIButton *)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNIL2CPPMethodFinderUXV2)

- (void)zn58ux_renderFinder {
    // After method exchange this calls the original v0.5.7 renderer.
    [self zn58ux_renderFinder];

    NSArray<UIView *> *views = ZN58UXDescendants(self.contentView);
    UITextField *queryField = (UITextField *)[self.contentView viewWithTag:kZN58UXQueryFieldTag];
    if ([queryField isKindOfClass:UITextField.class]) {
        queryField.placeholder = @"方法名 / Class::Method/0 / 0xRVA";
    }

    for (UIView *view in views) {
        if (![view isKindOfClass:UILabel.class]) continue;
        UILabel *label = (UILabel *)view;
        if ([label.text containsString:@"bounded streaming"] || [label.text containsString:@"不建立全量索引"]) {
            label.text = @"智能查找 · 完整类名直查 · 裸方法名 12000-Class 分片续扫 · 0xRVA 反查";
        }
    }

    NSDictionary *result = [self zn57mf_result];
    if (!result) return;

    NSDictionary *stats = result[@"searchStats"] ?: @{};
    NSNumber *shards = stats[@"shardsScanned"];
    if (shards) {
        for (UIView *view in views) {
            if (![view isKindOfClass:UILabel.class]) continue;
            UILabel *label = (UILabel *)view;
            if ([label.text hasPrefix:@"搜索："] && [label.text rangeOfString:@"shards="].location == NSNotFound) {
                label.text = [label.text stringByAppendingFormat:@" · shards=%@", shards];
            }
        }
    }

    NSArray<NSDictionary<NSString *, NSString *> *> *addressSpecs = @[
        @{@"old": @"RVA / Offset", @"title": @"RVA / Offset", @"value": result[@"rvaText"] ?: @"?"},
        @{@"old": @"Preferred / IDA", @"title": @"Preferred VA", @"value": ZN58UXHex([result[@"preferredVA"] unsignedLongLongValue])},
        @{@"old": @"Runtime VA", @"title": @"Runtime VA", @"value": ZN58UXHex([result[@"runtimeVA"] unsignedLongLongValue])},
        @{@"old": @"MethodInfo", @"title": @"MethodInfo", @"value": ZN58UXHex([result[@"methodInfo"] unsignedLongLongValue])},
        @{@"old": @"Method Pointer", @"title": @"Method Pointer", @"value": ZN58UXHex([result[@"methodPointer"] unsignedLongLongValue])},
    ];

    NSMutableSet<UILabel *> *usedLabels = [NSMutableSet set];
    for (NSDictionary<NSString *, NSString *> *spec in addressSpecs) {
        UILabel *target = nil;
        for (UIView *view in views) {
            if (![view isKindOfClass:UILabel.class]) continue;
            UILabel *label = (UILabel *)view;
            if ([usedLabels containsObject:label]) continue;
            NSString *oldPrefix = spec[@"old"];
            NSString *newPrefix = spec[@"title"];
            if ([label.text hasPrefix:oldPrefix] || [label.text hasPrefix:newPrefix]) {
                target = label;
                break;
            }
        }
        if (!target || !target.superview) continue;
        [usedLabels addObject:target];

        NSString *title = spec[@"title"] ?: @"地址";
        NSString *value = spec[@"value"] ?: @"?";
        target.text = [NSString stringWithFormat:@"%-14@ %@", title, value];
        CGRect frame = target.frame;
        CGFloat copyW = 42.0;
        target.frame = CGRectMake(frame.origin.x, frame.origin.y, MAX(80.0, frame.size.width - copyW - 5.0), frame.size.height);

        UIButton *copy = [UIButton buttonWithType:UIButtonTypeSystem];
        copy.frame = CGRectMake(CGRectGetWidth(target.superview.bounds) - 13.0 - copyW,
                                frame.origin.y - 1.0,
                                copyW,
                                MAX(19.0, frame.size.height + 2.0));
        [copy setTitle:@"复制" forState:UIControlStateNormal];
        [copy setTitleColor:self.theme.accentColor forState:UIControlStateNormal];
        copy.titleLabel.font = [self menuFont:8.4 weight:UIFontWeightSemibold];
        copy.backgroundColor = [self.theme.accentColor colorWithAlphaComponent:0.12];
        copy.layer.cornerRadius = 5.0;
        copy.layer.borderWidth = 0.7;
        copy.layer.borderColor = [self.theme.accentColor colorWithAlphaComponent:0.55].CGColor;
        objc_setAssociatedObject(copy, kZN58UXCopyValueKey, value, OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(copy, kZN58UXCopyLabelKey, title, OBJC_ASSOCIATION_COPY_NONATOMIC);
        [copy addTarget:self action:@selector(zn58ux_copyAddress:) forControlEvents:UIControlEventTouchUpInside];
        [target.superview addSubview:copy];
    }

    BOOL hasBuilderPage = [self.categories containsObject:@"其他"];
    for (UIView *view in views) {
        if (![view isKindOfClass:UIButton.class]) continue;
        UIButton *button = (UIButton *)view;
        if ([button.currentTitle isEqualToString:@"加入 Builder"] || [button.currentTitle hasPrefix:@"创建 Patch"]) {
            if (hasBuilderPage) {
                [button setTitle:@"创建 Patch" forState:UIControlStateNormal];
            } else {
                [button setTitle:@"创建 Patch（需其他）" forState:UIControlStateNormal];
                button.enabled = NO;
                button.alpha = 0.55;
            }
        }
    }

    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat y = 0.0;
    for (UIView *view in self.contentView.subviews) y = MAX(y, CGRectGetMaxY(view.frame));
    y += 8.0;

    UIView *addressHelp = [self cardAtY:y height:130.0 width:width compact:NO];
    UILabel *addressTitle = [self label:@"这些地址分别做什么" size:10.6 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    addressTitle.frame = CGRectMake(13, 7, addressHelp.bounds.size.width - 26, 17);
    [addressHelp addSubview:addressTitle];
    UILabel *addressText = [self label:@"RVA / Offset：UnityFramework 相对偏移，Patch/对照 dump 首选。\nPreferred VA：Mach-O __TEXT 首选基址 + RVA，适合静态反汇编；分析器若 rebase 过需以其基址为准。\nRuntime VA：本次启动真实地址，受 ASLR 影响，重启可能变化。\nMethodInfo：IL2CPP 方法元数据对象地址，不是代码入口。\nMethod Pointer：当前 native 代码入口，用于运行时反汇编/验证。"
                                  size:7.9
                                weight:UIFontWeightRegular
                                 color:self.theme.secondaryTextColor];
    addressText.frame = CGRectMake(13, 27, addressHelp.bounds.size.width - 26, 96);
    addressText.numberOfLines = 0;
    addressText.lineBreakMode = NSLineBreakByWordWrapping;
    [addressHelp addSubview:addressText];
    [self.contentView addSubview:addressHelp];
    y += 138.0;

    UIView *builderHelp = [self cardAtY:y height:66.0 width:width compact:NO];
    UILabel *builderTitle = [self label:@"创建 Patch 是什么" size:10.4 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    builderTitle.frame = CGRectMake(13, 7, builderHelp.bounds.size.width - 26, 17);
    [builderHelp addSubview:builderTitle];
    NSString *builderTextValue = hasBuilderPage
        ? @"只创建一条“未验证”的 Patch 编辑行：自动带入 UnityFramework + 当前方法；不会立即改内存。你仍需填写 Patch 字节 → 读取验证 → 再临时应用或生成。"
        : @"Patch 编辑器位于“其他”开发页；当前权限没有显示该页，因此这里不创建不可编辑的孤立 Patch 行。";
    UILabel *builderText = [self label:builderTextValue size:8.1 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    builderText.frame = CGRectMake(13, 27, builderHelp.bounds.size.width - 26, 33);
    builderText.numberOfLines = 2;
    builderText.lineBreakMode = NSLineBreakByWordWrapping;
    [builderHelp addSubview:builderText];
    [self.contentView addSubview:builderHelp];
    y += 74.0;

    [self zn40_updateContentHeight:y];
}

- (void)zn58ux_copyAddress:(UIButton *)sender {
    NSString *value = objc_getAssociatedObject(sender, kZN58UXCopyValueKey) ?: @"";
    NSString *label = objc_getAssociatedObject(sender, kZN58UXCopyLabelKey) ?: @"地址";
    if (!value.length) return;
    UIPasteboard.generalPasteboard.string = value;
    [self zn57mf_setStatus:[NSString stringWithFormat:@"已复制 %@：%@", label, value]];
    [self renderPage];
}

@end

extern "C" void ZNInstallIL2CPPMethodFinderUXV2Deferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        Method original = class_getInstanceMethod(cls, @selector(zn57mf_renderFinder));
        Method replacement = class_getInstanceMethod(cls, @selector(zn58ux_renderFinder));
        if (original && replacement) method_exchangeImplementations(original, replacement);
    });
}

#pragma mark - END ZNIL2CPPMethodFinderUXV2.mm


#pragma mark - BEGIN ZNIL2CPPMethodFinderUIV3.mm
#line 1 "ZNIL2CPPMethodFinderUIV3.mm"
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

#pragma mark - END ZNIL2CPPMethodFinderUIV3.mm


#pragma mark - BEGIN ZNIL2CPPMethodFinderM2.mm
#line 1 "ZNIL2CPPMethodFinderM2.mm"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/vm_prot.h>
#import <dlfcn.h>
#import <errno.h>
#import <limits.h>
#import <stdint.h>
#import <stdlib.h>
#import <stdio.h>
#import <string.h>

#import "ZNIL2CPPHybridFinder.h"
#import "ZNIL2CPPMethodFinderSearchV3.h"
#import "ZNIL2CPPResolver.h"
#import "ZNPatchCore.h"
#import "ZNTheme.h"

// v0.5.8-dev Method Finder V3 Milestone 2.
//
// M1 remains frozen on its own branch. M2 adds:
//   - asynchronous search so class scanning never blocks the menu thread;
//   - cooperative cancellation and shard progress;
//   - broad bare-method search (exact > prefix > suffix > contains);
//   - a compact persistent IL2CPP metadata index keyed by UnityFramework UUID
//     + file size. Runtime VA / MethodInfo / Method Pointer are NEVER persisted.
//
// Structured expressions and Named Offset keep their exact semantics.

static const NSUInteger kZN61ShardClasses = 12000;
static const NSUInteger kZN61HardLimit = 64;
static const NSUInteger kZN61IndexVersion = 1;
static const NSUInteger kZN61MaxExecRanges = 16;
static const NSInteger kZN61SearchFieldTag = 603001;

typedef void *(*ZN61DomainGetFn)(void);
typedef const void **(*ZN61DomainGetAssembliesFn)(const void *, size_t *);
typedef const void *(*ZN61AssemblyGetImageFn)(const void *);
typedef const char *(*ZN61ImageGetNameFn)(const void *);
typedef size_t (*ZN61ImageGetClassCountFn)(const void *);
typedef void *(*ZN61ImageGetClassFn)(const void *, size_t);
typedef const char *(*ZN61ClassGetNameFn)(void *);
typedef const char *(*ZN61ClassGetNamespaceFn)(void *);
typedef const void *(*ZN61ClassGetMethodsFn)(void *, void **);
typedef const char *(*ZN61MethodGetNameFn)(const void *);
typedef uint32_t (*ZN61MethodGetParamCountFn)(const void *);
typedef void *(*ZN61MethodGetPointerFn)(const void *);

typedef struct {
    void *handle;
    const struct mach_header_64 *header;
    char unityPath[PATH_MAX];
    uintptr_t runtimeBase;
    uint64_t preferredBase;
    uintptr_t execStarts[kZN61MaxExecRanges];
    uintptr_t execEnds[kZN61MaxExecRanges];
    NSUInteger execCount;

    ZN61DomainGetFn domainGet;
    ZN61DomainGetAssembliesFn domainGetAssemblies;
    ZN61AssemblyGetImageFn assemblyGetImage;
    ZN61ImageGetNameFn imageGetName;
    ZN61ImageGetClassCountFn imageGetClassCount;
    ZN61ImageGetClassFn imageGetClass;
    ZN61ClassGetNameFn classGetName;
    ZN61ClassGetNamespaceFn classGetNamespace;
    ZN61ClassGetMethodsFn classGetMethods;
    ZN61MethodGetNameFn methodGetName;
    ZN61MethodGetParamCountFn methodGetParamCount;
    ZN61MethodGetPointerFn methodGetPointer;
} ZN61Runtime;

typedef struct __attribute__((packed)) {
    uint32_t assemblyId;
    uint32_t namespaceId;
    uint32_t classId;
    uint32_t methodId;
    int32_t argumentCount;
    uint32_t reserved;
    uint64_t rva;
} ZN61IndexRecord;
static_assert(sizeof(ZN61IndexRecord) == 32, "ZN61IndexRecord must stay compact/stable");

typedef NS_ENUM(NSInteger, ZN61MatchRank) {
    ZN61MatchExact = 0,
    ZN61MatchPrefix = 1,
    ZN61MatchSuffix = 2,
    ZN61MatchContains = 3,
    ZN61MatchNone = 99,
};

typedef void (^ZN61ProgressBlock)(NSDictionary<NSString *, id> *progress);
typedef void (^ZN61CompletionBlock)(NSArray<NSDictionary<NSString *, id> *> * _Nullable results,
                                    NSDictionary<NSString *, id> * _Nullable stats,
                                    NSString * _Nullable error);

static NSString *ZN61Trim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *ZN61String(const char *value) {
    if (!value) return @"";
    return [NSString stringWithUTF8String:value] ?: @"";
}

static NSString *ZN61NormalizedAssembly(NSString *value) {
    NSString *s = ZN61Trim(value).lowercaseString;
    return [s hasSuffix:@".dll"] ? [s substringToIndex:s.length - 4] : s;
}

static BOOL ZN61AssemblyPreferred(NSString *assembly) {
    return [ZN61NormalizedAssembly(assembly) isEqualToString:@"assembly-csharp"];
}

static BOOL ZN61IsExecutable(const ZN61Runtime *runtime, uintptr_t address) {
    if (!address) return NO;
    for (NSUInteger i = 0; i < runtime->execCount; i++) {
        if (address >= runtime->execStarts[i] && address < runtime->execEnds[i]) return YES;
    }
    return NO;
}

static void *ZN61ResolveSymbol(ZN61Runtime *runtime, const char *name) {
    void *p = runtime->handle ? dlsym(runtime->handle, name) : NULL;
    if (!p) p = dlsym(RTLD_DEFAULT, name);
    return p;
}

static BOOL ZN61LoadRuntime(ZN61Runtime *runtime, NSString **error) {
    memset(runtime, 0, sizeof(*runtime));
    const struct mach_header_64 *unityHeader = NULL;
    const char *unityPath = NULL;

    uint32_t imageCount = _dyld_image_count();
    for (uint32_t i = 0; i < imageCount; i++) {
        const char *raw = _dyld_get_image_name(i);
        if (!raw) continue;
        NSString *path = [NSString stringWithUTF8String:raw] ?: @"";
        NSString *leaf = path.lastPathComponent;
        if ([leaf isEqualToString:@"UnityFramework"] ||
            [path rangeOfString:@"UnityFramework.framework/UnityFramework"
                         options:NSCaseInsensitiveSearch].location != NSNotFound) {
            unityPath = raw;
            unityHeader = (const struct mach_header_64 *)_dyld_get_image_header(i);
            break;
        }
    }

    if (!unityHeader || unityHeader->magic != MH_MAGIC_64 || !unityPath) {
        if (error) *error = @"UnityFramework 尚未加载或不是 arm64 Mach-O";
        return NO;
    }

    runtime->header = unityHeader;
    runtime->runtimeBase = (uintptr_t)unityHeader;
    snprintf(runtime->unityPath, sizeof(runtime->unityPath), "%s", unityPath);

    BOOL textFound = NO;
    const uint8_t *cursor = (const uint8_t *)(unityHeader + 1);
    const uint8_t *commandsEnd = cursor + unityHeader->sizeofcmds;
    for (uint32_t i = 0; i < unityHeader->ncmds; i++) {
        if (cursor + sizeof(struct load_command) > commandsEnd) break;
        const struct load_command *lc = (const struct load_command *)cursor;
        if (lc->cmdsize < sizeof(*lc) || cursor + lc->cmdsize > commandsEnd) break;
        if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(struct segment_command_64)) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)cursor;
            if (strncmp(seg->segname, SEG_TEXT, 16) == 0) {
                runtime->preferredBase = seg->vmaddr;
                textFound = YES;
                break;
            }
        }
        cursor += lc->cmdsize;
    }
    if (!textFound) {
        if (error) *error = @"UnityFramework Mach-O 缺少 __TEXT segment";
        return NO;
    }

    // A zero __TEXT.vmaddr is valid on the device-verified baseline.
    cursor = (const uint8_t *)(unityHeader + 1);
    for (uint32_t i = 0; i < unityHeader->ncmds; i++) {
        if (cursor + sizeof(struct load_command) > commandsEnd) break;
        const struct load_command *lc = (const struct load_command *)cursor;
        if (lc->cmdsize < sizeof(*lc) || cursor + lc->cmdsize > commandsEnd) break;
        if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(struct segment_command_64)) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)cursor;
            if ((seg->initprot & VM_PROT_EXECUTE) &&
                seg->vmaddr >= runtime->preferredBase &&
                runtime->execCount < kZN61MaxExecRanges) {
                uintptr_t start = runtime->runtimeBase + (uintptr_t)(seg->vmaddr - runtime->preferredBase);
                runtime->execStarts[runtime->execCount] = start;
                runtime->execEnds[runtime->execCount] = start + (uintptr_t)seg->vmsize;
                runtime->execCount++;
            }
        }
        cursor += lc->cmdsize;
    }

    if (!runtime->execCount) {
        if (error) *error = @"UnityFramework 没有可验证的 executable segment";
        return NO;
    }

#ifdef RTLD_NOLOAD
    runtime->handle = dlopen(runtime->unityPath, RTLD_LAZY | RTLD_NOLOAD);
#else
    runtime->handle = dlopen(runtime->unityPath, RTLD_LAZY);
#endif
    runtime->domainGet = (ZN61DomainGetFn)ZN61ResolveSymbol(runtime, "il2cpp_domain_get");
    runtime->domainGetAssemblies = (ZN61DomainGetAssembliesFn)ZN61ResolveSymbol(runtime, "il2cpp_domain_get_assemblies");
    runtime->assemblyGetImage = (ZN61AssemblyGetImageFn)ZN61ResolveSymbol(runtime, "il2cpp_assembly_get_image");
    runtime->imageGetName = (ZN61ImageGetNameFn)ZN61ResolveSymbol(runtime, "il2cpp_image_get_name");
    runtime->imageGetClassCount = (ZN61ImageGetClassCountFn)ZN61ResolveSymbol(runtime, "il2cpp_image_get_class_count");
    runtime->imageGetClass = (ZN61ImageGetClassFn)ZN61ResolveSymbol(runtime, "il2cpp_image_get_class");
    runtime->classGetName = (ZN61ClassGetNameFn)ZN61ResolveSymbol(runtime, "il2cpp_class_get_name");
    runtime->classGetNamespace = (ZN61ClassGetNamespaceFn)ZN61ResolveSymbol(runtime, "il2cpp_class_get_namespace");
    runtime->classGetMethods = (ZN61ClassGetMethodsFn)ZN61ResolveSymbol(runtime, "il2cpp_class_get_methods");
    runtime->methodGetName = (ZN61MethodGetNameFn)ZN61ResolveSymbol(runtime, "il2cpp_method_get_name");
    runtime->methodGetParamCount = (ZN61MethodGetParamCountFn)ZN61ResolveSymbol(runtime, "il2cpp_method_get_param_count");
    runtime->methodGetPointer = (ZN61MethodGetPointerFn)ZN61ResolveSymbol(runtime, "il2cpp_method_get_pointer");

    BOOL core = runtime->domainGet && runtime->domainGetAssemblies &&
                runtime->assemblyGetImage && runtime->imageGetName &&
                runtime->imageGetClassCount && runtime->imageGetClass &&
                runtime->classGetName && runtime->classGetNamespace &&
                runtime->classGetMethods && runtime->methodGetName;
    if (!core) {
        if (error) *error = @"IL2CPP Runtime 缺少 M2 索引所需 API";
        if (runtime->handle) dlclose(runtime->handle);
        memset(runtime, 0, sizeof(*runtime));
        return NO;
    }
    return YES;
}

static void ZN61CloseRuntime(ZN61Runtime *runtime) {
    if (runtime->handle) dlclose(runtime->handle);
    runtime->handle = NULL;
}

static const void **ZN61Assemblies(ZN61Runtime *runtime, size_t *count) {
    if (count) *count = 0;
    void *domain = runtime->domainGet ? runtime->domainGet() : NULL;
    if (!domain || !runtime->domainGetAssemblies) return NULL;
    size_t c = 0;
    const void **assemblies = runtime->domainGetAssemblies(domain, &c);
    if (count) *count = c;
    return assemblies;
}

static uintptr_t ZN61MethodPointer(ZN61Runtime *runtime, const void *method) {
    if (!method) return 0;
    if (runtime->methodGetPointer) {
        uintptr_t p = (uintptr_t)runtime->methodGetPointer(method);
        if (ZN61IsExecutable(runtime, p)) return p;
    }
    uintptr_t words[2] = {0, 0};
    memcpy(words, method, sizeof(words));
    if (ZN61IsExecutable(runtime, words[0])) return words[0];
    if (ZN61IsExecutable(runtime, words[1])) return words[1];
    return 0;
}

static NSString *ZN61UUIDString(const struct mach_header_64 *header) {
    if (!header || header->magic != MH_MAGIC_64) return @"";
    const uint8_t *cursor = (const uint8_t *)(header + 1);
    const uint8_t *end = cursor + header->sizeofcmds;
    for (uint32_t i = 0; i < header->ncmds; i++) {
        if (cursor + sizeof(struct load_command) > end) break;
        const struct load_command *lc = (const struct load_command *)cursor;
        if (lc->cmdsize < sizeof(*lc) || cursor + lc->cmdsize > end) break;
        if (lc->cmd == LC_UUID && lc->cmdsize >= sizeof(struct uuid_command)) {
            const struct uuid_command *uc = (const struct uuid_command *)cursor;
            const unsigned char *u = uc->uuid;
            return [NSString stringWithFormat:
                    @"%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
                    u[0],u[1],u[2],u[3],u[4],u[5],u[6],u[7],
                    u[8],u[9],u[10],u[11],u[12],u[13],u[14],u[15]];
        }
        cursor += lc->cmdsize;
    }
    return @"";
}

static NSString *ZN61Fingerprint(ZN61Runtime *runtime) {
    NSString *uuid = ZN61UUIDString(runtime->header);
    NSString *path = [NSString stringWithUTF8String:runtime->unityPath] ?: @"";
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil] ?: @{};
    unsigned long long size = [attrs[NSFileSize] unsignedLongLongValue];
    if (uuid.length) return [NSString stringWithFormat:@"%@-%llu", uuid, size];

    NSDate *date = attrs[NSFileModificationDate];
    long long stamp = date ? (long long)date.timeIntervalSince1970 : 0;
    return [NSString stringWithFormat:@"fallback-%llu-%lld", size, stamp];
}

static NSString *ZN61IndexDirectory(void) {
    NSString *cache = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    if (!cache.length) cache = NSTemporaryDirectory();
    return [[cache stringByAppendingPathComponent:@"ZonoPatch"] stringByAppendingPathComponent:@"IL2CPPMethodIndex"];
}

static NSString *ZN61IndexPath(NSString *fingerprint) {
    NSString *safe = [[fingerprint ?: @"unknown" stringByReplacingOccurrencesOfString:@"/" withString:@"_"]
                      stringByReplacingOccurrencesOfString:@":" withString:@"_"];
    return [[ZN61IndexDirectory() stringByAppendingPathComponent:safe] stringByAppendingPathExtension:@"bplist"];
}

static NSDictionary *ZN61LoadIndex(NSString *fingerprint) {
    NSData *data = [NSData dataWithContentsOfFile:ZN61IndexPath(fingerprint)];
    if (!data.length) return nil;
    NSError *error = nil;
    id plist = [NSPropertyListSerialization propertyListWithData:data
                                                         options:NSPropertyListImmutable
                                                          format:NULL
                                                           error:&error];
    if (![plist isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *index = (NSDictionary *)plist;
    if ([index[@"version"] unsignedIntegerValue] != kZN61IndexVersion) return nil;
    if (![index[@"fingerprint"] isEqualToString:fingerprint]) return nil;
    NSData *records = index[@"records"];
    if (![records isKindOfClass:NSData.class] || (records.length % sizeof(ZN61IndexRecord)) != 0) return nil;
    if (![index[@"assemblies"] isKindOfClass:NSArray.class] ||
        ![index[@"namespaces"] isKindOfClass:NSArray.class] ||
        ![index[@"classes"] isKindOfClass:NSArray.class] ||
        ![index[@"methods"] isKindOfClass:NSArray.class]) return nil;
    return index;
}

static BOOL ZN61SaveIndex(NSDictionary *index, NSString *fingerprint, NSString **errorText) {
    NSError *error = nil;
    NSString *dir = ZN61IndexDirectory();
    if (![[NSFileManager defaultManager] createDirectoryAtPath:dir
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:&error]) {
        if (errorText) *errorText = error.localizedDescription ?: @"无法创建索引目录";
        return NO;
    }
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:index
                                                               format:NSPropertyListBinaryFormat_v1_0
                                                              options:0
                                                                error:&error];
    if (!data.length || error) {
        if (errorText) *errorText = error.localizedDescription ?: @"索引序列化失败";
        return NO;
    }
    if (![data writeToFile:ZN61IndexPath(fingerprint) options:NSDataWritingAtomic error:&error]) {
        if (errorText) *errorText = error.localizedDescription ?: @"索引写入失败";
        return NO;
    }
    return YES;
}

static uint32_t ZN61Intern(NSMutableArray<NSString *> *table,
                           NSMutableDictionary<NSString *, NSNumber *> *map,
                           NSString *value) {
    NSString *s = value ?: @"";
    NSNumber *known = map[s];
    if (known) return known.unsignedIntValue;
    uint32_t idx = (uint32_t)table.count;
    [table addObject:s];
    map[s] = @(idx);
    return idx;
}

static ZN61MatchRank ZN61RankForMethod(NSString *method, NSString *query) {
    NSString *m = ZN61Trim(method);
    NSString *q = ZN61Trim(query);
    if (!m.length || !q.length) return ZN61MatchNone;
    if ([m caseInsensitiveCompare:q] == NSOrderedSame) return ZN61MatchExact;
    if ([m rangeOfString:q options:(NSCaseInsensitiveSearch | NSAnchoredSearch)].location != NSNotFound)
        return ZN61MatchPrefix;
    if ([m rangeOfString:q options:(NSCaseInsensitiveSearch | NSBackwardsSearch | NSAnchoredSearch)].location != NSNotFound)
        return ZN61MatchSuffix;
    if ([m rangeOfString:q options:NSCaseInsensitiveSearch].location != NSNotFound)
        return ZN61MatchContains;
    return ZN61MatchNone;
}

static NSString *ZN61RankText(ZN61MatchRank rank) {
    switch (rank) {
        case ZN61MatchExact: return @"exact";
        case ZN61MatchPrefix: return @"prefix";
        case ZN61MatchSuffix: return @"suffix";
        case ZN61MatchContains: return @"contains";
        default: return @"none";
    }
}

static NSString *ZN61Canonical(NSString *assembly,
                               NSString *namespaceName,
                               NSString *className,
                               NSString *methodName,
                               NSInteger argc) {
    NSString *classPath = namespaceName.length
        ? [NSString stringWithFormat:@"%@.%@", namespaceName, className ?: @""]
        : (className ?: @"");
    return [NSString stringWithFormat:@"%@!%@::%@%@",
            assembly.length ? assembly : @"?",
            classPath.length ? classPath : @"?",
            methodName.length ? methodName : @"?",
            argc >= 0 ? [NSString stringWithFormat:@"/%ld", (long)argc] : @""];
}

static NSMutableSet<NSString *> *ZN61CancelledTokens(void) {
    static NSMutableSet<NSString *> *tokens;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ tokens = [NSMutableSet set]; });
    return tokens;
}

static void ZN61Cancel(NSString *token) {
    if (!token.length) return;
    @synchronized (ZN61CancelledTokens()) {
        [ZN61CancelledTokens() addObject:token];
    }
}

static BOOL ZN61IsCancelled(NSString *token) {
    if (!token.length) return NO;
    @synchronized (ZN61CancelledTokens()) {
        return [ZN61CancelledTokens() containsObject:token];
    }
}

static void ZN61ClearCancelled(NSString *token) {
    if (!token.length) return;
    @synchronized (ZN61CancelledTokens()) {
        [ZN61CancelledTokens() removeObject:token];
    }
}

static void ZN61EmitProgress(ZN61ProgressBlock block, NSDictionary *progress) {
    if (!block) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        block(progress ?: @{});
    });
}

static NSComparisonResult ZN61HitCompare(NSDictionary *a, NSDictionary *b) {
    NSInteger ra = [a[@"rank"] integerValue], rb = [b[@"rank"] integerValue];
    if (ra != rb) return ra < rb ? NSOrderedAscending : NSOrderedDescending;
    BOOL pa = [a[@"assemblyPreferred"] boolValue], pb = [b[@"assemblyPreferred"] boolValue];
    if (pa != pb) return pa ? NSOrderedAscending : NSOrderedDescending;
    NSUInteger la = [a[@"method"] length], lb = [b[@"method"] length];
    if (la != lb) return la < lb ? NSOrderedAscending : NSOrderedDescending;
    NSComparisonResult byName = [a[@"method"] caseInsensitiveCompare:b[@"method"]];
    if (byName != NSOrderedSame) return byName;
    return [a[@"canonical"] caseInsensitiveCompare:b[@"canonical"]];
}

static void ZN61AddBoundedHit(NSMutableArray<NSDictionary *> *bucket,
                              NSDictionary *hit,
                              NSUInteger limit) {
    [bucket addObject:hit];
    if (bucket.count <= limit) return;
    [bucket sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return ZN61HitCompare(a, b);
    }];
    [bucket removeLastObject];
}

static NSArray<NSDictionary *> *ZN61FlattenBuckets(NSArray<NSMutableArray<NSDictionary *> *> *buckets,
                                                   NSUInteger limit) {
    NSMutableArray<NSDictionary *> *out = [NSMutableArray arrayWithCapacity:limit];
    for (NSMutableArray<NSDictionary *> *bucket in buckets) {
        [bucket sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return ZN61HitCompare(a, b);
        }];
        for (NSDictionary *hit in bucket) {
            [out addObject:hit];
            if (out.count >= limit) return out;
        }
    }
    return out;
}

static NSDictionary *ZN61HitFromRecord(ZN61IndexRecord record,
                                       NSArray *assemblies,
                                       NSArray *namespaces,
                                       NSArray *classes,
                                       NSArray *methods,
                                       ZN61MatchRank rank) {
    if (record.assemblyId >= assemblies.count ||
        record.namespaceId >= namespaces.count ||
        record.classId >= classes.count ||
        record.methodId >= methods.count) return nil;
    NSString *assembly = assemblies[record.assemblyId];
    NSString *ns = namespaces[record.namespaceId];
    NSString *cls = classes[record.classId];
    NSString *method = methods[record.methodId];
    return @{
        @"assembly": assembly ?: @"",
        @"namespace": ns ?: @"",
        @"class": cls ?: @"",
        @"method": method ?: @"",
        @"argumentCount": @(record.argumentCount),
        @"rva": @(record.rva),
        @"canonical": ZN61Canonical(assembly, ns, cls, method, record.argumentCount),
        @"rank": @(rank),
        @"matchReason": ZN61RankText(rank),
        @"assemblyPreferred": @(ZN61AssemblyPreferred(assembly)),
    };
}

static NSArray<NSDictionary *> *ZN61QueryIndex(NSDictionary *index,
                                               NSString *methodQuery,
                                               BOOL argumentSpecified,
                                               NSInteger wantedArguments,
                                               BOOL reverse,
                                               uint64_t reverseRVA,
                                               NSUInteger limit) {
    NSArray *assemblies = index[@"assemblies"];
    NSArray *namespaces = index[@"namespaces"];
    NSArray *classes = index[@"classes"];
    NSArray *methods = index[@"methods"];
    NSData *recordsData = index[@"records"];
    const ZN61IndexRecord *records = (const ZN61IndexRecord *)recordsData.bytes;
    NSUInteger count = recordsData.length / sizeof(ZN61IndexRecord);

    NSMutableArray<NSDictionary *> *b0 = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *b1 = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *b2 = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *b3 = [NSMutableArray array];
    NSArray *buckets = @[b0,b1,b2,b3];

    for (NSUInteger i = 0; i < count; i++) {
        ZN61IndexRecord r = records[i];
        if (argumentSpecified && r.argumentCount != wantedArguments) continue;
        ZN61MatchRank rank = ZN61MatchNone;
        if (reverse) {
            if (!r.rva || r.rva != reverseRVA) continue;
            rank = ZN61MatchExact;
        } else {
            if (r.methodId >= methods.count) continue;
            rank = ZN61RankForMethod(methods[r.methodId], methodQuery);
            if (rank == ZN61MatchNone) continue;
        }
        NSDictionary *hit = ZN61HitFromRecord(r, assemblies, namespaces, classes, methods, rank);
        if (!hit) continue;
        ZN61AddBoundedHit(buckets[(NSUInteger)rank], hit, limit);
    }
    return ZN61FlattenBuckets(buckets, limit);
}

static NSArray<NSDictionary *> *ZN61ResolveHits(NSArray<NSDictionary *> *hits,
                                                NSUInteger limit,
                                                NSString *mode,
                                                NSDictionary *stats,
                                                NSString *token) {
    NSMutableArray *resolved = [NSMutableArray arrayWithCapacity:MIN(limit, hits.count)];
    ZNIL2CPPHybridFinder *finder = [ZNIL2CPPHybridFinder sharedFinder];
    for (NSDictionary *hit in hits) {
        if (ZN61IsCancelled(token)) break;
        NSString *error = nil;
        NSArray *candidates = [finder zn60_searchCandidates:hit[@"canonical"] limit:2 error:&error];
        for (NSDictionary *candidate in candidates ?: @[]) {
            NSMutableDictionary *item = [candidate mutableCopy];
            item[@"searchMode"] = mode ?: @"m2";
            item[@"searchStats"] = stats ?: @{};
            item[@"matchRank"] = hit[@"rank"] ?: @0;
            item[@"matchReason"] = hit[@"matchReason"] ?: @"exact";
            item[@"indexRVA"] = hit[@"rva"] ?: @0;
            [resolved addObject:[item copy]];
            if (resolved.count >= limit) return resolved;
        }
    }
    return resolved;
}

@interface ZNMethodFinderM2Engine : NSObject
@property(nonatomic,copy) NSString *indexStatusText;
+ (instancetype)shared;
- (NSString *)startSearch:(NSString *)query
                    limit:(NSUInteger)limit
                 progress:(ZN61ProgressBlock)progress
               completion:(ZN61CompletionBlock)completion;
- (void)cancel:(NSString *)token;
@end

@implementation ZNMethodFinderM2Engine

+ (instancetype)shared {
    static ZNMethodFinderM2Engine *engine;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        engine = [ZNMethodFinderM2Engine new];
        engine.indexStatusText = @"本地索引：待检测（首次宽泛搜索自动建立）";
    });
    return engine;
}

- (void)cancel:(NSString *)token {
    ZN61Cancel(token);
}

- (NSString *)startSearch:(NSString *)query
                    limit:(NSUInteger)limit
                 progress:(ZN61ProgressBlock)progress
               completion:(ZN61CompletionBlock)completion {
    NSString *token = [NSUUID UUID].UUIDString;
    NSString *searchQuery = ZN61Trim(query);
    NSUInteger resultLimit = MAX((NSUInteger)1, MIN(limit ?: 32, kZN61HardLimit));

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
        if (!searchQuery.length) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil, @"请输入搜索内容"); });
            return;
        }

        uint64_t reverseRVA = 0;
        NSString *lower = searchQuery.lowercaseString;
        NSString *rvaText = searchQuery;
        if ([lower hasPrefix:@"rva:"]) rvaText = ZN61Trim([searchQuery substringFromIndex:4]);
        BOOL reverse = NO;
        if ([rvaText.lowercaseString hasPrefix:@"0x"]) {
            const char *c = rvaText.UTF8String;
            char *end = NULL;
            errno = 0;
            unsigned long long value = strtoull(c, &end, 0);
            if (!errno && end != c && (!end || !*end)) {
                reverse = YES;
                reverseRVA = (uint64_t)value;
            }
        }

        NSString *parseError = nil;
        NSDictionary *parsed = reverse ? nil : [ZNIL2CPPResolver parseNamedOffsetExpression:searchQuery error:&parseError];
        if (!reverse && !parsed) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil, parseError ?: @"搜索表达式无效"); });
            return;
        }

        NSString *assembly = parsed[@"assembly"] ?: @"";
        NSString *className = parsed[@"class"] ?: @"";
        BOOL namespaceSpecified = [parsed[@"namespaceSpecified"] boolValue];
        BOOL argumentSpecified = [parsed[@"argumentSpecified"] boolValue];
        NSInteger wantedArguments = argumentSpecified ? [parsed[@"argumentCount"] integerValue] : -1;
        int64_t delta = [parsed[@"delta"] longLongValue];
        NSString *methodQuery = parsed[@"method"] ?: @"";
        BOOL broad = !reverse && !assembly.length && !className.length && !namespaceSpecified && delta == 0;

        // Structured queries preserve M1 exact semantics but execute off-main.
        if (!broad && !reverse) {
            ZN61EmitProgress(progress, @{@"phase":@"exact", @"message":@"正在执行精确查询…"});
            if (ZN61IsCancelled(token)) {
                ZN61ClearCancelled(token);
                dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil, @"搜索已取消"); });
                return;
            }
            NSString *error = nil;
            NSArray *items = [[ZNIL2CPPHybridFinder sharedFinder] zn60_searchCandidates:searchQuery
                                                                                 limit:resultLimit
                                                                                 error:&error];
            if (ZN61IsCancelled(token)) {
                ZN61ClearCancelled(token);
                dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil, @"搜索已取消"); });
                return;
            }
            NSDictionary *stats = @{
                @"mode":@"m2-async-exact",
                @"indexSource":@"not-used",
                @"elapsedMs":@((CFAbsoluteTimeGetCurrent()-started)*1000.0),
                @"candidateCount":@(items.count),
                @"async":@YES
            };
            NSMutableArray *annotated = [NSMutableArray arrayWithCapacity:items.count];
            for (NSDictionary *candidate in items ?: @[]) {
                NSMutableDictionary *item = [candidate mutableCopy];
                item[@"searchMode"] = @"m2-async-exact";
                item[@"searchStats"] = stats;
                item[@"matchRank"] = @0;
                item[@"matchReason"] = @"exact";
                [annotated addObject:[item copy]];
            }
            ZN61ClearCancelled(token);
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(annotated.count ? annotated : nil, stats, annotated.count ? nil : (error ?: @"没有搜索结果"));
            });
            return;
        }

        ZN61Runtime runtime;
        NSString *runtimeError = nil;
        if (!ZN61LoadRuntime(&runtime, &runtimeError)) {
            ZN61ClearCancelled(token);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil, runtimeError ?: @"IL2CPP Runtime 不可用"); });
            return;
        }
        NSString *fingerprint = ZN61Fingerprint(&runtime);
        NSDictionary *index = ZN61LoadIndex(fingerprint);

        // RVA reverse can use the local index when present; otherwise preserve
        // the already-device-verified V3 reverse path instead of forcing a full
        // index build just for one address.
        if (reverse && !index) {
            ZN61CloseRuntime(&runtime);
            self.indexStatusText = @"本地索引：当前版本尚未建立";
            ZN61EmitProgress(progress, @{@"phase":@"reverse", @"message":@"本地索引未命中，使用已验证 RVA 反查…"});
            NSString *error = nil;
            NSArray *items = [[ZNIL2CPPHybridFinder sharedFinder] zn60_searchCandidates:searchQuery
                                                                                 limit:resultLimit
                                                                                 error:&error];
            NSDictionary *stats = @{
                @"mode":@"m2-reverse-fallback",
                @"indexSource":@"miss",
                @"elapsedMs":@((CFAbsoluteTimeGetCurrent()-started)*1000.0),
                @"candidateCount":@(items.count),
                @"async":@YES
            };
            NSMutableArray *annotated = [NSMutableArray arrayWithCapacity:items.count];
            for (NSDictionary *candidate in items ?: @[]) {
                NSMutableDictionary *item = [candidate mutableCopy];
                item[@"searchMode"] = @"m2-reverse-fallback";
                item[@"searchStats"] = stats;
                item[@"matchRank"] = @0;
                item[@"matchReason"] = @"rva";
                [annotated addObject:[item copy]];
            }
            ZN61ClearCancelled(token);
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(annotated.count ? annotated : nil, stats, annotated.count ? nil : (error ?: @"没有搜索结果"));
            });
            return;
        }

        if (index) {
            ZN61CloseRuntime(&runtime);
            self.indexStatusText = [NSString stringWithFormat:@"本地索引：已命中 · %@ records",
                                    index[@"recordCount"] ?: @0];
            ZN61EmitProgress(progress, @{@"phase":@"index-hit", @"message":@"正在查询本地 IL2CPP 索引…"});
            NSArray *hits = ZN61QueryIndex(index, methodQuery, argumentSpecified, wantedArguments,
                                           reverse, reverseRVA, resultLimit);
            NSDictionary *stats = @{
                @"mode": reverse ? @"m2-rva-index" : @"m2-wide-index",
                @"indexSource":@"hit",
                @"indexFingerprint":fingerprint ?: @"",
                @"indexRecordCount":index[@"recordCount"] ?: @0,
                @"elapsedMs":@((CFAbsoluteTimeGetCurrent()-started)*1000.0),
                @"candidateCount":@(hits.count),
                @"async":@YES,
                @"wideSearch":@(!reverse)
            };
            ZN61EmitProgress(progress, @{@"phase":@"resolving",
                                        @"message":[NSString stringWithFormat:@"索引命中 %lu 条，正在恢复 Runtime 地址…",
                                                   (unsigned long)hits.count]});
            NSArray *resolved = ZN61ResolveHits(hits, resultLimit,
                                                reverse ? @"m2-rva-index" : @"m2-wide-index",
                                                stats, token);
            BOOL cancelled = ZN61IsCancelled(token);
            ZN61ClearCancelled(token);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (cancelled) completion(nil, stats, @"搜索已取消");
                else completion(resolved.count ? resolved : nil, stats,
                                resolved.count ? nil : @"索引有匹配记录，但当前 Runtime 无法解析对应方法");
            });
            return;
        }

        // No index: broad search builds the complete compact index in the
        // background while simultaneously collecting ranked matches.
        self.indexStatusText = @"本地索引：正在建立…";
        size_t assemblyCount = 0;
        const void **assemblies = ZN61Assemblies(&runtime, &assemblyCount);
        if (!assemblies || !assemblyCount) {
            ZN61CloseRuntime(&runtime);
            ZN61ClearCancelled(token);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil, @"IL2CPP Domain 尚无可用程序集"); });
            return;
        }

        NSUInteger totalClasses = 0;
        for (size_t a = 0; a < assemblyCount; a++) {
            const void *image = runtime.assemblyGetImage(assemblies[a]);
            if (image) totalClasses += runtime.imageGetClassCount(image);
        }

        NSMutableArray<NSString *> *assemblyTable = [NSMutableArray array];
        NSMutableArray<NSString *> *namespaceTable = [NSMutableArray array];
        NSMutableArray<NSString *> *classTable = [NSMutableArray array];
        NSMutableArray<NSString *> *methodTable = [NSMutableArray array];
        NSMutableDictionary *assemblyMap = [NSMutableDictionary dictionary];
        NSMutableDictionary *namespaceMap = [NSMutableDictionary dictionary];
        NSMutableDictionary *classMap = [NSMutableDictionary dictionary];
        NSMutableDictionary *methodMap = [NSMutableDictionary dictionary];
        NSMutableData *recordData = [NSMutableData data];

        NSMutableArray *b0 = [NSMutableArray array];
        NSMutableArray *b1 = [NSMutableArray array];
        NSMutableArray *b2 = [NSMutableArray array];
        NSMutableArray *b3 = [NSMutableArray array];
        NSArray *buckets = @[b0,b1,b2,b3];

        NSUInteger classesDone = 0, shardsDone = 0, methodsDone = 0;
        BOOL cancelled = NO;
        for (NSUInteger pass = 0; pass < 2 && !cancelled; pass++) {
            for (size_t a = 0; a < assemblyCount && !cancelled; a++) {
                const void *image = runtime.assemblyGetImage(assemblies[a]);
                if (!image) continue;
                NSString *assemblyName = ZN61String(runtime.imageGetName(image));
                BOOL preferred = ZN61AssemblyPreferred(assemblyName);
                if ((pass == 0 && !preferred) || (pass == 1 && preferred)) continue;

                size_t classCount = runtime.imageGetClassCount(image);
                for (size_t shardStart = 0; shardStart < classCount && !cancelled; shardStart += kZN61ShardClasses) {
                    size_t shardEnd = MIN(classCount, shardStart + kZN61ShardClasses);
                    for (size_t c = shardStart; c < shardEnd; c++) {
                        if (ZN61IsCancelled(token)) { cancelled = YES; break; }
                        classesDone++;
                        @autoreleasepool {
                            void *klass = runtime.imageGetClass(image, c);
                            if (!klass) continue;
                            NSString *classNameValue = ZN61String(runtime.classGetName(klass));
                            NSString *namespaceName = ZN61String(runtime.classGetNamespace(klass));

                            uint32_t assemblyId = ZN61Intern(assemblyTable, assemblyMap, assemblyName);
                            uint32_t namespaceId = ZN61Intern(namespaceTable, namespaceMap, namespaceName);
                            uint32_t classId = ZN61Intern(classTable, classMap, classNameValue);

                            void *iter = NULL;
                            const void *method = NULL;
                            while ((method = runtime.classGetMethods(klass, &iter)) != NULL) {
                                if ((methodsDone & 0xFF) == 0 && ZN61IsCancelled(token)) {
                                    cancelled = YES;
                                    break;
                                }
                                methodsDone++;
                                NSString *methodName = ZN61String(runtime.methodGetName(method));
                                NSInteger argc = runtime.methodGetParamCount
                                    ? (NSInteger)runtime.methodGetParamCount(method) : -1;
                                uintptr_t pointer = ZN61MethodPointer(&runtime, method);
                                uint64_t rva = (pointer >= runtime.runtimeBase)
                                    ? (uint64_t)(pointer - runtime.runtimeBase) : 0;

                                uint32_t methodId = ZN61Intern(methodTable, methodMap, methodName);
                                ZN61IndexRecord record = {
                                    assemblyId, namespaceId, classId, methodId,
                                    (int32_t)argc, 0, rva
                                };
                                [recordData appendBytes:&record length:sizeof(record)];

                                if (argumentSpecified && argc != wantedArguments) continue;
                                ZN61MatchRank rank = ZN61RankForMethod(methodName, methodQuery);
                                if (rank == ZN61MatchNone) continue;
                                NSDictionary *hit = @{
                                    @"assembly":assemblyName ?: @"",
                                    @"namespace":namespaceName ?: @"",
                                    @"class":classNameValue ?: @"",
                                    @"method":methodName ?: @"",
                                    @"argumentCount":@(argc),
                                    @"rva":@(rva),
                                    @"canonical":ZN61Canonical(assemblyName, namespaceName, classNameValue, methodName, argc),
                                    @"rank":@(rank),
                                    @"matchReason":ZN61RankText(rank),
                                    @"assemblyPreferred":@(preferred)
                                };
                                ZN61AddBoundedHit(buckets[(NSUInteger)rank], hit, resultLimit);
                            }
                        }
                    }
                    shardsDone++;
                    ZN61EmitProgress(progress, @{
                        @"phase":@"index-build",
                        @"classesDone":@(classesDone),
                        @"classesTotal":@(totalClasses),
                        @"shardsDone":@(shardsDone),
                        @"records":@(recordData.length / sizeof(ZN61IndexRecord)),
                        @"message":[NSString stringWithFormat:
                                    @"正在建立索引：%lu/%lu classes · %lu shards · %lu methods",
                                    (unsigned long)classesDone, (unsigned long)totalClasses,
                                    (unsigned long)shardsDone, (unsigned long)methodsDone]
                    });
                    if (!cancelled) [NSThread sleepForTimeInterval:0.001];
                }
            }
        }

        ZN61CloseRuntime(&runtime);
        if (cancelled) {
            self.indexStatusText = @"本地索引：建立已取消（未保存半成品）";
            ZN61ClearCancelled(token);
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, @{@"mode":@"m2-wide-build", @"cancelled":@YES}, @"搜索已取消");
            });
            return;
        }

        NSDictionary *newIndex = @{
            @"version":@(kZN61IndexVersion),
            @"fingerprint":fingerprint ?: @"",
            @"builtAt":@([[NSDate date] timeIntervalSince1970]),
            @"recordCount":@(recordData.length / sizeof(ZN61IndexRecord)),
            @"assemblies":assemblyTable,
            @"namespaces":namespaceTable,
            @"classes":classTable,
            @"methods":methodTable,
            @"records":recordData
        };

        ZN61EmitProgress(progress, @{@"phase":@"index-save", @"message":@"扫描完成，正在保存本地索引…"});
        NSString *saveError = nil;
        BOOL saved = ZN61SaveIndex(newIndex, fingerprint, &saveError);
        self.indexStatusText = saved
            ? [NSString stringWithFormat:@"本地索引：已建立 · %@ records", newIndex[@"recordCount"]]
            : [NSString stringWithFormat:@"本地索引：本次可用但保存失败 · %@", saveError ?: @"unknown"];

        NSArray *hits = ZN61FlattenBuckets(buckets, resultLimit);
        NSDictionary *stats = @{
            @"mode":@"m2-wide-build",
            @"indexSource": saved ? @"built-and-saved" : @"built-memory-only",
            @"indexFingerprint":fingerprint ?: @"",
            @"indexRecordCount":newIndex[@"recordCount"] ?: @0,
            @"classesScanned":@(classesDone),
            @"classesTotal":@(totalClasses),
            @"shardsScanned":@(shardsDone),
            @"methodsScanned":@(methodsDone),
            @"elapsedMs":@((CFAbsoluteTimeGetCurrent()-started)*1000.0),
            @"candidateCount":@(hits.count),
            @"async":@YES,
            @"wideSearch":@YES
        };
        ZN61EmitProgress(progress, @{@"phase":@"resolving",
                                    @"message":[NSString stringWithFormat:@"宽泛匹配 %lu 条，正在恢复 Runtime 地址…",
                                               (unsigned long)hits.count]});
        NSArray *resolved = ZN61ResolveHits(hits, resultLimit, @"m2-wide-build", stats, token);
        BOOL wasCancelled = ZN61IsCancelled(token);
        ZN61ClearCancelled(token);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (wasCancelled) completion(nil, stats, @"搜索已取消");
            else completion(resolved.count ? resolved : nil, stats,
                            resolved.count ? nil : [NSString stringWithFormat:@"找不到包含“%@”的方法", methodQuery ?: searchQuery]);
        });
    });

    return token;
}

@end

// ---------- UI integration ----------

static const void *kZN61M2TokenKey = &kZN61M2TokenKey;

@interface ZNRuntimeMenuControllerV040 (ZNMethodFinderM2UI)
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)renderPage;
- (NSString *)zn57mf_query;
- (void)zn57mf_setQuery:(NSString *)value;

- (void)zn60v3_setCandidates:(NSArray<NSDictionary *> *)items;
- (void)zn60v3_setSelected:(NSDictionary * _Nullable)candidate;
- (void)zn60v3_setStatus:(NSString *)status;
- (void)zn60v3_setPage:(NSInteger)page;
- (NSUInteger)zn60v3_limit;
- (void)zn60v3_startSearch:(id)sender;
- (void)zn60v3_renderSearchAtWidth:(CGFloat)width;

- (void)zn61m2_startSearch:(id)sender;
- (void)zn61m2_renderSearchAtWidth:(CGFloat)width;
- (void)zn61m2_cancelSearch:(id)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNMethodFinderM2UI)

- (NSString *)zn61m2_activeToken {
    return objc_getAssociatedObject(self, kZN61M2TokenKey);
}

- (void)zn61m2_setActiveToken:(NSString *)token {
    objc_setAssociatedObject(self, kZN61M2TokenKey, token, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (void)zn61m2_renderSearchAtWidth:(CGFloat)width {
    // After swizzling this selector calls the original M1 renderer.
    [self zn61m2_renderSearchAtWidth:width];

    for (UIView *card in self.contentView.subviews) {
        for (UIView *child in card.subviews) {
            if (![child isKindOfClass:UILabel.class]) continue;
            UILabel *label = (UILabel *)child;
            if ([label.text containsString:@"忽略大小写（精确方法名）"]) {
                label.text = @"✓ 裸方法名宽泛搜索    ✓ exact > prefix > suffix > contains";
                label.adjustsFontSizeToFitWidth = YES;
                label.minimumScaleFactor = 0.68;
            } else if ([label.text containsString:@"阶段 1：多候选工作流"]) {
                label.text = @"阶段 2：异步分片 · 进度/取消 · UUID 绑定本地索引";
            }
        }
    }

    NSString *token = [self zn61m2_activeToken];
    if (!token.length) return;

    CGFloat maxY = 0;
    for (UIView *v in self.contentView.subviews) maxY = MAX(maxY, CGRectGetMaxY(v.frame));
    UIView *card = [self cardAtY:maxY + 8 height:48 width:width compact:NO];
    UILabel *label = [self label:@"后台搜索运行中，可随时取消；取消不会保存半成品索引。"
                             size:8.2
                           weight:UIFontWeightRegular
                            color:self.theme.secondaryTextColor];
    label.frame = CGRectMake(13, 8, card.bounds.size.width - 108, 32);
    label.numberOfLines = 2;
    [card addSubview:label];

    UIButton *cancel = [self zn40_button:@"取消"
                                selector:@selector(zn61m2_cancelSearch:)
                                   frame:CGRectMake(card.bounds.size.width - 86, 9, 73, 30)];
    cancel.backgroundColor = [self.theme.controlColor colorWithAlphaComponent:0.85];
    cancel.layer.borderColor = self.theme.borderColor.CGColor;
    [card addSubview:cancel];
    [self.contentView addSubview:card];
    [self zn40_updateContentHeight:CGRectGetMaxY(card.frame) + 8];
}

- (void)zn61m2_startSearch:(id)sender {
    [self.hostWindow endEditing:YES];

    NSString *query = [self zn57mf_query];
    if (!query.length) {
        UITextField *field = (UITextField *)[self.contentView viewWithTag:kZN61SearchFieldTag];
        query = field.text ?: @"";
        [self zn57mf_setQuery:query];
    }
    query = ZN61Trim(query);
    if (!query.length) {
        [self zn60v3_setStatus:@"请输入方法名、Class::Method 或 0xRVA"];
        [self zn60v3_setPage:0];
        [self renderPage];
        return;
    }

    NSString *old = [self zn61m2_activeToken];
    if (old.length) [[ZNMethodFinderM2Engine shared] cancel:old];

    [self zn60v3_setStatus:@"M2 异步搜索已启动…"];
    [self zn60v3_setPage:0];

    __weak typeof(self) weakSelf = self;
    __block NSString *issuedToken = nil;
    issuedToken = [[ZNMethodFinderM2Engine shared] startSearch:query
                                                       limit:[self zn60v3_limit]
                                                    progress:^(NSDictionary *progress) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || ![[self zn61m2_activeToken] isEqualToString:issuedToken]) return;
        NSString *message = progress[@"message"] ?: @"正在搜索…";
        [self zn60v3_setStatus:message];
        [self renderPage];
    } completion:^(NSArray<NSDictionary<NSString *,id> *> *results,
                   NSDictionary<NSString *,id> *stats,
                   NSString *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || ![[self zn61m2_activeToken] isEqualToString:issuedToken]) return;
        [self zn61m2_setActiveToken:nil];

        if (!results.count) {
            [self zn60v3_setStatus:error ?: @"没有搜索结果"];
            [[ZNRuntimeLogger sharedLogger] log:
             [NSString stringWithFormat:@"[method-finder-m2] %@ failed: %@",
              query, error ?: @"unknown"]];
            [self zn60v3_setPage:0];
            [self renderPage];
            return;
        }

        [self zn60v3_setCandidates:results];
        [self zn60v3_setSelected:nil];
        NSString *mode = stats[@"mode"] ?: @"m2";
        NSString *source = stats[@"indexSource"] ?: @"not-used";
        [self zn60v3_setStatus:
         [NSString stringWithFormat:@"%@：%lu 个候选 · %@ · index=%@ · %.1fms",
          query, (unsigned long)results.count, mode, source,
          [stats[@"elapsedMs"] doubleValue]]];
        [[ZNRuntimeLogger sharedLogger] log:
         [NSString stringWithFormat:@"[method-finder-m2] %@ -> %lu candidates (%@, index=%@, %.1fms)",
          query, (unsigned long)results.count, mode, source,
          [stats[@"elapsedMs"] doubleValue]]];
        [self zn60v3_setPage:1];
        [self renderPage];
    }];

    [self zn61m2_setActiveToken:issuedToken];
    [self renderPage];
}

- (void)zn61m2_cancelSearch:(id)sender {
    NSString *token = [self zn61m2_activeToken];
    if (!token.length) return;
    [[ZNMethodFinderM2Engine shared] cancel:token];
    [self zn60v3_setStatus:@"正在取消搜索…"];
    [self renderPage];
}

@end

extern "C" void ZNInstallIL2CPPMethodFinderM2Deferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;

        Method searchOriginal = class_getInstanceMethod(cls, @selector(zn60v3_startSearch:));
        Method searchReplacement = class_getInstanceMethod(cls, @selector(zn61m2_startSearch:));
        if (searchOriginal && searchReplacement) {
            method_exchangeImplementations(searchOriginal, searchReplacement);
        }

        Method renderOriginal = class_getInstanceMethod(cls, @selector(zn60v3_renderSearchAtWidth:));
        Method renderReplacement = class_getInstanceMethod(cls, @selector(zn61m2_renderSearchAtWidth:));
        if (renderOriginal && renderReplacement) {
            method_exchangeImplementations(renderOriginal, renderReplacement);
        }
    });
}

#pragma mark - END ZNIL2CPPMethodFinderM2.mm


#pragma mark - BEGIN ZNIL2CPPMethodFinderM21CancelUX.mm
#line 1 "ZNIL2CPPMethodFinderM21CancelUX.mm"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNTheme.h"

// v0.5.8-dev Method Finder V3 M2.1
//
// M2 already provides cooperative cancellation, but its Cancel control is
// appended at the bottom of the search page. On fast devices the search can
// finish before that extra card is ever visibly presented. M2.1 keeps the
// engine unchanged and makes cancellation discoverable by turning the primary
// Search button into Cancel for the lifetime of an active M2 token.

static UIButton *ZN62FindButtonWithTitle(UIView *root, NSString *title) {
    if (!root) return nil;
    if ([root isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)root;
        if ([button.currentTitle isEqualToString:title]) return button;
    }
    for (UIView *child in root.subviews) {
        UIButton *found = ZN62FindButtonWithTitle(child, title);
        if (found) return found;
    }
    return nil;
}

static UIView *ZN62LegacyCancelCard(UIView *contentView) {
    for (UIView *card in contentView.subviews) {
        UIButton *cancel = ZN62FindButtonWithTitle(card, @"取消");
        if (cancel) return card;
    }
    return nil;
}

@interface ZNRuntimeMenuControllerV040 (ZNMethodFinderM21CancelUX)
- (void)zn62m21_renderSearchAtWidth:(CGFloat)width;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNMethodFinderM21CancelUX)

- (void)zn62m21_renderSearchAtWidth:(CGFloat)width {
    // After swizzling this selector calls the complete M2 search-page renderer.
    [self zn62m21_renderSearchAtWidth:width];

    NSString *token = [self zn61m2_activeToken];
    if (!token.length) return;

    // M2's bottom-of-page Cancel card is redundant once the primary action is
    // converted in place. Remove it so there is only one clear cancellation
    // affordance and no need to scroll during a short search.
    UIView *legacyCancelCard = ZN62LegacyCancelCard(self.contentView);
    if (legacyCancelCard) [legacyCancelCard removeFromSuperview];

    UIButton *primary = ZN62FindButtonWithTitle(self.contentView, @"搜索");
    if (primary) {
        [primary setTitle:@"取消" forState:UIControlStateNormal];
        [primary removeTarget:self action:@selector(zn60v3_startSearch:) forControlEvents:UIControlEventTouchUpInside];
        [primary removeTarget:self action:@selector(zn61m2_startSearch:) forControlEvents:UIControlEventTouchUpInside];
        [primary addTarget:self action:@selector(zn61m2_cancelSearch:) forControlEvents:UIControlEventTouchUpInside];
        primary.accessibilityIdentifier = @"ZNMethodFinderPrimaryCancel";
        primary.accessibilityLabel = @"取消 IL2CPP 搜索";
    }

    CGFloat maxY = 0.0;
    for (UIView *view in self.contentView.subviews) {
        maxY = MAX(maxY, CGRectGetMaxY(view.frame));
    }
    [self zn40_updateContentHeight:maxY + 8.0];
}

@end

extern "C" void ZNInstallIL2CPPMethodFinderM21CancelUXDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;

        Method original = class_getInstanceMethod(cls, @selector(zn60v3_renderSearchAtWidth:));
        Method replacement = class_getInstanceMethod(cls, @selector(zn62m21_renderSearchAtWidth:));
        if (original && replacement) {
            method_exchangeImplementations(original, replacement);
        }
    });
}

#pragma mark - END ZNIL2CPPMethodFinderM21CancelUX.mm


#pragma mark - BEGIN ZNIL2CPPMethodFinderM22StableCancelUX.mm
#line 1 "ZNIL2CPPMethodFinderM22StableCancelUX.mm"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// M2.2 stabilizes the M2.1 Search->Cancel UX. M2 progress currently calls
// renderPage for every shard/status update; rebuilding the complete page makes
// the primary button visibly flash on fast devices. This overlay permits the
// first full render (so M2.1 can turn Search into Cancel), then updates only the
// existing status label until completion/cancellation clears the active token.

static const void *kZN63SuppressProgressRenderKey = &kZN63SuppressProgressRenderKey;
static const void *kZN63StatusLabelKey = &kZN63StatusLabelKey;

static BOOL ZN63IsFinderVisible(ZNRuntimeMenuControllerV040 *controller) {
    NSInteger index = controller.selectedCategory;
    if (index < 0 || index >= (NSInteger)controller.categories.count) return NO;
    return [controller.categories[(NSUInteger)index] isEqualToString:@"方法查找"];
}

static UILabel *ZN63FindLabelWithText(UIView *root, NSString *text) {
    if (!root || !text.length) return nil;
    if ([root isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)root;
        if ([label.text isEqualToString:text]) return label;
    }
    for (UIView *child in root.subviews) {
        UILabel *found = ZN63FindLabelWithText(child, text);
        if (found) return found;
    }
    return nil;
}

static BOOL ZN63ViewBelongsToRoot(UIView *view, UIView *root) {
    if (!view || !root) return NO;
    UIView *cursor = view;
    while (cursor) {
        if (cursor == root) return YES;
        cursor = cursor.superview;
    }
    return NO;
}

@interface ZNRuntimeMenuControllerV040 (ZNMethodFinderM22StableCancelUX)
- (void)zn63m22_startSearch:(id)sender;
- (void)zn63m22_renderPage;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNMethodFinderM22StableCancelUX)

- (void)zn63m22_startSearch:(id)sender {
    objc_setAssociatedObject(self, kZN63SuppressProgressRenderKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kZN63StatusLabelKey, nil, OBJC_ASSOCIATION_ASSIGN);

    // After swizzling this selector reaches the complete M2 startSearch path.
    [self zn63m22_startSearch:sender];

    if ([self zn61m2_activeToken].length && ZN63IsFinderVisible(self)) {
        objc_setAssociatedObject(self, kZN63SuppressProgressRenderKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSString *status = [self zn60v3_status];
        UILabel *label = ZN63FindLabelWithText(self.contentView, status);
        if (label) objc_setAssociatedObject(self, kZN63StatusLabelKey, label, OBJC_ASSOCIATION_ASSIGN);
    }
}

- (void)zn63m22_renderPage {
    NSString *token = [self zn61m2_activeToken];
    BOOL suppress = [objc_getAssociatedObject(self, kZN63SuppressProgressRenderKey) boolValue];
    UILabel *cached = objc_getAssociatedObject(self, kZN63StatusLabelKey);

    if (token.length && suppress && ZN63IsFinderVisible(self) &&
        cached && ZN63ViewBelongsToRoot(cached, self.contentView)) {
        cached.text = [self zn60v3_status] ?: @"正在搜索…";
        return;
    }

    // First search render, navigation changes, and completion still use the
    // normal renderer. M2.1 therefore gets one stable chance to install Cancel.
    [self zn63m22_renderPage];

    token = [self zn61m2_activeToken];
    if (token.length && ZN63IsFinderVisible(self)) {
        NSString *status = [self zn60v3_status];
        UILabel *label = ZN63FindLabelWithText(self.contentView, status);
        if (label) objc_setAssociatedObject(self, kZN63StatusLabelKey, label, OBJC_ASSOCIATION_ASSIGN);
    } else {
        objc_setAssociatedObject(self, kZN63SuppressProgressRenderKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kZN63StatusLabelKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }
}

@end

extern "C" void ZNInstallIL2CPPMethodFinderM22StableCancelUXDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;

        Method startOriginal = class_getInstanceMethod(cls, @selector(zn60v3_startSearch:));
        Method startReplacement = class_getInstanceMethod(cls, @selector(zn63m22_startSearch:));
        if (startOriginal && startReplacement) method_exchangeImplementations(startOriginal, startReplacement);

        Method renderOriginal = class_getInstanceMethod(cls, @selector(renderPage));
        Method renderReplacement = class_getInstanceMethod(cls, @selector(zn63m22_renderPage));
        if (renderOriginal && renderReplacement) method_exchangeImplementations(renderOriginal, renderReplacement);
    });
}

#pragma mark - END ZNIL2CPPMethodFinderM22StableCancelUX.mm


#pragma mark - BEGIN ZNIL2CPPABIDetailUI.mm
#line 1 "ZNIL2CPPABIDetailUI.mm"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNIL2CPPABIMetadata.h"
#import "ZNTheme.h"

static const void *kZN65ABICopyKey = &kZN65ABICopyKey;

@interface ZNRuntimeMenuControllerV040 (ZNIL2CPPABIDetailUI)
- (void)zn65abi_renderDetailAtWidth:(CGFloat)width;
- (void)zn65abi_copy:(UIButton *)sender;
@end

static CGFloat ZN65ContentBottom(UIView *root) {
    CGFloat bottom = 9.0;
    for (UIView *view in root.subviews) bottom = MAX(bottom, CGRectGetMaxY(view.frame));
    return bottom;
}

static NSString *ZN65ParameterSummary(NSArray<NSDictionary *> *params) {
    if (!params.count) return @"参数：无";
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:params.count];
    for (NSDictionary *p in params) {
        NSString *name = p[@"name"] ?: @"?";
        NSString *kind = ZNIL2CPPABIValueKindName((ZNIL2CPPABIValueKind)[p[@"kind"] integerValue]);
        [parts addObject:[NSString stringWithFormat:@"%@→%@", name, kind]];
    }
    return [NSString stringWithFormat:@"参数 ABI：%@", [parts componentsJoinedByString:@" · "]];
}

@implementation ZNRuntimeMenuControllerV040 (ZNIL2CPPABIDetailUI)

- (void)zn65abi_renderDetailAtWidth:(CGFloat)width {
    // Swizzled: this calls the complete existing V3/M2 detail renderer first.
    [self zn65abi_renderDetailAtWidth:width];
    NSDictionary *candidate = [self zn60v3_selected];
    if (!candidate) return;

    NSDictionary *abi = ZNIL2CPPDescribeMethodABI(candidate);
    CGFloat y = ZN65ContentBottom(self.contentView) + 8.0;
    UIView *card = [self cardAtY:y height:170 width:width compact:NO];

    UILabel *title = [self label:@"IL2CPP Signature / ABI · M3.1" size:10.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    title.frame = CGRectMake(13, 7, card.bounds.size.width - 70, 18);
    [card addSubview:title];

    NSString *signature = abi[@"signature"] ?: (abi[@"reason"] ?: @"ABI metadata unavailable");
    UILabel *sig = [self label:signature size:8.3 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    sig.frame = CGRectMake(13, 29, card.bounds.size.width - 26, 34);
    sig.numberOfLines = 2;
    sig.lineBreakMode = NSLineBreakByTruncatingTail;
    [card addSubview:sig];

    NSDictionary *ret = abi[@"return"] ?: @{};
    NSString *returnName = ret[@"name"] ?: @"?";
    NSString *returnKind = ZNIL2CPPABIValueKindName((ZNIL2CPPABIValueKind)[ret[@"kind"] integerValue]);
    UILabel *rl = [self label:[NSString stringWithFormat:@"返回：%@    ABI：%@", returnName, returnKind] size:8.5 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    rl.frame = CGRectMake(13, 66, card.bounds.size.width - 26, 17);
    rl.adjustsFontSizeToFitWidth = YES;
    rl.minimumScaleFactor = 0.66;
    [card addSubview:rl];

    NSString *mode = [abi[@"instanceKnown"] boolValue] ? ([abi[@"instance"] boolValue] ? @"instance" : @"static") : @"instance/static ?";
    NSString *generic = [abi[@"genericStatusKnown"] boolValue]
        ? [NSString stringWithFormat:@"generic=%@ · inflated=%@", [abi[@"generic"] boolValue] ? @"yes" : @"no", [abi[@"inflated"] boolValue] ? @"yes" : @"no"]
        : @"generic/inflated=unknown";
    UILabel *flags = [self label:[NSString stringWithFormat:@"调用：%@    %@", mode, generic] size:8.2 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    flags.frame = CGRectMake(13, 87, card.bounds.size.width - 26, 17);
    [card addSubview:flags];

    UILabel *params = [self label:ZN65ParameterSummary(abi[@"parameters"] ?: @[]) size:7.8 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    params.frame = CGRectMake(13, 107, card.bounds.size.width - 26, 20);
    params.adjustsFontSizeToFitWidth = YES;
    params.minimumScaleFactor = 0.60;
    [card addSubview:params];

    BOOL eligible = [abi[@"returnOverrideEligible"] boolValue];
    NSString *reason = abi[@"returnOverrideReason"] ?: (abi[@"reason"] ?: @"ABI metadata unavailable");
    UILabel *status = [self label:[NSString stringWithFormat:@"Return Override：%@ · %@", eligible ? @"Foundation Ready" : @"Blocked", reason] size:7.8 weight:UIFontWeightSemibold color:(eligible ? self.theme.accentColor : self.theme.secondaryTextColor)];
    status.frame = CGRectMake(13, 130, card.bounds.size.width - 69, 30);
    status.numberOfLines = 2;
    [card addSubview:status];

    NSString *copyText = [NSString stringWithFormat:@"%@\nReturn: %@ (%@)\nMode: %@\n%@\nReturn Override: %@\nReason: %@",
                          signature,
                          returnName,
                          returnKind,
                          mode,
                          ZN65ParameterSummary(abi[@"parameters"] ?: @[]),
                          eligible ? @"Foundation Ready" : @"Blocked",
                          reason];
    UIButton *copy = [self zn40_button:@"复制 ABI" selector:@selector(zn65abi_copy:) frame:CGRectMake(card.bounds.size.width - 61, 132, 48, 24)];
    copy.titleLabel.font = [UIFont systemFontOfSize:7.0 weight:UIFontWeightSemibold];
    objc_setAssociatedObject(copy, kZN65ABICopyKey, copyText, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [card addSubview:copy];

    [self.contentView addSubview:card];
    y += 178.0;

    UILabel *note = [self label:@"M3.1 只解析签名并建立 Return Override 计划；此版本不会安装 Hook、不会改写函数入口。复杂 struct、generic/inflated、托管对象返回默认阻止自动覆盖。" size:7.5 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    note.frame = CGRectMake(13, y, width - 26, 38);
    note.numberOfLines = 3;
    [self.contentView addSubview:note];
    [self zn40_updateContentHeight:y + 46.0];
}

- (void)zn65abi_copy:(UIButton *)sender {
    NSString *text = objc_getAssociatedObject(sender, kZN65ABICopyKey);
    if (text.length) UIPasteboard.generalPasteboard.string = text;
}

@end

extern "C" void ZNInstallIL2CPPABIDetailUIDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        Method original = class_getInstanceMethod(cls, @selector(zn60v3_renderDetailAtWidth:));
        Method replacement = class_getInstanceMethod(cls, @selector(zn65abi_renderDetailAtWidth:));
        if (original && replacement) method_exchangeImplementations(original, replacement);
    });
}

#pragma mark - END ZNIL2CPPABIDetailUI.mm


#pragma mark - BEGIN ZNRuntimeMethodCallFinderUI.mm
#line 1 "ZNRuntimeMethodCallFinderUI.mm"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNRuntimeActionModel.h"
#import "ZNIL2CPPInvokeEngine.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

static CGFloat ZNRMCFinderMaxY(UIView *view) {
    CGFloat y = 0;
    for (UIView *subview in view.subviews) y = MAX(y, CGRectGetMaxY(subview.frame));
    return y;
}

@interface ZNRuntimeMenuControllerV040 (ZNRuntimeMethodCallFinderUI)
- (void)znrmc_renderDetailAtWidth:(CGFloat)width;
- (void)znrmc_createMethodAction:(id)sender;
- (void)znrmc_testInvoke:(id)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNRuntimeMethodCallFinderUI)

- (void)znrmc_renderDetailAtWidth:(CGFloat)width {
    // Swizzled: this selector points to the original Method Finder V3 detail renderer.
    [self znrmc_renderDetailAtWidth:width];

    NSDictionary *candidate = [self zn60v3_selected];
    if (!candidate) return;
    NSInteger argc = [candidate[@"argumentCount"] respondsToSelector:@selector(integerValue)]
        ? [candidate[@"argumentCount"] integerValue] : -1;
    NSString *candidateClass = [candidate[@"class"] isKindOfClass:NSString.class] ? candidate[@"class"] : @"";
    NSString *candidateMethod = [candidate[@"method"] isKindOfClass:NSString.class] ? candidate[@"method"] : @"";
    // Detail-page action buttons intentionally remain /0-only. M4.2 /1 takes its
    // typed argument from the inline input on the result card, so duplicating a
    // second unsynchronised input in Details would be ambiguous.
    BOOL detailActionSupported = (argc == 0 && candidateClass.length && candidateMethod.length);

    CGFloat y = ZNRMCFinderMaxY(self.contentView) + 8.0;
    UIView *card = [self cardAtY:y height:92 width:width compact:NO];
    UILabel *title = [self label:@"Runtime Method Call · M4.2" size:10.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    title.frame = CGRectMake(13, 7, card.bounds.size.width - 26, 18);
    [card addSubview:title];

    NSString *hint = nil;
    if (argc == 0) {
        hint = @"/0：可在详情直接测试或创建。实例方法继续 fail closed。";
    } else if (argc == 1) {
        hint = @"/1 已支持 typed argument；请返回搜索结果，在卡片输入参数后使用“测试执行 / 创建方法”。";
    } else {
        hint = [NSString stringWithFormat:@"当前 /%ld 可搜索和筛选；M4.2 首版暂不执行 /2+。", (long)argc];
    }
    UILabel *note = [self label:hint size:7.9 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
    note.frame = CGRectMake(13, 27, card.bounds.size.width - 26, 24);
    note.numberOfLines = 2;
    [card addSubview:note];

    CGFloat gap = 8.0;
    CGFloat buttonW = (card.bounds.size.width - 26 - gap) / 2.0;
    UIButton *create = [self zn40_button:(detailActionSupported ? @"创建方法" : @"返回结果输入参数")
                                   selector:@selector(znrmc_createMethodAction:)
                                      frame:CGRectMake(13, 55, buttonW, 29)];
    create.enabled = detailActionSupported;
    create.alpha = detailActionSupported ? 1.0 : 0.55;
    [card addSubview:create];

    UIButton *test = [self zn40_button:(detailActionSupported ? @"测试执行" : @"详情仅查看")
                                 selector:@selector(znrmc_testInvoke:)
                                    frame:CGRectMake(13 + buttonW + gap, 55, buttonW, 29)];
    test.enabled = detailActionSupported;
    test.alpha = detailActionSupported ? 1.0 : 0.55;
    test.backgroundColor = [self.theme.accentColor colorWithAlphaComponent:0.18];
    test.layer.borderColor = self.theme.accentColor.CGColor;
    [card addSubview:test];

    [self.contentView addSubview:card];
    [self zn40_updateContentHeight:CGRectGetMaxY(card.frame) + 8.0];
}

- (void)znrmc_createMethodAction:(id)sender {
    (void)sender;
    NSDictionary *candidate = [self zn60v3_selected];
    if (!candidate || [candidate[@"argumentCount"] integerValue] != 0) return;
    NSString *error = nil;
    ZNRuntimeMethodAction *action = [[ZNRuntimeActionStore sharedStore] addMethodCandidate:candidate
                                                                                     title:candidate[@"method"]
                                                                                     error:&error];
    if (!action) {
        [self zn60v3_setStatus:error ?: @"创建 Runtime Method Call 失败"];
    } else {
        [self zn60v3_setStatus:[NSString stringWithFormat:@"已加入 Builder：%@", action.canonicalIdentity]];
    }
    [self renderPage];
}

- (void)znrmc_testInvoke:(id)sender {
    (void)sender;
    NSDictionary *candidate = [self zn60v3_selected];
    if (!candidate || [candidate[@"argumentCount"] integerValue] != 0) return;
    NSString *assembly = [candidate[@"assembly"] isKindOfClass:NSString.class] ? candidate[@"assembly"] : @"Assembly-CSharp.dll";
    NSString *namespaceName = [candidate[@"namespace"] isKindOfClass:NSString.class] ? candidate[@"namespace"] : @"";
    NSString *className = [candidate[@"class"] isKindOfClass:NSString.class] ? candidate[@"class"] : @"";
    NSString *methodName = [candidate[@"method"] isKindOfClass:NSString.class] ? candidate[@"method"] : @"";
    NSString *error = nil;
    NSDictionary *result = [[ZNIL2CPPInvokeEngine sharedEngine] executeAssembly:assembly
                                                                      namespace:namespaceName
                                                                      className:className
                                                                         method:methodName
                                                                  argumentCount:0
                                                                          error:&error];
    if (result) {
        [self zn60v3_setStatus:[NSString stringWithFormat:@"Runtime Invoke SUCCESS：%@::%@/0", className, methodName]];
    } else {
        [self zn60v3_setStatus:error ?: @"Runtime Invoke FAILED"];
    }
    [self renderPage];
}

@end

extern "C" void ZNInstallRuntimeMethodCallFinderUIDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        Method original = class_getInstanceMethod(cls, @selector(zn60v3_renderDetailAtWidth:));
        Method replacement = class_getInstanceMethod(cls, @selector(znrmc_renderDetailAtWidth:));
        if (original && replacement) {
            method_exchangeImplementations(original, replacement);
            [[ZNRuntimeLogger sharedLogger] log:@"[runtime-method-call] Method Finder detail UI installed (M4.2 /0 direct; /1 inline result input)"];
        }
    });
}

#pragma mark - END ZNRuntimeMethodCallFinderUI.mm


#pragma mark - BEGIN ZNRuntimeMethodCallBuilderUI.mm
#line 1 "ZNRuntimeMethodCallBuilderUI.mm"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNRuntimeActionModel.h"
#import "ZNBinaryPatchWorkspace.h"
#import "ZNNativeHookAction.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

static const NSInteger kZNRMCBuilderDeleteTagBase = 671000;
static const NSInteger kZNRMCBuilderTitleTagBase = 672000;
static const NSInteger kZNRMCBuilderArgumentTagBase = 674000;
static const NSInteger kZNRMCBuilderDescriptionTagBase = 675000;
static const NSInteger kZNNativeHookDeleteTagBase = 676000;

static CGFloat ZNRMCBuilderMaxY(UIView *view) {
    CGFloat y = 0;
    for (UIView *subview in view.subviews) y = MAX(y, CGRectGetMaxY(subview.frame));
    return y;
}

static UIButton *ZNRMCBuilderFindBuildButton(UIView *root) {
    for (UIView *view in root.subviews ?: @[]) {
        if ([view isKindOfClass:UIButton.class]) {
            NSString *title=[(UIButton *)view titleForState:UIControlStateNormal] ?: @"";
            if ([title isEqualToString:@"生成新二进制"] || [title isEqualToString:@"正在生成…"]) return (UIButton *)view;
        }
        UIButton *nested=ZNRMCBuilderFindBuildButton(view);
        if (nested) return nested;
    }
    return nil;
}

static NSUInteger ZNRMCBuilderCompleteStaticRows(ZNBinaryPatchWorkspace *workspace) {
    NSUInteger count=0;
    for (ZNBinaryPatchRow *row in workspace.rows ?: @[]) {
        if (row.offsetText.length>0 && row.enabledText.length>0) count++;
    }
    return count;
}

static void ZNRMCBuilderFinalizeBuildGate(UIView *root,
                                         NSUInteger runtimeCount,
                                         NSUInteger nativeHookCount) {
    if (!runtimeCount && !nativeHookCount) return;
    UIButton *build=ZNRMCBuilderFindBuildButton(root);
    if (!build) return;
    ZNBinaryPatchWorkspace *workspace=[ZNBinaryPatchWorkspace sharedWorkspace];
    NSUInteger completeStatic=ZNRMCBuilderCompleteStaticRows(workspace);
    if (completeStatic!=0) return; // Static/mixed mode keeps its own validation gate.
    BOOL ready=!workspace.isBuilding && !workspace.hasAnyApplied;
    build.enabled=ready;
    build.alpha=ready?1.0:0.5;
    if (ready) {
        build.accessibilityHint=nativeHookCount>0 && runtimeCount==0
            ? @"Native Hook-only：可以直接生成二进制"
            : @"Runtime/Native Hook-only：可以直接生成二进制";
    }
}


static UITextField *ZNRMCBuilderTextField(CGRect frame, ZNTheme *theme) {
    UITextField *field = [[UITextField alloc] initWithFrame:frame];
    field.textColor = theme.primaryTextColor;
    field.backgroundColor = theme.controlColor;
    field.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightSemibold];
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.returnKeyType = UIReturnKeyDone;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.layer.cornerRadius = 7.0;
    field.layer.borderWidth = 1.0;
    field.layer.borderColor = theme.borderColor.CGColor;
    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 7, 1)];
    field.leftView = pad;
    field.leftViewMode = UITextFieldViewModeAlways;
    return field;
}

@interface ZNRuntimeMenuControllerV040 (ZNRuntimeMethodCallBuilderUI)
- (void)znrmc_renderOther;
- (void)znrmc_clearAuthoringActions:(id)sender;
- (void)znrmc_deleteAuthoringAction:(UIButton *)sender;
- (void)znrmc_titleEditingEnded:(UITextField *)field;
- (void)znrmc_descriptionEditingEnded:(UITextField *)field;
- (void)znrmc_argumentEditingChanged:(UITextField *)field;
- (void)znrmc_argumentEditingEnded:(UITextField *)field;
- (void)zn64_deleteNativeHook:(UIButton *)sender;
- (void)zn64_clearNativeHooks:(id)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNRuntimeMethodCallBuilderUI)

- (void)znrmc_renderOther {
    [self znrmc_renderOther];

    NSArray<ZNRuntimeMethodAction *> *actions = [[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat y = ZNRMCBuilderMaxY(self.contentView) + 8.0;

    UIView *header = [self cardAtY:y height:48 width:width compact:NO];
    UILabel *title = [self label:[NSString stringWithFormat:@"Runtime Method Call · %lu", (unsigned long)actions.count]
                               size:10.8
                             weight:UIFontWeightSemibold
                              color:self.theme.primaryTextColor];
    title.frame = CGRectMake(13, 8, header.bounds.size.width - 96, 31);
    [header addSubview:title];
    UIButton *clear = [self zn40_button:@"清空" selector:@selector(znrmc_clearAuthoringActions:) frame:CGRectMake(header.bounds.size.width - 75, 8, 62, 31)];
    clear.enabled = actions.count > 0;
    clear.alpha = clear.enabled ? 1.0 : 0.5;
    [header addSubview:clear];
    [self.contentView addSubview:header];
    y += 56.0;

    if (!actions.count) {
        UIView *empty = [self cardAtY:y height:54 width:width compact:NO];
        UILabel *label = [self label:@"在“方法查找”选择 /0 或受支持的方法 → 创建方法。制作数据会自动保存。"
                                    size:8.4
                                  weight:UIFontWeightRegular
                                   color:self.theme.secondaryTextColor];
        label.frame = CGRectMake(13, 8, empty.bounds.size.width - 26, 38);
        label.numberOfLines = 2;
        [empty addSubview:label];
        [self.contentView addSubview:empty];
        y += 62.0;
    } else {
        for (NSUInteger i = 0; i < actions.count; i++) {
            ZNRuntimeMethodAction *action = actions[i];
            BOOL hasArgument = action.argumentCount == 1;
            CGFloat cardH = hasArgument ? 149.0 : 109.0;
            UIView *card = [self cardAtY:y height:cardH width:width compact:NO];

            UITextField *name = ZNRMCBuilderTextField(CGRectMake(13, 7, card.bounds.size.width - 82, 27), self.theme);
            name.tag = kZNRMCBuilderTitleTagBase + (NSInteger)i;
            name.text = action.title.length ? action.title : action.methodName;
            name.placeholder = action.methodName;
            [name addTarget:self action:@selector(znrmc_titleEditingEnded:) forControlEvents:UIControlEventEditingDidEndOnExit | UIControlEventEditingDidEnd];
            [card addSubview:name];

            UIButton *deleteButton = [self zn40_button:@"删除"
                                               selector:@selector(znrmc_deleteAuthoringAction:)
                                                  frame:CGRectMake(card.bounds.size.width - 65, 7, 52, 27)];
            deleteButton.tag = kZNRMCBuilderDeleteTagBase + (NSInteger)i;
            [card addSubview:deleteButton];

            UILabel *identity = [self label:action.canonicalIdentity
                                        size:7.8
                                      weight:UIFontWeightRegular
                                       color:self.theme.secondaryTextColor];
            identity.frame = CGRectMake(13, 40, card.bounds.size.width - 26, 20);
            identity.numberOfLines = 2;
            identity.lineBreakMode = NSLineBreakByTruncatingMiddle;
            [card addSubview:identity];

            UITextField *description = ZNRMCBuilderTextField(CGRectMake(13, 65, card.bounds.size.width - 26, 29), self.theme);
            description.tag = kZNRMCBuilderDescriptionTagBase + (NSInteger)i;
            description.text = action.featureDescription ?: @"";
            description.placeholder = @"功能说明";
            description.font = [UIFont systemFontOfSize:9.2 weight:UIFontWeightRegular];
            [description addTarget:self action:@selector(znrmc_descriptionEditingEnded:) forControlEvents:UIControlEventEditingDidEndOnExit | UIControlEventEditingDidEnd];
            [card addSubview:description];

            if (hasArgument) {
                UITextField *argument = ZNRMCBuilderTextField(CGRectMake(13, 104, card.bounds.size.width - 26, 31), self.theme);
                argument.tag = kZNRMCBuilderArgumentTagBase + (NSInteger)i;
                argument.text = action.argumentValues.count ? action.argumentValues.firstObject : @"";
                argument.placeholder = @"参数值";
                argument.font = [UIFont monospacedDigitSystemFontOfSize:9.6 weight:UIFontWeightMedium];
                // M5.8.3: keep the model current while typing. This is required
                // for Slider authoring because the value at build time is its max.
                [argument addTarget:self action:@selector(znrmc_argumentEditingChanged:) forControlEvents:UIControlEventEditingChanged];
                [argument addTarget:self action:@selector(znrmc_argumentEditingEnded:) forControlEvents:UIControlEventEditingDidEndOnExit | UIControlEventEditingDidEnd];
                [card addSubview:argument];
            }

            [self.contentView addSubview:card];
            y += cardH + 10.0;
        }
    }
    NSArray<ZNNativeHookAction *> *hooks=[[ZNNativeHookStore sharedStore] actionsSnapshot];
    y += 4.0;
    UIView *hookHeader=[self cardAtY:y height:48 width:width compact:NO];
    UILabel *hookTitle=[self label:[NSString stringWithFormat:@"IL2CPP Native Hook · %lu",(unsigned long)hooks.count]
                              size:10.8 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    hookTitle.frame=CGRectMake(13,8,hookHeader.bounds.size.width-96,31);
    [hookHeader addSubview:hookTitle];
    UIButton *hookClear=[self zn40_button:@"清空" selector:@selector(zn64_clearNativeHooks:) frame:CGRectMake(hookHeader.bounds.size.width-75,8,62,31)];
    hookClear.enabled=hooks.count>0;hookClear.alpha=hookClear.enabled?1.0:.5;
    [hookHeader addSubview:hookClear];
    [self.contentView addSubview:hookHeader];
    y += 56.0;

    if(!hooks.count){
        UIView *empty=[self cardAtY:y height:54 width:width compact:NO];
        UILabel *label=[self label:@"方法查找 → Hook 测试 → 安装真机测试 Hook → 创建 Hook 方法。"
                              size:8.4 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        label.frame=CGRectMake(13,8,empty.bounds.size.width-26,38);label.numberOfLines=2;
        [empty addSubview:label];[self.contentView addSubview:empty];y+=62.0;
    }else{
        for(NSUInteger i=0;i<hooks.count;i++){
            ZNNativeHookAction *hook=hooks[i];
            UIView *card=[self cardAtY:y height:104 width:width compact:NO];
            UILabel *name=[self label:hook.title.length?hook.title:hook.methodName
                                size:10.0 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
            name.frame=CGRectMake(13,7,card.bounds.size.width-82,22);[card addSubview:name];
            UIButton *del=[self zn40_button:@"删除" selector:@selector(zn64_deleteNativeHook:) frame:CGRectMake(card.bounds.size.width-65,7,52,27)];
            del.tag=kZNNativeHookDeleteTagBase+(NSInteger)i;[card addSubview:del];
            UILabel *identity=[self label:hook.canonicalIdentity size:7.8 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
            identity.frame=CGRectMake(13,35,card.bounds.size.width-26,20);identity.lineBreakMode=NSLineBreakByTruncatingMiddle;[card addSubview:identity];
            NSString *info=nil;
            if(hook.templateKind==ZNNativeHookTemplateManagedCallbackShortCircuit){
                info=[NSString stringWithFormat:@"%@ · callback arg%lu · value=%@ · SkipOriginal · RVA=%@",
                      ZNNativeHookTemplateKey(hook.templateKind),(unsigned long)hook.callbackArgumentIndex,
                      hook.callbackValue?@"true":@"false",
                      hook.fallbackRVA?[NSString stringWithFormat:@"0x%llX",(unsigned long long)hook.fallbackRVA]:@"—"];
            }else{
                info=[NSString stringWithFormat:@"%@ · arg%lu · Slider %ld~%ld · default=%ld · RVA=%@",
                      ZNNativeHookTemplateKey(hook.templateKind),(unsigned long)hook.argumentIndex,
                      (long)hook.minValue,(long)hook.maxValue,(long)hook.defaultValue,
                      hook.fallbackRVA?[NSString stringWithFormat:@"0x%llX",(unsigned long long)hook.fallbackRVA]:@"—"];
            }
            UILabel *meta=[self label:info size:8.1 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
            meta.frame=CGRectMake(13,60,card.bounds.size.width-26,18);meta.adjustsFontSizeToFitWidth=YES;meta.minimumScaleFactor=.65;[card addSubview:meta];
            UILabel *desc=[self label:(hook.featureDescription.length?hook.featureDescription:@"Native Hook V1 · Dobby")
                                size:8.1 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
            desc.frame=CGRectMake(13,81,card.bounds.size.width-26,16);[card addSubview:desc];
            [self.contentView addSubview:card];y+=114.0;
        }
    }

    // M6.8 final gate runs after Native Hook authoring cards are rendered.
    // This intentionally uses the same snapshots that produced the visible
    // "Runtime Method Call · N" / "IL2CPP Native Hook · N" counts, avoiding
    // earlier swizzle/render ordering from leaving the build button stale.
    ZNRMCBuilderFinalizeBuildGate(self.contentView,actions.count,hooks.count);

    [self zn40_updateContentHeight:y];
}

- (void)znrmc_clearAuthoringActions:(id)sender {
    (void)sender;
    [[ZNRuntimeActionStore sharedStore] clear];
    [self renderPage];
}

- (void)zn64_clearNativeHooks:(id)sender {
    (void)sender;
    [[ZNNativeHookStore sharedStore] clear];
    [self renderPage];
}

- (void)zn64_deleteNativeHook:(UIButton *)sender {
    NSInteger index=sender.tag-kZNNativeHookDeleteTagBase;
    if(index>=0)[[ZNNativeHookStore sharedStore] removeActionAtIndex:(NSUInteger)index];
    [self renderPage];
}

- (void)znrmc_deleteAuthoringAction:(UIButton *)sender {
    NSInteger index = sender.tag - kZNRMCBuilderDeleteTagBase;
    if (index >= 0) [[ZNRuntimeActionStore sharedStore] removeActionAtIndex:(NSUInteger)index];
    [self renderPage];
}

- (void)znrmc_titleEditingEnded:(UITextField *)field {
    NSInteger index = field.tag - kZNRMCBuilderTitleTagBase;
    if (index < 0) return;
    NSString *error = nil;
    if (![[ZNRuntimeActionStore sharedStore] updateTitle:field.text atIndex:(NSUInteger)index error:&error]) {
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[runtime-method-call] rename failed: %@", error ?: @"unknown"]];
    }
    NSArray<ZNRuntimeMethodAction *> *actions = [[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    if ((NSUInteger)index < actions.count) field.text = actions[(NSUInteger)index].title;
    [field resignFirstResponder];
}

- (void)znrmc_descriptionEditingEnded:(UITextField *)field {
    NSInteger index = field.tag - kZNRMCBuilderDescriptionTagBase;
    if (index < 0) return;
    NSString *error = nil;
    [[ZNRuntimeActionStore sharedStore] updateFeatureDescription:field.text atIndex:(NSUInteger)index error:&error];
    NSArray<ZNRuntimeMethodAction *> *actions = [[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    if ((NSUInteger)index < actions.count) field.text = actions[(NSUInteger)index].featureDescription ?: @"";
    [field resignFirstResponder];
}

- (void)znrmc_argumentEditingChanged:(UITextField *)field {
    NSInteger index = field.tag - kZNRMCBuilderArgumentTagBase;
    if (index < 0) return;
    NSString *error = nil;
    if (![[ZNRuntimeActionStore sharedStore] updateArgumentValues:@[field.text ?: @""] atIndex:(NSUInteger)index error:&error]) {
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m5.8.3-authoring] live argument update failed: %@", error ?: @"unknown"]];
    }
}

- (void)znrmc_argumentEditingEnded:(UITextField *)field {
    [self znrmc_argumentEditingChanged:field];
    NSInteger index = field.tag - kZNRMCBuilderArgumentTagBase;
    if (index < 0) return;
    NSArray<ZNRuntimeMethodAction *> *actions = [[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    if ((NSUInteger)index < actions.count) {
        ZNRuntimeMethodAction *action = actions[(NSUInteger)index];
        field.text = action.argumentValues.count ? action.argumentValues.firstObject : @"";
    }
    [field resignFirstResponder];
}

@end

extern "C" void ZNInstallRuntimeMethodCallBuilderUIDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        Method original = class_getInstanceMethod(cls, @selector(zn50b_renderOther));
        Method replacement = class_getInstanceMethod(cls, @selector(znrmc_renderOther));
        if (original && replacement) {
            method_exchangeImplementations(original, replacement);
            [[ZNRuntimeLogger sharedLogger] log:@"[runtime-method-call] Builder action list UI installed (M5.8.3 live argument sync)"];
        }
    });
}

#pragma mark - END ZNRuntimeMethodCallBuilderUI.mm


#pragma mark - BEGIN ZNRuntimeMethodCallFeatureUI.mm
#line 1 "ZNRuntimeMethodCallFeatureUI.mm"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNRuntimeActionRuntime.h"
#import "ZNStaticDispatchRuntime.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

static const NSInteger kZNRMCFeatureExecuteTagBase = 672000;
static const NSInteger kZNRMCFeatureCompactExecuteTagBase = 673000;

static CGFloat ZNRMCFeatureMaxY(UIView *view) {
    CGFloat y = 0;
    for (UIView *subview in view.subviews) y = MAX(y, CGRectGetMaxY(subview.frame));
    return y;
}

static void ZNRMCRemoveEmptyStaticCardIfNeeded(UIView *contentView) {
    ZNStaticDispatchRuntime *staticRuntime = [ZNStaticDispatchRuntime sharedRuntime];
    [staticRuntime refresh];
    if (staticRuntime.records.count) return;
    for (UIView *subview in [contentView.subviews copy]) {
        BOOL isEmpty = NO;
        for (UIView *child in subview.subviews) {
            if ([child isKindOfClass:UILabel.class] && [((UILabel *)child).text isEqualToString:@"暂无功能"]) {
                isEmpty = YES;
                break;
            }
        }
        if (isEmpty) [subview removeFromSuperview];
    }
}

@interface ZNRuntimeMenuControllerV040 (ZNRuntimeMethodCallFeatureUI)
- (void)znrmc_renderFeatureGroupsFull;
- (void)znrmc_renderFeatureGroupsCompact;
- (void)znrmc_executeAction:(UIButton *)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNRuntimeMethodCallFeatureUI)

- (void)znrmc_renderFeatureGroupsFull {
    [self znrmc_renderFeatureGroupsFull];
    ZNRuntimeActionRuntime *runtime = [ZNRuntimeActionRuntime sharedRuntime];
    [runtime refresh];
    NSArray<ZNRuntimeMethodActionRecord *> *actions = runtime.records;
    if (!actions.count) return;

    ZNRMCRemoveEmptyStaticCardIfNeeded(self.contentView);
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat y = ZNRMCFeatureMaxY(self.contentView) + 8.0;
    for (NSUInteger i = 0; i < actions.count; i++) {
        ZNRuntimeMethodActionRecord *record = actions[i];
        UIView *card = [self cardAtY:y height:46 width:width compact:NO];
        UILabel *name = [self label:(record.title.length ? record.title : record.methodName)
                                size:11.4
                              weight:UIFontWeightSemibold
                               color:self.theme.primaryTextColor];
        name.frame = CGRectMake(13, 13, card.bounds.size.width - 100, 20);
        name.lineBreakMode = NSLineBreakByTruncatingTail;
        [card addSubview:name];
        UIButton *execute = [self zn40_button:@"执行"
                                      selector:@selector(znrmc_executeAction:)
                                         frame:CGRectMake(card.bounds.size.width - 78, 8, 66, 30)];
        execute.tag = kZNRMCFeatureExecuteTagBase + (NSInteger)i;
        execute.backgroundColor = [self.theme.accentColor colorWithAlphaComponent:0.18];
        execute.layer.borderColor = self.theme.accentColor.CGColor;
        [card addSubview:execute];
        [self.contentView addSubview:card];
        y += 52.0;
    }
    [self zn40_updateContentHeight:y];
}

- (void)znrmc_renderFeatureGroupsCompact {
    [self znrmc_renderFeatureGroupsCompact];
    ZNRuntimeActionRuntime *runtime = [ZNRuntimeActionRuntime sharedRuntime];
    [runtime refresh];
    NSArray<ZNRuntimeMethodActionRecord *> *actions = runtime.records;
    if (!actions.count) return;

    ZNRMCRemoveEmptyStaticCardIfNeeded(self.contentView);
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat y = ZNRMCFeatureMaxY(self.contentView) + 6.0;
    for (NSUInteger i = 0; i < actions.count; i++) {
        ZNRuntimeMethodActionRecord *record = actions[i];
        UIView *card = [self cardAtY:y height:40 width:width compact:YES];
        UILabel *name = [self label:(record.title.length ? record.title : record.methodName)
                                size:10.7
                              weight:UIFontWeightSemibold
                               color:self.theme.primaryTextColor];
        name.frame = CGRectMake(9, 10, card.bounds.size.width - 82, 20);
        name.lineBreakMode = NSLineBreakByTruncatingTail;
        [card addSubview:name];
        UIButton *execute = [self zn40_button:@"执行"
                                      selector:@selector(znrmc_executeAction:)
                                         frame:CGRectMake(card.bounds.size.width - 69, 6, 60, 28)];
        execute.tag = kZNRMCFeatureCompactExecuteTagBase + (NSInteger)i;
        execute.titleLabel.font = [UIFont systemFontOfSize:9.0 weight:UIFontWeightSemibold];
        execute.backgroundColor = [self.theme.accentColor colorWithAlphaComponent:0.18];
        execute.layer.borderColor = self.theme.accentColor.CGColor;
        [card addSubview:execute];
        [self.contentView addSubview:card];
        y += 46.0;
    }
    [self zn40_updateContentHeight:y];
}

- (void)znrmc_executeAction:(UIButton *)sender {
    NSInteger index = sender.tag - kZNRMCFeatureExecuteTagBase;
    if (sender.tag >= kZNRMCFeatureCompactExecuteTagBase) index = sender.tag - kZNRMCFeatureCompactExecuteTagBase;
    if (index < 0) return;

    ZNRuntimeActionRuntime *runtime = [ZNRuntimeActionRuntime sharedRuntime];
    [runtime refresh];
    if ((NSUInteger)index >= runtime.records.count) return;
    ZNRuntimeMethodActionRecord *record = runtime.records[(NSUInteger)index];
    NSString *error = nil;
    BOOL ok = [runtime executeRecord:record error:&error];
    NSString *oldTitle = [sender titleForState:UIControlStateNormal] ?: @"执行";
    [sender setTitle:(ok ? @"完成" : @"失败") forState:UIControlStateNormal];
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[runtime-method-call] UI %@ %@%@",
                                         ok ? @"SUCCESS" : @"FAILED",
                                         record.canonicalIdentity,
                                         error.length ? [@" · " stringByAppendingString:error] : @""]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [sender setTitle:oldTitle forState:UIControlStateNormal];
    });
}

@end

extern "C" void ZNInstallRuntimeMethodCallFeatureUIDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        Method fullOriginal = class_getInstanceMethod(cls, @selector(zn50_renderFeatureGroupsFull));
        Method fullReplacement = class_getInstanceMethod(cls, @selector(znrmc_renderFeatureGroupsFull));
        if (fullOriginal && fullReplacement) method_exchangeImplementations(fullOriginal, fullReplacement);
        Method compactOriginal = class_getInstanceMethod(cls, @selector(zn50_renderFeatureGroupsCompact));
        Method compactReplacement = class_getInstanceMethod(cls, @selector(znrmc_renderFeatureGroupsCompact));
        if (compactOriginal && compactReplacement) method_exchangeImplementations(compactOriginal, compactReplacement);
        [[ZNRuntimeLogger sharedLogger] log:@"[runtime-method-call] public Feature action UI installed"];
    });
}

#pragma mark - END ZNRuntimeMethodCallFeatureUI.mm


#pragma mark - BEGIN ZNUXFixesV2.mm
#line 1 "ZNUXFixesV2.mm"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNRuntimeActionModel.h"
#import "ZNPatchCore.h"
#import "ZNTheme.h"

// M4.1 UI/UX repair layer.
// - Default Builder target: UnityFramework when present, otherwise main executable.
// - Builder target is a picker backed by app-local dyld images, not free text.
// - Builder can be generated directly; manual "读取验证" is optional. Build performs
//   the same required validation internally before entering Static Builder V3.
// - renderPage preserves the current UIScrollView position for same-page actions.
// - Menu panel is hosted by a real child UIViewController in the game's existing
//   UIWindow. Its transparent root returns nil from hitTest outside the panel so
//   Unity/game content below keeps receiving touches.

static NSString * const kZNUXSelectedTargetKey = @"ZonoePatch.Builder.SelectedTarget";
static const void *kZNUXAutoTargetInitializedKey = &kZNUXAutoTargetInitializedKey;
static const void *kZNUXOverlayControllerKey = &kZNUXOverlayControllerKey;

@interface ZNUXPassthroughRootView : UIView
@end

@implementation ZNUXPassthroughRootView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    // When the transparent root itself would consume the event, decline the hit.
    // Because this view is a child in the game's existing UIWindow hierarchy,
    // UIKit continues hit-testing sibling game views underneath it.
    return hit == self ? nil : hit;
}
@end

@interface ZNUXOverlayController : UIViewController
@property(nonatomic,strong) UIView *menuPanel;
- (instancetype)initWithPanel:(UIView *)panel;
@end

@implementation ZNUXOverlayController
- (instancetype)initWithPanel:(UIView *)panel {
    self = [super initWithNibName:nil bundle:nil];
    if (!self) return nil;
    _menuPanel = panel;
    return self;
}

- (void)loadView {
    ZNUXPassthroughRootView *root = [ZNUXPassthroughRootView new];
    root.backgroundColor = UIColor.clearColor;
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = root;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (self.menuPanel.superview != self.view) {
        [self.menuPanel removeFromSuperview];
        [self.view addSubview:self.menuPanel];
    }
}
@end

static UIViewController *ZNUXTopController(UIViewController *vc) {
    if (!vc) return nil;
    UIViewController *presented = vc.presentedViewController;
    if (presented && !presented.isBeingDismissed) return ZNUXTopController(presented);
    if ([vc isKindOfClass:UINavigationController.class]) {
        UIViewController *top = ((UINavigationController *)vc).visibleViewController;
        return top ? ZNUXTopController(top) : vc;
    }
    if ([vc isKindOfClass:UITabBarController.class]) {
        UIViewController *selected = ((UITabBarController *)vc).selectedViewController;
        return selected ? ZNUXTopController(selected) : vc;
    }
    if ([vc isKindOfClass:UISplitViewController.class]) {
        UIViewController *last = ((UISplitViewController *)vc).viewControllers.lastObject;
        return last ? ZNUXTopController(last) : vc;
    }
    return vc;
}

static NSString *ZNUXStandardPath(NSString *path) {
    return path.length ? path.stringByStandardizingPath : @"";
}

static BOOL ZNUXIsAppLocalImage(NSDictionary<NSString *, id> *item) {
    NSString *path = ZNUXStandardPath(item[@"path"]);
    NSString *bundle = ZNUXStandardPath(NSBundle.mainBundle.bundlePath);
    NSString *main = ZNUXStandardPath(NSBundle.mainBundle.executablePath);
    if (!path.length || !bundle.length) return NO;
    if ([path isEqualToString:main]) return YES;
    NSString *frameworks = [bundle stringByAppendingPathComponent:@"Frameworks"];
    NSString *prefix = [frameworks stringByAppendingString:@"/"];
    return [path hasPrefix:prefix];
}

static NSInteger ZNUXImageRank(NSDictionary<NSString *, id> *item) {
    NSString *name = item[@"name"] ?: @"";
    NSString *path = ZNUXStandardPath(item[@"path"]);
    if ([name caseInsensitiveCompare:@"UnityFramework"] == NSOrderedSame ||
        [path hasSuffix:@"/UnityFramework.framework/UnityFramework"]) return 0;
    if ([path isEqualToString:ZNUXStandardPath(NSBundle.mainBundle.executablePath)]) return 1;
    if ([name.pathExtension caseInsensitiveCompare:@"dylib"] == NSOrderedSame) return 2;
    return 3;
}

static NSArray<NSDictionary<NSString *, id> *> *ZNUXAppLocalImages(void) {
    NSMutableArray<NSDictionary<NSString *, id> *> *items = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSDictionary<NSString *, id> *item in [ZNModuleManager sharedManager].loadedImages) {
        if (!ZNUXIsAppLocalImage(item)) continue;
        NSString *path = ZNUXStandardPath(item[@"path"]);
        if (!path.length || [seen containsObject:path]) continue;
        [seen addObject:path];
        [items addObject:item];
    }
    [items sortUsingComparator:^NSComparisonResult(NSDictionary<NSString *,id> *a, NSDictionary<NSString *,id> *b) {
        NSInteger ra = ZNUXImageRank(a), rb = ZNUXImageRank(b);
        if (ra != rb) return ra < rb ? NSOrderedAscending : NSOrderedDescending;
        NSString *na = a[@"name"] ?: @"";
        NSString *nb = b[@"name"] ?: @"";
        return [na localizedCaseInsensitiveCompare:nb];
    }];
    return items;
}

static NSString *ZNUXPreferredTarget(void) {
    NSDictionary *unity = [ZNModuleManager sharedManager].unityFramework;
    NSString *unityDiskPath = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks/UnityFramework.framework/UnityFramework"];
    BOOL unityExists = [[NSFileManager defaultManager] fileExistsAtPath:unityDiskPath];
    if (unity || unityExists) return @"UnityFramework";
    NSDictionary *main = [ZNModuleManager sharedManager].mainExecutable;
    NSString *name = [main[@"name"] isKindOfClass:NSString.class] ? main[@"name"] : @"";
    if (!name.length) name = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleExecutable"];
    return name.length ? name : @"main";
}

static NSString *ZNUXRelativePath(NSString *path) {
    NSString *bundle = ZNUXStandardPath(NSBundle.mainBundle.bundlePath);
    NSString *full = ZNUXStandardPath(path);
    if (bundle.length && [full hasPrefix:[bundle stringByAppendingString:@"/"]]) {
        return [full substringFromIndex:bundle.length + 1];
    }
    return full;
}

static void ZNUXForEachSubview(UIView *view, void (^block)(UIView *view)) {
    if (!view || !block) return;
    block(view);
    for (UIView *sub in view.subviews) ZNUXForEachSubview(sub, block);
}

static CGFloat ZNUXClampScrollY(UIScrollView *scroll, CGFloat y) {
    if (!scroll) return 0;
    CGFloat minY = -scroll.adjustedContentInset.top;
    CGFloat maxY = MAX(minY, scroll.contentSize.height - CGRectGetHeight(scroll.bounds) + scroll.adjustedContentInset.bottom);
    return MIN(MAX(y, minY), maxY);
}

@interface ZNRuntimeMenuControllerV040 (ZNUXFixesV2)
- (void)znux_renderPage;
- (void)znux_show;
- (void)znux_hide;
- (BOOL)znux_isVisible;
- (void)znux_buildBinary:(id)sender;
- (void)znux_binaryPickerTapped:(UIButton *)sender;
- (void)znux_applyAutoTargetOnce;
- (void)znux_customizeRenderedBuilder;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNUXFixesV2)

- (void)znux_applyAutoTargetOnce {
    if ([objc_getAssociatedObject(self, kZNUXAutoTargetInitializedKey) boolValue]) return;
    objc_setAssociatedObject(self, kZNUXAutoTargetInitializedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:kZNUXSelectedTargetKey];
    NSDictionary *savedModule = saved.length ? [[ZNModuleManager sharedManager] moduleNamed:saved] : nil;
    if (savedModule && ZNUXIsAppLocalImage(savedModule)) {
        [workspace updateDefaultTarget:saved];
        return;
    }

    NSString *preferred = ZNUXPreferredTarget();
    if (preferred.length) [workspace updateDefaultTarget:preferred];
}

- (void)znux_customizeRenderedBuilder {
    if (!self.contentView) return;
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];

    // Replace the old free-text target field with a single-tap app-library picker.
    UIView *targetView = [self.contentView viewWithTag:440000];
    if ([targetView isKindOfClass:UITextField.class] && targetView.superview) {
        UIView *container = targetView.superview;
        CGRect frame = targetView.frame;
        [targetView removeFromSuperview];

        NSString *title = workspace.defaultTarget.length ? workspace.defaultTarget : ZNUXPreferredTarget();
        UIButton *picker = [self zn40_button:[NSString stringWithFormat:@"%@   ›", title]
                                    selector:@selector(znux_binaryPickerTapped:)
                                       frame:frame];
        picker.tag = 440000;
        picker.enabled = !workspace.isBuilding && !workspace.hasAnyApplied;
        picker.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        picker.titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        picker.titleLabel.adjustsFontSizeToFitWidth = YES;
        picker.titleLabel.minimumScaleFactor = 0.65;
        [container addSubview:picker];
    }

    // Manual read/validate remains available, but it is no longer a prerequisite
    // for enabling the Build button. Build will run the same preflight itself.
    ZNUXForEachSubview(self.contentView, ^(UIView *view) {
        if (![view isKindOfClass:UIButton.class]) return;
        UIButton *button = (UIButton *)view;
        NSArray<NSString *> *actions = [button actionsForTarget:self forControlEvent:UIControlEventTouchUpInside];
        if (![actions containsObject:NSStringFromSelector(@selector(zn44_buildBinary:))]) return;
        button.enabled = !workspace.isBuilding && !workspace.hasAnyApplied && workspace.filledCount > 0;
        button.alpha = button.enabled ? 1.0 : 0.5;
    });
}

- (void)znux_renderPage {
    UIScrollView *scroll = self.contentScroll;
    CGPoint oldOffset = scroll ? scroll.contentOffset : CGPointZero;

    [self znux_applyAutoTargetOnce];
    [self znux_renderPage];
    [self znux_customizeRenderedBuilder];

    if (scroll) {
        CGFloat y = ZNUXClampScrollY(scroll, oldOffset.y);
        [scroll setContentOffset:CGPointMake(oldOffset.x, y) animated:NO];
    }
}

- (void)znux_binaryPickerTapped:(UIButton *)sender {
    NSArray<NSDictionary<NSString *, id> *> *images = ZNUXAppLocalImages();
    if (!images.count) {
        [ZNBinaryPatchWorkspace sharedWorkspace].lastStatus = @"当前 App 没有发现可选择的本地 Mach-O image";
        [self renderPage];
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"App Libraries"
                                                                   message:@"优先 UnityFramework；也可以选择主程序或当前 App 已加载的 Framework / dylib"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (NSDictionary<NSString *, id> *item in images) {
        NSString *name = [item[@"name"] isKindOfClass:NSString.class] ? item[@"name"] : @"";
        NSString *path = [item[@"path"] isKindOfClass:NSString.class] ? item[@"path"] : @"";
        if (!name.length) continue;
        NSString *relative = ZNUXRelativePath(path);
        NSString *label = relative.length ? [NSString stringWithFormat:@"%@  ·  %@", name, relative] : name;
        UIAlertAction *action = [UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
            [workspace updateDefaultTarget:name];
            [NSUserDefaults.standardUserDefaults setObject:name forKey:kZNUXSelectedTargetKey];
            workspace.lastStatus = [NSString stringWithFormat:@"当前二进制：%@", relative.length ? relative : name];
            [weakSelf renderPage];
        }];
        [alert addAction:action];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    UIWindow *window = self.hostWindow ?: [self currentWindow];
    UIViewController *presenter = ZNUXTopController(window.rootViewController);
    if (!presenter) return;
    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    if (popover) {
        popover.sourceView = sender;
        popover.sourceRect = sender.bounds;
        popover.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }
    [presenter presentViewController:alert animated:YES completion:nil];
}

- (void)znux_buildBinary:(id)sender {
    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    if (!workspace.isBuilding && !workspace.hasAnyApplied && workspace.filledCount > 0 &&
        workspace.validatedCount != workspace.filledCount) {
        NSString *error = nil;
        if (![workspace validateAll:&error]) {
            workspace.lastStatus = [NSString stringWithFormat:@"生成预检失败：%@", error ?: workspace.lastStatus ?: @"未知错误"];
            [self renderPage];
            return;
        }
        [[ZNRuntimeLogger sharedLogger] log:@"[builder] direct build: manual validate skipped; internal preflight passed"];
    }
    [self znux_buildBinary:sender];
}

- (void)znux_show {
    if (!self.uiReady) [self tick:nil];
    if (!self.uiReady || [self isVisible]) return;

    UIWindow *window = self.hostWindow ?: [self currentWindow];
    UIViewController *presenter = ZNUXTopController(window.rootViewController);
    if (!window || !presenter) return;

    ZNUXOverlayController *overlay = [[ZNUXOverlayController alloc] initWithPanel:self.panel];
    [presenter addChildViewController:overlay];
    overlay.view.frame = presenter.view.bounds;
    overlay.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [presenter.view addSubview:overlay.view];
    [overlay didMoveToParentViewController:presenter];

    self.panel.hidden = NO;
    objc_setAssociatedObject(self, kZNUXOverlayControllerKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (self.floatButton.superview == window) [window bringSubviewToFront:self.floatButton];
    [[ZNRuntimeLogger sharedLogger] log:@"[menu-overlay] child-controller passthrough shell shown"];
}

- (void)znux_hide {
    ZNUXOverlayController *overlay = objc_getAssociatedObject(self, kZNUXOverlayControllerKey);
    if (!overlay) {
        self.panel.hidden = YES;
        [self.panel removeFromSuperview];
        return;
    }

    self.panel.hidden = YES;
    [overlay willMoveToParentViewController:nil];
    [self.panel removeFromSuperview];
    [overlay.view removeFromSuperview];
    [overlay removeFromParentViewController];
    objc_setAssociatedObject(self, kZNUXOverlayControllerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    self.floatButton.hidden = NO;
    if (self.floatButton.superview == self.hostWindow) [self.hostWindow bringSubviewToFront:self.floatButton];
    [[ZNRuntimeLogger sharedLogger] log:@"[menu-overlay] child-controller passthrough shell hidden"];
}

- (BOOL)znux_isVisible {
    ZNUXOverlayController *overlay = objc_getAssociatedObject(self, kZNUXOverlayControllerKey);
    return self.uiReady && overlay.parentViewController != nil && !self.panel.hidden;
}

@end

static void ZNUXSwap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallUXFixesV2Deferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNUXSwap(cls, @selector(renderPage), @selector(znux_renderPage));
        ZNUXSwap(cls, @selector(zn44_buildBinary:), @selector(znux_buildBinary:));
        ZNUXSwap(cls, @selector(show), @selector(znux_show));
        ZNUXSwap(cls, @selector(hide), @selector(znux_hide));
        ZNUXSwap(cls, @selector(isVisible), @selector(znux_isVisible));
        [[ZNRuntimeLogger sharedLogger] log:@"[ux-v2] auto target + app libraries picker + direct build preflight + scroll preservation + touch passthrough installed"];
    });
}

#pragma mark - END ZNUXFixesV2.mm


#pragma mark - BEGIN ZNMethodFinderM42UI.mm
#line 1 "ZNMethodFinderM42UI.mm"
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

#pragma mark - END ZNMethodFinderM42UI.mm


#pragma mark - BEGIN ZNMethodFinderM43UI.mm
#line 1 "ZNMethodFinderM43UI.mm"
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

// M4.3 UI layer
// - Assembly picker using the same action-sheet interaction as App Libraries.
// - User-editable result limit.
// - /1 input moved below the method/class rows so the method name gets full width.
// - Return key becomes Done and dismisses the keyboard.
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
    if (argc != 1) return @{@"supported": @NO, @"reason": [NSString stringWithFormat:@"M4.3 V1 暂不执行 /%ld", (long)argc], @"type": @"", @"name": @""};
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
    UILabel *title = [self label:@"IL2CPP 方法查找 · M4.3" size:12.6 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
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
    limit.keyboardType = UIKeyboardTypeNumberPad;
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
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.3-search] assembly=%@ query=%@ limit=%lu -> %lu", scope, query, (unsigned long)[self zn60v3_limit], (unsigned long)items.count]];
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
        CGFloat cardH = argc == 1 ? 108.0 : 82.0;
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

        CGFloat assemblyY = argc == 1 ? 84.0 : 55.0;
        UILabel *assembly = [self label:ZNM43AssemblyDisplay(candidate[@"assembly"] ?: @"?") size:8.1 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        assembly.frame = CGRectMake(13, assemblyY, leftW - 8.0, 16); assembly.lineBreakMode = NSLineBreakByTruncatingTail; [card addSubview:assembly];

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
        [[ZNRuntimeLogger sharedLogger] log:@"[m4.3-ui] assembly picker + custom result limit + lower /1 input + Done key + detail cleanup installed"];
    });
}

#pragma mark - END ZNMethodFinderM43UI.mm


#pragma mark - BEGIN ZNMethodFinderM43Polish.mm
#line 1 "ZNMethodFinderM43Polish.mm"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNPatchCore.h"

static const NSInteger kZNM43PolishLimitTag = 643001;

static NSString *ZNM43PolishAssemblyDisplay(NSString *assembly) {
    NSString *value = assembly ?: @"";
    return [value.lowercaseString hasSuffix:@".dll"] && value.length > 4
        ? [value substringToIndex:value.length - 4] : value;
}

static void ZNM43PolishHideAssemblyLabels(UIView *root, NSString *display) {
    if (!root || !display.length) return;
    for (UIView *view in root.subviews) {
        if ([view isKindOfClass:UILabel.class]) {
            UILabel *label = (UILabel *)view;
            if ([label.text isEqualToString:display]) label.hidden = YES;
        }
        ZNM43PolishHideAssemblyLabels(view, display);
    }
}

@interface ZNRuntimeMenuControllerV040 (ZNMethodFinderM43Polish)
- (void)znm43p_renderSearchAtWidth:(CGFloat)width;
- (void)znm43p_renderResultsAtWidth:(CGFloat)width;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNMethodFinderM43Polish)

- (void)znm43p_renderSearchAtWidth:(CGFloat)width {
    [self znm43p_renderSearchAtWidth:width];
    UITextField *limit = (UITextField *)[self.contentView viewWithTag:kZNM43PolishLimitTag];
    if ([limit isKindOfClass:UITextField.class]) {
        limit.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        limit.returnKeyType = UIReturnKeyDone;
    }
}

- (void)znm43p_renderResultsAtWidth:(CGFloat)width {
    [self znm43p_renderResultsAtWidth:width];
    NSString *assembly = [self znm43_selectedAssembly];
    if (!assembly.length) return;
    ZNM43PolishHideAssemblyLabels(self.contentView, ZNM43PolishAssemblyDisplay(assembly));
}

@end

static void ZNM43PolishSwap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallMethodFinderM43PolishDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNM43PolishSwap(cls, @selector(zn60v3_renderSearchAtWidth:), @selector(znm43p_renderSearchAtWidth:));
        ZNM43PolishSwap(cls, @selector(zn60v3_renderResultsAtWidth:), @selector(znm43p_renderResultsAtWidth:));
        [[ZNRuntimeLogger sharedLogger] log:@"[m4.3-polish] Done keyboard + deduplicated single-Assembly result labels installed"];
    });
}

#pragma mark - END ZNMethodFinderM43Polish.mm


#pragma mark - BEGIN ZNInstanceSelectionV2UI.mm
#line 1 "ZNInstanceSelectionV2UI.mm"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

#import "ZNIL2CPPInstanceResolver.h"
#import "ZNIL2CPPInstanceSelectionV2.h"
#import "ZNIL2CPPResolver.h"
#import "ZNRuntimeActionRuntime.h"
#import "ZNPatchCore.h"

static const uint32_t kZNM44MethodAttributeStatic = 0x0010u;
static const NSInteger kZNM44FeatureExecuteTagBase = 672000;
static const NSInteger kZNM44FeatureCompactExecuteTagBase = 673000;

typedef uint32_t (*ZNM44MethodGetFlagsFn)(const void *, uint32_t *);

static UIViewController *ZNM44TopController(UIViewController *vc) {
    if (!vc) return nil;
    if (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) return ZNM44TopController(vc.presentedViewController);
    if ([vc isKindOfClass:UINavigationController.class]) return ZNM44TopController(((UINavigationController *)vc).visibleViewController ?: vc);
    if ([vc isKindOfClass:UITabBarController.class]) return ZNM44TopController(((UITabBarController *)vc).selectedViewController ?: vc);
    if ([vc isKindOfClass:UISplitViewController.class]) return ZNM44TopController(((UISplitViewController *)vc).viewControllers.lastObject ?: vc);
    return vc;
}

static void ZNM44CollectTestButtons(UIView *view, id target, NSMutableArray<UIButton *> *out) {
    for (UIView *child in view.subviews) {
        if ([child isKindOfClass:UIButton.class]) {
            UIButton *button = (UIButton *)child;
            NSArray<NSString *> *actions = [button actionsForTarget:target forControlEvent:UIControlEventTouchUpInside] ?: @[];
            if ([actions containsObject:NSStringFromSelector(@selector(znm43_testCandidate:))]) [out addObject:button];
        }
        ZNM44CollectTestButtons(child, target, out);
    }
}

static CGFloat ZNM44ButtonY(UIButton *button, UIView *contentView) {
    CGRect rect = [button convertRect:button.bounds toView:contentView];
    return CGRectGetMinY(rect);
}

static NSDictionary *ZNM44CandidateForButton(ZNRuntimeMenuControllerV040 *controller, UIButton *sender) {
    NSArray<NSDictionary *> *all = [controller zn60v3_candidates] ?: @[];
    NSInteger filter = [controller znm42_filter];
    NSMutableArray<NSDictionary *> *visible = [NSMutableArray array];
    for (NSDictionary *candidate in all) {
        if (filter < 0 || [candidate[@"argumentCount"] integerValue] == filter) [visible addObject:candidate];
    }
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    ZNM44CollectTestButtons(controller.contentView, controller, buttons);
    [buttons sortUsingComparator:^NSComparisonResult(UIButton *a, UIButton *b) {
        CGFloat ay = ZNM44ButtonY(a, controller.contentView);
        CGFloat by = ZNM44ButtonY(b, controller.contentView);
        if (ay < by) return NSOrderedAscending;
        if (ay > by) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    NSUInteger index = [buttons indexOfObjectIdenticalTo:sender];
    return index != NSNotFound && index < visible.count ? visible[index] : nil;
}

static void *ZNM44ResolveSymbol(NSString *path, const char *name) {
    void *symbol = dlsym(RTLD_DEFAULT, name);
    if (symbol || !path.length) return symbol;
#ifdef RTLD_NOLOAD
    void *handle = dlopen(path.fileSystemRepresentation, RTLD_LAZY | RTLD_NOLOAD);
#else
    void *handle = dlopen(path.fileSystemRepresentation, RTLD_LAZY);
#endif
    return handle ? dlsym(handle, name) : NULL;
}

static BOOL ZNM44MethodIsStatic(NSString *assembly,
                                NSString *namespaceName,
                                NSString *className,
                                NSString *methodName,
                                NSUInteger argumentCount,
                                NSNumber *methodInfoHint,
                                BOOL *known) {
    if (known) *known = NO;
    ZNIL2CPPResolver *resolver = [ZNIL2CPPResolver sharedResolver];
    [resolver refresh];
    if (!resolver.isAvailable) return NO;
    uintptr_t methodInfo = [methodInfoHint unsignedLongLongValue];
    if (!methodInfo) {
        NSDictionary *resolved = [resolver resolveMethodAssembly:assembly
                                                       namespace:namespaceName ?: @""
                                                       className:className
                                                          method:methodName
                                                   argumentCount:(NSInteger)argumentCount];
        methodInfo = [resolved[@"methodInfo"] unsignedLongLongValue];
    }
    if (!methodInfo) return NO;
    ZNM44MethodGetFlagsFn getFlags = (ZNM44MethodGetFlagsFn)ZNM44ResolveSymbol(resolver.unityPath, "il2cpp_method_get_flags");
    if (!getFlags) return NO;
    uint32_t implFlags = 0;
    uint32_t flags = getFlags((const void *)methodInfo, &implFlags);
    if (known) *known = YES;
    return (flags & kZNM44MethodAttributeStatic) != 0;
}

typedef void (^ZNM44ReadyBlock)(void);

static void ZNM44EnsureInstance(ZNRuntimeMenuControllerV040 *controller,
                                NSString *assembly,
                                NSString *namespaceName,
                                NSString *className,
                                UIView *sourceView,
                                ZNM44ReadyBlock ready) {
    ZNIL2CPPInstanceResolver *resolver = [ZNIL2CPPInstanceResolver sharedResolver];
    uintptr_t selected = [resolver znm44_selectedInstanceForAssembly:assembly namespace:namespaceName className:className];
    if (selected) {
        NSString *validationError = nil;
        if ([resolver znm44_validateInstanceAddress:selected assembly:assembly namespace:namespaceName className:className error:&validationError]) {
            if (ready) ready();
            return;
        }
        [resolver znm44_clearSelectedInstanceForAssembly:assembly namespace:namespaceName className:className];
    }

    NSString *diagnostics = nil;
    NSString *findError = nil;
    NSArray<NSNumber *> *instances = [resolver candidateAddressesForAssembly:assembly
                                                                    namespace:namespaceName ?: @""
                                                                    className:className
                                                                        limit:32
                                                                  diagnostics:&diagnostics
                                                                        error:&findError];
    if (!instances.count) {
        [controller zn60v3_setStatus:findError ?: @"Instance Resolver：没有找到活实例"];
        [controller renderPage];
        return;
    }
    if (instances.count == 1) {
        NSString *selectionError = nil;
        if ([resolver znm44_selectInstanceAddress:instances.firstObject.unsignedLongLongValue
                                         assembly:assembly
                                        namespace:namespaceName ?: @""
                                        className:className
                                            error:&selectionError]) {
            if (ready) ready();
        } else {
            [controller zn60v3_setStatus:selectionError ?: @"Instance Resolver：唯一实例验证失败"];
            [controller renderPage];
        }
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"选择实例 · %@", className ?: @"Object"]
                                                                   message:[NSString stringWithFormat:@"发现 %lu 个活实例；本次选择仅在当前进程有效", (unsigned long)instances.count]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak ZNRuntimeMenuControllerV040 *weakController = controller;
    for (NSUInteger i = 0; i < instances.count; i++) {
        uintptr_t address = instances[i].unsignedLongLongValue;
        NSString *title = [NSString stringWithFormat:@"实例 %lu · 0x%llX", (unsigned long)(i + 1), (unsigned long long)address];
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            ZNRuntimeMenuControllerV040 *strongController = weakController;
            if (!strongController) return;
            NSString *selectionError = nil;
            BOOL ok = [[ZNIL2CPPInstanceResolver sharedResolver] znm44_selectInstanceAddress:address
                                                                                     assembly:assembly
                                                                                    namespace:namespaceName ?: @""
                                                                                    className:className
                                                                                        error:&selectionError];
            if (ok) {
                [strongController zn60v3_setStatus:[NSString stringWithFormat:@"已选择 %@ 实例：0x%llX", className ?: @"Object", (unsigned long long)address]];
                if (ready) ready();
            } else {
                [strongController zn60v3_setStatus:selectionError ?: @"实例验证失败"];
                [strongController renderPage];
            }
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    UIWindow *window = controller.hostWindow ?: [controller currentWindow];
    UIViewController *presenter = ZNM44TopController(window.rootViewController);
    if (!presenter) return;
    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    if (popover) {
        popover.sourceView = sourceView ?: controller.contentView;
        popover.sourceRect = sourceView ? sourceView.bounds : controller.contentView.bounds;
        popover.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }
    [presenter presentViewController:alert animated:YES completion:nil];
}

@interface ZNRuntimeMenuControllerV040 (ZNInstanceSelectionV2UI)
- (void)znm44_testCandidate:(UIButton *)sender;
- (void)znm44_executeAction:(UIButton *)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNInstanceSelectionV2UI)

- (void)znm44_testCandidate:(UIButton *)sender {
    NSDictionary *candidate = ZNM44CandidateForButton(self, sender);
    if (!candidate) {
        [self znm44_testCandidate:sender];
        return;
    }
    NSString *assembly = candidate[@"assembly"] ?: @"Assembly-CSharp.dll";
    NSString *namespaceName = candidate[@"namespace"] ?: @"";
    NSString *className = candidate[@"class"] ?: @"";
    NSString *methodName = candidate[@"method"] ?: @"";
    NSUInteger argc = [candidate[@"argumentCount"] unsignedIntegerValue];
    BOOL known = NO;
    BOOL isStatic = ZNM44MethodIsStatic(assembly, namespaceName, className, methodName, argc, candidate[@"methodInfo"], &known);
    if (!known || isStatic) {
        [self znm44_testCandidate:sender];
        return;
    }
    __weak typeof(self) weakSelf = self;
    ZNM44EnsureInstance(self, assembly, namespaceName, className, sender, ^{
        [weakSelf znm44_testCandidate:sender];
    });
}

- (void)znm44_executeAction:(UIButton *)sender {
    NSInteger index = sender.tag - kZNM44FeatureExecuteTagBase;
    if (sender.tag >= kZNM44FeatureCompactExecuteTagBase) index = sender.tag - kZNM44FeatureCompactExecuteTagBase;
    ZNRuntimeActionRuntime *runtime = [ZNRuntimeActionRuntime sharedRuntime];
    [runtime refresh];
    if (index < 0 || (NSUInteger)index >= runtime.records.count) {
        [self znm44_executeAction:sender];
        return;
    }
    ZNRuntimeMethodActionRecord *record = runtime.records[(NSUInteger)index];
    BOOL known = NO;
    BOOL isStatic = ZNM44MethodIsStatic(record.assembly,
                                        record.namespaceName,
                                        record.className,
                                        record.methodName,
                                        record.argumentCount,
                                        nil,
                                        &known);
    if (!known || isStatic) {
        [self znm44_executeAction:sender];
        return;
    }
    __weak typeof(self) weakSelf = self;
    ZNM44EnsureInstance(self, record.assembly, record.namespaceName, record.className, sender, ^{
        [weakSelf znm44_executeAction:sender];
    });
}

@end

static void ZNM44Swap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallInstanceSelectionV2UIDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ZNInstallIL2CPPInstanceSelectionV2Deferred();
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNM44Swap(cls, @selector(znm43_testCandidate:), @selector(znm44_testCandidate:));
        ZNM44Swap(cls, @selector(znrmc_executeAction:), @selector(znm44_executeAction:));
        [[ZNRuntimeLogger sharedLogger] log:@"[instance-selection-v2] multi-instance picker UI installed"];
    });
}

#pragma mark - END ZNInstanceSelectionV2UI.mm


#pragma mark - BEGIN ZNM441Hotfix.mm
#line 1 "ZNM441Hotfix.mm"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <errno.h>
#import <ctype.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNIL2CPPABIMetadata.h"
#import "ZNIL2CPPHybridFinder.h"
#import "ZNIL2CPPInstanceResolver.h"
#import "ZNIL2CPPInvokeEngine.h"
#import "ZNIL2CPPResolver.h"
#import "ZNPatchCore.h"

// M4.4.1 hotfix
// 1) Finder keyboard Search and visible Search button share one submit handler.
// 2) Finder accepts bare HEX / 0x / rva: forms and va: runtime addresses.
// 3) Patch Offset accepts bare HEX and normalizes to 0x... on Done.
// 4) /1 Unity value structs Vector2/Vector3/Quaternion/Color are supported as
//    comma/space separated float components; unsupported /1 fields show why.

static const NSInteger kZNM441LimitTag = 643001;
static const uint32_t kZNM441MethodAttributeStatic = 0x0010u;

typedef void *(*ZNM441RuntimeInvokeFn)(const void *method, void *object, void **params, void **exception);
typedef uint32_t (*ZNM441MethodGetFlagsFn)(const void *method, uint32_t *iflags);

typedef struct { float x, y; } ZNM441Vector2;
typedef struct { float x, y, z; } ZNM441Vector3;
typedef struct { float x, y, z, w; } ZNM441Quaternion;
typedef struct { float r, g, b, a; } ZNM441Color;

static NSString *ZNM441Trim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL ZNM441AllHex(NSString *value, BOOL *hasDigit) {
    NSString *s = ZNM441Trim(value);
    if (!s.length) return NO;
    BOOL digit = NO;
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) return NO;
        if (c >= '0' && c <= '9') digit = YES;
    }
    if (hasDigit) *hasDigit = digit;
    return YES;
}

static BOOL ZNM441ParseHexBody(NSString *body, uint64_t *outValue) {
    NSString *s = ZNM441Trim(body);
    if ([s.lowercaseString hasPrefix:@"0x"]) s = [s substringFromIndex:2];
    if (!s.length || !ZNM441AllHex(s, NULL)) return NO;
    const char *raw = s.UTF8String;
    if (!raw) return NO;
    errno = 0;
    char *end = NULL;
    unsigned long long value = strtoull(raw, &end, 16);
    if (errno || end == raw || (end && *end)) return NO;
    if (outValue) *outValue = (uint64_t)value;
    return YES;
}

static uintptr_t ZNM441UnityRuntimeBase(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *raw = _dyld_get_image_name(i);
        if (!raw) continue;
        NSString *path = [NSString stringWithUTF8String:raw] ?: @"";
        if ([path.lastPathComponent isEqualToString:@"UnityFramework"] ||
            [path rangeOfString:@"UnityFramework.framework/UnityFramework" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

static NSString *ZNM441NormalizeFinderQuery(NSString *raw, BOOL *isAddress, NSString **error) {
    NSString *s = ZNM441Trim(raw);
    if (isAddress) *isAddress = NO;
    if (!s.length) return s;

    NSString *lower = s.lowercaseString;
    BOOL explicitRVA = [lower hasPrefix:@"rva:"];
    BOOL explicitVA = [lower hasPrefix:@"va:"];
    BOOL explicit0x = [lower hasPrefix:@"0x"];
    BOOL hasDigit = NO;
    BOOL bareHex = ZNM441AllHex(s, &hasDigit) && hasDigit && s.length >= 5;
    if (!explicitRVA && !explicitVA && !explicit0x && !bareHex) return s;

    NSString *body = s;
    if (explicitRVA) body = [s substringFromIndex:4];
    else if (explicitVA) body = [s substringFromIndex:3];

    uint64_t value = 0;
    if (!ZNM441ParseHexBody(body, &value)) {
        if (error) *error = [NSString stringWithFormat:@"地址格式无效：%@", raw ?: @""];
        return nil;
    }
    if (explicitVA) {
        uintptr_t base = ZNM441UnityRuntimeBase();
        if (!base || value < (uint64_t)base) {
            if (error) *error = [NSString stringWithFormat:@"Runtime VA 无法换算 UnityFramework RVA：0x%llX", (unsigned long long)value];
            return nil;
        }
        value -= (uint64_t)base;
    }
    if (isAddress) *isAddress = YES;
    return [NSString stringWithFormat:@"rva:0x%llX", (unsigned long long)value];
}

static NSString *ZNM441NormalizePatchOffset(NSString *raw) {
    NSString *s = ZNM441Trim(raw);
    if (!s.length) return @"";
    NSString *lower = s.lowercaseString;
    if ([lower hasPrefix:@"rva:"]) s = [s substringFromIndex:4];
    uint64_t value = 0;
    if (!ZNM441ParseHexBody(s, &value)) return raw ?: @"";
    return [NSString stringWithFormat:@"0x%llX", (unsigned long long)value];
}

static NSString *ZNM441SimpleTypeName(NSString *typeName) {
    NSString *t = ZNM441Trim(typeName);
    NSArray<NSString *> *parts = [t componentsSeparatedByString:@"."];
    return parts.lastObject.length ? parts.lastObject : t;
}

static NSUInteger ZNM441StructComponentCount(NSString *typeName) {
    NSString *n = ZNM441Trim(typeName).lowercaseString;
    if ([n isEqualToString:@"unityengine.vector2"] || [n isEqualToString:@"vector2"]) return 2;
    if ([n isEqualToString:@"unityengine.vector3"] || [n isEqualToString:@"vector3"]) return 3;
    if ([n isEqualToString:@"unityengine.quaternion"] || [n isEqualToString:@"quaternion"]) return 4;
    if ([n isEqualToString:@"unityengine.color"] || [n isEqualToString:@"color"]) return 4;
    return 0;
}

static BOOL ZNM441ParseFloatComponents(NSString *text, NSUInteger expected, float outValues[4], NSString **error) {
    NSMutableCharacterSet *separators = [[NSCharacterSet whitespaceAndNewlineCharacterSet] mutableCopy];
    [separators addCharactersInString:@",，;；"];
    NSArray<NSString *> *rawParts = [ZNM441Trim(text) componentsSeparatedByCharactersInSet:separators];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *part in rawParts) if (ZNM441Trim(part).length) [parts addObject:ZNM441Trim(part)];
    if (parts.count != expected) {
        if (error) *error = [NSString stringWithFormat:@"需要 %lu 个浮点分量，当前=%lu", (unsigned long)expected, (unsigned long)parts.count];
        return NO;
    }
    for (NSUInteger i = 0; i < expected; i++) {
        const char *raw = parts[i].UTF8String;
        if (!raw) return NO;
        errno = 0;
        char *end = NULL;
        double value = strtod(raw, &end);
        while (end && *end && isspace((unsigned char)*end)) end++;
        if (errno || end == raw || (end && *end)) {
            if (error) *error = [NSString stringWithFormat:@"第 %lu 个分量不是有效浮点数：%@", (unsigned long)i + 1, parts[i]];
            return NO;
        }
        outValues[i] = (float)value;
    }
    return YES;
}

static void *ZNM441ResolveSymbol(NSString *unityPath, const char *name) {
    void *symbol = dlsym(RTLD_DEFAULT, name);
    if (symbol || !unityPath.length) return symbol;
#ifdef RTLD_NOLOAD
    void *handle = dlopen(unityPath.fileSystemRepresentation, RTLD_LAZY | RTLD_NOLOAD);
#else
    void *handle = dlopen(unityPath.fileSystemRepresentation, RTLD_LAZY);
#endif
    return handle ? dlsym(handle, name) : NULL;
}

static void ZNM441Walk(UIView *root, void (^block)(UIView *view)) {
    if (!root || !block) return;
    block(root);
    for (UIView *child in root.subviews) ZNM441Walk(child, block);
}

static void ZNM441EnableCardActions(UIView *root) {
    if (!root) return;
    for (UIView *view in root.subviews) {
        if ([view isKindOfClass:UIButton.class]) {
            UIButton *button = (UIButton *)view;
            NSString *title = [button titleForState:UIControlStateNormal] ?: @"";
            if ([title isEqualToString:@"测试执行"] || [title isEqualToString:@"创建方法"]) {
                button.enabled = YES;
                button.alpha = 1.0;
            }
        }
    }
}

static NSString *ZNM441UnsupportedFieldReason(NSString *placeholder) {
    NSString *p = placeholder ?: @"";
    NSString *lower = p.lowercaseString;
    if ([p containsString:@"&"]) return @"ref/out 暂不支持";
    if ([p containsString:@"*"]) return @"pointer 暂不支持";
    if ([lower containsString:@"?"]) return @"ABI 类型不可用";
    if ([lower containsString:@"list"] || [lower containsString:@"dictionary"] || [lower containsString:@"[]"] ||
        [lower containsString:@"gameobject"] || [lower containsString:@"component"] || [lower containsString:@"transform"]) {
        return @"对象参数暂不支持";
    }
    return @"对象/复杂值类型暂不支持";
}

@interface ZNRuntimeMenuControllerV040 (ZNM441Hotfix)
- (void)znm441_renderSearchAtWidth:(CGFloat)width;
- (void)znm441_renderResultsAtWidth:(CGFloat)width;
- (void)znm441_submitSearch:(id)sender;
- (void)znm441_endEditing:(UITextField *)field;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM441Hotfix)

- (void)znm441_renderSearchAtWidth:(CGFloat)width {
    [self znm441_renderSearchAtWidth:width];

    __block UITextField *queryField = nil;
    __block UIButton *searchButton = nil;
    ZNM441Walk(self.contentView, ^(UIView *view) {
        if ([view isKindOfClass:UITextField.class]) {
            UITextField *field = (UITextField *)view;
            if (field.tag != kZNM441LimitTag && field.returnKeyType == UIReturnKeySearch) queryField = field;
        } else if ([view isKindOfClass:UIButton.class]) {
            UIButton *button = (UIButton *)view;
            if ([[button titleForState:UIControlStateNormal] isEqualToString:@"搜索"]) searchButton = button;
        }
    });

    if (queryField) {
        [queryField removeTarget:nil action:NULL forControlEvents:UIControlEventEditingDidEndOnExit];
        [queryField addTarget:self action:@selector(znm441_submitSearch:) forControlEvents:UIControlEventEditingDidEndOnExit];
    }
    if (searchButton) {
        [searchButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        [searchButton addTarget:self action:@selector(znm441_submitSearch:) forControlEvents:UIControlEventTouchUpInside];
    }
}

- (void)znm441_submitSearch:(id)sender {
    (void)sender;
    [self.hostWindow endEditing:YES];

    UITextField *limitField = (UITextField *)[self.contentView viewWithTag:kZNM441LimitTag];
    if ([limitField isKindOfClass:UITextField.class] && limitField.text.length) {
        NSInteger rawLimit = limitField.text.integerValue;
        NSUInteger value = (NSUInteger)MAX(1, MIN(1024, rawLimit));
        [self zn60v3_setLimit:value];
    }

    NSString *rawQuery = ZNM441Trim([self zn57mf_query]);
    if (!rawQuery.length) {
        [self zn60v3_setStatus:@"请输入方法名或地址"];
        [self renderPage];
        return;
    }

    BOOL addressQuery = NO;
    NSString *normalizeError = nil;
    NSString *query = ZNM441NormalizeFinderQuery(rawQuery, &addressQuery, &normalizeError);
    if (!query) {
        [self zn60v3_setStatus:normalizeError ?: @"地址格式无效"];
        [self renderPage];
        return;
    }
    if (addressQuery && ![query isEqualToString:rawQuery]) [self zn57mf_setQuery:query];

    NSString *assembly = [self znm43_selectedAssembly] ?: @"";
    NSString *expression = query;
    if (assembly.length && !addressQuery && [query rangeOfString:@"!"].location == NSNotFound) {
        expression = [NSString stringWithFormat:@"%@!%@", assembly, query];
    }

    NSString *searchError = nil;
    NSArray<NSDictionary *> *items = [[ZNIL2CPPHybridFinder sharedFinder] zn60_searchCandidates:expression
                                                                                           limit:[self zn60v3_limit]
                                                                                           error:&searchError];
    if (!items.count) {
        [self zn60v3_setStatus:searchError ?: @"没有搜索结果"];
        [self zn60v3_setPage:0];
        [self renderPage];
        return;
    }

    [self zn60v3_setCandidates:items];
    [self zn60v3_setSelected:nil];
    NSDictionary *stats = items.firstObject[@"searchStats"] ?: @{};
    NSString *scope = addressQuery ? @"地址反查" : (assembly.length ? ZNM441SimpleTypeName([assembly stringByDeletingPathExtension]) : @"全部 Assembly");
    [self zn60v3_setStatus:[NSString stringWithFormat:@"%@ · %@：%lu 个候选 · %@ classes · %.1fms",
                              scope,
                              query,
                              (unsigned long)items.count,
                              stats[@"classesScanned"] ?: @0,
                              [stats[@"elapsedMs"] doubleValue]]];
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.4.1-search] scope=%@ raw=%@ normalized=%@ limit=%lu -> %lu",
                                         scope, rawQuery, query, (unsigned long)[self zn60v3_limit], (unsigned long)items.count]];
    [self zn60v3_setPage:1];
    [self renderPage];
}

- (void)znm441_renderResultsAtWidth:(CGFloat)width {
    [self znm441_renderResultsAtWidth:width];
    ZNM441Walk(self.contentView, ^(UIView *view) {
        if (![view isKindOfClass:UITextField.class]) return;
        UITextField *field = (UITextField *)view;
        if (field.enabled) return;
        NSString *placeholder = field.placeholder ?: @"";
        NSString *lower = placeholder.lowercaseString;
        NSUInteger components = 0;
        NSString *componentHint = nil;
        if ([lower containsString:@"vector2"]) { components = 2; componentHint = @"x,y"; }
        else if ([lower containsString:@"vector3"]) { components = 3; componentHint = @"x,y,z"; }
        else if ([lower containsString:@"quaternion"]) { components = 4; componentHint = @"x,y,z,w"; }
        else if ([lower containsString:@"color"]) { components = 4; componentHint = @"r,g,b,a"; }

        if (components) {
            field.enabled = YES;
            field.alpha = 1.0;
            field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
            field.returnKeyType = UIReturnKeyDone;
            if (![placeholder containsString:componentHint]) {
                field.placeholder = placeholder.length ? [NSString stringWithFormat:@"%@ · %@", placeholder, componentHint] : componentHint;
            }
            ZNM441EnableCardActions(field.superview);
        } else if (![placeholder containsString:@"暂不支持"]) {
            NSString *reason = ZNM441UnsupportedFieldReason(placeholder);
            field.placeholder = placeholder.length ? [NSString stringWithFormat:@"%@ · %@", placeholder, reason] : reason;
        }
    });
}

- (void)znm441_endEditing:(UITextField *)field {
    if (field.tag >= 441000 && field.tag < 442000) {
        NSString *normalized = ZNM441NormalizePatchOffset(field.text ?: @"");
        field.text = normalized;
        [[ZNBinaryPatchWorkspace sharedWorkspace] updateOffset:normalized row:(NSUInteger)(field.tag - 441000)];
    }
    [self znm441_endEditing:field];
}

@end

@interface ZNIL2CPPInvokeEngine (ZNM441CommonStruct)
- (NSDictionary<NSString *, id> * _Nullable)znm441_executeAssembly:(NSString *)assembly
                                                          namespace:(NSString *)namespaceName
                                                          className:(NSString *)className
                                                             method:(NSString *)methodName
                                                      argumentCount:(NSUInteger)argumentCount
                                                     argumentValues:(NSArray<NSString *> *)argumentValues
                                                              error:(NSString * _Nullable * _Nullable)error;
@end

@implementation ZNIL2CPPInvokeEngine (ZNM441CommonStruct)

- (NSDictionary<NSString *,id> *)znm441_executeAssembly:(NSString *)assembly
                                               namespace:(NSString *)namespaceName
                                               className:(NSString *)className
                                                  method:(NSString *)methodName
                                           argumentCount:(NSUInteger)argumentCount
                                          argumentValues:(NSArray<NSString *> *)argumentValues
                                                   error:(NSString **)error {
    if (argumentCount != 1 || argumentValues.count != 1) {
        return [self znm441_executeAssembly:assembly namespace:namespaceName className:className method:methodName argumentCount:argumentCount argumentValues:argumentValues error:error];
    }

    ZNIL2CPPResolver *resolver = [ZNIL2CPPResolver sharedResolver];
    [resolver refresh];
    if (!resolver.isAvailable) {
        return [self znm441_executeAssembly:assembly namespace:namespaceName className:className method:methodName argumentCount:argumentCount argumentValues:argumentValues error:error];
    }
    NSDictionary *resolved = [resolver resolveMethodAssembly:assembly namespace:namespaceName ?: @"" className:className method:methodName argumentCount:1];
    uintptr_t methodInfo = [resolved[@"methodInfo"] unsignedLongLongValue];
    if (!methodInfo) {
        return [self znm441_executeAssembly:assembly namespace:namespaceName className:className method:methodName argumentCount:argumentCount argumentValues:argumentValues error:error];
    }

    NSMutableDictionary *candidate = [NSMutableDictionary dictionaryWithDictionary:resolved ?: @{}];
    candidate[@"methodInfo"] = @(methodInfo);
    candidate[@"assembly"] = assembly ?: @"";
    candidate[@"namespace"] = namespaceName ?: @"";
    candidate[@"class"] = className ?: @"";
    candidate[@"method"] = methodName ?: @"";
    candidate[@"argumentCount"] = @1;
    NSDictionary *abi = ZNIL2CPPDescribeMethodABI(candidate);
    NSDictionary *param = [abi[@"parameters"] firstObject];
    NSString *typeName = [param[@"name"] isKindOfClass:NSString.class] ? param[@"name"] : @"";
    NSUInteger componentCount = ZNM441StructComponentCount(typeName);
    if (!componentCount || [param[@"byRef"] boolValue] || [param[@"pointer"] boolValue]) {
        return [self znm441_executeAssembly:assembly namespace:namespaceName className:className method:methodName argumentCount:argumentCount argumentValues:argumentValues error:error];
    }
    if ([abi[@"genericStatusKnown"] boolValue] && [abi[@"generic"] boolValue]) {
        if (error) *error = @"FAILED_ARGUMENT_ABI：generic definition 暂不执行 Unity struct 参数";
        return nil;
    }

    float components[4] = {0, 0, 0, 0};
    NSString *parseError = nil;
    if (!ZNM441ParseFloatComponents(argumentValues.firstObject, componentCount, components, &parseError)) {
        if (error) *error = [NSString stringWithFormat:@"FAILED_ARGUMENT_VALUE：%@ %@", ZNM441SimpleTypeName(typeName), parseError ?: @"格式错误"];
        return nil;
    }

    ZNM441RuntimeInvokeFn runtimeInvoke = (ZNM441RuntimeInvokeFn)ZNM441ResolveSymbol(resolver.unityPath, "il2cpp_runtime_invoke");
    ZNM441MethodGetFlagsFn methodGetFlags = (ZNM441MethodGetFlagsFn)ZNM441ResolveSymbol(resolver.unityPath, "il2cpp_method_get_flags");
    if (!runtimeInvoke || !methodGetFlags) {
        if (error) *error = @"FAILED_INVOKE_UNAVAILABLE：Unity struct invoke 所需 IL2CPP API 不完整";
        return nil;
    }

    uint32_t implFlags = 0;
    uint32_t methodFlags = methodGetFlags((const void *)methodInfo, &implFlags);
    BOOL isStatic = (methodFlags & kZNM441MethodAttributeStatic) != 0;
    void *targetObject = NULL;
    NSString *instanceDiagnostics = @"";
    if (!isStatic) {
        NSString *instanceError = nil;
        targetObject = [[ZNIL2CPPInstanceResolver sharedResolver] resolveUniqueInstanceForAssembly:assembly
                                                                                        namespace:namespaceName ?: @""
                                                                                        className:className
                                                                                      diagnostics:&instanceDiagnostics
                                                                                            error:&instanceError];
        if (!targetObject) {
            if (error) *error = instanceError ?: @"FAILED_INSTANCE_REQUIRED：无法解析对象实例";
            return nil;
        }
    }

    ZNM441Vector2 v2 = { components[0], components[1] };
    ZNM441Vector3 v3 = { components[0], components[1], components[2] };
    ZNM441Quaternion q = { components[0], components[1], components[2], components[3] };
    ZNM441Color color = { components[0], components[1], components[2], components[3] };
    void *valuePtr = NULL;
    NSString *simple = ZNM441SimpleTypeName(typeName).lowercaseString;
    if ([simple isEqualToString:@"vector2"]) valuePtr = &v2;
    else if ([simple isEqualToString:@"vector3"]) valuePtr = &v3;
    else if ([simple isEqualToString:@"quaternion"]) valuePtr = &q;
    else if ([simple isEqualToString:@"color"]) valuePtr = &color;
    if (!valuePtr) {
        return [self znm441_executeAssembly:assembly namespace:namespaceName className:className method:methodName argumentCount:argumentCount argumentValues:argumentValues error:error];
    }

    void *params[1] = { valuePtr };
    void *exception = NULL;
    void *result = runtimeInvoke((const void *)methodInfo, targetObject, params, &exception);
    if (exception) {
        if (error) *error = [NSString stringWithFormat:@"FAILED_EXCEPTION：IL2CPP exception=0x%llX", (unsigned long long)(uintptr_t)exception];
        return nil;
    }

    NSDictionary *output = @{
        @"status": @"SUCCESS",
        @"methodInfo": @(methodInfo),
        @"methodPointer": resolved[@"methodPointer"] ?: @0,
        @"pointerSource": resolved[@"pointerSource"] ?: @"unavailable",
        @"methodFlags": @(methodFlags),
        @"implFlags": @(implFlags),
        @"static": @(isStatic),
        @"instance": @((uintptr_t)targetObject),
        @"instanceDiagnostics": instanceDiagnostics ?: @"",
        @"argumentCount": @1,
        @"argumentValues": argumentValues ?: @[],
        @"parameterType": typeName ?: @"",
        @"result": @((uintptr_t)result),
        @"m441CommonStruct": @YES,
    };
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.4.1-struct] SUCCESS %@!%@.%@::%@/1 type=%@ value=%@ static=%@ object=0x%llX",
                                         assembly ?: @"", namespaceName ?: @"", className ?: @"", methodName ?: @"",
                                         typeName ?: @"", argumentValues.firstObject ?: @"", isStatic ? @"YES" : @"NO",
                                         (unsigned long long)(uintptr_t)targetObject]];
    if (error) *error = nil;
    return output;
}

@end

static void ZNM441Swap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallM441HotfixDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class menu = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (menu) {
            ZNM441Swap(menu, @selector(zn60v3_renderSearchAtWidth:), @selector(znm441_renderSearchAtWidth:));
            ZNM441Swap(menu, @selector(zn60v3_renderResultsAtWidth:), @selector(znm441_renderResultsAtWidth:));
            ZNM441Swap(menu, @selector(zn44_endEditing:), @selector(znm441_endEditing:));
        }
        Class engine = ZNIL2CPPInvokeEngine.class;
        ZNM441Swap(engine,
                   @selector(executeAssembly:namespace:className:method:argumentCount:argumentValues:error:),
                   @selector(znm441_executeAssembly:namespace:className:method:argumentCount:argumentValues:error:));
        [[ZNRuntimeLogger sharedLogger] log:@"[m4.4.1-hotfix] unified search route + hex normalization + common Unity /1 structs installed"];
    });
}

#pragma mark - END ZNM441Hotfix.mm


#pragma mark - BEGIN ZNM442SearchRestore.mm
#line 1 "ZNM442SearchRestore.mm"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <errno.h>

#import "ZNPatchCore.h"

// M4.4.2 search-route restore
//
// M4.3 swaps zn60v3_startSearch: <-> znm43_startSearch:. After that swap the
// selector znm43_startSearch: intentionally points at the original, device-
// proven V3 search implementation. M4.4.1 accidentally bypassed that path by
// rebinding both keyboard Search and the visible Search button to a third
// implementation. This outer hotfix keeps M4.4.1's input improvements but
// routes both UI entry points back through the proven V3 implementation.
//
// Assembly semantics are also restored:
// - before the user explicitly chooses an Assembly, search remains global and
//   the V3 backend keeps its original Assembly-CSharp-first priority;
// - after an explicit picker choice, a non-empty Assembly becomes a strict
//   Assembly filter by temporarily qualifying the query as Assembly!query.

static const void *kZNM442AssemblyExplicitKey = &kZNM442AssemblyExplicitKey;
static const NSInteger kZNM442LimitTag = 643001;

static NSString *ZNM442Trim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static void ZNM442Walk(UIView *root, void (^block)(UIView *view)) {
    if (!root || !block) return;
    block(root);
    for (UIView *subview in root.subviews) ZNM442Walk(subview, block);
}

static BOOL ZNM442AllHex(NSString *value, BOOL *hasDigit) {
    NSString *s = ZNM442Trim(value);
    if (!s.length) return NO;
    BOOL digit = NO;
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        BOOL hex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
        if (!hex) return NO;
        if (c >= '0' && c <= '9') digit = YES;
    }
    if (hasDigit) *hasDigit = digit;
    return YES;
}

static BOOL ZNM442ParseHexBody(NSString *body, uint64_t *outValue) {
    NSString *s = ZNM442Trim(body);
    if ([s.lowercaseString hasPrefix:@"0x"]) s = [s substringFromIndex:2];
    if (!s.length || !ZNM442AllHex(s, NULL)) return NO;
    const char *raw = s.UTF8String;
    if (!raw) return NO;
    errno = 0;
    char *end = NULL;
    unsigned long long value = strtoull(raw, &end, 16);
    if (errno || end == raw || (end && *end)) return NO;
    if (outValue) *outValue = (uint64_t)value;
    return YES;
}

static uintptr_t ZNM442UnityRuntimeBase(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *raw = _dyld_get_image_name(i);
        if (!raw) continue;
        NSString *path = [NSString stringWithUTF8String:raw] ?: @"";
        if ([path.lastPathComponent isEqualToString:@"UnityFramework"] ||
            [path rangeOfString:@"UnityFramework.framework/UnityFramework" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

static NSString *ZNM442NormalizeQuery(NSString *raw, BOOL *isAddress, NSString **error) {
    NSString *s = ZNM442Trim(raw);
    if (isAddress) *isAddress = NO;
    if (!s.length) return s;

    NSString *lower = s.lowercaseString;
    BOOL explicitRVA = [lower hasPrefix:@"rva:"];
    BOOL explicitVA = [lower hasPrefix:@"va:"];
    BOOL explicit0x = [lower hasPrefix:@"0x"];
    BOOL hasDigit = NO;
    BOOL bareHex = ZNM442AllHex(s, &hasDigit) && hasDigit && s.length >= 5;
    if (!explicitRVA && !explicitVA && !explicit0x && !bareHex) return s;

    NSString *body = s;
    if (explicitRVA) body = [s substringFromIndex:4];
    else if (explicitVA) body = [s substringFromIndex:3];

    uint64_t value = 0;
    if (!ZNM442ParseHexBody(body, &value)) {
        if (error) *error = [NSString stringWithFormat:@"地址格式无效：%@", raw ?: @""];
        return nil;
    }
    if (explicitVA) {
        uintptr_t base = ZNM442UnityRuntimeBase();
        if (!base || value < (uint64_t)base) {
            if (error) *error = [NSString stringWithFormat:@"Runtime VA 无法换算 UnityFramework RVA：0x%llX", (unsigned long long)value];
            return nil;
        }
        value -= (uint64_t)base;
    }
    if (isAddress) *isAddress = YES;
    return [NSString stringWithFormat:@"rva:0x%llX", (unsigned long long)value];
}

@interface ZNRuntimeMenuControllerV040 (ZNM442SearchRestore)
- (void)znm442_renderSearchAtWidth:(CGFloat)width;
- (void)znm442_submitSearch:(id)sender;
- (void)znm442_setSelectedAssembly:(NSString *)value;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM442SearchRestore)

- (void)znm442_setSelectedAssembly:(NSString *)value {
    // This method is swapped with znm43_setSelectedAssembly:. Calling the alias
    // reaches the original setter while this flag records explicit user intent.
    objc_setAssociatedObject(self, kZNM442AssemblyExplicitKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self znm442_setSelectedAssembly:value];
}

- (void)znm442_renderSearchAtWidth:(CGFloat)width {
    // Call the previous outer render chain (M4.4.1 -> M4.3 -> V3).
    [self znm442_renderSearchAtWidth:width];

    __block UITextField *queryField = nil;
    __block UIButton *searchButton = nil;
    __block UIButton *assemblyButton = nil;
    ZNM442Walk(self.contentView, ^(UIView *view) {
        if ([view isKindOfClass:UITextField.class]) {
            UITextField *field = (UITextField *)view;
            if (field.tag != kZNM442LimitTag && field.returnKeyType == UIReturnKeySearch) queryField = field;
        } else if ([view isKindOfClass:UIButton.class]) {
            UIButton *button = (UIButton *)view;
            NSString *title = [button titleForState:UIControlStateNormal] ?: @"";
            if ([title isEqualToString:@"搜索"]) searchButton = button;
            if ([title containsString:@"Assembly-CSharp"] && [title containsString:@"›"]) assemblyButton = button;
        }
    });

    if (queryField) {
        [queryField removeTarget:nil action:NULL forControlEvents:UIControlEventEditingDidEndOnExit];
        [queryField addTarget:self action:@selector(znm442_submitSearch:) forControlEvents:UIControlEventEditingDidEndOnExit];
    }
    if (searchButton) {
        [searchButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        [searchButton addTarget:self action:@selector(znm442_submitSearch:) forControlEvents:UIControlEventTouchUpInside];
    }

    BOOL explicitAssembly = [objc_getAssociatedObject(self, kZNM442AssemblyExplicitKey) boolValue];
    if (!explicitAssembly && assemblyButton) {
        [assemblyButton setTitle:@"Assembly-CSharp · 优先  ›" forState:UIControlStateNormal];
    }
}

- (void)znm442_submitSearch:(id)sender {
    UITextField *limitField = (UITextField *)[self.contentView viewWithTag:kZNM442LimitTag];
    if ([limitField isKindOfClass:UITextField.class] && limitField.text.length) {
        NSInteger raw = limitField.text.integerValue;
        [self zn60v3_setLimit:(NSUInteger)MAX(1, MIN(1024, raw))];
    }

    NSString *rawQuery = ZNM442Trim([self zn57mf_query]);
    if (!rawQuery.length) return;

    BOOL addressQuery = NO;
    NSString *normalizeError = nil;
    NSString *normalized = ZNM442NormalizeQuery(rawQuery, &addressQuery, &normalizeError);
    if (!normalized) {
        // Fall back to the proven V3 path with the original text so the existing
        // UI/status chain reports the same error semantics as before.
        normalized = rawQuery;
    }

    BOOL explicitAssembly = [objc_getAssociatedObject(self, kZNM442AssemblyExplicitKey) boolValue];
    NSString *assembly = [self znm43_selectedAssembly] ?: @"";
    NSString *expression = normalized;
    if (!addressQuery && explicitAssembly && assembly.length && [normalized rangeOfString:@"!"].location == NSNotFound) {
        expression = [NSString stringWithFormat:@"%@!%@", assembly, normalized];
    }

    // Critical behavior: delegate execution to selector znm43_startSearch:.
    // Because M4.3 already exchanged implementations, this selector is the
    // original V3 search implementation that was device-proven by the visible
    // Search button before M4.4.1.
    [self zn57mf_setQuery:expression];
    [self znm43_startSearch:sender];

    // Do not leak temporary Assembly! qualification back into the visible field.
    [self zn57mf_setQuery:normalized];
    ZNM442Walk(self.contentView, ^(UIView *view) {
        if (![view isKindOfClass:UITextField.class]) return;
        UITextField *field = (UITextField *)view;
        if (field.tag != kZNM442LimitTag && field.returnKeyType == UIReturnKeySearch) field.text = normalized;
    });

    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.4.2-search-restore] raw=%@ normalized=%@ explicitAssembly=%@ assembly=%@ engine=proven-v3",
                                         rawQuery,
                                         normalized,
                                         explicitAssembly ? @"YES" : @"NO",
                                         assembly.length ? assembly : @"<all>"]];
}

@end

static void ZNM442Swap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallM442SearchRestoreDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class menu = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!menu) return;
        ZNM442Swap(menu, @selector(zn60v3_renderSearchAtWidth:), @selector(znm442_renderSearchAtWidth:));
        ZNM442Swap(menu, @selector(znm43_setSelectedAssembly:), @selector(znm442_setSelectedAssembly:));
        [[ZNRuntimeLogger sharedLogger] log:@"[m4.4.2-search-restore] proven V3 engine restored for keyboard + button; Assembly-CSharp default is priority, explicit picker choice is strict"];
    });
}

#pragma mark - END ZNM442SearchRestore.mm


#pragma mark - BEGIN ZNM45AddressOwningMethodUI.mm
#line 1 "ZNM45AddressOwningMethodUI.mm"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <errno.h>

#import "ZNIL2CPPOwningMethodResolver.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

// M4.5 outer Finder layer.
// Named method searches remain on M4.4.2's device-proven V3 route. Address
// queries are intercepted and resolved by an interval-aware owning-method
// resolver so an instruction inside a method can map back to MethodInfo.
// Unsupported /1 arguments are rendered as explanatory labels instead of
// disabled gray text fields; only actually marshalable parameters stay inputs.

static NSString *ZNM45Trim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL ZNM45AllHex(NSString *value, BOOL *hasDigit) {
    NSString *s = ZNM45Trim(value);
    if (!s.length) return NO;
    BOOL digit = NO;
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        BOOL hex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
        if (!hex) return NO;
        if (c >= '0' && c <= '9') digit = YES;
    }
    if (hasDigit) *hasDigit = digit;
    return YES;
}

static BOOL ZNM45ParseHex(NSString *body, uint64_t *value) {
    NSString *s = ZNM45Trim(body);
    if ([s.lowercaseString hasPrefix:@"0x"]) s = [s substringFromIndex:2];
    if (!s.length || !ZNM45AllHex(s, NULL)) return NO;
    const char *raw = s.UTF8String;
    if (!raw) return NO;
    errno = 0;
    char *end = NULL;
    unsigned long long parsed = strtoull(raw, &end, 16);
    if (errno || end == raw || (end && *end)) return NO;
    if (value) *value = (uint64_t)parsed;
    return YES;
}

static uintptr_t ZNM45UnityRuntimeBase(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *raw = _dyld_get_image_name(i);
        if (!raw) continue;
        NSString *path = [NSString stringWithUTF8String:raw] ?: @"";
        if ([path.lastPathComponent isEqualToString:@"UnityFramework"] ||
            [path rangeOfString:@"UnityFramework.framework/UnityFramework" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

static BOOL ZNM45NormalizeAddress(NSString *raw, uint64_t *rva, NSString **normalized, NSString **error) {
    NSString *s = ZNM45Trim(raw);
    if (!s.length) return NO;
    NSString *lower = s.lowercaseString;
    BOOL explicitRVA = [lower hasPrefix:@"rva:"];
    BOOL explicitVA = [lower hasPrefix:@"va:"];
    BOOL explicit0x = [lower hasPrefix:@"0x"];
    BOOL hasDigit = NO;
    BOOL bareHex = ZNM45AllHex(s, &hasDigit) && hasDigit && s.length >= 5;
    if (!explicitRVA && !explicitVA && !explicit0x && !bareHex) return NO;

    NSString *body = s;
    if (explicitRVA) body = [s substringFromIndex:4];
    else if (explicitVA) body = [s substringFromIndex:3];

    uint64_t value = 0;
    if (!ZNM45ParseHex(body, &value)) {
        if (error) *error = [NSString stringWithFormat:@"M4.5：地址格式无效：%@", raw ?: @""];
        return YES;
    }
    if (explicitVA) {
        uintptr_t base = ZNM45UnityRuntimeBase();
        if (!base || value < (uint64_t)base) {
            if (error) *error = [NSString stringWithFormat:@"M4.5：Runtime VA 无法换算 UnityFramework RVA：0x%llX", (unsigned long long)value];
            return YES;
        }
        value -= (uint64_t)base;
    }
    if (rva) *rva = value;
    if (normalized) *normalized = [NSString stringWithFormat:@"rva:0x%llX", (unsigned long long)value];
    return YES;
}

static CGFloat ZNM45BottomY(UIView *content) {
    CGFloat bottom = 0;
    for (UIView *view in content.subviews) bottom = MAX(bottom, CGRectGetMaxY(view.frame));
    return bottom;
}

static BOOL ZNM45UnsupportedReasonText(NSString *text) {
    NSString *value = text ?: @"";
    if (!value.length) return NO;
    return [value containsString:@"暂不支持"] ||
           [value containsString:@"ABI 类型不可用"] ||
           [value containsString:@"尚未识别"];
}

static void ZNM45ReplaceUnsupportedInputs(UIView *root, ZNTheme *theme) {
    if (!root) return;
    NSArray<UIView *> *children = [root.subviews copy];
    for (UIView *view in children) {
        if ([view isKindOfClass:UITextField.class]) {
            UITextField *field = (UITextField *)view;
            NSString *reason = field.placeholder ?: @"";
            if (!field.enabled && ZNM45UnsupportedReasonText(reason) && field.superview) {
                UILabel *label = [[UILabel alloc] initWithFrame:field.frame];
                label.text = reason;
                label.textColor = theme.secondaryTextColor;
                label.font = [UIFont systemFontOfSize:8.4 weight:UIFontWeightRegular];
                label.numberOfLines = 2;
                label.lineBreakMode = NSLineBreakByTruncatingTail;
                label.adjustsFontSizeToFitWidth = YES;
                label.minimumScaleFactor = 0.72;
                label.backgroundColor = UIColor.clearColor;
                label.alpha = 1.0;
                [field.superview insertSubview:label aboveSubview:field];
                [field removeFromSuperview];
                continue;
            }
        }
        ZNM45ReplaceUnsupportedInputs(view, theme);
    }
}

@interface ZNRuntimeMenuControllerV040 (ZNM45AddressOwningMethod)
- (void)znm45_submitSearch:(id)sender;
- (void)znm45_renderResultsAtWidth:(CGFloat)width;
- (void)znm45_renderDetailAtWidth:(CGFloat)width;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM45AddressOwningMethod)

- (void)znm45_submitSearch:(id)sender {
    NSString *raw = ZNM45Trim([self zn57mf_query]);
    uint64_t rva = 0;
    NSString *normalized = nil;
    NSString *normalizeError = nil;
    BOOL addressQuery = ZNM45NormalizeAddress(raw, &rva, &normalized, &normalizeError);
    if (!addressQuery) {
        // After swizzling, this alias reaches M4.4.2's proven named-search route.
        [self znm45_submitSearch:sender];
        return;
    }

    [self.hostWindow endEditing:YES];
    if (normalizeError.length) {
        [self zn60v3_setStatus:normalizeError];
        [self zn60v3_setPage:0];
        [self renderPage];
        return;
    }

    [self zn57mf_setQuery:normalized ?: raw];
    NSString *resolveError = nil;
    NSArray<NSDictionary *> *items = [[ZNIL2CPPOwningMethodResolver sharedResolver] resolveRVA:rva
                                                                                          limit:[self zn60v3_limit]
                                                                                          error:&resolveError];
    if (!items.count) {
        [self zn60v3_setStatus:resolveError ?: @"M4.5：找不到所属 IL2CPP 方法"];
        [self zn60v3_setPage:0];
        [self renderPage];
        return;
    }

    [self zn60v3_setCandidates:items];
    [self zn60v3_setSelected:nil];
    NSDictionary *first = items.firstObject;
    NSString *className = first[@"class"] ?: @"?";
    NSString *methodName = first[@"method"] ?: @"?";
    NSInteger argc = [first[@"argumentCount"] integerValue];
    uint64_t methodRVA = [first[@"methodRVA"] unsignedLongLongValue];
    uint64_t delta = [first[@"intraMethodOffset"] unsignedLongLongValue];
    NSString *suffix = delta ? [NSString stringWithFormat:@" +0x%llX", (unsigned long long)delta] : @" · 方法入口";
    NSString *shared = items.count > 1 ? [NSString stringWithFormat:@" · %lu 个共享代码入口候选", (unsigned long)items.count] : @"";
    [self zn60v3_setStatus:[NSString stringWithFormat:@"0x%llX → %@::%@/%ld · start=0x%llX%@%@",
                              (unsigned long long)rva,
                              className,
                              methodName,
                              (long)argc,
                              (unsigned long long)methodRVA,
                              suffix,
                              shared]];
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.5-owning-method-ui] query=%@ rva=0x%llX candidates=%lu start=0x%llX delta=0x%llX",
                                         raw,
                                         (unsigned long long)rva,
                                         (unsigned long)items.count,
                                         (unsigned long long)methodRVA,
                                         (unsigned long long)delta]];
    [self zn60v3_setPage:1];
    [self renderPage];
}

- (void)znm45_renderResultsAtWidth:(CGFloat)width {
    // Previous chain renders normal supported inputs and M4.4.1 reason text.
    [self znm45_renderResultsAtWidth:width];
    ZNM45ReplaceUnsupportedInputs(self.contentView, self.theme);
}

- (void)znm45_renderDetailAtWidth:(CGFloat)width {
    // Alias reaches the previous detail renderer chain (M4.3 cleanup + V3 info).
    [self znm45_renderDetailAtWidth:width];
    NSDictionary *candidate = [self zn60v3_selected];
    if (![candidate[@"ownershipKind"] isKindOfClass:NSString.class]) return;

    CGFloat y = ZNM45BottomY(self.contentView) + 8.0;
    UIView *card = [self cardAtY:y height:112 width:width compact:NO];
    UILabel *title = [self label:@"地址归属（M4.5）" size:10.6 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
    title.frame = CGRectMake(13, 7, card.bounds.size.width - 26, 18);
    [card addSubview:title];

    NSString *query = candidate[@"queryRVAText"] ?: candidate[@"rvaText"] ?: @"—";
    NSString *start = candidate[@"methodRVAText"] ?: @"—";
    NSString *offset = candidate[@"intraMethodOffsetText"] ?: @"+0x0";
    NSString *next = candidate[@"nextMethodRVAText"] ?: @"—";
    NSString *kind = candidate[@"ownershipKind"] ?: @"?";
    NSArray<NSString *> *lines = @[
        [NSString stringWithFormat:@"查询 RVA      %@", query],
        [NSString stringWithFormat:@"方法入口       %@  (%@)", start, offset],
        [NSString stringWithFormat:@"下一方法入口   %@", next],
        [NSString stringWithFormat:@"判定           %@", kind],
    ];
    CGFloat ly = 30.0;
    for (NSString *line in lines) {
        UILabel *label = [self label:line size:8.5 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        label.frame = CGRectMake(13, ly, card.bounds.size.width - 26, 17);
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.7;
        [card addSubview:label];
        ly += 18.0;
    }
    [self.contentView addSubview:card];
    [self zn40_updateContentHeight:y + 120.0];
}

@end

static void ZNM45Swap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallM45AddressOwningMethodDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class menu = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!menu) return;
        ZNM45Swap(menu, @selector(znm442_submitSearch:), @selector(znm45_submitSearch:));
        ZNM45Swap(menu, @selector(zn60v3_renderResultsAtWidth:), @selector(znm45_renderResultsAtWidth:));
        ZNM45Swap(menu, @selector(zn60v3_renderDetailAtWidth:), @selector(znm45_renderDetailAtWidth:));
        [[ZNRuntimeLogger sharedLogger] log:@"[m4.5-owning-method] address owning-method resolver + unsupported-argument-label UI installed; named search remains proven-v3"];
    });
}

#pragma mark - END ZNM45AddressOwningMethodUI.mm


#pragma mark - BEGIN ZNM46FullSignatureUI.mm
#line 1 "ZNM46FullSignatureUI.mm"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

#import "ZNIL2CPPInstanceResolver.h"
#import "ZNIL2CPPInstanceSelectionV2.h"
#import "ZNIL2CPPInvokeEngine.h"
#import "ZNIL2CPPMethodSignature.h"
#import "ZNIL2CPPResolver.h"
#import "ZNRuntimeActionModel.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

static const uint32_t kZNM46MethodAttributeStatic = 0x0010u;
typedef uint32_t (*ZNM46MethodGetFlagsFn)(const void *, uint32_t *);

typedef void (^ZNM46ReadyBlock)(void);

static NSString *ZNM46LegacyShortName(NSDictionary *candidate) {
    NSString *method = [candidate[@"method"] isKindOfClass:NSString.class] ? candidate[@"method"] : @"Method";
    NSInteger argc = [candidate[@"argumentCount"] respondsToSelector:@selector(integerValue)] ? [candidate[@"argumentCount"] integerValue] : -1;
    return argc >= 0 ? [NSString stringWithFormat:@"%@/%ld", method, (long)argc] : method;
}

static NSString *ZNM46CandidateCollisionKey(NSDictionary *candidate) {
    return [NSString stringWithFormat:@"%@|%@|%@|%@|%@",
            candidate[@"assembly"] ?: @"",
            candidate[@"namespace"] ?: @"",
            candidate[@"class"] ?: @"",
            candidate[@"method"] ?: @"",
            candidate[@"argumentCount"] ?: @(-1)];
}

static NSArray<NSDictionary *> *ZNM46VisibleCandidates(ZNRuntimeMenuControllerV040 *controller) {
    NSArray<NSDictionary *> *all = [controller zn60v3_candidates] ?: @[];
    NSInteger filter = [controller znm42_filter];
    NSMutableArray<NSDictionary *> *visible = [NSMutableArray array];
    for (NSDictionary *candidate in all) {
        if (filter < 0 || [candidate[@"argumentCount"] integerValue] == filter) [visible addObject:candidate];
    }
    return visible;
}

static void ZNM46CollectTestButtons(UIView *view, id target, NSMutableArray<UIButton *> *out) {
    for (UIView *child in view.subviews) {
        if ([child isKindOfClass:UIButton.class]) {
            UIButton *button = (UIButton *)child;
            NSArray<NSString *> *actions = [button actionsForTarget:target forControlEvent:UIControlEventTouchUpInside] ?: @[];
            if ([actions containsObject:NSStringFromSelector(@selector(znm43_testCandidate:))]) [out addObject:button];
        }
        ZNM46CollectTestButtons(child, target, out);
    }
}

static CGFloat ZNM46ViewY(UIView *view, UIView *content) {
    return CGRectGetMinY([view convertRect:view.bounds toView:content]);
}

static NSDictionary *ZNM46CandidateForButton(ZNRuntimeMenuControllerV040 *controller, UIButton *sender) {
    NSArray<NSDictionary *> *visible = ZNM46VisibleCandidates(controller);
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    ZNM46CollectTestButtons(controller.contentView, controller, buttons);
    [buttons sortUsingComparator:^NSComparisonResult(UIButton *a, UIButton *b) {
        CGFloat ay = ZNM46ViewY(a, controller.contentView), by = ZNM46ViewY(b, controller.contentView);
        return ay < by ? NSOrderedAscending : ay > by ? NSOrderedDescending : NSOrderedSame;
    }];
    NSUInteger index = [buttons indexOfObjectIdenticalTo:sender];
    return index != NSNotFound && index < visible.count ? visible[index] : nil;
}

static void ZNM46CollectMethodLabels(UIView *view,
                                     UIView *content,
                                     NSSet<NSString *> *legacyNames,
                                     NSMutableArray<UILabel *> *out) {
    for (UIView *child in view.subviews) {
        if ([child isKindOfClass:UILabel.class]) {
            UILabel *label = (UILabel *)child;
            if ([legacyNames containsObject:label.text ?: @""]) [out addObject:label];
        }
        ZNM46CollectMethodLabels(child, content, legacyNames, out);
    }
}

static void *ZNM46ResolveSymbol(NSString *path, const char *name) {
    void *p = dlsym(RTLD_DEFAULT, name);
    if (p || !path.length) return p;
#ifdef RTLD_NOLOAD
    void *handle = dlopen(path.fileSystemRepresentation, RTLD_LAZY | RTLD_NOLOAD);
#else
    void *handle = dlopen(path.fileSystemRepresentation, RTLD_LAZY);
#endif
    return handle ? dlsym(handle, name) : NULL;
}

static UIViewController *ZNM46TopController(UIViewController *vc) {
    if (!vc) return nil;
    if (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) return ZNM46TopController(vc.presentedViewController);
    if ([vc isKindOfClass:UINavigationController.class]) return ZNM46TopController(((UINavigationController *)vc).visibleViewController ?: vc);
    if ([vc isKindOfClass:UITabBarController.class]) return ZNM46TopController(((UITabBarController *)vc).selectedViewController ?: vc);
    if ([vc isKindOfClass:UISplitViewController.class]) return ZNM46TopController(((UISplitViewController *)vc).viewControllers.lastObject ?: vc);
    return vc;
}

static BOOL ZNM46CandidateIsStatic(NSDictionary *candidate, BOOL *known) {
    if (known) *known = NO;
    uintptr_t methodInfo = [candidate[@"methodInfo"] unsignedLongLongValue];
    if (!methodInfo) return NO;
    ZNIL2CPPResolver *resolver = [ZNIL2CPPResolver sharedResolver];
    [resolver refresh];
    ZNM46MethodGetFlagsFn getFlags = (ZNM46MethodGetFlagsFn)ZNM46ResolveSymbol(resolver.unityPath, "il2cpp_method_get_flags");
    if (!getFlags) return NO;
    uint32_t implFlags = 0;
    uint32_t flags = getFlags((const void *)methodInfo, &implFlags);
    if (known) *known = YES;
    return (flags & kZNM46MethodAttributeStatic) != 0;
}

static ZNRuntimeMethodAction *ZNM46EphemeralAction(NSDictionary *candidate,
                                                   NSArray<NSString *> *values,
                                                   NSString **error) {
    NSString *signatureError = nil;
    NSArray<NSString *> *types = ZNIL2CPPParameterTypeNamesForCandidate(candidate, &signatureError);
    NSUInteger argc = [candidate[@"argumentCount"] unsignedIntegerValue];
    if (!types || types.count != argc) {
        if (error) *error = signatureError ?: @"M4.6：无法读取完整参数签名";
        return nil;
    }
    ZNRuntimeMethodAction *action = [ZNRuntimeMethodAction new];
    action.assembly = [candidate[@"assembly"] isKindOfClass:NSString.class] ? candidate[@"assembly"] : @"Assembly-CSharp.dll";
    action.namespaceName = [candidate[@"namespace"] isKindOfClass:NSString.class] ? candidate[@"namespace"] : @"";
    action.className = [candidate[@"class"] isKindOfClass:NSString.class] ? candidate[@"class"] : @"";
    action.methodName = [candidate[@"method"] isKindOfClass:NSString.class] ? candidate[@"method"] : @"";
    action.argumentCount = argc;
    action.argumentValues = values ?: @[];
    action.parameterTypeNames = types;
    action.signatureAvailable = YES;
    action.title = action.methodName;
    return action;
}

static void ZNM46ExecuteExactCandidate(ZNRuntimeMenuControllerV040 *controller,
                                       NSDictionary *candidate) {
    NSArray<NSString *> *values = [controller znm43_argumentValues:candidate] ?: @[];
    NSString *actionError = nil;
    ZNRuntimeMethodAction *action = ZNM46EphemeralAction(candidate, values, &actionError);
    if (!action) {
        [controller zn60v3_setStatus:actionError ?: @"M4.6：完整签名不可用"];
        [controller renderPage];
        return;
    }
    NSString *invokeError = nil;
    NSDictionary *result = [[ZNIL2CPPInvokeEngine sharedEngine] executeAction:action error:&invokeError];
    if (result) {
        BOOL isStatic = [result[@"static"] boolValue];
        NSString *suffix = isStatic ? @"static" : [NSString stringWithFormat:@"instance=0x%llX", (unsigned long long)[result[@"instance"] unsignedLongLongValue]];
        [controller zn60v3_setStatus:[NSString stringWithFormat:@"Runtime Invoke SUCCESS：%@ · %@", action.canonicalIdentity, suffix]];
    } else {
        [controller zn60v3_setStatus:invokeError ?: @"Runtime Invoke FAILED"];
    }
    [controller renderPage];
}

static void ZNM46EnsureInstanceThenExecute(ZNRuntimeMenuControllerV040 *controller,
                                           NSDictionary *candidate,
                                           UIView *sourceView) {
    NSString *assembly = candidate[@"assembly"] ?: @"Assembly-CSharp.dll";
    NSString *namespaceName = candidate[@"namespace"] ?: @"";
    NSString *className = candidate[@"class"] ?: @"";
    ZNIL2CPPInstanceResolver *resolver = [ZNIL2CPPInstanceResolver sharedResolver];

    uintptr_t selected = [resolver znm44_selectedInstanceForAssembly:assembly namespace:namespaceName className:className];
    if (selected) {
        NSString *validationError = nil;
        if ([resolver znm44_validateInstanceAddress:selected assembly:assembly namespace:namespaceName className:className error:&validationError]) {
            ZNM46ExecuteExactCandidate(controller, candidate);
            return;
        }
        [resolver znm44_clearSelectedInstanceForAssembly:assembly namespace:namespaceName className:className];
    }

    NSString *diagnostics = nil;
    NSString *findError = nil;
    NSArray<NSNumber *> *instances = [resolver candidateAddressesForAssembly:assembly
                                                                    namespace:namespaceName
                                                                    className:className
                                                                        limit:32
                                                                  diagnostics:&diagnostics
                                                                        error:&findError];
    if (!instances.count) {
        [controller zn60v3_setStatus:findError ?: @"M4.6 Instance Resolver：没有找到活实例"];
        [controller renderPage];
        return;
    }
    if (instances.count == 1) {
        NSString *selectionError = nil;
        if ([resolver znm44_selectInstanceAddress:instances.firstObject.unsignedLongLongValue
                                         assembly:assembly
                                        namespace:namespaceName
                                        className:className
                                            error:&selectionError]) {
            ZNM46ExecuteExactCandidate(controller, candidate);
        } else {
            [controller zn60v3_setStatus:selectionError ?: @"M4.6 Instance Resolver：唯一实例验证失败"];
            [controller renderPage];
        }
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"选择实例 · %@", className.length ? className : @"Object"]
                                                                   message:[NSString stringWithFormat:@"发现 %lu 个活实例；完整方法签名已锁定，实例选择仅当前进程有效", (unsigned long)instances.count]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak ZNRuntimeMenuControllerV040 *weakController = controller;
    for (NSUInteger i = 0; i < instances.count; i++) {
        uintptr_t address = instances[i].unsignedLongLongValue;
        [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"实例 %lu · 0x%llX", (unsigned long)(i + 1), (unsigned long long)address]
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(__unused UIAlertAction *a) {
            ZNRuntimeMenuControllerV040 *strong = weakController;
            if (!strong) return;
            NSString *selectionError = nil;
            if ([[ZNIL2CPPInstanceResolver sharedResolver] znm44_selectInstanceAddress:address
                                                                              assembly:assembly
                                                                             namespace:namespaceName
                                                                             className:className
                                                                                 error:&selectionError]) {
                ZNM46ExecuteExactCandidate(strong, candidate);
            } else {
                [strong zn60v3_setStatus:selectionError ?: @"M4.6 实例验证失败"];
                [strong renderPage];
            }
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    UIWindow *window = controller.hostWindow ?: [controller currentWindow];
    UIViewController *presenter = ZNM46TopController(window.rootViewController);
    if (!presenter) return;
    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    if (popover) {
        popover.sourceView = sourceView ?: controller.contentView;
        popover.sourceRect = sourceView ? sourceView.bounds : controller.contentView.bounds;
    }
    [presenter presentViewController:alert animated:YES completion:nil];
}

@interface ZNRuntimeMenuControllerV040 (ZNM46FullSignatureUI)
- (void)znm46_testCandidate:(UIButton *)sender;
- (void)znm46_createPatch:(id)sender;
- (void)znm46_renderResultsAtWidth:(CGFloat)width;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM46FullSignatureUI)

- (void)znm46_testCandidate:(UIButton *)sender {
    NSDictionary *candidate = ZNM46CandidateForButton(self, sender);
    if (!candidate) {
        [self znm46_testCandidate:sender];
        return;
    }
    NSString *signatureError = nil;
    NSArray *types = ZNIL2CPPParameterTypeNamesForCandidate(candidate, &signatureError);
    if (!types || types.count != [candidate[@"argumentCount"] unsignedIntegerValue]) {
        // Preserve the M4.5 path when the runtime hides signature APIs. Do not
        // claim exact-overload resolution in this compatibility fallback.
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.6-signature-ui] legacy test fallback %@ reason=%@",
                                             ZNM46LegacyShortName(candidate), signatureError ?: @"signature unavailable"]];
        [self znm46_testCandidate:sender];
        return;
    }

    BOOL staticKnown = NO;
    BOOL isStatic = ZNM46CandidateIsStatic(candidate, &staticKnown);
    if (!staticKnown || isStatic) {
        ZNM46ExecuteExactCandidate(self, candidate);
        return;
    }
    ZNM46EnsureInstanceThenExecute(self, candidate, sender);
}

- (void)znm46_createPatch:(id)sender {
    NSDictionary *candidate = [self zn60v3_selected];
    if (!candidate || ![candidate[@"addressResolved"] boolValue]) {
        [self znm46_createPatch:sender];
        return;
    }
    uint64_t exactRVA = [candidate[@"queryRVA"] respondsToSelector:@selector(unsignedLongLongValue)]
        ? [candidate[@"queryRVA"] unsignedLongLongValue]
        : [candidate[@"rva"] unsignedLongLongValue];
    if (!exactRVA) {
        [self znm46_createPatch:sender];
        return;
    }

    NSString *previous = [self zn57mf_query] ?: @"";
    NSString *exactQuery = [NSString stringWithFormat:@"rva:0x%llX", (unsigned long long)exactRVA];
    [self zn57mf_setQuery:exactQuery];
    // zn61v3_createPatch: is the post-swap alias containing the original V3
    // implementation. Calling it directly intentionally bypasses the older
    // Method/N PatchBridge wrapper so overload identity cannot be re-guessed.
    [self zn61v3_createPatch:sender];
    [self zn57mf_setQuery:previous];
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.6-signature-ui] Static Patch locked to exact candidate RVA %@", exactQuery]];
}

- (void)znm46_renderResultsAtWidth:(CGFloat)width {
    [self znm46_renderResultsAtWidth:width];
    NSArray<NSDictionary *> *visible = ZNM46VisibleCandidates(self);
    if (visible.count < 2) return;

    NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *legacyNames = [NSMutableSet set];
    for (NSDictionary *candidate in visible) {
        NSString *key = ZNM46CandidateCollisionKey(candidate);
        counts[key] = @([counts[key] unsignedIntegerValue] + 1);
        [legacyNames addObject:ZNM46LegacyShortName(candidate)];
    }

    BOOL hasCollision = NO;
    for (NSNumber *count in counts.allValues) if (count.unsignedIntegerValue > 1) { hasCollision = YES; break; }
    if (!hasCollision) return;

    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    ZNM46CollectMethodLabels(self.contentView, self.contentView, legacyNames, labels);
    [labels sortUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) {
        CGFloat ay = ZNM46ViewY(a, self.contentView), by = ZNM46ViewY(b, self.contentView);
        return ay < by ? NSOrderedAscending : ay > by ? NSOrderedDescending : NSOrderedSame;
    }];
    if (labels.count < visible.count) return;

    for (NSUInteger i = 0; i < visible.count && i < labels.count; i++) {
        NSDictionary *candidate = visible[i];
        if ([counts[ZNM46CandidateCollisionKey(candidate)] unsignedIntegerValue] <= 1) continue;
        NSString *signatureError = nil;
        NSArray<NSString *> *types = ZNIL2CPPParameterTypeNamesForCandidate(candidate, &signatureError);
        if (!types || types.count != [candidate[@"argumentCount"] unsignedIntegerValue]) continue;
        labels[i].text = ZNIL2CPPShortSignature(candidate[@"method"] ?: @"Method", types);
        labels[i].adjustsFontSizeToFitWidth = YES;
        labels[i].minimumScaleFactor = 0.55;
    }
}

@end

static void ZNM46UISwap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallM46FullSignatureUIDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class menu = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!menu) return;
        ZNM46UISwap(menu, @selector(znm43_testCandidate:), @selector(znm46_testCandidate:));
        ZNM46UISwap(menu, @selector(zn60v3_createPatch:), @selector(znm46_createPatch:));
        ZNM46UISwap(menu, @selector(zn60v3_renderResultsAtWidth:), @selector(znm46_renderResultsAtWidth:));
        [[ZNRuntimeLogger sharedLogger] log:@"[m4.6-signature-ui] exact candidate test + exact-RVA Static Patch + overload labels installed"];
    });
}

#pragma mark - END ZNM46FullSignatureUI.mm


#pragma mark - BEGIN ZNM461Polish.mm
#line 1 "ZNM461Polish.mm"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNIL2CPPMethodSignature.h"
#import "ZNRuntimeActionModel.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

static const CGFloat kZNM461SignatureRowHeight = 16.0;

static NSString *ZNM461LegacyName(NSDictionary *candidate) {
    NSString *method = [candidate[@"method"] isKindOfClass:NSString.class] ? candidate[@"method"] : @"Method";
    NSInteger argc = [candidate[@"argumentCount"] respondsToSelector:@selector(integerValue)] ? [candidate[@"argumentCount"] integerValue] : -1;
    return argc >= 0 ? [NSString stringWithFormat:@"%@/%ld", method, (long)argc] : method;
}

static NSString *ZNM461CollisionKey(NSDictionary *candidate) {
    return [NSString stringWithFormat:@"%@|%@|%@|%@|%@",
            candidate[@"assembly"] ?: @"",
            candidate[@"namespace"] ?: @"",
            candidate[@"class"] ?: @"",
            candidate[@"method"] ?: @"",
            candidate[@"argumentCount"] ?: @(-1)];
}

static NSArray<NSDictionary *> *ZNM461VisibleCandidates(ZNRuntimeMenuControllerV040 *controller) {
    NSArray<NSDictionary *> *all = [controller zn60v3_candidates] ?: @[];
    NSInteger filter = [controller znm42_filter];
    NSMutableArray<NSDictionary *> *visible = [NSMutableArray array];
    for (NSDictionary *candidate in all) {
        if (filter < 0 || [candidate[@"argumentCount"] integerValue] == filter) [visible addObject:candidate];
    }
    return visible;
}

static CGFloat ZNM461Y(UIView *view, UIView *root) {
    return CGRectGetMinY([view convertRect:view.bounds toView:root]);
}

static void ZNM461CollectButtons(UIView *view,
                                 id target,
                                 SEL selector,
                                 NSMutableArray<UIButton *> *out) {
    for (UIView *child in view.subviews) {
        if ([child isKindOfClass:UIButton.class]) {
            UIButton *button = (UIButton *)child;
            NSArray<NSString *> *actions = [button actionsForTarget:target forControlEvent:UIControlEventTouchUpInside] ?: @[];
            if ([actions containsObject:NSStringFromSelector(selector)]) [out addObject:button];
        }
        ZNM461CollectButtons(child, target, selector, out);
    }
}

static UILabel *ZNM461MethodLabelInCard(UIView *card) {
    UILabel *best = nil;
    for (UIView *view in card.subviews) {
        if (![view isKindOfClass:UILabel.class]) continue;
        UILabel *label = (UILabel *)view;
        CGFloat y = CGRectGetMinY(label.frame);
        if (y >= 4.0 && y <= 28.0) {
            if (!best || y < CGRectGetMinY(best.frame)) best = label;
        }
    }
    return best;
}

static void ZNM461MoveLowerLabels(UIView *card, CGFloat threshold, CGFloat delta) {
    for (UIView *view in card.subviews) {
        if (![view isKindOfClass:UILabel.class]) continue;
        if (CGRectGetMinY(view.frame) < threshold) continue;
        CGRect frame = view.frame;
        frame.origin.y += delta;
        view.frame = frame;
    }
}

static CGFloat ZNM461Bottom(UIView *root) {
    CGFloat bottom = 0;
    for (UIView *view in root.subviews) bottom = MAX(bottom, CGRectGetMaxY(view.frame));
    return bottom;
}

@interface ZNRuntimeMenuControllerV040 (ZNM461Polish)
- (void)znm461_renderPage;
- (void)znm461_renderResultsAtWidth:(CGFloat)width;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM461Polish)

- (void)znm461_renderPage {
    [self znm461_renderPage];

    ZNBinaryPatchWorkspace *workspace = [ZNBinaryPatchWorkspace sharedWorkspace];
    NSUInteger runtimeCount = [ZNRuntimeActionStore sharedStore].actionsSnapshot.count;
    BOOL runtimeOnlyReady = runtimeCount > 0 && workspace.filledCount == 0;
    if (!runtimeOnlyReady) return;

    // ZNUXFixesV2 historically re-applies a Static-only filledCount gate after
    // the Builder page renders. Runtime-only generation has its own safe path,
    // so override that UI gate after the complete render chain.
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    ZNM461CollectButtons(self.contentView, self, @selector(zn44_buildBinary:), buttons);
    for (UIButton *button in buttons) {
        button.enabled = !workspace.isBuilding;
        button.alpha = button.enabled ? 1.0 : 0.5;
    }
}

- (void)znm461_renderResultsAtWidth:(CGFloat)width {
    [self znm461_renderResultsAtWidth:width];

    NSArray<NSDictionary *> *visible = ZNM461VisibleCandidates(self);
    if (visible.count < 2) return;

    NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
    for (NSDictionary *candidate in visible) {
        NSString *key = ZNM461CollisionKey(candidate);
        counts[key] = @([counts[key] unsignedIntegerValue] + 1);
    }

    NSMutableArray<UIButton *> *testButtons = [NSMutableArray array];
    ZNM461CollectButtons(self.contentView, self, @selector(znm43_testCandidate:), testButtons);
    [testButtons sortUsingComparator:^NSComparisonResult(UIButton *a, UIButton *b) {
        CGFloat ay = ZNM461Y(a, self.contentView), by = ZNM461Y(b, self.contentView);
        return ay < by ? NSOrderedAscending : ay > by ? NSOrderedDescending : NSOrderedSame;
    }];
    if (testButtons.count < visible.count) return;

    for (NSUInteger i = 0; i < visible.count && i < testButtons.count; i++) {
        NSDictionary *candidate = visible[i];
        if ([counts[ZNM461CollisionKey(candidate)] unsignedIntegerValue] <= 1) continue;

        NSString *signatureError = nil;
        NSArray<NSString *> *types = ZNIL2CPPParameterTypeNamesForCandidate(candidate, &signatureError);
        if (!types || types.count != [candidate[@"argumentCount"] unsignedIntegerValue]) continue;

        UIButton *test = testButtons[i];
        UIView *card = test.superview;
        if (!card || card.superview != self.contentView) continue;

        // M4.6 V1 replaced the top title with Method(Type). M4.6.1 restores the
        // compact Method/N title and moves exact overload identity below input.
        UILabel *methodLabel = ZNM461MethodLabelInCard(card);
        if (methodLabel) methodLabel.text = ZNM461LegacyName(candidate);

        NSInteger argc = [candidate[@"argumentCount"] integerValue];
        CGFloat signatureY = argc == 1 ? 82.0 : 54.0;
        CGFloat oldBottom = CGRectGetMaxY(card.frame);

        // Existing Assembly row occupies this vertical slot. Shift it down one
        // helper row (hidden Assembly labels are moved too, keeping all-mode UI).
        ZNM461MoveLowerLabels(card, signatureY - 2.0, kZNM461SignatureRowHeight);

        CGRect cardFrame = card.frame;
        cardFrame.size.height += kZNM461SignatureRowHeight;
        card.frame = cardFrame;

        CGFloat rightEdge = MAX(80.0, CGRectGetMinX(test.frame) - 8.0);
        UILabel *signature = [[UILabel alloc] initWithFrame:CGRectMake(13.0,
                                                                      signatureY,
                                                                      MAX(40.0, rightEdge - 13.0),
                                                                      15.0)];
        signature.text = ZNIL2CPPShortSignature(candidate[@"method"] ?: @"Method", types);
        signature.textColor = self.theme.secondaryTextColor;
        signature.font = [UIFont monospacedSystemFontOfSize:7.9 weight:UIFontWeightMedium];
        signature.lineBreakMode = NSLineBreakByTruncatingMiddle;
        signature.adjustsFontSizeToFitWidth = YES;
        signature.minimumScaleFactor = 0.65;
        signature.userInteractionEnabled = NO;
        [card addSubview:signature];

        // Result cards are top-level siblings. Preserve their spacing by moving
        // everything that originally followed this card by exactly one row.
        for (UIView *sibling in self.contentView.subviews) {
            if (sibling == card) continue;
            if (CGRectGetMinY(sibling.frame) + 0.5 < oldBottom) continue;
            CGRect frame = sibling.frame;
            frame.origin.y += kZNM461SignatureRowHeight;
            sibling.frame = frame;
        }
    }

    [self zn40_updateContentHeight:ZNM461Bottom(self.contentView) + 8.0];
}

@end

static void ZNM461Swap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallM461PolishDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNM461Swap(cls, @selector(renderPage), @selector(znm461_renderPage));
        ZNM461Swap(cls, @selector(zn60v3_renderResultsAtWidth:), @selector(znm461_renderResultsAtWidth:));
        [[ZNRuntimeLogger sharedLogger] log:@"[m4.6.1-polish] signature helper row + runtime-only build gate override installed"];
    });
}

#pragma mark - END ZNM461Polish.mm


#pragma mark - BEGIN ZNM462CandidateBindingUI.mm
#line 1 "ZNM462CandidateBindingUI.mm"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

#import "ZNIL2CPPInstanceResolver.h"
#import "ZNIL2CPPInstanceSelectionV2.h"
#import "ZNIL2CPPInvokeEngine.h"
#import "ZNIL2CPPMethodSignature.h"
#import "ZNIL2CPPResolver.h"
#import "ZNRuntimeActionModel.h"
#import "ZNPatchCore.h"

// M4.6.2 removes the fragile "sort test buttons by Y and assume candidate order"
// execution route. M4.3 already creates result cards in candidate order and
// stores the real candidate on each button. This outer render layer walks the
// freshly-created result hierarchy in insertion order once, gives every test
// button an explicit M4.6.2 candidate association, then replaces its target
// with a handler that never performs geometric lookup.
static const void *kZNM462BoundCandidateKey = &kZNM462BoundCandidateKey;
static const uint32_t kZNM462MethodAttributeStatic = 0x0010u;
typedef uint32_t (*ZNM462MethodGetFlagsFn)(const void *, uint32_t *);

static NSArray<NSDictionary *> *ZNM462VisibleCandidates(ZNRuntimeMenuControllerV040 *controller) {
    NSArray<NSDictionary *> *all = [controller zn60v3_candidates] ?: @[];
    NSInteger filter = [controller znm42_filter];
    NSMutableArray<NSDictionary *> *visible = [NSMutableArray array];
    for (NSDictionary *candidate in all) {
        if (filter < 0 || [candidate[@"argumentCount"] integerValue] == filter) [visible addObject:candidate];
    }
    return visible;
}

static void ZNM462CollectTestButtonsInHierarchyOrder(UIView *root,
                                                      id target,
                                                      NSMutableArray<UIButton *> *buttons) {
    for (UIView *child in root.subviews) {
        if ([child isKindOfClass:UIButton.class]) {
            UIButton *button = (UIButton *)child;
            NSArray<NSString *> *actions = [button actionsForTarget:target forControlEvent:UIControlEventTouchUpInside] ?: @[];
            if ([actions containsObject:NSStringFromSelector(@selector(znm43_testCandidate:))]) [buttons addObject:button];
        }
        ZNM462CollectTestButtonsInHierarchyOrder(child, target, buttons);
    }
}

static void *ZNM462Symbol(NSString *path, const char *name) {
    void *symbol = dlsym(RTLD_DEFAULT, name);
    if (symbol || !path.length) return symbol;
#ifdef RTLD_NOLOAD
    void *handle = dlopen(path.fileSystemRepresentation, RTLD_LAZY | RTLD_NOLOAD);
#else
    void *handle = dlopen(path.fileSystemRepresentation, RTLD_LAZY);
#endif
    return handle ? dlsym(handle, name) : NULL;
}

static BOOL ZNM462CandidateIsStatic(NSDictionary *candidate, BOOL *known) {
    if (known) *known = NO;
    uintptr_t methodInfo = [candidate[@"methodInfo"] unsignedLongLongValue];
    if (!methodInfo) return NO;
    ZNIL2CPPResolver *resolver = [ZNIL2CPPResolver sharedResolver];
    [resolver refresh];
    ZNM462MethodGetFlagsFn getFlags = (ZNM462MethodGetFlagsFn)ZNM462Symbol(resolver.unityPath, "il2cpp_method_get_flags");
    if (!getFlags) return NO;
    uint32_t implFlags = 0;
    uint32_t flags = getFlags((const void *)methodInfo, &implFlags);
    if (known) *known = YES;
    return (flags & kZNM462MethodAttributeStatic) != 0;
}

static UIViewController *ZNM462TopController(UIViewController *vc) {
    if (!vc) return nil;
    if (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) return ZNM462TopController(vc.presentedViewController);
    if ([vc isKindOfClass:UINavigationController.class]) return ZNM462TopController(((UINavigationController *)vc).visibleViewController ?: vc);
    if ([vc isKindOfClass:UITabBarController.class]) return ZNM462TopController(((UITabBarController *)vc).selectedViewController ?: vc);
    if ([vc isKindOfClass:UISplitViewController.class]) return ZNM462TopController(((UISplitViewController *)vc).viewControllers.lastObject ?: vc);
    return vc;
}

static ZNRuntimeMethodAction *ZNM462ExactAction(ZNRuntimeMenuControllerV040 *controller,
                                                NSDictionary *candidate,
                                                NSArray<NSString *> *types) {
    ZNRuntimeMethodAction *action = [ZNRuntimeMethodAction new];
    action.assembly = [candidate[@"assembly"] isKindOfClass:NSString.class] ? candidate[@"assembly"] : @"Assembly-CSharp.dll";
    action.namespaceName = [candidate[@"namespace"] isKindOfClass:NSString.class] ? candidate[@"namespace"] : @"";
    action.className = [candidate[@"class"] isKindOfClass:NSString.class] ? candidate[@"class"] : @"";
    action.methodName = [candidate[@"method"] isKindOfClass:NSString.class] ? candidate[@"method"] : @"";
    action.argumentCount = [candidate[@"argumentCount"] unsignedIntegerValue];
    action.argumentValues = [controller znm43_argumentValues:candidate] ?: @[];
    action.parameterTypeNames = types ?: @[];
    action.signatureAvailable = YES;
    action.title = action.methodName;
    return action;
}

static void ZNM462ExecuteExact(ZNRuntimeMenuControllerV040 *controller,
                               NSDictionary *candidate,
                               NSArray<NSString *> *types) {
    ZNRuntimeMethodAction *action = ZNM462ExactAction(controller, candidate, types);
    NSString *error = nil;
    NSDictionary *result = [[ZNIL2CPPInvokeEngine sharedEngine] executeAction:action error:&error];
    if (result) {
        BOOL isStatic = [result[@"static"] boolValue];
        NSString *suffix = isStatic ? @"static" : [NSString stringWithFormat:@"instance=0x%llX", (unsigned long long)[result[@"instance"] unsignedLongLongValue]];
        [controller zn60v3_setStatus:[NSString stringWithFormat:@"Runtime Invoke SUCCESS：%@ · %@", action.canonicalIdentity, suffix]];
    } else {
        [controller zn60v3_setStatus:error ?: @"Runtime Invoke FAILED"];
    }
    [controller renderPage];
}

typedef void (^ZNM462ReadyBlock)(void);
static void ZNM462EnsureInstance(ZNRuntimeMenuControllerV040 *controller,
                                 NSDictionary *candidate,
                                 UIView *sourceView,
                                 ZNM462ReadyBlock ready) {
    NSString *assembly = candidate[@"assembly"] ?: @"Assembly-CSharp.dll";
    NSString *namespaceName = candidate[@"namespace"] ?: @"";
    NSString *className = candidate[@"class"] ?: @"";
    ZNIL2CPPInstanceResolver *resolver = [ZNIL2CPPInstanceResolver sharedResolver];

    uintptr_t selected = [resolver znm44_selectedInstanceForAssembly:assembly namespace:namespaceName className:className];
    if (selected) {
        NSString *validationError = nil;
        if ([resolver znm44_validateInstanceAddress:selected assembly:assembly namespace:namespaceName className:className error:&validationError]) {
            if (ready) ready();
            return;
        }
        [resolver znm44_clearSelectedInstanceForAssembly:assembly namespace:namespaceName className:className];
    }

    NSString *diagnostics = nil;
    NSString *findError = nil;
    NSArray<NSNumber *> *instances = [resolver candidateAddressesForAssembly:assembly
                                                                    namespace:namespaceName
                                                                    className:className
                                                                        limit:32
                                                                  diagnostics:&diagnostics
                                                                        error:&findError];
    if (!instances.count) {
        [controller zn60v3_setStatus:findError ?: @"M4.6.2 Instance Resolver：没有找到活实例"];
        [controller renderPage];
        return;
    }
    if (instances.count == 1) {
        NSString *selectionError = nil;
        if ([resolver znm44_selectInstanceAddress:instances.firstObject.unsignedLongLongValue
                                         assembly:assembly
                                        namespace:namespaceName
                                        className:className
                                            error:&selectionError]) {
            if (ready) ready();
        } else {
            [controller zn60v3_setStatus:selectionError ?: @"M4.6.2 Instance Resolver：唯一实例验证失败"];
            [controller renderPage];
        }
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"选择实例 · %@", className.length ? className : @"Object"]
                                                                   message:[NSString stringWithFormat:@"发现 %lu 个活实例；M4.6.2 使用 GCHandle（可用时）保持当前会话 receiver", (unsigned long)instances.count]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak ZNRuntimeMenuControllerV040 *weakController = controller;
    for (NSUInteger i = 0; i < instances.count; i++) {
        uintptr_t address = instances[i].unsignedLongLongValue;
        [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"实例 %lu · 0x%llX", (unsigned long)(i + 1), (unsigned long long)address]
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(__unused UIAlertAction *a) {
            ZNRuntimeMenuControllerV040 *strong = weakController;
            if (!strong) return;
            NSString *selectionError = nil;
            if ([[ZNIL2CPPInstanceResolver sharedResolver] znm44_selectInstanceAddress:address
                                                                              assembly:assembly
                                                                             namespace:namespaceName
                                                                             className:className
                                                                                 error:&selectionError]) {
                if (ready) ready();
            } else {
                [strong zn60v3_setStatus:selectionError ?: @"M4.6.2 receiver 选择失败"];
                [strong renderPage];
            }
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    UIWindow *window = controller.hostWindow ?: [controller currentWindow];
    UIViewController *presenter = ZNM462TopController(window.rootViewController);
    if (!presenter) return;
    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    if (popover) {
        popover.sourceView = sourceView ?: controller.contentView;
        popover.sourceRect = sourceView ? sourceView.bounds : controller.contentView.bounds;
        popover.permittedArrowDirections = UIPopoverArrowDirectionAny;
    }
    [presenter presentViewController:alert animated:YES completion:nil];
}

@interface ZNRuntimeMenuControllerV040 (ZNM462CandidateBindingUI)
- (void)znm462_renderResultsAtWidth:(CGFloat)width;
- (void)znm462_boundTestCandidate:(UIButton *)sender;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM462CandidateBindingUI)

- (void)znm462_renderResultsAtWidth:(CGFloat)width {
    [self znm462_renderResultsAtWidth:width];

    NSArray<NSDictionary *> *visible = ZNM462VisibleCandidates(self);
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    ZNM462CollectTestButtonsInHierarchyOrder(self.contentView, self, buttons);
    if (!visible.count || buttons.count != visible.count) {
        if (visible.count || buttons.count) {
            [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.6.2-candidate-binding] count mismatch candidates=%lu buttons=%lu; preserving previous route",
                                                 (unsigned long)visible.count, (unsigned long)buttons.count]];
        }
        return;
    }

    for (NSUInteger i = 0; i < visible.count; i++) {
        UIButton *button = buttons[i];
        NSDictionary *candidate = visible[i];
        objc_setAssociatedObject(button, kZNM462BoundCandidateKey, candidate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [button removeTarget:self action:@selector(znm43_testCandidate:) forControlEvents:UIControlEventTouchUpInside];
        [button addTarget:self action:@selector(znm462_boundTestCandidate:) forControlEvents:UIControlEventTouchUpInside];
    }
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.6.2-candidate-binding] explicitly bound %lu result buttons without Y-coordinate mapping",
                                         (unsigned long)visible.count]];
}

- (void)znm462_boundTestCandidate:(UIButton *)sender {
    NSDictionary *candidate = objc_getAssociatedObject(sender, kZNM462BoundCandidateKey);
    if (!candidate) {
        // Fail-safe only: an unbound button keeps the previous M4.6 route.
        [self znm43_testCandidate:sender];
        return;
    }

    NSString *signatureError = nil;
    NSArray<NSString *> *types = ZNIL2CPPParameterTypeNamesForCandidate(candidate, &signatureError);
    BOOL exact = types && types.count == [candidate[@"argumentCount"] unsignedIntegerValue];

    BOOL staticKnown = NO;
    BOOL isStatic = ZNM462CandidateIsStatic(candidate, &staticKnown);
    void (^execute)(void) = ^{
        if (exact) {
            ZNM462ExecuteExact(self, candidate, types);
        } else {
            // znm44_testCandidate: is the post-M4.4 selector alias containing
            // the original M4.3 candidate-associated handler. It consumes the
            // association placed on the button at creation, so no geometry is
            // used even in the legacy signature fallback.
            [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.6.2-candidate-binding] exact signature unavailable; direct candidate legacy route reason=%@",
                                                 signatureError ?: @"signature unavailable"]];
            [self znm44_testCandidate:sender];
        }
    };

    if (!staticKnown || isStatic) {
        execute();
        return;
    }
    ZNM462EnsureInstance(self, candidate, sender, execute);
}

@end

static void ZNM462UISwap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallM462CandidateBindingUIDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNM462UISwap(cls, @selector(zn60v3_renderResultsAtWidth:), @selector(znm462_renderResultsAtWidth:));
        [[ZNRuntimeLogger sharedLogger] log:@"[m4.6.2-candidate-binding] structural explicit binding layer installed"];
    });
}

#pragma mark - END ZNM462CandidateBindingUI.mm


#pragma mark - BEGIN ZNM47ReceiverCaptureUI.mm
#line 1 "ZNM47ReceiverCaptureUI.mm"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

#import "ZNIL2CPPInstanceResolver.h"
#import "ZNIL2CPPInstanceSelectionV2.h"
#import "ZNIL2CPPResolver.h"
#import "ZNM47ReceiverCapture.h"
#import "ZNPatchCore.h"

static const void *kZNM47CaptureCandidateKey = &kZNM47CaptureCandidateKey;
static const uint32_t kZNM47MethodAttributeStatic = 0x0010u;
typedef uint32_t (*ZNM47MethodGetFlagsFn)(const void *, uint32_t *);

static NSArray<NSDictionary *> *ZNM47VisibleCandidates(ZNRuntimeMenuControllerV040 *controller) {
    NSArray<NSDictionary *> *all = [controller zn60v3_candidates] ?: @[];
    NSInteger filter = [controller znm42_filter];
    NSMutableArray<NSDictionary *> *visible = [NSMutableArray array];
    for (NSDictionary *candidate in all) {
        if (filter < 0 || [candidate[@"argumentCount"] integerValue] == filter) [visible addObject:candidate];
    }
    return visible;
}

static void ZNM47CollectBoundTestButtons(UIView *root,
                                         id target,
                                         NSMutableArray<UIButton *> *buttons) {
    for (UIView *child in root.subviews) {
        if ([child isKindOfClass:UIButton.class]) {
            UIButton *button = (UIButton *)child;
            NSArray<NSString *> *actions = [button actionsForTarget:target forControlEvent:UIControlEventTouchUpInside] ?: @[];
            if ([actions containsObject:NSStringFromSelector(@selector(znm462_boundTestCandidate:))]) [buttons addObject:button];
        }
        ZNM47CollectBoundTestButtons(child, target, buttons);
    }
}

static void *ZNM47Symbol(NSString *path, const char *name) {
    void *symbol = dlsym(RTLD_DEFAULT, name);
    if (symbol || !path.length) return symbol;
#ifdef RTLD_NOLOAD
    void *handle = dlopen(path.fileSystemRepresentation, RTLD_LAZY | RTLD_NOLOAD);
#else
    void *handle = dlopen(path.fileSystemRepresentation, RTLD_LAZY);
#endif
    return handle ? dlsym(handle, name) : NULL;
}

static BOOL ZNM47CandidateIsInstance(NSDictionary *candidate) {
    uintptr_t methodInfo = [candidate[@"methodInfo"] unsignedLongLongValue];
    if (!methodInfo) return NO;
    ZNIL2CPPResolver *resolver = [ZNIL2CPPResolver sharedResolver];
    [resolver refresh];
    ZNM47MethodGetFlagsFn getFlags = (ZNM47MethodGetFlagsFn)ZNM47Symbol(resolver.unityPath, "il2cpp_method_get_flags");
    if (!getFlags) return NO;
    uint32_t implFlags = 0;
    uint32_t flags = getFlags((const void *)methodInfo, &implFlags);
    return (flags & kZNM47MethodAttributeStatic) == 0;
}

@interface ZNRuntimeMenuControllerV040 (ZNM47ReceiverCaptureUI)
- (void)znm47_renderResultsAtWidth:(CGFloat)width;
- (void)znm47_captureLongPress:(UILongPressGestureRecognizer *)gesture;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM47ReceiverCaptureUI)

- (void)znm47_renderResultsAtWidth:(CGFloat)width {
    [self znm47_renderResultsAtWidth:width];

    NSArray<NSDictionary *> *visible = ZNM47VisibleCandidates(self);
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    ZNM47CollectBoundTestButtons(self.contentView, self, buttons);
    if (!visible.count || visible.count != buttons.count) return;

    NSUInteger armed = 0;
    for (NSUInteger i = 0; i < visible.count; i++) {
        NSDictionary *candidate = visible[i];
        UIButton *button = buttons[i];
        if (!ZNM47CandidateIsInstance(candidate)) continue;
        uintptr_t methodPointer = [candidate[@"methodPointer"] unsignedLongLongValue];
        if (!methodPointer || (methodPointer & 3ULL)) continue;

        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(znm47_captureLongPress:)];
        longPress.minimumPressDuration = 0.65;
        longPress.cancelsTouchesInView = YES;
        objc_setAssociatedObject(longPress, kZNM47CaptureCandidateKey, candidate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [button addGestureRecognizer:longPress];
        [button setTitle:@"测试/捕获" forState:UIControlStateNormal];
        armed++;
    }
    if (armed) {
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.7-receiver-ui] capture gesture armed on %lu instance method buttons", (unsigned long)armed]];
    }
}

- (void)znm47_captureLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    NSDictionary *candidate = objc_getAssociatedObject(gesture, kZNM47CaptureCandidateKey);
    if (!candidate) return;

    if (ZNM47ReceiverCaptureBusy()) {
        [self zn60v3_setStatus:@"M4.7 Receiver Capture：已有捕获任务运行中"];
        [self renderPage];
        return;
    }

    NSString *assembly = [candidate[@"assembly"] isKindOfClass:NSString.class] ? candidate[@"assembly"] : @"Assembly-CSharp.dll";
    NSString *namespaceName = [candidate[@"namespace"] isKindOfClass:NSString.class] ? candidate[@"namespace"] : @"";
    NSString *className = [candidate[@"class"] isKindOfClass:NSString.class] ? candidate[@"class"] : @"";
    NSString *methodName = [candidate[@"method"] isKindOfClass:NSString.class] ? candidate[@"method"] : @"Method";

    __weak typeof(self) weakSelf = self;
    NSString *startError = nil;
    BOOL started = ZNM47StartReceiverCapture(candidate, 5.0, ^(uintptr_t receiver, NSString *captureError) {
        ZNRuntimeMenuControllerV040 *strong = weakSelf;
        if (!strong) return;
        if (!receiver) {
            [strong zn60v3_setStatus:captureError ?: @"M4.7 Receiver Capture：未捕获到实例"];
            [strong renderPage];
            return;
        }

        ZNIL2CPPInstanceResolver *resolver = [ZNIL2CPPInstanceResolver sharedResolver];
        NSString *validationError = nil;
        if (![resolver znm44_validateInstanceAddress:receiver
                                           assembly:assembly
                                          namespace:namespaceName
                                          className:className
                                              error:&validationError]) {
            [strong zn60v3_setStatus:[NSString stringWithFormat:@"M4.7 捕获到 x0=0x%llX，但类型验证失败：%@",
                                      (unsigned long long)receiver,
                                      validationError ?: @"unknown"]];
            [strong renderPage];
            return;
        }

        NSString *selectionError = nil;
        if (![resolver znm44_selectInstanceAddress:receiver
                                          assembly:assembly
                                         namespace:namespaceName
                                         className:className
                                             error:&selectionError]) {
            [strong zn60v3_setStatus:selectionError ?: @"M4.7：捕获 receiver 保存失败"];
            [strong renderPage];
            return;
        }

        [strong zn60v3_setStatus:[NSString stringWithFormat:@"M4.7 捕获成功：%@.%@ receiver=0x%llX；现在可直接点测试执行",
                                  className.length ? className : @"?",
                                  methodName,
                                  (unsigned long long)receiver]];
        [strong renderPage];
    }, &startError);

    if (!started) {
        [self zn60v3_setStatus:startError ?: @"M4.7 Receiver Capture 启动失败"];
        [self renderPage];
        return;
    }

    [self zn60v3_setStatus:[NSString stringWithFormat:@"M4.7 捕获中（5 秒）：请在游戏里触发 %@.%@；捕获的是 ARM64 x0/this",
                            className.length ? className : @"?",
                            methodName]];
    [self renderPage];
}

@end

static void ZNM47ReceiverUISwap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallM47ReceiverCaptureUIDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNM47ReceiverUISwap(cls, @selector(zn60v3_renderResultsAtWidth:), @selector(znm47_renderResultsAtWidth:));
        [[ZNRuntimeLogger sharedLogger] log:@"[m4.7-receiver-ui] long-press receiver capture layer installed"];
    });
}

#pragma mark - END ZNM47ReceiverCaptureUI.mm


#pragma mark - BEGIN ZNM47MultiArgUI.mm
#line 1 "ZNM47MultiArgUI.mm"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNIL2CPPABIMetadata.h"
#import "ZNIL2CPPMethodSignature.h"
#import "ZNRuntimeActionFormat.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

static const void *kZNM47ArgumentKey = &kZNM47ArgumentKey;
static const NSInteger kZNM47ArgumentTagBase = 647200;

static NSString *ZNM47DisplayAssembly(NSString *assembly) {
    NSString *s = assembly ?: @"";
    return [s.lowercaseString hasSuffix:@".dll"] && s.length > 4 ? [s substringToIndex:s.length - 4] : s;
}

static NSString *ZNM47CandidateIdentity(NSDictionary *candidate) {
    NSString *canonical = [candidate[@"canonical"] isKindOfClass:NSString.class] ? candidate[@"canonical"] : @"";
    if (canonical.length) return canonical;
    return [NSString stringWithFormat:@"%@|%@|%@|%@|%@",
            candidate[@"assembly"] ?: @"", candidate[@"namespace"] ?: @"", candidate[@"class"] ?: @"",
            candidate[@"method"] ?: @"", candidate[@"argumentCount"] ?: @(-1)];
}

static NSString *ZNM47ArgumentStoreKey(NSDictionary *candidate, NSUInteger index) {
    return [NSString stringWithFormat:@"%@#arg:%lu", ZNM47CandidateIdentity(candidate), (unsigned long)index];
}

static NSArray<NSDictionary *> *ZNM47Visible(ZNRuntimeMenuControllerV040 *controller) {
    NSArray<NSDictionary *> *all = [controller zn60v3_candidates] ?: @[];
    NSInteger filter = [controller znm42_filter];
    NSMutableArray *visible = [NSMutableArray array];
    for (NSDictionary *candidate in all) if (filter < 0 || [candidate[@"argumentCount"] integerValue] == filter) [visible addObject:candidate];
    return visible;
}

static void ZNM47CollectBoundButtons(UIView *root, id target, NSMutableArray<UIButton *> *out) {
    for (UIView *child in root.subviews) {
        if ([child isKindOfClass:UIButton.class]) {
            UIButton *button = (UIButton *)child;
            NSArray<NSString *> *actions = [button actionsForTarget:target forControlEvent:UIControlEventTouchUpInside] ?: @[];
            if ([actions containsObject:NSStringFromSelector(@selector(znm462_boundTestCandidate:))]) [out addObject:button];
        }
        ZNM47CollectBoundButtons(child, target, out);
    }
}

static UIButton *ZNM47CreateButton(UIView *card) {
    for (UIView *view in card.subviews) {
        if (![view isKindOfClass:UIButton.class]) continue;
        UIButton *button = (UIButton *)view;
        if ([[button titleForState:UIControlStateNormal] isEqualToString:@"创建方法"]) return button;
    }
    return nil;
}

static UILabel *ZNM47LabelWithText(UIView *card, NSString *text) {
    for (UIView *view in card.subviews) {
        if ([view isKindOfClass:UILabel.class] && [((UILabel *)view).text isEqualToString:text]) return (UILabel *)view;
    }
    return nil;
}

static CGFloat ZNM47Bottom(UIView *root) {
    CGFloat bottom = 0;
    for (UIView *view in root.subviews) bottom = MAX(bottom, CGRectGetMaxY(view.frame));
    return bottom;
}

static NSString *ZNM47ShortType(NSString *type) {
    NSArray<NSString *> *parts = [type ?: @"" componentsSeparatedByString:@"."];
    NSString *last = parts.lastObject;
    return last.length ? last : (type ?: @"?");
}

static NSUInteger ZNM47StructCount(NSString *type) {
    NSString *n = [type ?: @"" lowercaseString];
    if ([n isEqualToString:@"unityengine.vector2"] || [n isEqualToString:@"vector2"]) return 2;
    if ([n isEqualToString:@"unityengine.vector3"] || [n isEqualToString:@"vector3"]) return 3;
    if ([n isEqualToString:@"unityengine.quaternion"] || [n isEqualToString:@"quaternion"] ||
        [n isEqualToString:@"unityengine.color"] || [n isEqualToString:@"color"]) return 4;
    return 0;
}

static BOOL ZNM47IsString(NSString *type) {
    NSString *n = [type ?: @"" lowercaseString];
    return [n isEqualToString:@"system.string"] || [n isEqualToString:@"string"];
}

static NSString *ZNM47UnsupportedReason(NSDictionary *param) {
    if ([param[@"byRef"] boolValue]) return @"ref/out 暂不支持";
    if ([param[@"pointer"] boolValue]) return @"pointer 暂不支持";
    NSString *type = param[@"name"] ?: @"?";
    if (ZNM47IsString(type)) return nil;
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
            return ZNM47StructCount(type) ? nil : [NSString stringWithFormat:@"%@ 暂不支持", ZNM47ShortType(type)];
        case ZNIL2CPPABIValueKindObjectReference:
            return [NSString stringWithFormat:@"%@ 对象参数暂不支持", ZNM47ShortType(type)];
        default:
            return [NSString stringWithFormat:@"%@ 类型未识别", ZNM47ShortType(type)];
    }
}

static UITextField *ZNM47Field(CGRect frame, ZNTheme *theme, UIFont *font) {
    UITextField *field = [[UITextField alloc] initWithFrame:frame];
    field.textColor = theme.primaryTextColor;
    field.backgroundColor = theme.controlColor;
    field.tintColor = theme.accentColor;
    field.font = font;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.returnKeyType = UIReturnKeyDone;
    field.layer.cornerRadius = 6.0;
    field.layer.borderWidth = 1.0;
    field.layer.borderColor = theme.borderColor.CGColor;
    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 7, 1)];
    field.leftView = pad;
    field.leftViewMode = UITextFieldViewModeAlways;
    return field;
}

@interface ZNRuntimeMenuControllerV040 (ZNM47MultiArgUI)
- (void)znm47ma_renderResultsAtWidth:(CGFloat)width;
- (NSArray<NSString *> *)znm47ma_argumentValues:(NSDictionary *)candidate;
- (void)znm47ma_argumentChanged:(UITextField *)field;
- (void)znm47ma_done:(UITextField *)field;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM47MultiArgUI)

- (NSArray<NSString *> *)znm47ma_argumentValues:(NSDictionary *)candidate {
    NSUInteger argc = [candidate[@"argumentCount"] unsignedIntegerValue];
    if (argc < 2) return [self znm47ma_argumentValues:candidate];
    if (argc > ZN_RUNTIME_ACTION_MAX_ARGUMENTS) return @[];
    NSMutableArray<NSString *> *values = [NSMutableArray arrayWithCapacity:argc];
    for (NSUInteger i = 0; i < argc; i++) [values addObject:[self znm42_inputStore][ZNM47ArgumentStoreKey(candidate, i)] ?: @""];
    return [values copy];
}

- (void)znm47ma_argumentChanged:(UITextField *)field {
    NSString *key = objc_getAssociatedObject(field, kZNM47ArgumentKey);
    if (key.length) [self znm42_inputStore][key] = field.text ?: @"";
}

- (void)znm47ma_done:(UITextField *)field {
    [self znm47ma_argumentChanged:field];
    [field resignFirstResponder];
}

- (void)znm47ma_renderResultsAtWidth:(CGFloat)width {
    [self znm47ma_renderResultsAtWidth:width];

    NSArray<NSDictionary *> *visible = ZNM47Visible(self);
    NSMutableArray<UIButton *> *testButtons = [NSMutableArray array];
    ZNM47CollectBoundButtons(self.contentView, self, testButtons);
    if (!visible.count || visible.count != testButtons.count) return;

    for (NSUInteger i = 0; i < visible.count; i++) {
        NSDictionary *candidate = visible[i];
        NSUInteger argc = [candidate[@"argumentCount"] unsignedIntegerValue];
        if (argc < 2 || argc > ZN_RUNTIME_ACTION_MAX_ARGUMENTS) continue;

        UIButton *test = testButtons[i];
        UIView *card = test.superview;
        if (!card || card.superview != self.contentView) continue;
        UIButton *create = ZNM47CreateButton(card);

        NSDictionary *abi = ZNIL2CPPDescribeMethodABI(candidate);
        NSArray<NSDictionary *> *params = [abi[@"parameters"] isKindOfClass:NSArray.class] ? abi[@"parameters"] : nil;
        BOOL metadataOK = [abi[@"available"] boolValue] && params.count == argc && !([abi[@"genericStatusKnown"] boolValue] && [abi[@"generic"] boolValue]);
        BOOL callable = metadataOK;
        NSMutableArray<NSString *> *types = [NSMutableArray arrayWithCapacity:argc];
        if (metadataOK) {
            for (NSDictionary *param in params) {
                NSString *type = param[@"name"] ?: @"?";
                [types addObject:type];
                if (ZNM47UnsupportedReason(param).length) callable = NO;
            }
        }

        CGFloat oldBottom = CGRectGetMaxY(card.frame);
        CGFloat oldHeight = CGRectGetHeight(card.frame);
        CGFloat leftRight = CGRectGetMinX(test.frame) - 8.0;
        CGFloat inputY = 54.0;
        CGFloat rowStep = 34.0;

        for (NSUInteger arg = 0; arg < argc; arg++) {
            NSDictionary *param = metadataOK ? params[arg] : nil;
            NSString *type = param ? (param[@"name"] ?: @"?") : @"?";
            NSString *name = param ? (param[@"paramName"] ?: @"") : @"";
            NSString *reason = param ? ZNM47UnsupportedReason(param) : (abi[@"reason"] ?: @"参数 ABI 不可用");
            CGRect frame = CGRectMake(13.0, inputY + arg * rowStep, MAX(60.0, leftRight - 13.0), 28.0);
            if (!reason.length) {
                UITextField *field = ZNM47Field(frame, self.theme, [self menuFont:8.9 weight:UIFontWeightMedium]);
                NSString *shortType = ZNM47ShortType(type);
                field.placeholder = name.length
                    ? [NSString stringWithFormat:@"参数%lu · %@ · %@", (unsigned long)arg + 1, name, shortType]
                    : [NSString stringWithFormat:@"参数%lu · %@", (unsigned long)arg + 1, shortType];
                NSString *key = ZNM47ArgumentStoreKey(candidate, arg);
                field.text = [self znm42_inputStore][key] ?: @"";
                field.keyboardType = ZNM47IsString(type) ? UIKeyboardTypeDefault : UIKeyboardTypeNumbersAndPunctuation;
                field.tag = kZNM47ArgumentTagBase + (NSInteger)arg;
                objc_setAssociatedObject(field, kZNM47ArgumentKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
                [field addTarget:self action:@selector(znm47ma_argumentChanged:) forControlEvents:UIControlEventEditingChanged];
                [field addTarget:self action:@selector(znm47ma_done:) forControlEvents:UIControlEventEditingDidEndOnExit];
                [card addSubview:field];
            } else {
                UILabel *label = [[UILabel alloc] initWithFrame:frame];
                label.text = [NSString stringWithFormat:@"参数%lu · %@ · %@", (unsigned long)arg + 1, ZNM47ShortType(type), reason];
                label.textColor = self.theme.secondaryTextColor;
                label.font = [self menuFont:8.2 weight:UIFontWeightRegular];
                label.lineBreakMode = NSLineBreakByTruncatingMiddle;
                [card addSubview:label];
            }
        }

        NSString *assemblyText = ZNM47DisplayAssembly(candidate[@"assembly"] ?: @"?");
        UILabel *assembly = ZNM47LabelWithText(card, assemblyText);
        NSString *signatureText = metadataOK ? ZNIL2CPPShortSignature(candidate[@"method"] ?: @"Method", types) : nil;
        UILabel *signature = signatureText.length ? ZNM47LabelWithText(card, signatureText) : nil;

        CGFloat signatureY = inputY + argc * rowStep;
        if (signature) {
            CGRect f = signature.frame; f.origin.y = signatureY; signature.frame = f;
        }
        CGFloat assemblyY = signatureY + (signature ? 17.0 : 0.0);
        if (assembly) {
            CGRect f = assembly.frame; f.origin.y = assemblyY; assembly.frame = f;
        }
        CGFloat desiredHeight = assemblyY + 22.0;
        if (desiredHeight < oldHeight) desiredHeight = oldHeight;
        CGFloat delta = desiredHeight - oldHeight;
        if (delta > 0.5) {
            CGRect f = card.frame; f.size.height = desiredHeight; card.frame = f;
            for (UIView *sibling in self.contentView.subviews) {
                if (sibling == card) continue;
                if (CGRectGetMinY(sibling.frame) + 0.5 < oldBottom) continue;
                CGRect sf = sibling.frame; sf.origin.y += delta; sibling.frame = sf;
            }
        }

        test.enabled = callable;
        test.alpha = callable ? 1.0 : 0.48;
        if (create) { create.enabled = callable; create.alpha = callable ? 1.0 : 0.48; }
    }

    [self zn40_updateContentHeight:ZNM47Bottom(self.contentView) + 8.0];
}

@end

static void ZNM47UISwap(Class cls, SEL a, SEL b) {
    Method ma = class_getInstanceMethod(cls, a), mb = class_getInstanceMethod(cls, b);
    if (ma && mb) method_exchangeImplementations(ma, mb);
}

extern "C" void ZNInstallM47MultiArgUIDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNM47UISwap(cls, @selector(zn60v3_renderResultsAtWidth:), @selector(znm47ma_renderResultsAtWidth:));
        ZNM47UISwap(cls, @selector(znm43_argumentValues:), @selector(znm47ma_argumentValues:));
        [[ZNRuntimeLogger sharedLogger] log:@"[m4.7-multiarg-ui] /2-/8 dynamic parameter rows installed"];
    });
}

#pragma mark - END ZNM47MultiArgUI.mm


#pragma mark - BEGIN ZNM47BuilderArgsUI.mm
#line 1 "ZNM47BuilderArgsUI.mm"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNRuntimeActionFormat.h"
#import "ZNRuntimeActionModel.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

static const NSInteger kZNM47BuilderTitleTagBase = 672000;
static const NSInteger kZNM47BuilderArgTagBase = 690000;
static const void *kZNM47BuilderActionIndexKey = &kZNM47BuilderActionIndexKey;
static const void *kZNM47BuilderArgumentIndexKey = &kZNM47BuilderArgumentIndexKey;

static CGFloat ZNM47BuilderBottom(UIView *root) {
    CGFloat y = 0;
    for (UIView *view in root.subviews) y = MAX(y, CGRectGetMaxY(view.frame));
    return y;
}

static UITextField *ZNM47BuilderField(CGRect frame, ZNTheme *theme) {
    UITextField *field = [[UITextField alloc] initWithFrame:frame];
    field.textColor = theme.primaryTextColor;
    field.backgroundColor = theme.controlColor;
    field.tintColor = theme.accentColor;
    field.font = [UIFont monospacedDigitSystemFontOfSize:9.2 weight:UIFontWeightMedium];
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.returnKeyType = UIReturnKeyDone;
    field.layer.cornerRadius = 6.0;
    field.layer.borderWidth = 1.0;
    field.layer.borderColor = theme.borderColor.CGColor;
    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 6, 1)];
    field.leftView = pad;
    field.leftViewMode = UITextFieldViewModeAlways;
    return field;
}

static UITextField *ZNM47FindTitleField(UIView *root, NSUInteger index) {
    NSInteger tag = kZNM47BuilderTitleTagBase + (NSInteger)index;
    for (UIView *view in root.subviews) {
        if ([view isKindOfClass:UITextField.class] && view.tag == tag) return (UITextField *)view;
        UITextField *nested = ZNM47FindTitleField(view, index);
        if (nested) return nested;
    }
    return nil;
}

@interface ZNRuntimeMenuControllerV040 (ZNM47BuilderArgsUI)
- (void)znm47b_renderOther;
- (void)znm47b_argumentEnded:(UITextField *)field;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM47BuilderArgsUI)

- (void)znm47b_renderOther {
    [self znm47b_renderOther];

    NSArray<ZNRuntimeMethodAction *> *actions = [[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    for (NSUInteger i = 0; i < actions.count; i++) {
        ZNRuntimeMethodAction *action = actions[i];
        if (action.argumentCount < 2 || action.argumentCount > ZN_RUNTIME_ACTION_MAX_ARGUMENTS) continue;

        UITextField *titleField = ZNM47FindTitleField(self.contentView, i);
        UIView *card = titleField.superview;
        if (!card || card.superview != self.contentView) continue;

        CGFloat oldBottom = CGRectGetMaxY(card.frame);
        CGFloat oldHeight = CGRectGetHeight(card.frame);
        CGFloat rowY = 68.0;
        CGFloat rowStep = 34.0;

        for (NSUInteger arg = 0; arg < action.argumentCount; arg++) {
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(13, rowY + arg * rowStep, 48, 28)];
            NSString *type = (action.parameterTypeNames.count == action.argumentCount) ? action.parameterTypeNames[arg] : @"?";
            NSArray<NSString *> *parts = [type componentsSeparatedByString:@"."];
            NSString *last = parts.lastObject;
            NSString *shortType = last.length ? last : type;
            label.text = [NSString stringWithFormat:@"参数%lu", (unsigned long)arg + 1];
            label.textColor = self.theme.secondaryTextColor;
            label.font = [UIFont systemFontOfSize:8.2 weight:UIFontWeightSemibold];
            [card addSubview:label];

            UITextField *field = ZNM47BuilderField(CGRectMake(60, rowY + arg * rowStep, card.bounds.size.width - 73, 28), self.theme);
            field.tag = kZNM47BuilderArgTagBase + (NSInteger)(i * ZN_RUNTIME_ACTION_MAX_ARGUMENTS + arg);
            field.text = action.argumentValues.count == action.argumentCount ? action.argumentValues[arg] : @"";
            field.placeholder = [NSString stringWithFormat:@"参数%lu · %@", (unsigned long)arg + 1, shortType ?: @"?"];
            objc_setAssociatedObject(field, kZNM47BuilderActionIndexKey, @(i), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(field, kZNM47BuilderArgumentIndexKey, @(arg), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [field addTarget:self action:@selector(znm47b_argumentEnded:) forControlEvents:UIControlEventEditingDidEndOnExit | UIControlEventEditingDidEnd];
            [card addSubview:field];
        }

        CGFloat desired = rowY + action.argumentCount * rowStep + 5.0;
        CGFloat delta = MAX(0.0, desired - oldHeight);
        if (delta > 0.5) {
            CGRect frame = card.frame; frame.size.height = desired; card.frame = frame;
            for (UIView *sibling in self.contentView.subviews) {
                if (sibling == card) continue;
                if (CGRectGetMinY(sibling.frame) + 0.5 < oldBottom) continue;
                CGRect sf = sibling.frame; sf.origin.y += delta; sibling.frame = sf;
            }
        }
    }
    [self zn40_updateContentHeight:ZNM47BuilderBottom(self.contentView) + 8.0];
}

- (void)znm47b_argumentEnded:(UITextField *)field {
    NSNumber *actionIndexNumber = objc_getAssociatedObject(field, kZNM47BuilderActionIndexKey);
    NSNumber *argumentIndexNumber = objc_getAssociatedObject(field, kZNM47BuilderArgumentIndexKey);
    if (!actionIndexNumber || !argumentIndexNumber) return;
    NSUInteger actionIndex = actionIndexNumber.unsignedIntegerValue;
    NSUInteger argumentIndex = argumentIndexNumber.unsignedIntegerValue;
    NSArray<ZNRuntimeMethodAction *> *actions = [[ZNRuntimeActionStore sharedStore] actionsSnapshot];
    if (actionIndex >= actions.count) return;
    ZNRuntimeMethodAction *action = actions[actionIndex];
    if (argumentIndex >= action.argumentCount) return;

    NSMutableArray<NSString *> *values = [NSMutableArray arrayWithCapacity:action.argumentCount];
    for (NSUInteger i = 0; i < action.argumentCount; i++) {
        NSString *value = (action.argumentValues.count == action.argumentCount) ? action.argumentValues[i] : @"";
        [values addObject:value ?: @""];
    }
    values[argumentIndex] = field.text ?: @"";
    NSString *error = nil;
    if (![[ZNRuntimeActionStore sharedStore] updateArgumentValues:values atIndex:actionIndex error:&error]) {
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.7-builder-args] update failed index=%lu arg=%lu error=%@",
                                             (unsigned long)actionIndex, (unsigned long)argumentIndex, error ?: @"unknown"]];
    }
    [field resignFirstResponder];
}

@end

static void ZNM47BuilderSwap(Class cls, SEL a, SEL b) {
    Method ma = class_getInstanceMethod(cls, a), mb = class_getInstanceMethod(cls, b);
    if (ma && mb) method_exchangeImplementations(ma, mb);
}

extern "C" void ZNInstallM47BuilderArgsUIDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNM47BuilderSwap(cls, @selector(zn50b_renderOther), @selector(znm47b_renderOther));
        [[ZNRuntimeLogger sharedLogger] log:@"[m4.7-builder-args] /2-/8 Builder parameter editor installed"];
    });
}

#pragma mark - END ZNM47BuilderArgsUI.mm


#pragma mark - BEGIN ZNM47VersionUI.mm
#line 1 "ZNM47VersionUI.mm"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNBuildVersion.h"
#import "ZNPatchCore.h"

@implementation ZNRuntimeMenuControllerV040 (ZNM47VersionUI)

- (void)znm47_tick:(NSTimer *)timer {
    [self znm47_tick:timer];
    if (!self.uiReady || !self.footerLabel) return;
    self.footerLabel.text = [NSString stringWithFormat:@"PatchCore %@    %@    iOS %@",
                            ZN_MENU_VERSION_DISPLAY,
                            ZN_MENU_VERSION_FEATURE,
                            UIDevice.currentDevice.systemVersion];
}

@end

static void ZNM47VersionSwap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallM47VersionUIDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZNM47VersionSwap(cls, @selector(tick:), @selector(znm47_tick:));
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.7-version] footer version source installed %@", ZN_MENU_VERSION_DISPLAY]];
    });
}

#pragma mark - END ZNM47VersionUI.mm
