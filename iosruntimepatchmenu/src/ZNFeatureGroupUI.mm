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

static NSString *ZN50Trim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *ZN50FeaturePreferenceKey(uint64_t featureID) {
    if (!featureID) return nil;
    return [NSString stringWithFormat:@"zn.f.%016llx.enabled", featureID];
}

static NSDictionary<NSString *, id> *ZN50DisplayMetadata(ZNStaticPatchRecord *record) {
    // Authoritative path for new builds: the name travels with the generated
    // Mach-O as FeatureID + encoded UTF-8 bytes, so reinstalling the IPA does
    // not depend on the previous app container or NSUserDefaults.
    NSDictionary<NSString *, id> *embedded = ZNFeatureMetadataDecodeEntry(record.entry);
    if (embedded) return embedded;

    // Legacy generated binaries that still contain plaintext title/group remain
    // readable. The first Privacy-UI-only output (zeroed names + registry only)
    // intentionally falls back to a generic label instead of reintroducing the
    // leaking registry.
    NSString *title = ZN50Trim(record.title);
    NSString *group = ZN50Trim(record.group);

    if (!title.length || [title hasPrefix:@"Patch #"]) {
        title = [NSString stringWithFormat:@"功能 #%u", record.patchID];
    }
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
            // Stable ID is the primary identity. This keeps one Feature switch
            // intact even if Patch ordering changes or the Feature spans targets.
            key = [NSString stringWithFormat:@"id:%016llx", featureID];
        } else if (explicitFeature) {
            key = [@"group:" stringByAppendingString:group.lowercaseString];
            title = group;
        } else {
            // Legacy/no-group entries remain one switch per logical Patch.
            key = [NSString stringWithFormat:@"patch:%@:%u",
                   record.target.lowercaseString ?: @"",
                   record.patchID];
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

static NSString *ZN50FeatureStateText(NSArray<ZNStaticPatchRecord *> *records) {
    BOOL all = ZN50AllEnabled(records);
    BOOL any = ZN50AnyEnabled(records);
    if (all) return @"开";
    if (any) return @"MIXED";
    return @"关";
}

static BOOL ZN50SetFeatureEnabled(NSArray<ZNStaticPatchRecord *> *records,
                                  BOOL enabled,
                                  NSString **error) {
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
                *error = [NSString stringWithFormat:@"%@+0x%llX：%@",
                          record.target ?: @"target",
                          record.siteRVA,
                          localError ?: @"切换失败"];
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
            [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[feature-pref] restore failed id=%016llx: %@",
                                                  featureID,
                                                  restoreError ?: @"unknown"]];
        }
    }
}

@interface ZNRuntimeMenuControllerV040 (ZNFeatureGroupUI)
- (void)zn50_renderFullPage;
- (void)zn50_renderCompactPage;
- (void)zn50_renderFeatureGroupsCompact;
- (void)zn50_renderFeatureGroupsFull;
- (void)zn50_toggleFeature:(UIButton *)sender;
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
    NSString *category = (self.selectedCategory >= 0 && self.selectedCategory < (NSInteger)self.categories.count)
        ? self.categories[(NSUInteger)self.selectedCategory]
        : @"";
    if ([category isEqualToString:@"功能"]) {
        [self zn50_renderFeatureGroupsCompact];
        return;
    }
    [self zn50_renderCompactPage];
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
        NSString *state = ZN50FeatureStateText(records);

        UIView *card = [self cardAtY:y height:46 width:width compact:NO];
        UILabel *name = [self label:title ?: @"功能" size:11.4 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
        name.frame = CGRectMake(13, 13, card.bounds.size.width - 90, 20);
        name.lineBreakMode = NSLineBreakByTruncatingTail;
        [card addSubview:name];

        UIButton *toggle = [self zn40_button:state
                                    selector:@selector(zn50_toggleFeature:)
                                       frame:CGRectMake(card.bounds.size.width - 70, 8, 58, 30)];
        toggle.tag = kZN50FeatureToggleTagBase + (NSInteger)featureIndex;
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
        NSString *state = ZN50FeatureStateText(records);

        UIView *card = [self cardAtY:y height:40 width:width compact:YES];
        UILabel *name = [self label:title ?: @"功能" size:10.7 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
        name.frame = CGRectMake(9, 10, card.bounds.size.width - 78, 20);
        name.lineBreakMode = NSLineBreakByTruncatingTail;
        [card addSubview:name];

        UIButton *toggle = [self zn40_button:state
                                    selector:@selector(zn50_toggleFeature:)
                                       frame:CGRectMake(card.bounds.size.width - 65, 6, 56, 28)];
        toggle.tag = kZN50FeatureToggleTagBase + (NSInteger)featureIndex;
        [card addSubview:toggle];

        [self.contentView addSubview:card];
        y += 46;
    }

    [self zn40_updateContentHeight:y];
}

- (void)zn50_toggleFeature:(UIButton *)sender {
    NSInteger index = sender.tag - kZN50FeatureToggleTagBase;
    if (index < 0) return;

    ZNStaticDispatchRuntime *runtime = [ZNStaticDispatchRuntime sharedRuntime];
    [runtime refresh];
    NSArray<NSDictionary *> *features = ZN50FeatureGroups(runtime.records);
    if ((NSUInteger)index >= features.count) return;

    NSDictionary *feature = features[(NSUInteger)index];
    NSArray<ZNStaticPatchRecord *> *records = feature[@"records"];
    BOOL desired = !ZN50AllEnabled(records); // 关/MIXED -> 开, 开 -> 关.
    NSString *localError = nil;
    if (!ZN50SetFeatureEnabled(records, desired, &localError)) {
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[feature] toggle rollback: %@", localError ?: @"unknown"]];
    } else {
        uint64_t featureID = [feature[@"featureID"] unsignedLongLongValue];
        NSString *preferenceKey = ZN50FeaturePreferenceKey(featureID);
        if (preferenceKey.length) {
            [NSUserDefaults.standardUserDefaults setBool:desired forKey:preferenceKey];
        }
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[feature] %@ %@ (%lu patches)",
                                              desired ? @"ON" : @"OFF",
                                              feature[@"title"] ?: @"功能",
                                              (unsigned long)records.count]];
    }
    [self renderPage];
}

@end

static void ZN50SwapInstanceMethod(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

__attribute__((constructor(120))) static void ZNInstallFeatureGroupUI(void) {
    @autoreleasepool {
        Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (!cls) return;
        ZN50SwapInstanceMethod(cls, @selector(renderFullPage), @selector(zn50_renderFullPage));
        ZN50SwapInstanceMethod(cls, @selector(renderCompactPage), @selector(zn50_renderCompactPage));
        [[ZNRuntimeLogger sharedLogger] log:@"[bootstrap][main] feature UI installed: embedded FeatureID + display name; preferences contain opaque state only"];
    }
}
