#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "ZNFeatureControlModel.h"
#import "ZNFeatureMetadataCodec.h"
#import "ZNStaticDispatchRuntime.h"
#import "ZNStaticPatchFormat.h"
#import "ZNTheme.h"
#import "ZNPatchCore.h"

// M2.2 public Feature-control renderer. Toggle keeps the proven Static Dispatch
// behavior. Number/Action/Slider are generic control surfaces that publish
// typed runtime events; later hook/invoke backends bind to those events without
// hard-coding game-specific names such as Damage/God Mode/Debug Menu.

static const NSInteger kZN65ToggleTagBase = 450000;
static const NSInteger kZN65NumberTagBase = 469000;
static const NSInteger kZN65ActionTagBase = 470000;
static const NSInteger kZN65SliderTagBase = 471000;

@interface ZNStaticPatchRecord (ZNFeatureRuntimeControlEntry)
@property(nonatomic,assign) ZN44StaticEntry *entry;
@end

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIWindow *hostWindow;
@property(nonatomic,strong) ZNTheme *theme;
- (UIButton *)zn40_button:(NSString *)title selector:(SEL)selector frame:(CGRect)frame;
- (void)zn50_renderFeatureGroupsFull;
- (void)zn50_renderFeatureGroupsCompact;
@end

static NSString *ZN65Trim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSDictionary<NSString *, id> *ZN65DisplayMetadata(ZNStaticPatchRecord *record) {
    NSDictionary *embedded = ZNFeatureMetadataDecodeEntry(record.entry);
    if (embedded) return embedded;
    NSString *title = ZN65Trim(record.title);
    NSString *group = ZN65Trim(record.group);
    if (!title.length || [title hasPrefix:@"Patch #"]) title = [NSString stringWithFormat:@"功能 #%u", record.patchID];
    if (!group.length) group = @"Imported";
    return @{
        @"featureID": @0,
        @"title": title,
        @"group": group,
        @"explicitGroup": @([group caseInsensitiveCompare:@"Imported"] != NSOrderedSame)
    };
}

static NSArray<NSDictionary *> *ZN65FeatureGroups(void) {
    ZNStaticDispatchRuntime *runtime = [ZNStaticDispatchRuntime sharedRuntime];
    [runtime refresh];
    NSArray<ZNStaticPatchRecord *> *records = runtime.records;
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray<ZNStaticPatchRecord *> *> *members = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableDictionary *> *metadata = [NSMutableDictionary dictionary];

    for (ZNStaticPatchRecord *record in records) {
        NSDictionary *display = ZN65DisplayMetadata(record);
        NSString *group = ZN65Trim(display[@"group"]);
        NSString *title = ZN65Trim(display[@"title"]);
        uint64_t featureID = [display[@"featureID"] unsignedLongLongValue];
        BOOL explicitFeature = [display[@"explicitGroup"] boolValue] ||
                               (group.length && [group caseInsensitiveCompare:@"Imported"] != NSOrderedSame);
        NSString *key = nil;
        if (featureID) key = [NSString stringWithFormat:@"id:%016llx", featureID];
        else if (explicitFeature) key = [@"group:" stringByAppendingString:group.lowercaseString];
        else key = [NSString stringWithFormat:@"patch:%@:%u", record.target.lowercaseString ?: @"", record.patchID];

        if (!members[key]) {
            members[key] = [NSMutableArray array];
            ZNFeatureControlType type = record.entry ? ZNFeatureControlTypeFromFlags(record.entry->flags) : ZNFeatureControlTypeToggle;
            metadata[key] = [@{
                @"key": key,
                @"featureID": @(featureID),
                @"title": explicitFeature && group.length ? group : (title.length ? title : @"功能"),
                @"controlType": @(type)
            } mutableCopy];
            [order addObject:key];
        }
        [members[key] addObject:record];
    }

    NSMutableArray *out = [NSMutableArray arrayWithCapacity:order.count];
    for (NSString *key in order) {
        NSMutableDictionary *item = [metadata[key] mutableCopy] ?: [NSMutableDictionary dictionary];
        item[@"records"] = [members[key] copy] ?: @[];
        [out addObject:[item copy]];
    }
    return out;
}

static NSString *ZN65PreferenceKey(NSDictionary *feature, NSString *suffix) {
    uint64_t featureID = [feature[@"featureID"] unsignedLongLongValue];
    NSString *identity = featureID
        ? [NSString stringWithFormat:@"%016llx", featureID]
        : [feature[@"key"] description];
    return [NSString stringWithFormat:@"zn.fc.%@.%@", identity ?: @"feature", suffix ?: @"value"];
}

static double ZN65StoredValue(NSDictionary *feature, double fallback) {
    NSString *key = ZN65PreferenceKey(feature, @"value");
    id stored = [NSUserDefaults.standardUserDefaults objectForKey:key];
    return [stored isKindOfClass:NSNumber.class] ? [stored doubleValue] : fallback;
}

static NSDictionary *ZN65EventInfo(NSDictionary *feature, NSNumber *value) {
    NSMutableDictionary *info = [@{
        @"featureID": feature[@"featureID"] ?: @0,
        @"title": feature[@"title"] ?: @"功能",
        @"controlType": feature[@"controlType"] ?: @(ZNFeatureControlTypeToggle),
        @"key": feature[@"key"] ?: @""
    } mutableCopy];
    if (value) info[@"value"] = value;
    return info;
}

@interface ZNRuntimeMenuControllerV040 (ZNFeatureRuntimeControlsV2)
- (void)zn65fc_renderFull;
- (void)zn65fc_renderCompact;
- (void)zn65fc_numberChanged:(UITextField *)field;
- (void)zn65fc_actionTapped:(UIButton *)button;
- (void)zn65fc_sliderChanged:(UISlider *)slider;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNFeatureRuntimeControlsV2)

- (void)zn65fc_decorateCompact:(BOOL)compact {
    NSArray<NSDictionary *> *features = ZN65FeatureGroups();
    for (NSUInteger i = 0; i < features.count; i++) {
        NSDictionary *feature = features[i];
        ZNFeatureControlType type = (ZNFeatureControlType)[feature[@"controlType"] unsignedIntValue];
        if (type == ZNFeatureControlTypeToggle) continue;

        UIView *old = [self.contentView viewWithTag:kZN65ToggleTagBase + (NSInteger)i];
        UIView *card = old.superview;
        if (!old || !card) continue;
        CGRect oldFrame = old.frame;
        [old removeFromSuperview];

        if (type == ZNFeatureControlTypeNumber) {
            CGFloat width = compact ? 72.0 : 78.0;
            UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(CGRectGetWidth(card.bounds) - width - (compact ? 9.0 : 12.0), oldFrame.origin.y, width, oldFrame.size.height)];
            field.tag = kZN65NumberTagBase + (NSInteger)i;
            field.text = [NSString stringWithFormat:@"%.2f", ZN65StoredValue(feature, 1.0)];
            field.textAlignment = NSTextAlignmentCenter;
            field.keyboardType = UIKeyboardTypeDecimalPad;
            field.textColor = self.theme.primaryTextColor;
            field.backgroundColor = [self.theme.controlColor colorWithAlphaComponent:0.82];
            field.font = [UIFont systemFontOfSize:(compact ? 9.0 : 9.6) weight:UIFontWeightSemibold];
            field.layer.cornerRadius = 7.0;
            field.layer.borderWidth = 1.0;
            field.layer.borderColor = self.theme.borderColor.CGColor;
            [field addTarget:self action:@selector(zn65fc_numberChanged:) forControlEvents:UIControlEventEditingDidEnd | UIControlEventEditingDidEndOnExit];
            field.accessibilityLabel = [NSString stringWithFormat:@"%@ 数值", feature[@"title"] ?: @"功能"];
            [card addSubview:field];
        } else if (type == ZNFeatureControlTypeAction) {
            UIButton *button = [self zn40_button:@"执行"
                                         selector:@selector(zn65fc_actionTapped:)
                                            frame:oldFrame];
            button.tag = kZN65ActionTagBase + (NSInteger)i;
            button.accessibilityLabel = [NSString stringWithFormat:@"执行 %@", feature[@"title"] ?: @"功能"];
            [card addSubview:button];
        } else if (type == ZNFeatureControlTypeSlider) {
            CGFloat width = compact ? 88.0 : 112.0;
            UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(CGRectGetWidth(card.bounds) - width - (compact ? 7.0 : 10.0), oldFrame.origin.y, width, oldFrame.size.height)];
            slider.tag = kZN65SliderTagBase + (NSInteger)i;
            slider.minimumValue = 0.0f;
            slider.maximumValue = 10.0f;
            slider.value = (float)MIN(10.0, MAX(0.0, ZN65StoredValue(feature, 1.0)));
            slider.minimumTrackTintColor = self.theme.accentColor;
            [slider addTarget:self action:@selector(zn65fc_sliderChanged:) forControlEvents:UIControlEventValueChanged];
            slider.accessibilityLabel = [NSString stringWithFormat:@"%@ 滑杆", feature[@"title"] ?: @"功能"];
            [card addSubview:slider];
        }
    }
}

- (void)zn65fc_renderFull {
    [self zn65fc_renderFull];
    [self zn65fc_decorateCompact:NO];
}

- (void)zn65fc_renderCompact {
    [self zn65fc_renderCompact];
    [self zn65fc_decorateCompact:YES];
}

- (void)zn65fc_numberChanged:(UITextField *)field {
    NSInteger index = field.tag - kZN65NumberTagBase;
    NSArray<NSDictionary *> *features = ZN65FeatureGroups();
    if (index < 0 || (NSUInteger)index >= features.count) return;
    NSDictionary *feature = features[(NSUInteger)index];
    NSString *trimmed = [field.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSScanner *scanner = [NSScanner scannerWithString:trimmed ?: @""];
    double value = 0.0;
    if (!trimmed.length || ![scanner scanDouble:&value] || !scanner.isAtEnd || !isfinite(value)) {
        value = ZN65StoredValue(feature, 1.0);
        field.text = [NSString stringWithFormat:@"%.2f", value];
        return;
    }
    [NSUserDefaults.standardUserDefaults setDouble:value forKey:ZN65PreferenceKey(feature, @"value")];
    field.text = [NSString stringWithFormat:@"%.2f", value];
    NSDictionary *info = ZN65EventInfo(feature, @(value));
    [NSNotificationCenter.defaultCenter postNotificationName:ZNFeatureNumberValueDidChangeNotification object:self userInfo:info];
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[feature-control] number %@ = %.4f", feature[@"title"] ?: @"功能", value]];
}

- (void)zn65fc_actionTapped:(UIButton *)button {
    NSInteger index = button.tag - kZN65ActionTagBase;
    NSArray<NSDictionary *> *features = ZN65FeatureGroups();
    if (index < 0 || (NSUInteger)index >= features.count) return;
    NSDictionary *feature = features[(NSUInteger)index];
    NSDictionary *info = ZN65EventInfo(feature, nil);
    [NSNotificationCenter.defaultCenter postNotificationName:ZNFeatureActionRequestedNotification object:self userInfo:info];
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[feature-control] action %@ requested", feature[@"title"] ?: @"功能"]];
}

- (void)zn65fc_sliderChanged:(UISlider *)slider {
    NSInteger index = slider.tag - kZN65SliderTagBase;
    NSArray<NSDictionary *> *features = ZN65FeatureGroups();
    if (index < 0 || (NSUInteger)index >= features.count) return;
    NSDictionary *feature = features[(NSUInteger)index];
    double value = slider.value;
    [NSUserDefaults.standardUserDefaults setDouble:value forKey:ZN65PreferenceKey(feature, @"value")];
    NSDictionary *info = ZN65EventInfo(feature, @(value));
    [NSNotificationCenter.defaultCenter postNotificationName:ZNFeatureSliderValueDidChangeNotification object:self userInfo:info];
}

@end

extern "C" void ZNInstallFeatureRuntimeControlsV2Deferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        Method fullOriginal = class_getInstanceMethod(cls, @selector(zn50_renderFeatureGroupsFull));
        Method fullReplacement = class_getInstanceMethod(cls, @selector(zn65fc_renderFull));
        if (fullOriginal && fullReplacement) method_exchangeImplementations(fullOriginal, fullReplacement);

        Method compactOriginal = class_getInstanceMethod(cls, @selector(zn50_renderFeatureGroupsCompact));
        Method compactReplacement = class_getInstanceMethod(cls, @selector(zn65fc_renderCompact));
        if (compactOriginal && compactReplacement) method_exchangeImplementations(compactOriginal, compactReplacement);
    });
}
