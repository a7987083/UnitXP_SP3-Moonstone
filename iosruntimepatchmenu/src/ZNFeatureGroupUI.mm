#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <stdint.h>
#import <string.h>

#import "ZNTheme.h"
#import "ZNPatchCore.h"
#import "ZNStaticDispatchRuntime.h"
#import "ZNStaticPatchFormat.h"

// ZonoPatch v0.5 feature aggregation layer.
//
// One Feature owns one public switch and may contain multiple Static Dispatch
// Patch records. Full mode can expand a Feature to inspect each Patch's
// Offset / Enabled / Original. The byte view is recovered from the generated
// OFF/ON variants by reversing the same ARM64 PC-relative relocation classes
// accepted by ZNStaticBinaryBuilder V1; no executable page is modified here.

@interface ZNStaticPatchRecord (ZNFeatureGroupInternal)
@property(nonatomic,assign) uintptr_t imageBase;
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
- (void)addSection:(NSString *)title subtitle:(NSString *)subtitle y:(CGFloat *)y width:(CGFloat)width;
- (void)zn40_updateContentHeight:(CGFloat)y;
- (void)renderFullPage;
- (void)renderCompactPage;
- (void)renderPage;
@end

static const void *kZN50ExpandedFeatureKeys = &kZN50ExpandedFeatureKeys;
static const NSInteger kZN50FeatureToggleTagBase = 450000;
static const NSInteger kZN50FeatureExpandTagBase = 451000;

static int64_t ZN50SignExtend(uint64_t value, int bits) {
    uint64_t sign = UINT64_C(1) << (bits - 1);
    return (int64_t)((value ^ sign) - sign);
}

static uint32_t ZN50Read32(const void *p) {
    uint32_t value = 0;
    memcpy(&value, p, sizeof(value));
    return value;
}

static BOOL ZN50EncodeB(uint64_t fromRVA, uint64_t toRVA, BOOL link, uint32_t *outInstruction) {
    int64_t delta = (int64_t)toRVA - (int64_t)fromRVA;
    if ((delta & 3) || delta < -(1LL << 27) || delta >= (1LL << 27)) return NO;
    uint32_t imm26 = (uint32_t)((delta >> 2) & 0x03FFFFFFu);
    if (outInstruction) *outInstruction = (link ? 0x94000000u : 0x14000000u) | imm26;
    return YES;
}

static BOOL ZN50IsTerminal(uint32_t instruction) {
    return ((instruction & 0xFFFFFC1Fu) == 0xD65F0000u) ||
           ((instruction & 0xFFFFFC1Fu) == 0xD61F0000u);
}

static BOOL ZN50ReverseRelocation(uint32_t relocated,
                                  uint64_t sourceRVA,
                                  uint64_t destinationRVA,
                                  uint32_t *original) {
    if (!original) return NO;

    // B / BL (imm26).
    if ((relocated & 0x7C000000u) == 0x14000000u) {
        BOOL link = (relocated & 0x80000000u) != 0;
        int64_t delta = ZN50SignExtend(relocated & 0x03FFFFFFu, 26) << 2;
        uint64_t target = (uint64_t)((int64_t)destinationRVA + delta);
        return ZN50EncodeB(sourceRVA, target, link, original);
    }

    // B.cond / CBZ / CBNZ / LDR literal family (imm19).
    if ((relocated & 0xFF000010u) == 0x54000000u ||
        (relocated & 0x7E000000u) == 0x34000000u ||
        (relocated & 0x3B000000u) == 0x18000000u) {
        int64_t delta = ZN50SignExtend((relocated >> 5) & 0x7FFFFu, 19) << 2;
        uint64_t target = (uint64_t)((int64_t)destinationRVA + delta);
        int64_t originalDelta = (int64_t)target - (int64_t)sourceRVA;
        if ((originalDelta & 3) || originalDelta < -(1LL << 20) || originalDelta >= (1LL << 20)) return NO;
        *original = (relocated & ~0x00FFFFE0u) |
                    (((uint32_t)(originalDelta >> 2) & 0x7FFFFu) << 5);
        return YES;
    }

    // TBZ / TBNZ (imm14).
    if ((relocated & 0x7E000000u) == 0x36000000u) {
        int64_t delta = ZN50SignExtend((relocated >> 5) & 0x3FFFu, 14) << 2;
        uint64_t target = (uint64_t)((int64_t)destinationRVA + delta);
        int64_t originalDelta = (int64_t)target - (int64_t)sourceRVA;
        if ((originalDelta & 3) || originalDelta < -(1LL << 15) || originalDelta >= (1LL << 15)) return NO;
        *original = (relocated & ~0x0007FFE0u) |
                    (((uint32_t)(originalDelta >> 2) & 0x3FFFu) << 5);
        return YES;
    }

    // ADR / ADRP (imm21).
    uint32_t adrMask = relocated & 0x9F000000u;
    if (adrMask == 0x10000000u || adrMask == 0x90000000u) {
        uint64_t imm = ((uint64_t)((relocated >> 5) & 0x7FFFFu) << 2) |
                       ((relocated >> 29) & 3u);
        int64_t signedImm = ZN50SignExtend(imm, 21);
        uint64_t target = 0;
        if (adrMask == 0x90000000u) {
            target = (uint64_t)((int64_t)(destinationRVA & ~0xFFFULL) + (signedImm << 12));
        } else {
            target = (uint64_t)((int64_t)destinationRVA + signedImm);
        }

        int64_t originalImm = 0;
        if (adrMask == 0x90000000u) {
            originalImm = ((int64_t)(target & ~0xFFFULL) - (int64_t)(sourceRVA & ~0xFFFULL)) >> 12;
        } else {
            originalImm = (int64_t)target - (int64_t)sourceRVA;
        }
        if (originalImm < -(1LL << 20) || originalImm >= (1LL << 20)) return NO;

        uint64_t u = (uint64_t)originalImm & 0x1FFFFFu;
        *original = (relocated & ~((3u << 29) | (0x7FFFFu << 5))) |
                    ((uint32_t)(u & 3u) << 29) |
                    ((uint32_t)((u >> 2) & 0x7FFFFu) << 5);
        return YES;
    }

    // Non-PC-relative instructions are copied unchanged by Builder V1.
    *original = relocated;
    return YES;
}

static void ZN50AppendInstructionHex(NSMutableString *hex, uint32_t instruction) {
    uint8_t bytes[4] = {0};
    memcpy(bytes, &instruction, sizeof(bytes));
    [hex appendFormat:@"%02X%02X%02X%02X", bytes[0], bytes[1], bytes[2], bytes[3]];
}

static NSString *ZN50RecoveredHex(ZNStaticPatchRecord *record, BOOL enabledVariant) {
    ZN44StaticEntry *entry = record.entry;
    uintptr_t imageBase = record.imageBase;
    if (!entry || !imageBase) return @"-";

    uint32_t length = entry->enabledLength ? entry->enabledLength : entry->windowLength;
    if (!length || (length & 3u) || length > 512u || entry->windowLength < length) return @"-";

    uint64_t variantRVA = enabledVariant ? entry->onRVA : entry->offRVA;
    if (!variantRVA) return @"-";

    // Variant layout: LDP X16,X17,[SP],#16 followed by relocated source bytes.
    const uint8_t *variant = (const uint8_t *)(imageBase + (uintptr_t)variantRVA);
    NSMutableString *hex = [NSMutableString stringWithCapacity:(NSUInteger)length * 2u];
    BOOL complete = YES;

    for (uint32_t offset = 0; offset < length; offset += 4u) {
        uint32_t relocated = ZN50Read32(variant + 4u + offset);
        uint32_t source = 0;
        if (!ZN50ReverseRelocation(relocated,
                                   entry->siteRVA + offset,
                                   variantRVA + 4u + offset,
                                   &source)) {
            complete = NO;
            [hex appendString:@"????????"];
        } else {
            ZN50AppendInstructionHex(hex, source);
        }

        // Builder V1 stops emitting after an unconditional terminal. Bytes
        // after it are padding and cannot be represented as exact source.
        if (ZN50IsTerminal(source) && offset + 4u < length) {
            complete = NO;
            [hex appendString:@"…"];
            break;
        }
    }

    if (!hex.length) return @"-";
    return complete ? hex : [hex stringByAppendingString:@"*"];
}

static NSString *ZN50Trim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSArray<NSDictionary *> *ZN50FeatureGroups(NSArray<ZNStaticPatchRecord *> *records) {
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray<ZNStaticPatchRecord *> *> *members = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *titles = [NSMutableDictionary dictionary];

    for (ZNStaticPatchRecord *record in records) {
        NSString *group = ZN50Trim(record.group);
        BOOL explicitFeature = group.length && [group caseInsensitiveCompare:@"Imported"] != NSOrderedSame;
        NSString *key = nil;
        NSString *title = nil;

        if (explicitFeature) {
            key = [@"group:" stringByAppendingString:group.lowercaseString];
            title = group;
        } else {
            // Backward compatibility: legacy JSON without a group remains one
            // switch per Patch instead of collapsing every "Imported" entry.
            key = [NSString stringWithFormat:@"patch:%@:%u", record.target.lowercaseString ?: @"", record.patchID];
            title = ZN50Trim(record.title);
            if (!title.length) title = [NSString stringWithFormat:@"Patch #%u", record.patchID];
        }

        if (!members[key]) {
            members[key] = [NSMutableArray array];
            titles[key] = title;
            [order addObject:key];
        }
        [members[key] addObject:record];
    }

    NSMutableArray<NSDictionary *> *result = [NSMutableArray arrayWithCapacity:order.count];
    for (NSString *key in order) {
        [result addObject:@{
            @"key": key,
            @"title": titles[key] ?: @"Feature",
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
    if (all) return @"ON";
    if (any) return @"MIXED";
    return @"OFF";
}

static NSMutableSet<NSString *> *ZN50ExpandedKeys(ZNRuntimeMenuControllerV040 *controller) {
    NSMutableSet<NSString *> *set = objc_getAssociatedObject(controller, kZN50ExpandedFeatureKeys);
    if (!set) {
        set = [NSMutableSet set];
        objc_setAssociatedObject(controller, kZN50ExpandedFeatureKeys, set, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return set;
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

@interface ZNRuntimeMenuControllerV040 (ZNFeatureGroupUI)
- (void)zn50_renderFullPage;
- (void)zn50_renderCompactPage;
- (void)zn50_renderFeatureGroupsCompact;
- (void)zn50_renderFeatureGroupsFull;
- (void)zn50_toggleFeature:(UIButton *)sender;
- (void)zn50_expandFeature:(UIButton *)sender;
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
    NSMutableSet<NSString *> *expanded = ZN50ExpandedKeys(self);

    [self addSection:@"功能"
            subtitle:@"一个 Feature 一个开关 · 支持多个 Patch · 点击展开查看 Offset / Enabled / Original"
                   y:&y
               width:width];

    if (!features.count) {
        UIView *card = [self cardAtY:y height:54 width:width compact:NO];
        UILabel *label = [self label:@"暂无 Runtime Patch" size:11.0 weight:UIFontWeightSemibold color:self.theme.secondaryTextColor];
        label.frame = CGRectMake(13, 9, card.bounds.size.width - 26, 18);
        [card addSubview:label];
        UILabel *hint = [self label:@"导入 JSON 并生成新二进制后，Feature 会显示在这里。" size:8.7 weight:UIFontWeightRegular color:self.theme.secondaryTextColor];
        hint.frame = CGRectMake(13, 29, card.bounds.size.width - 26, 15);
        [card addSubview:hint];
        [self.contentView addSubview:card];
        y += 62;
        [self zn40_updateContentHeight:y];
        return;
    }

    for (NSUInteger featureIndex = 0; featureIndex < features.count; featureIndex++) {
        NSDictionary *feature = features[featureIndex];
        NSString *key = feature[@"key"];
        NSString *title = feature[@"title"];
        NSArray<ZNStaticPatchRecord *> *records = feature[@"records"];
        BOOL isExpanded = [expanded containsObject:key];
        NSString *state = ZN50FeatureStateText(records);

        UIView *card = [self cardAtY:y height:58 width:width compact:NO];
        UILabel *name = [self label:title ?: @"Feature" size:11.4 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
        name.frame = CGRectMake(13, 7, card.bounds.size.width - 126, 18);
        name.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [card addSubview:name];

        UILabel *summary = [self label:[NSString stringWithFormat:@"%lu Patch · %@", (unsigned long)records.count, state]
                                     size:8.7
                                   weight:UIFontWeightRegular
                                    color:self.theme.secondaryTextColor];
        summary.frame = CGRectMake(13, 29, card.bounds.size.width - 126, 16);
        [card addSubview:summary];

        UIButton *expandButton = [self zn40_button:(isExpanded ? @"▼" : @"▶")
                                          selector:@selector(zn50_expandFeature:)
                                             frame:CGRectMake(card.bounds.size.width - 111, 12, 35, 32)];
        expandButton.tag = kZN50FeatureExpandTagBase + (NSInteger)featureIndex;
        [card addSubview:expandButton];

        UIButton *toggle = [self zn40_button:state
                                    selector:@selector(zn50_toggleFeature:)
                                       frame:CGRectMake(card.bounds.size.width - 70, 12, 58, 32)];
        toggle.tag = kZN50FeatureToggleTagBase + (NSInteger)featureIndex;
        [card addSubview:toggle];

        [self.contentView addSubview:card];
        y += 64;

        if (!isExpanded) continue;

        for (NSUInteger patchIndex = 0; patchIndex < records.count; patchIndex++) {
            ZNStaticPatchRecord *record = records[patchIndex];
            UIView *detail = [self cardAtY:y height:84 width:width compact:NO];

            NSString *patchTitle = ZN50Trim(record.title);
            if (!patchTitle.length) patchTitle = [NSString stringWithFormat:@"Patch #%u", record.patchID];
            UILabel *head = [self label:[NSString stringWithFormat:@"#%lu  %@", (unsigned long)patchIndex + 1, patchTitle]
                                     size:9.8
                                   weight:UIFontWeightSemibold
                                    color:self.theme.primaryTextColor];
            head.frame = CGRectMake(18, 5, detail.bounds.size.width - 82, 16);
            head.lineBreakMode = NSLineBreakByTruncatingMiddle;
            [detail addSubview:head];

            UILabel *patchState = [self label:(record.enabled ? @"ON" : @"OFF")
                                           size:8.6
                                         weight:UIFontWeightSemibold
                                          color:self.theme.secondaryTextColor];
            patchState.frame = CGRectMake(detail.bounds.size.width - 55, 5, 42, 16);
            patchState.textAlignment = NSTextAlignmentRight;
            [detail addSubview:patchState];

            NSString *offset = [NSString stringWithFormat:@"Offset    %@ + 0x%llX", record.target ?: @"target", record.siteRVA];
            NSString *enabledHex = ZN50RecoveredHex(record, YES);
            NSString *originalHex = ZN50RecoveredHex(record, NO);
            NSArray<NSString *> *lines = @[
                offset,
                [NSString stringWithFormat:@"Enabled   %@", enabledHex],
                [NSString stringWithFormat:@"Original  %@", originalHex],
            ];
            for (NSUInteger lineIndex = 0; lineIndex < lines.count; lineIndex++) {
                UILabel *line = [self label:lines[lineIndex]
                                       size:8.3
                                     weight:UIFontWeightRegular
                                      color:self.theme.secondaryTextColor];
                line.frame = CGRectMake(18, 24 + lineIndex * 18, detail.bounds.size.width - 31, 15);
                line.lineBreakMode = NSLineBreakByTruncatingMiddle;
                [detail addSubview:line];
            }

            [self.contentView addSubview:detail];
            y += 90;
        }
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

    if (!features.count) {
        UIView *card = [self cardAtY:y height:44 width:width compact:YES];
        UILabel *label = [self label:@"暂无 Runtime Patch" size:11.0 weight:UIFontWeightSemibold color:self.theme.secondaryTextColor];
        label.frame = CGRectMake(9, 11, card.bounds.size.width - 18, 20);
        [card addSubview:label];
        [self.contentView addSubview:card];
        y += 50;
    } else {
        for (NSUInteger featureIndex = 0; featureIndex < features.count; featureIndex++) {
            NSDictionary *feature = features[featureIndex];
            NSString *title = feature[@"title"];
            NSArray<ZNStaticPatchRecord *> *records = feature[@"records"];
            NSString *state = ZN50FeatureStateText(records);

            UIView *card = [self cardAtY:y height:44 width:width compact:YES];
            UILabel *label = [self label:title ?: @"Feature" size:10.7 weight:UIFontWeightSemibold color:self.theme.primaryTextColor];
            label.frame = CGRectMake(9, 5, card.bounds.size.width - 78, 17);
            label.lineBreakMode = NSLineBreakByTruncatingMiddle;
            [card addSubview:label];

            UILabel *count = [self label:[NSString stringWithFormat:@"%lu Patch", (unsigned long)records.count]
                                      size:8.0
                                    weight:UIFontWeightRegular
                                     color:self.theme.secondaryTextColor];
            count.frame = CGRectMake(9, 22, card.bounds.size.width - 78, 14);
            [card addSubview:count];

            UIButton *toggle = [self zn40_button:state
                                        selector:@selector(zn50_toggleFeature:)
                                           frame:CGRectMake(card.bounds.size.width - 65, 8, 56, 28)];
            toggle.tag = kZN50FeatureToggleTagBase + (NSInteger)featureIndex;
            [card addSubview:toggle];
            [self.contentView addSubview:card];
            y += 50;
        }
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

    NSArray<ZNStaticPatchRecord *> *records = features[(NSUInteger)index][@"records"];
    BOOL desired = !ZN50AllEnabled(records); // OFF/MIXED -> ON, ON -> OFF.
    NSString *error = nil;
    if (!ZN50SetFeatureEnabled(records, desired, &error)) {
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[feature] toggle rollback: %@", error ?: @"unknown"]];
    } else {
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[feature] %@ %@ (%lu patches)", desired ? @"ON" : @"OFF", features[(NSUInteger)index][@"title"] ?: @"Feature", (unsigned long)records.count]];
    }
    [self renderPage];
}

- (void)zn50_expandFeature:(UIButton *)sender {
    NSInteger index = sender.tag - kZN50FeatureExpandTagBase;
    if (index < 0) return;

    ZNStaticDispatchRuntime *runtime = [ZNStaticDispatchRuntime sharedRuntime];
    [runtime refresh];
    NSArray<NSDictionary *> *features = ZN50FeatureGroups(runtime.records);
    if ((NSUInteger)index >= features.count) return;

    NSString *key = features[(NSUInteger)index][@"key"];
    NSMutableSet<NSString *> *expanded = ZN50ExpandedKeys(self);
    if ([expanded containsObject:key]) [expanded removeObject:key];
    else [expanded addObject:key];
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
        [[ZNRuntimeLogger sharedLogger] log:@"[bootstrap][main] v0.5 Feature groups installed: one switch -> multiple patches -> expandable details"];
    }
}
