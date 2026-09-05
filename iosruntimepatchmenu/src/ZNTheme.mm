#import "ZNTheme.h"

static UIColor *ZNHexColor(uint32_t rgb, CGFloat alpha) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:alpha];
}

@interface ZNTheme ()
@property(nonatomic, assign, readwrite) ZNThemeMode mode;
@property(nonatomic, copy, readwrite) NSString *name;
@property(nonatomic, assign, readwrite) BOOL lightAppearance;
@property(nonatomic, assign, readwrite) BOOL neonAppearance;
@property(nonatomic, assign, readwrite) BOOL mechanicalAppearance;
@property(nonatomic, strong, readwrite) UIColor *panelColor;
@property(nonatomic, strong, readwrite) UIColor *headerColor;
@property(nonatomic, strong, readwrite) UIColor *sidebarColor;
@property(nonatomic, strong, readwrite) UIColor *cardColor;
@property(nonatomic, strong, readwrite) UIColor *popoverColor;
@property(nonatomic, strong, readwrite) UIColor *controlColor;
@property(nonatomic, strong, readwrite) UIColor *footerColor;
@property(nonatomic, strong, readwrite) UIColor *primaryTextColor;
@property(nonatomic, strong, readwrite) UIColor *secondaryTextColor;
@property(nonatomic, strong, readwrite) UIColor *accentColor;
@property(nonatomic, strong, readwrite) UIColor *accent2Color;
@property(nonatomic, strong, readwrite) UIColor *separatorColor;
@property(nonatomic, strong, readwrite) UIColor *borderColor;
@property(nonatomic, strong, readwrite) UIColor *selectedColor;
@property(nonatomic, strong, readwrite) UIColor *trackColor;
@property(nonatomic, strong, readwrite) UIColor *floatColor;
@property(nonatomic, strong, readwrite) UIColor *shadowColor;
@end

@implementation ZNTheme

+ (NSArray<NSString *> *)themeNames {
    return @[@"跟随系统", @"曜石暗夜", @"霓虹赛博", @"冰川蓝图", @"琥珀机械", @"抹茶极简"];
}

+ (NSString *)nameForMode:(ZNThemeMode)mode {
    NSArray *names = [self themeNames];
    NSInteger index = MAX(0, MIN((NSInteger)names.count - 1, (NSInteger)mode));
    return names[index];
}

+ (UIColor *)indicatorColorForMode:(ZNThemeMode)mode {
    switch (mode) {
        case ZNThemeModeSystem:   return ZNHexColor(0xB8BEC8, 1.0);
        case ZNThemeModeObsidian: return ZNHexColor(0x18243B, 1.0);
        case ZNThemeModeNeon:     return ZNHexColor(0xA73CFF, 1.0);
        case ZNThemeModeGlacier:  return ZNHexColor(0x3DBBEF, 1.0);
        case ZNThemeModeAmber:    return ZNHexColor(0xFFB12B, 1.0);
        case ZNThemeModeMatcha:   return ZNHexColor(0x45C663, 1.0);
    }
    return [UIColor grayColor];
}

+ (ZNTheme *)themeForMode:(ZNThemeMode)mode interfaceStyle:(UIUserInterfaceStyle)style {
    ZNTheme *t = [[ZNTheme alloc] init];
    t.mode = mode;
    t.name = [self nameForMode:mode];

    if (mode == ZNThemeModeSystem) {
        BOOL dark = (style == UIUserInterfaceStyleDark);
        t.lightAppearance = !dark;
        t.neonAppearance = NO;
        t.mechanicalAppearance = NO;
        if (dark) {
            t.panelColor = ZNHexColor(0x15181E, 0.96);
            t.headerColor = ZNHexColor(0x1A1E25, 0.98);
            t.sidebarColor = ZNHexColor(0x171A20, 0.96);
            t.cardColor = ZNHexColor(0x232831, 0.92);
            t.popoverColor = ZNHexColor(0x20242B, 0.99);
            t.controlColor = ZNHexColor(0x2B313B, 0.96);
            t.footerColor = ZNHexColor(0x171A20, 0.98);
            t.primaryTextColor = ZNHexColor(0xF3F5F8, 1.0);
            t.secondaryTextColor = ZNHexColor(0xAAB1BC, 1.0);
            t.accentColor = ZNHexColor(0x4B8DFF, 1.0);
            t.accent2Color = ZNHexColor(0x74A7FF, 1.0);
            t.separatorColor = ZNHexColor(0xFFFFFF, 0.10);
            t.borderColor = ZNHexColor(0xFFFFFF, 0.14);
            t.selectedColor = ZNHexColor(0x4B8DFF, 0.20);
            t.trackColor = ZNHexColor(0xFFFFFF, 0.12);
            t.floatColor = ZNHexColor(0x11151B, 0.98);
            t.shadowColor = ZNHexColor(0x000000, 0.50);
        } else {
            t.panelColor = ZNHexColor(0xF6F8FB, 0.97);
            t.headerColor = ZNHexColor(0xFBFCFE, 0.99);
            t.sidebarColor = ZNHexColor(0xF0F3F8, 0.98);
            t.cardColor = ZNHexColor(0xFFFFFF, 0.94);
            t.popoverColor = ZNHexColor(0xFFFFFF, 0.99);
            t.controlColor = ZNHexColor(0xEEF2F7, 0.98);
            t.footerColor = ZNHexColor(0xF3F6FA, 0.99);
            t.primaryTextColor = ZNHexColor(0x18202A, 1.0);
            t.secondaryTextColor = ZNHexColor(0x687383, 1.0);
            t.accentColor = ZNHexColor(0x3478F6, 1.0);
            t.accent2Color = ZNHexColor(0x64A0FF, 1.0);
            t.separatorColor = ZNHexColor(0x10233D, 0.10);
            t.borderColor = ZNHexColor(0x1B365A, 0.13);
            t.selectedColor = ZNHexColor(0x3478F6, 0.13);
            t.trackColor = ZNHexColor(0x193A67, 0.11);
            t.floatColor = ZNHexColor(0x244B84, 0.98);
            t.shadowColor = ZNHexColor(0x45678E, 0.24);
        }
        return t;
    }

    if (mode == ZNThemeModeObsidian) {
        t.lightAppearance = NO;
        t.neonAppearance = NO;
        t.mechanicalAppearance = NO;
        t.panelColor = ZNHexColor(0x11151B, 0.965);
        t.headerColor = ZNHexColor(0x171B21, 0.99);
        t.sidebarColor = ZNHexColor(0x14181E, 0.98);
        t.cardColor = ZNHexColor(0x20262E, 0.93);
        t.popoverColor = ZNHexColor(0x1A1F26, 0.995);
        t.controlColor = ZNHexColor(0x2B323C, 0.96);
        t.footerColor = ZNHexColor(0x171B21, 0.99);
        t.primaryTextColor = ZNHexColor(0xF2F4F7, 1.0);
        t.secondaryTextColor = ZNHexColor(0x9DA6B3, 1.0);
        t.accentColor = ZNHexColor(0x4D8DFF, 1.0);
        t.accent2Color = ZNHexColor(0x79A8FF, 1.0);
        t.separatorColor = ZNHexColor(0xFFFFFF, 0.09);
        t.borderColor = ZNHexColor(0x8792A3, 0.35);
        t.selectedColor = ZNHexColor(0x4D8DFF, 0.20);
        t.trackColor = ZNHexColor(0xFFFFFF, 0.12);
        t.floatColor = ZNHexColor(0x151A22, 0.99);
        t.shadowColor = ZNHexColor(0x000000, 0.58);
        return t;
    }

    if (mode == ZNThemeModeNeon) {
        t.lightAppearance = NO;
        t.neonAppearance = YES;
        t.mechanicalAppearance = NO;
        t.panelColor = ZNHexColor(0x080D1E, 0.96);
        t.headerColor = ZNHexColor(0x0D1530, 0.98);
        t.sidebarColor = ZNHexColor(0x091126, 0.97);
        t.cardColor = ZNHexColor(0x111B36, 0.91);
        t.popoverColor = ZNHexColor(0x0A1023, 0.995);
        t.controlColor = ZNHexColor(0x182345, 0.96);
        t.footerColor = ZNHexColor(0x0B1329, 0.99);
        t.primaryTextColor = ZNHexColor(0xF5F6FF, 1.0);
        t.secondaryTextColor = ZNHexColor(0x94ACDF, 1.0);
        t.accentColor = ZNHexColor(0xD12DFF, 1.0);
        t.accent2Color = ZNHexColor(0x21D8FF, 1.0);
        t.separatorColor = ZNHexColor(0x4E90FF, 0.26);
        t.borderColor = ZNHexColor(0x3D7FFF, 0.68);
        t.selectedColor = ZNHexColor(0xA527FF, 0.32);
        t.trackColor = ZNHexColor(0x5268A5, 0.28);
        t.floatColor = ZNHexColor(0x0B1020, 0.99);
        t.shadowColor = ZNHexColor(0x8D22FF, 0.80);
        return t;
    }

    if (mode == ZNThemeModeGlacier) {
        t.lightAppearance = YES;
        t.neonAppearance = NO;
        t.mechanicalAppearance = NO;
        t.panelColor = ZNHexColor(0xEAF4FF, 0.94);
        t.headerColor = ZNHexColor(0xE3F0FF, 0.97);
        t.sidebarColor = ZNHexColor(0xE7F2FF, 0.95);
        t.cardColor = ZNHexColor(0xFFFFFF, 0.72);
        t.popoverColor = ZNHexColor(0xF7FBFF, 0.99);
        t.controlColor = ZNHexColor(0xE4EFFB, 0.95);
        t.footerColor = ZNHexColor(0xE4F0FD, 0.98);
        t.primaryTextColor = ZNHexColor(0x0A356F, 1.0);
        t.secondaryTextColor = ZNHexColor(0x4C6F9F, 1.0);
        t.accentColor = ZNHexColor(0x3389F7, 1.0);
        t.accent2Color = ZNHexColor(0x30C2F4, 1.0);
        t.separatorColor = ZNHexColor(0x2760A5, 0.12);
        t.borderColor = ZNHexColor(0x7BA9DD, 0.38);
        t.selectedColor = ZNHexColor(0x3389F7, 0.15);
        t.trackColor = ZNHexColor(0x2E6EBA, 0.13);
        t.floatColor = ZNHexColor(0x1E4C91, 0.98);
        t.shadowColor = ZNHexColor(0x498FD6, 0.36);
        return t;
    }

    if (mode == ZNThemeModeAmber) {
        t.lightAppearance = NO;
        t.neonAppearance = NO;
        t.mechanicalAppearance = YES;
        t.panelColor = ZNHexColor(0x15120E, 0.97);
        t.headerColor = ZNHexColor(0x1B1711, 0.99);
        t.sidebarColor = ZNHexColor(0x18140F, 0.985);
        t.cardColor = ZNHexColor(0x242019, 0.95);
        t.popoverColor = ZNHexColor(0x1B1712, 0.997);
        t.controlColor = ZNHexColor(0x30291E, 0.98);
        t.footerColor = ZNHexColor(0x18140F, 0.99);
        t.primaryTextColor = ZNHexColor(0xFFF5E2, 1.0);
        t.secondaryTextColor = ZNHexColor(0xC8B89D, 1.0);
        t.accentColor = ZNHexColor(0xFFB52B, 1.0);
        t.accent2Color = ZNHexColor(0xD88312, 1.0);
        t.separatorColor = ZNHexColor(0xFFB52B, 0.20);
        t.borderColor = ZNHexColor(0xC98222, 0.58);
        t.selectedColor = ZNHexColor(0xFFB52B, 0.22);
        t.trackColor = ZNHexColor(0xBCA078, 0.18);
        t.floatColor = ZNHexColor(0x1B160F, 0.99);
        t.shadowColor = ZNHexColor(0xFF9C16, 0.45);
        return t;
    }

    t.lightAppearance = YES;
    t.neonAppearance = NO;
    t.mechanicalAppearance = NO;
    t.panelColor = ZNHexColor(0xF6F8F3, 0.97);
    t.headerColor = ZNHexColor(0xF8FAF6, 0.99);
    t.sidebarColor = ZNHexColor(0xF0F5ED, 0.98);
    t.cardColor = ZNHexColor(0xFFFFFF, 0.84);
    t.popoverColor = ZNHexColor(0xFBFCFA, 0.995);
    t.controlColor = ZNHexColor(0xEDF4EA, 0.98);
    t.footerColor = ZNHexColor(0xF2F6EF, 0.99);
    t.primaryTextColor = ZNHexColor(0x153A2B, 1.0);
    t.secondaryTextColor = ZNHexColor(0x617569, 1.0);
    t.accentColor = ZNHexColor(0x43B95D, 1.0);
    t.accent2Color = ZNHexColor(0x2D7B48, 1.0);
    t.separatorColor = ZNHexColor(0x315D43, 0.11);
    t.borderColor = ZNHexColor(0x8FB29A, 0.34);
    t.selectedColor = ZNHexColor(0x43B95D, 0.14);
    t.trackColor = ZNHexColor(0x426D50, 0.12);
    t.floatColor = ZNHexColor(0x285D3C, 0.98);
    t.shadowColor = ZNHexColor(0x5E8F6C, 0.28);
    return t;
}

@end
