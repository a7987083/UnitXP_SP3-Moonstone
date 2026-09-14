#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNTheme.h"
#import "ZNPatchCore.h"
#import "ZNStaticDispatchRuntime.h"
#import "ZNStaticPatchFormat.h"
#import "ZNFeatureMetadataCodec.h"

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

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIScrollView *contentScroll;
@property(nonatomic,copy) NSArray<NSString *> *categories;
@property(nonatomic,assign) NSInteger selectedCategory;
@property(nonatomic,strong) ZNTheme *theme;
- (UIView *)cardAtY:(CGFloat)y height:(CGFloat)h width:(CGFloat)w compact:(BOOL)compact;
- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)renderFullPage;
- (void)renderCompactPage;
- (void)renderPage;
@end

static const NSInteger kZN50FeatureToggleTagBase = 450000;

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
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray<ZNStaticPatchRecord *> *> *members = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *titles = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSNumber *> *featureIDs = [NSMutableDictionary dictionary];

    for (ZNStaticPatchRecord *record in records) {
        NSDictionary<NSString *, id> *display = ZN50DisplayMetadata(record);
        NSString *group = ZN50Trim(display[@"group"]);
        NSString *title = ZN50Trim(display[@"title"]);
        uint64_t featureID = [display[@"featureID"] unsignedLongLongValue];
        BOOL explicitFeature = [display[@"explicitGroup"] boolValue] ||
                               (group.length && [group caseInsensitiveCompare:@"Imported"] != NSOrderedSame);
        NSString *key = nil;

        if (featureID) {
            key = [NSString stringWithFormat:@"id:%016llx", featureID];
        } else if (explicitFeature) {
            key = [@"group:" stringByAppendingString:group.lowercaseString];
            title = group;
        } else {
            key = [NSString stringWithFormat:@"patch:%@:%u", record.target.lowercaseString ?: @"", record.patchID];
        }

        if (!members[key]) {
            members[key] = [NSMutableArray array];
            titles[key] = title.length ? title : [NSString stringWithFormat:@"功能 #%u", record.patchID];
            featureIDs[key] = @(featureID);
            [order addObject:key];
        }
        [members[key] addObject:record];
    }

    NSMutableArray<NSDictionary *> *result = [NSMutableArray arrayWithCapacity:order.count];
    for (NSString *key in order) {
        [result addObject:@{
            @"key": key,
            @"featureID": featureIDs[key] ?: @0,
            @"title": titles[key] ?: @"功能",
            @"records": [members[key] copy] ?: @[],
        }];
    }
    return result;
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
    } else {
        uint64_t featureID = [feature[@"featureID"] unsignedLongLongValue];
        NSString *preferenceKey = ZN50FeaturePreferenceKey(featureID);
        if (preferenceKey.length) [NSUserDefaults.standardUserDefaults setBool:desired forKey:preferenceKey];
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[feature] %@ %@ (%lu patches)", desired ? @"ON" : @"OFF", feature[@"title"] ?: @"功能", (unsigned long)records.count]];
    }
    [self renderPage];
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
