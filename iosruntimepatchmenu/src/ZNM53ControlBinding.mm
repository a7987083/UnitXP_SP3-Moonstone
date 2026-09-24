#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>

#import "ZNFeatureControlModel.h"
#import "ZNFeatureMetadataCodec.h"
#import "ZNRuntimeActionFormat.h"
#import "ZNRuntimePatchExecutor.h"
#import "ZNStaticDispatchRuntime.h"
#import "ZNStaticPatchFormat.h"
#import "ZNPatchCore.h"

// M5.3 Control Binding V1
// Runtime controls: Button/Switch/Number/Slider execute with their current value.
// Static controls: Button enables the fixed variant. Number/Slider dynamically
// rewrite only a verified MOVZ(+MOVK...) constant sequence in the generated ON
// variant. Anything else fails closed; arbitrary Enabled bytes are never guessed.

static const NSInteger kZNM53ExecTag = 796000;
static const NSInteger kZNM53FieldTag = 797000;
static const NSInteger kZNM53SwitchTag = 798000;
static const NSInteger kZNM53SliderTag = 799000;
static const void *kZNM53SliderCommitInstalledKey = &kZNM53SliderCommitInstalledKey;

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIWindow *hostWindow;
- (void)zn51_runtimeExecute:(UIButton *)sender;
- (void)zn51_runtimeNumberChanged:(UITextField *)field;
- (void)zn51_runtimeSwitchChanged:(UISwitch *)control;
- (void)zn51_runtimeSliderChanged:(UISlider *)control;
@end

// Private properties are intentionally redeclared only inside this outer binding
// layer. They already exist on ZNStaticPatchRecord in ZNStaticDispatchRuntime.mm.
@interface ZNStaticPatchRecord (ZNM53Private)
@property(nonatomic,assign) uintptr_t imageBase;
@property(nonatomic,assign) ZN44StaticEntry *entry;
@property(nonatomic,assign) uint64_t onRVA;
@property(nonatomic,assign) BOOL payloadProtectionV2;
@end

static UIViewController *ZNM53TopController(void) {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
            if (candidate.isKeyWindow) { window = candidate; break; }
        }
        if (window) break;
    }
    if (!window) window = UIApplication.sharedApplication.windows.firstObject;
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController && !vc.presentedViewController.isBeingDismissed) vc = vc.presentedViewController;
    return vc;
}

static void ZNM53ShowFailure(NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = ZNM53TopController();
        if (!top || [top isKindOfClass:UIAlertController.class]) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"执行失败"
                                                                       message:(message.length ? message : @"执行失败")
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [top presentViewController:alert animated:YES completion:nil];
    });
}

static void ZNM53ExecuteRuntimeRecord(ZNRuntimeMenuControllerV040 *controller, NSUInteger recordIndex) {
    UIButton *proxy = [UIButton buttonWithType:UIButtonTypeCustom];
    proxy.tag = kZNM53ExecTag + (NSInteger)recordIndex;
    [controller zn51_runtimeExecute:proxy];
}

@interface ZNRuntimeMenuControllerV040 (ZNM53RuntimeAutoExecute)
- (void)znm53_numberChanged:(UITextField *)field;
- (void)znm53_switchChanged:(UISwitch *)control;
- (void)znm53_sliderChanged:(UISlider *)control;
- (void)znm53_sliderCommitted:(UISlider *)control;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM53RuntimeAutoExecute)

- (void)znm53_numberChanged:(UITextField *)field {
    [self znm53_numberChanged:field];
    NSInteger slot = field.tag - kZNM53FieldTag;
    if (slot < 0 || field.isEditing) return;
    ZNM53ExecuteRuntimeRecord(self, (NSUInteger)slot / ZN_RUNTIME_ACTION_MAX_ARGUMENTS);
}

- (void)znm53_switchChanged:(UISwitch *)control {
    [self znm53_switchChanged:control];
    NSInteger slot = control.tag - kZNM53SwitchTag;
    if (slot < 0) return;
    ZNM53ExecuteRuntimeRecord(self, (NSUInteger)slot / ZN_RUNTIME_ACTION_MAX_ARGUMENTS);
}

- (void)znm53_sliderChanged:(UISlider *)control {
    [self znm53_sliderChanged:control];
    if (![objc_getAssociatedObject(control, kZNM53SliderCommitInstalledKey) boolValue]) {
        [control addTarget:self action:@selector(znm53_sliderCommitted:)
          forControlEvents:(UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel)];
        objc_setAssociatedObject(control, kZNM53SliderCommitInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (void)znm53_sliderCommitted:(UISlider *)control {
    NSInteger slot = control.tag - kZNM53SliderTag;
    if (slot < 0) return;
    // zn51_runtimeSliderChanged: has already cached/quantized the latest ValueChanged.
    ZNM53ExecuteRuntimeRecord(self, (NSUInteger)slot / ZN_RUNTIME_ACTION_MAX_ARGUMENTS);
}

@end

static BOOL ZNM53IsMOVZ(uint32_t insn) { return (insn & 0x7F800000u) == 0x52800000u; }
static BOOL ZNM53IsMOVK(uint32_t insn) { return (insn & 0x7F800000u) == 0x72800000u; }
static uint32_t ZNM53Read32(uintptr_t address) { uint32_t v = 0; memcpy(&v, (const void *)address, sizeof(v)); return v; }

static BOOL ZNM53DecodeBTarget(uint64_t branchRVA, uint32_t insn, uint64_t *targetRVA) {
    if ((insn & 0x7C000000u) != 0x14000000u || (insn & 0x80000000u)) return NO;
    int64_t imm = (int64_t)(insn & 0x03FFFFFFu);
    if (imm & 0x02000000LL) imm |= ~0x03FFFFFFLL;
    if (targetRVA) *targetRVA = (uint64_t)((int64_t)branchRVA + (imm << 2));
    return YES;
}

static NSArray<NSNumber *> *ZNM53SourceInstructionAddresses(ZNStaticPatchRecord *record, NSString **error) {
    if (!record || !record.entry || !record.imageBase || !record.onRVA) {
        if (error) *error = @"Static dynamic record metadata unavailable";
        return nil;
    }
    if (!record.payloadProtectionV2) {
        if (error) *error = @"Static Number/Slider V1 仅支持当前 Protection V2 生成物";
        return nil;
    }
    uint32_t enabledLength = record.entry->enabledLength;
    if (!enabledLength || (enabledLength & 3u)) {
        if (error) *error = @"Enabled 长度必须为 4-byte 倍数";
        return nil;
    }
    NSUInteger count = enabledLength / 4u;
    if (!count || count > 32) {
        if (error) *error = @"Static dynamic V1 Enabled 指令数量超出 1-32";
        return nil;
    }

    NSMutableArray<NSNumber *> *addresses = [NSMutableArray arrayWithCapacity:count];
    uint64_t fragmentRVA = record.onRVA;
    for (NSUInteger i = 0; i < count; i++) {
        uint64_t sourceRVA = fragmentRVA + (i == 0 ? 4u : 0u); // entry fragment starts with LDP X16,X17
        uintptr_t sourceAddress = record.imageBase + (uintptr_t)sourceRVA;
        [addresses addObject:@(sourceAddress)];
        if (i + 1 >= count) break;
        uint64_t branchRVA = sourceRVA + 4u;
        uint32_t branch = ZNM53Read32(record.imageBase + (uintptr_t)branchRVA);
        uint64_t next = 0;
        if (!ZNM53DecodeBTarget(branchRVA, branch, &next)) {
            if (error) *error = [NSString stringWithFormat:@"Protection V2 fragment %lu next branch 无法解析", (unsigned long)i];
            return nil;
        }
        fragmentRVA = next;
    }
    return addresses;
}

static NSArray<ZNPatchActionDescriptor *> *ZNM53ActionsForValue(ZNStaticPatchRecord *record,
                                                                 double input,
                                                                 NSString **error) {
    if (!isfinite(input) || input < 0.0 || floor(input) != input) {
        if (error) *error = @"Static Number/Slider V1 仅接受非负整数";
        return nil;
    }
    NSArray<NSNumber *> *addresses = ZNM53SourceInstructionAddresses(record, error);
    if (!addresses.count) return nil;

    uint32_t first = ZNM53Read32((uintptr_t)addresses[0].unsignedLongLongValue);
    if (!ZNM53IsMOVZ(first)) {
        if (error) *error = [NSString stringWithFormat:@"Enabled 首指令不是可参数化 MOVZ（0x%08X）；为避免盲写已拒绝", first];
        return nil;
    }
    BOOL is64 = (first & 0x80000000u) != 0;
    uint64_t maxValue = is64 ? UINT64_C(9007199254740991) : UINT64_C(0xFFFFFFFF);
    if (input > (double)maxValue) {
        if (error) *error = is64 ? @"X 寄存器动态值 V1 最大 2^53-1" : @"W 寄存器动态值最大 UINT32_MAX";
        return nil;
    }
    uint64_t value = (uint64_t)input;
    uint32_t rd = first & 31u;
    uint32_t covered = 0;
    NSMutableArray<NSDictionary *> *moves = [NSMutableArray array];

    for (NSUInteger i = 0; i < addresses.count; i++) {
        uintptr_t address = (uintptr_t)addresses[i].unsignedLongLongValue;
        uint32_t insn = ZNM53Read32(address);
        BOOL compatible = (i == 0 ? ZNM53IsMOVZ(insn) : ZNM53IsMOVK(insn));
        if (!compatible) break;
        if (((insn & 0x80000000u) != 0) != is64 || (insn & 31u) != rd) break;
        uint32_t hw = (insn >> 21) & 3u;
        if (!is64 && hw > 1u) break;
        covered |= (1u << hw);
        [moves addObject:@{@"address": @(address), @"instruction": @(insn), @"hw": @(hw)}];
    }
    if (!moves.count) {
        if (error) *error = @"未发现 MOVZ/MOVK 参数化序列";
        return nil;
    }

    uint32_t chunks = is64 ? 4u : 2u;
    for (uint32_t hw = 0; hw < chunks; hw++) {
        uint16_t chunk = (uint16_t)((value >> (hw * 16u)) & 0xFFFFu);
        if (chunk && !(covered & (1u << hw))) {
            if (error) *error = [NSString stringWithFormat:@"数值 0x%llX 需要 MOVK LSL #%u，但 Enabled 没有该槽位", (unsigned long long)value, hw * 16u];
            return nil;
        }
    }

    NSMutableArray<ZNPatchActionDescriptor *> *actions = [NSMutableArray array];
    for (NSDictionary *move in moves) {
        uintptr_t address = [move[@"address"] unsignedLongLongValue];
        uint32_t oldInsn = [move[@"instruction"] unsignedIntValue];
        uint32_t hw = [move[@"hw"] unsignedIntValue];
        uint16_t chunk = (uint16_t)((value >> (hw * 16u)) & 0xFFFFu);
        uint32_t newInsn = (oldInsn & ~0x001FFFE0u) | ((uint32_t)chunk << 5);
        if (newInsn == oldInsn) continue;
        ZNPatchActionDescriptor *a = [[ZNPatchActionDescriptor alloc] initWithIdentifier:[NSString stringWithFormat:@"m53-static-%u-%u", record.patchID, hw] type:ZNPatchActionTypeBytes];
        a.resolvedAddress = address;
        a.zn_expectedBytes = [NSData dataWithBytes:&oldInsn length:sizeof(oldInsn)];
        a.zn_patchBytes = [NSData dataWithBytes:&newInsn length:sizeof(newInsn)];
        a.zn_targetWritable = NO;
        [actions addObject:a];
    }
    return actions;
}

static BOOL ZNM53RecordMatches(ZNStaticPatchRecord *record, NSDictionary *info) {
    uint64_t wantedID = [info[@"featureID"] unsignedLongLongValue];
    NSDictionary *meta = record.entry ? ZNFeatureMetadataDecodeEntry(record.entry) : nil;
    uint64_t recordID = [meta[@"featureID"] unsignedLongLongValue];
    if (wantedID && recordID) return wantedID == recordID;
    NSString *wanted = [info[@"title"] isKindOfClass:NSString.class] ? info[@"title"] : @"";
    NSString *recordName = [meta[@"title"] isKindOfClass:NSString.class] ? meta[@"title"] : (record.group.length ? record.group : record.title);
    return wanted.length && [wanted caseInsensitiveCompare:recordName ?: @""] == NSOrderedSame;
}

@interface ZNM53StaticControlBinder : NSObject
@property(nonatomic,strong) NSMutableDictionary<NSString *, NSNumber *> *sliderGenerations;
+ (instancetype)shared;
- (void)numberChanged:(NSNotification *)note;
- (void)sliderChanged:(NSNotification *)note;
- (void)actionRequested:(NSNotification *)note;
@end

@implementation ZNM53StaticControlBinder
+ (instancetype)shared {
    static ZNM53StaticControlBinder *s; static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ s = [ZNM53StaticControlBinder new]; s.sliderGenerations = [NSMutableDictionary dictionary]; });
    return s;
}

- (NSArray<ZNStaticPatchRecord *> *)recordsForInfo:(NSDictionary *)info {
    ZNStaticDispatchRuntime *runtime = [ZNStaticDispatchRuntime sharedRuntime];
    [runtime refresh];
    NSMutableArray *out = [NSMutableArray array];
    for (ZNStaticPatchRecord *record in runtime.records) if (ZNM53RecordMatches(record, info)) [out addObject:record];
    return out;
}

- (BOOL)applyValue:(double)value info:(NSDictionary *)info error:(NSString **)error {
    NSArray<ZNStaticPatchRecord *> *records = [self recordsForInfo:info];
    if (!records.count) { if (error) *error = @"找不到 Static Feature 记录"; return NO; }
    NSMutableArray<ZNPatchActionDescriptor *> *allActions = [NSMutableArray array];
    for (ZNStaticPatchRecord *record in records) {
        NSString *local = nil;
        NSArray *actions = ZNM53ActionsForValue(record, value, &local);
        if (!actions) { if (error) *error = local ?: @"Static dynamic encode failed"; return NO; }
        [allActions addObjectsFromArray:actions];
    }

    ZNStaticDispatchRuntime *runtime = [ZNStaticDispatchRuntime sharedRuntime];
    NSMutableArray<NSNumber *> *prior = [NSMutableArray arrayWithCapacity:records.count];
    for (ZNStaticPatchRecord *record in records) {
        [prior addObject:@(record.isEnabled)];
        if (record.isEnabled) [runtime setEnabled:NO forRecord:record error:nil];
    }

    if (allActions.count) {
        NSString *writeError = nil;
        if (![[ZNRuntimePatchExecutor sharedExecutor] setActions:allActions enabled:YES error:&writeError]) {
            for (NSUInteger i = 0; i < records.count; i++) if (prior[i].boolValue) [runtime setEnabled:YES forRecord:records[i] error:nil];
            if (error) *error = writeError ?: @"Static dynamic write failed";
            return NO;
        }
    }
    for (ZNStaticPatchRecord *record in records) {
        NSString *enableError = nil;
        if (![runtime setEnabled:YES forRecord:record error:&enableError]) {
            if (error) *error = enableError ?: @"Static dynamic variant enable failed";
            return NO;
        }
    }
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m5.3-binding] static %@ value=%.0f records=%lu SUCCESS", info[@"title"] ?: @"feature", value, (unsigned long)records.count]];
    return YES;
}

- (void)numberChanged:(NSNotification *)note {
    NSNumber *value = note.userInfo[@"value"];
    if (![value isKindOfClass:NSNumber.class]) return;
    NSString *error = nil;
    if (![self applyValue:value.doubleValue info:note.userInfo ?: @{} error:&error]) ZNM53ShowFailure(error);
}

- (void)sliderChanged:(NSNotification *)note {
    NSNumber *value = note.userInfo[@"value"];
    if (![value isKindOfClass:NSNumber.class]) return;
    NSString *key = [note.userInfo[@"key"] isKindOfClass:NSString.class] ? note.userInfo[@"key"] : (note.userInfo[@"title"] ?: @"feature");
    NSUInteger generation = [self.sliderGenerations[key] unsignedIntegerValue] + 1;
    self.sliderGenerations[key] = @(generation);
    NSDictionary *info = [note.userInfo copy] ?: @{};
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([self.sliderGenerations[key] unsignedIntegerValue] != generation) return;
        NSString *error = nil;
        if (![self applyValue:value.doubleValue info:info error:&error]) ZNM53ShowFailure(error);
    });
}

- (void)actionRequested:(NSNotification *)note {
    NSArray<ZNStaticPatchRecord *> *records = [self recordsForInfo:note.userInfo ?: @{}];
    if (!records.count) { ZNM53ShowFailure(@"找不到 Static Feature 记录"); return; }
    ZNStaticDispatchRuntime *runtime = [ZNStaticDispatchRuntime sharedRuntime];
    for (ZNStaticPatchRecord *record in records) {
        NSString *error = nil;
        if (![runtime setEnabled:YES forRecord:record error:&error]) { ZNM53ShowFailure(error); return; }
    }
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m5.3-binding] static action %@ SUCCESS", note.userInfo[@"title"] ?: @"feature"]];
}
@end

static void ZNM53Swap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original), b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallM53ControlBindingDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class menu = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (menu) {
            ZNM53Swap(menu, @selector(zn51_runtimeNumberChanged:), @selector(znm53_numberChanged:));
            ZNM53Swap(menu, @selector(zn51_runtimeSwitchChanged:), @selector(znm53_switchChanged:));
            ZNM53Swap(menu, @selector(zn51_runtimeSliderChanged:), @selector(znm53_sliderChanged:));
        }
        ZNM53StaticControlBinder *binder = [ZNM53StaticControlBinder shared];
        [NSNotificationCenter.defaultCenter addObserver:binder selector:@selector(numberChanged:) name:ZNFeatureNumberValueDidChangeNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:binder selector:@selector(sliderChanged:) name:ZNFeatureSliderValueDidChangeNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:binder selector:@selector(actionRequested:) name:ZNFeatureActionRequestedNotification object:nil];
        [[ZNRuntimeLogger sharedLogger] log:@"[m5.3-binding] Runtime auto-execute + Static MOVZ/MOVK Number/Slider binding installed"];
    });
}
