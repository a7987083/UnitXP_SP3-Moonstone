#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, ZNThemeMode) {
    ZNThemeModeSystem = 0,
    ZNThemeModeObsidian = 1,
    ZNThemeModeNeon = 2,
    ZNThemeModeGlacier = 3,
    ZNThemeModeAmber = 4,
    ZNThemeModeMatcha = 5,
};

@interface ZNTheme : NSObject

@property(nonatomic, assign, readonly) ZNThemeMode mode;
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, assign, readonly) BOOL lightAppearance;
@property(nonatomic, assign, readonly) BOOL neonAppearance;
@property(nonatomic, assign, readonly) BOOL mechanicalAppearance;

@property(nonatomic, strong, readonly) UIColor *panelColor;
@property(nonatomic, strong, readonly) UIColor *headerColor;
@property(nonatomic, strong, readonly) UIColor *sidebarColor;
@property(nonatomic, strong, readonly) UIColor *cardColor;
@property(nonatomic, strong, readonly) UIColor *popoverColor;
@property(nonatomic, strong, readonly) UIColor *controlColor;
@property(nonatomic, strong, readonly) UIColor *footerColor;
@property(nonatomic, strong, readonly) UIColor *primaryTextColor;
@property(nonatomic, strong, readonly) UIColor *secondaryTextColor;
@property(nonatomic, strong, readonly) UIColor *accentColor;
@property(nonatomic, strong, readonly) UIColor *accent2Color;
@property(nonatomic, strong, readonly) UIColor *separatorColor;
@property(nonatomic, strong, readonly) UIColor *borderColor;
@property(nonatomic, strong, readonly) UIColor *selectedColor;
@property(nonatomic, strong, readonly) UIColor *trackColor;
@property(nonatomic, strong, readonly) UIColor *floatColor;
@property(nonatomic, strong, readonly) UIColor *shadowColor;

+ (NSArray<NSString *> *)themeNames;
+ (NSString *)nameForMode:(ZNThemeMode)mode;
+ (UIColor *)indicatorColorForMode:(ZNThemeMode)mode;
+ (ZNTheme *)themeForMode:(ZNThemeMode)mode interfaceStyle:(UIUserInterfaceStyle)style;

@end
