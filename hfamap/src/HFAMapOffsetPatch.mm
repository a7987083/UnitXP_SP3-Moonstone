#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <sys/mman.h>
#import <unistd.h>
#import <stdint.h>
#import <string.h>

// fenpingvip v7 — authorized offset-patch validation build.
// Static anchors were verified against the supplied NVideo arm64 Mach-O:
//   -[DIYVIP updateStatus:type:]  RVA 0x4AAE8
//   status write site             RVA 0x4AB18 : 02 0C 00 F9  (str x2,[x0,#0x18])
//   -[DIYVIP status]              RVA 0x4FC10
//   -[DIYVIP isVIP]               RVA 0x48D88
//   DIYVIP::_status               offset 0x18
//
// Test mode patches ONLY the write instruction at 0x4AB18 to ARM64 NOP,
// then writes a selected 0/1/2/3 value to the verified _status slot. This
// allows deterministic authorization-state testing while preserving a one-tap
// restore of the original instruction.

static const uintptr_t kHFAMethodRVA = 0x4AAE8;
static const uintptr_t kHFAWriteRVA = 0x4AB18;
static const uintptr_t kHFAStatusGetterRVA = 0x4FC10;
static const uintptr_t kHFAIsVIPRVA = 0x48D88;
static const ptrdiff_t kHFAStatusIvarOffset = 0x18;

static const uint32_t kHFAWriteOriginal = 0xF9000C02; // 02 0C 00 F9
static const uint32_t kHFAWriteNOP = 0xD503201F;      // 1F 20 03 D5

static UIView *gPanel = nil;
static UIButton *gFloatingButton = nil;
static UILabel *gValueLabel = nil;
static UILabel *gAnchorLabel = nil;
static __unsafe_unretained UIWindow *gWindow = nil;
static NSString *gLogPath = nil;
static __unsafe_unretained id gVIP = nil;
static BOOL gPatchInstalled = NO;
static NSInteger gLastSelectedLevel = -1;
static NSString *gLastAction = nil;

static uintptr_t HFAMainBase(void) {
    const struct mach_header *header = _dyld_get_image_header(0);
    return (uintptr_t)header;
}

static uintptr_t HFAAddress(uintptr_t rva) {
    uintptr_t base = HFAMainBase();
    return base ? base + rva : 0;
}

static void HFALog(NSString *line) {
    if (!line.length) return;
    if (!gLogPath) {
        NSString *home = NSHomeDirectory();
        if (home.length) gLogPath = [[home stringByAppendingPathComponent:@"Documents/HFAMap_NVideoVIP_OffsetPatch.log"] copy];
    }
    NSLog(@"[HFAMap][OffsetPatch] %@", line);
    if (!gLogPath) return;

    NSString *out = [line hasSuffix:@"\n"] ? line : [line stringByAppendingString:@"\n"];
    NSData *data = [out dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return;

    @synchronized([NSUserDefaults class]) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:gLogPath]) {
            [data writeToFile:gLogPath atomically:YES];
        } else {
            NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:gLogPath];
            if (h) {
                [h seekToEndOfFile];
                [h writeData:data];
                [h closeFile];
            }
        }
    }
}

static id HFASharedVIP(void) {
    if (gVIP) return gVIP;
    Class cls = objc_getClass("DIYVIP");
    if (!cls) return nil;
    SEL shared = sel_registerName("shared");
    if (![(id)cls respondsToSelector:shared]) return nil;
    id vip = ((id(*)(id, SEL))objc_msgSend)((id)cls, shared);
    if (vip) gVIP = vip;
    return vip;
}

static NSInteger HFAStatus(id vip) {
    if (!vip) return -1;
    SEL sel = sel_registerName("status");
    if (![vip respondsToSelector:sel]) return -1;
    return ((NSInteger(*)(id, SEL))objc_msgSend)(vip, sel);
}

static BOOL HFAIsVIP(id vip) {
    if (!vip) return NO;
    SEL sel = sel_registerName("isVIP");
    if (![vip respondsToSelector:sel]) return NO;
    return ((BOOL(*)(id, SEL))objc_msgSend)(vip, sel);
}

static ptrdiff_t HFAActualStatusIvarOffset(void) {
    Class cls = objc_getClass("DIYVIP");
    if (!cls) return -1;
    Ivar ivar = class_getInstanceVariable(cls, "_status");
    return ivar ? ivar_getOffset(ivar) : -1;
}

static uintptr_t HFASelectorRVA(const char *name) {
    Class cls = objc_getClass("DIYVIP");
    if (!cls || !name) return 0;
    Method method = class_getInstanceMethod(cls, sel_registerName(name));
    if (!method) return 0;
    IMP imp = method_getImplementation(method);
    uintptr_t base = HFAMainBase();
    uintptr_t address = (uintptr_t)imp;
    if (!base || address < base) return 0;
    return address - base;
}

static uint32_t HFAReadWriteInstruction(void) {
    uintptr_t address = HFAAddress(kHFAWriteRVA);
    uint32_t value = 0;
    if (address) memcpy(&value, (const void *)address, sizeof(value));
    return value;
}

static NSString *HFABytesString(uint32_t value) {
    const uint8_t *b = (const uint8_t *)&value;
    return [NSString stringWithFormat:@"%02X %02X %02X %02X", b[0], b[1], b[2], b[3]];
}

static BOOL HFAWriteInstruction(uint32_t value) {
    uintptr_t address = HFAAddress(kHFAWriteRVA);
    if (!address) return NO;

    long pageSizeRaw = sysconf(_SC_PAGESIZE);
    size_t pageSize = pageSizeRaw > 0 ? (size_t)pageSizeRaw : 0x4000;
    uintptr_t page = address & ~((uintptr_t)pageSize - 1);

    int mp = mprotect((void *)page, pageSize, PROT_READ | PROT_WRITE | PROT_EXEC);
    if (mp != 0) {
        kern_return_t kr = vm_protect(mach_task_self(),
                                      (vm_address_t)page,
                                      (vm_size_t)pageSize,
                                      FALSE,
                                      VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY | VM_PROT_EXECUTE);
        if (kr != KERN_SUCCESS) {
            HFALog([NSString stringWithFormat:@"[PATCH_FAIL] protect address=0x%llX mprotect=%d vm=%d",
                    (unsigned long long)address, mp, kr]);
            return NO;
        }
    }

    memcpy((void *)address, &value, sizeof(value));
    __builtin___clear_cache((char *)address, (char *)(address + sizeof(value)));

    // Best-effort return to RX. Some jailbreak kernels keep COW executable pages writable;
    // that is acceptable for this diagnostic process, but never required by later writes.
    mprotect((void *)page, pageSize, PROT_READ | PROT_EXEC);

    uint32_t observed = HFAReadWriteInstruction();
    BOOL ok = (observed == value);
    HFALog([NSString stringWithFormat:@"[PATCH_WRITE] rva=0x%llX va=0x%llX bytes=%@ verify=%@",
            (unsigned long long)kHFAWriteRVA,
            (unsigned long long)address,
            HFABytesString(value),
            ok ? @"PASS" : @"FAIL"]);
    return ok;
}

static BOOL HFAAnchorReady(void) {
    uintptr_t base = HFAMainBase();
    if (!base) return NO;

    uint32_t current = HFAReadWriteInstruction();
    if (current != kHFAWriteOriginal && current != kHFAWriteNOP) return NO;

    ptrdiff_t ivarOffset = HFAActualStatusIvarOffset();
    if (ivarOffset != kHFAStatusIvarOffset) return NO;

    return YES;
}

static BOOL HFAEnsureOffsetPatch(void) {
    uint32_t current = HFAReadWriteInstruction();
    if (current == kHFAWriteNOP) {
        gPatchInstalled = YES;
        return YES;
    }
    if (current != kHFAWriteOriginal) {
        HFALog([NSString stringWithFormat:@"[PATCH_REFUSE] expected=%@ actual=%@",
                HFABytesString(kHFAWriteOriginal), HFABytesString(current)]);
        return NO;
    }
    BOOL ok = HFAWriteInstruction(kHFAWriteNOP);
    gPatchInstalled = ok;
    return ok;
}

static BOOL HFARestoreOffsetPatch(void) {
    uint32_t current = HFAReadWriteInstruction();
    if (current == kHFAWriteOriginal) {
        gPatchInstalled = NO;
        return YES;
    }
    if (current != kHFAWriteNOP) return NO;
    BOOL ok = HFAWriteInstruction(kHFAWriteOriginal);
    if (ok) gPatchInstalled = NO;
    return ok;
}

static void HFARefreshPanel(void) {
    if (!gValueLabel || !gAnchorLabel) return;

    id vip = HFASharedVIP();
    uintptr_t base = HFAMainBase();
    uint32_t current = HFAReadWriteInstruction();
    ptrdiff_t ivarOffset = HFAActualStatusIvarOffset();
    uintptr_t methodRVA = HFASelectorRVA("updateStatus:type:");
    uintptr_t statusRVA = HFASelectorRVA("status");
    uintptr_t isVIPRVA = HFASelectorRVA("isVIP");
    NSInteger status = HFAStatus(vip);
    BOOL isVIP = HFAIsVIP(vip);

    BOOL codeMatch = (current == kHFAWriteOriginal || current == kHFAWriteNOP);
    BOOL ivarMatch = (ivarOffset == kHFAStatusIvarOffset);

    gAnchorLabel.text = [NSString stringWithFormat:
        @"Base 0x%llX\nMethod 0x%llX %@\nWrite  0x%llX  %@\nGetter 0x%llX %@\nisVIP  0x%llX %@",
        (unsigned long long)base,
        (unsigned long long)HFAAddress(kHFAMethodRVA), methodRVA == kHFAMethodRVA ? @"✓" : @"!",
        (unsigned long long)HFAAddress(kHFAWriteRVA), HFABytesString(current),
        (unsigned long long)HFAAddress(kHFAStatusGetterRVA), statusRVA == kHFAStatusGetterRVA ? @"✓" : @"!",
        (unsigned long long)HFAAddress(kHFAIsVIPRVA), isVIPRVA == kHFAIsVIPRVA ? @"✓" : @"!"];

    NSString *action = gLastAction ?: @"尚未执行 Offset Patch";
    gValueLabel.text = [NSString stringWithFormat:
        @"Anchor：%@  Code:%@ Ivar:%@\n"
         "Write 原始：%@\n"
         "Write 当前：%@\n"
         "_status offset：0x%lX\n"
         "Patch：%@\n"
         "当前等级：%ld  isVIP：%@\n"
         "最后选择：%@\n"
         "%@",
        HFAAnchorReady() ? @"PASS" : @"FAIL",
        codeMatch ? @"PASS" : @"FAIL",
        ivarMatch ? @"PASS" : @"FAIL",
        HFABytesString(kHFAWriteOriginal),
        HFABytesString(current),
        (long)ivarOffset,
        current == kHFAWriteNOP ? @"ON · NOP@0x4AB18" : @"OFF · ORIGINAL",
        (long)status,
        isVIP ? @"YES" : @"NO",
        gLastSelectedLevel >= 0 ? [NSString stringWithFormat:@"等级 %ld", (long)gLastSelectedLevel] : @"-",
        action];
}

static void HFASetOffsetLevel(NSInteger target) {
    id vip = HFASharedVIP();
    if (!vip || target < 0 || target > 3) return;

    if (!HFAAnchorReady()) {
        [gLastAction release];
        gLastAction = [@"拒绝：RVA/原始指令/_status offset 锚点不匹配" copy];
        HFALog(@"[STATE_REFUSE] anchor mismatch");
        HFARefreshPanel();
        return;
    }

    if (!HFAEnsureOffsetPatch()) {
        [gLastAction release];
        gLastAction = [@"失败：无法把 0x4AB18 Patch 为 NOP" copy];
        HFARefreshPanel();
        return;
    }

    ptrdiff_t actualOffset = HFAActualStatusIvarOffset();
    if (actualOffset != kHFAStatusIvarOffset) return;

    NSInteger *slot = (NSInteger *)((uint8_t *)(void *)vip + kHFAStatusIvarOffset);
    NSInteger before = *slot;
    *slot = target;
    __sync_synchronize();

    NSInteger getter = HFAStatus(vip);
    BOOL isVIP = HFAIsVIP(vip);
    BOOL expectedVIP = (target == 1 || target == 3);
    BOOL pass = (getter == target && isVIP == expectedVIP);

    gLastSelectedLevel = target;
    [gLastAction release];
    gLastAction = [[NSString stringWithFormat:@"Offset Patch 测试：raw %ld→%ld / getter=%ld / isVIP=%@ / %@",
                    (long)before, (long)target, (long)getter,
                    isVIP ? @"YES" : @"NO", pass ? @"PASS" : @"CONFLICT"] copy];

    HFALog([NSString stringWithFormat:
        @"[STATE_OFFSET_PATCH] base=0x%llX writeVA=0x%llX writeRVA=0x%llX ivar=0x%lX before=%ld target=%ld getter=%ld isVIP=%d pass=%d",
        (unsigned long long)HFAMainBase(),
        (unsigned long long)HFAAddress(kHFAWriteRVA),
        (unsigned long long)kHFAWriteRVA,
        (long)kHFAStatusIvarOffset,
        (long)before, (long)target, (long)getter,
        isVIP ? 1 : 0, pass ? 1 : 0]);

    HFARefreshPanel();
}

static UIWindow *HFAWindow(void) {
    UIApplication *app = [UIApplication sharedApplication];
    UIWindow *window = app.keyWindow;
    if (window) return window;
    NSArray *windows = app.windows;
    return windows.count ? [windows lastObject] : nil;
}

@interface HFAOffsetPatchTarget : NSObject
+ (instancetype)shared;
- (void)toggle;
- (void)refresh;
- (void)restore;
- (void)setLevel:(UIButton *)sender;
- (void)pan:(UIPanGestureRecognizer *)gesture;
- (void)panelPan:(UIPanGestureRecognizer *)gesture;
- (void)tick:(NSTimer *)timer;
@end

@implementation HFAOffsetPatchTarget
+ (instancetype)shared {
    static HFAOffsetPatchTarget *obj = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ obj = [[HFAOffsetPatchTarget alloc] init]; });
    return obj;
}
- (void)toggle {
    if (!gPanel) return;
    gPanel.hidden = !gPanel.hidden;
    if (!gPanel.hidden) HFARefreshPanel();
}
- (void)refresh { HFARefreshPanel(); }
- (void)restore {
    BOOL ok = HFARestoreOffsetPatch();
    [gLastAction release];
    gLastAction = [ok ? @"已恢复 0x4AB18 原始指令 02 0C 00 F9" : @"恢复失败：当前字节不是受支持状态" copy];
    HFALog(ok ? @"[PATCH_RESTORE] PASS" : @"[PATCH_RESTORE] FAIL");
    HFARefreshPanel();
}
- (void)setLevel:(UIButton *)sender { HFASetOffsetLevel(sender.tag); }
- (void)pan:(UIPanGestureRecognizer *)gesture {
    if (!gFloatingButton || !gWindow) return;
    if (gesture.state != UIGestureRecognizerStateBegan && gesture.state != UIGestureRecognizerStateChanged) return;
    CGPoint tr = [gesture translationInView:gWindow];
    CGPoint center = gFloatingButton.center;
    center.x += tr.x; center.y += tr.y;
    CGRect b = gWindow.bounds;
    CGFloat half = 26.0;
    center.x = MAX(half, MIN(b.size.width - half, center.x));
    center.y = MAX(half, MIN(b.size.height - half, center.y));
    gFloatingButton.center = center;
    [gesture setTranslation:CGPointZero inView:gWindow];
}
- (void)panelPan:(UIPanGestureRecognizer *)gesture {
    if (!gPanel || !gWindow) return;
    if (gesture.state != UIGestureRecognizerStateBegan && gesture.state != UIGestureRecognizerStateChanged) return;
    CGPoint tr = [gesture translationInView:gWindow];
    CGPoint center = gPanel.center;
    center.x += tr.x; center.y += tr.y;
    gPanel.center = center;
    [gesture setTranslation:CGPointZero inView:gWindow];
}
- (void)tick:(NSTimer *)timer {
    (void)timer;
    UIWindow *window = HFAWindow();
    if (!window) return;

    if (!gFloatingButton || !gPanel) {
        extern BOOL HFAInstallOffsetPatchUI(UIWindow *window);
        HFAInstallOffsetPatchUI(window);
    }

    if (gFloatingButton && gPanel && (gWindow != window || !gFloatingButton.superview || !gPanel.superview)) {
        [window addSubview:gPanel];
        [window addSubview:gFloatingButton];
        gWindow = window;
    }
    if (gPanel && gFloatingButton) {
        [window bringSubviewToFront:gPanel];
        [window bringSubviewToFront:gFloatingButton];
    }
}
@end

BOOL HFAInstallOffsetPatchUI(UIWindow *window) {
    if (!window) return NO;
    if (gFloatingButton && gPanel) return YES;

    CGRect bounds = window.bounds;
    CGFloat safeTop = window.safeAreaInsets.top;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(18.0, 165.0, 52.0, 52.0);
    button.layer.cornerRadius = 26.0;
    button.layer.masksToBounds = YES;
    button.backgroundColor = [UIColor colorWithRed:0.12 green:0.12 blue:0.15 alpha:0.94];
    [button setTitle:@"HF" forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:15.0];
    [button addTarget:[HFAOffsetPatchTarget shared] action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *buttonPan = [[[UIPanGestureRecognizer alloc] initWithTarget:[HFAOffsetPatchTarget shared] action:@selector(pan:)] autorelease];
    [button addGestureRecognizer:buttonPan];

    CGFloat panelW = MIN(350.0, MAX(300.0, bounds.size.width - 20.0));
    CGFloat panelH = MIN(560.0, MAX(490.0, bounds.size.height - safeTop - 30.0));
    CGFloat panelX = (bounds.size.width - panelW) / 2.0;
    CGFloat panelY = MAX(safeTop + 10.0, (bounds.size.height - panelH) / 2.0);

    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(panelX, panelY, panelW, panelH)];
    panel.backgroundColor = [UIColor colorWithWhite:0.055 alpha:0.97];
    panel.layer.cornerRadius = 16.0;
    panel.layer.borderWidth = 1.0;
    panel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    panel.hidden = YES;

    UIPanGestureRecognizer *panelPan = [[[UIPanGestureRecognizer alloc] initWithTarget:[HFAOffsetPatchTarget shared] action:@selector(panelPan:)] autorelease];
    panelPan.cancelsTouchesInView = NO;
    [panel addGestureRecognizer:panelPan];

    UILabel *title = [[[UILabel alloc] initWithFrame:CGRectMake(16.0, 12.0, panelW - 32.0, 24.0)] autorelease];
    title.text = @"HFAMapUniversal · Offset Patch";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:16.0];
    [panel addSubview:title];

    UILabel *subtitle = [[[UILabel alloc] initWithFrame:CGRectMake(16.0, 38.0, panelW - 32.0, 18.0)] autorelease];
    subtitle.text = @"NVideo VIP Authorization State Test · RVA Anchored";
    subtitle.textColor = [UIColor colorWithWhite:0.72 alpha:1.0];
    subtitle.font = [UIFont systemFontOfSize:10.5];
    [panel addSubview:subtitle];

    UILabel *anchor = [[[UILabel alloc] initWithFrame:CGRectMake(16.0, 64.0, panelW - 32.0, 90.0)] autorelease];
    anchor.numberOfLines = 5;
    anchor.textColor = [UIColor colorWithRed:0.65 green:0.86 blue:1.0 alpha:1.0];
    anchor.font = [UIFont monospacedSystemFontOfSize:9.5 weight:UIFontWeightRegular];
    anchor.adjustsFontSizeToFitWidth = YES;
    anchor.minimumScaleFactor = 0.72;
    [panel addSubview:anchor];

    UIView *line = [[[UIView alloc] initWithFrame:CGRectMake(16.0, 160.0, panelW - 32.0, 1.0)] autorelease];
    line.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    [panel addSubview:line];

    UILabel *values = [[[UILabel alloc] initWithFrame:CGRectMake(16.0, 169.0, panelW - 32.0, 166.0)] autorelease];
    values.numberOfLines = 9;
    values.textColor = [UIColor colorWithWhite:0.93 alpha:1.0];
    values.font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightRegular];
    values.adjustsFontSizeToFitWidth = YES;
    values.minimumScaleFactor = 0.72;
    [panel addSubview:values];

    UILabel *levelTitle = [[[UILabel alloc] initWithFrame:CGRectMake(16.0, 340.0, panelW - 32.0, 18.0)] autorelease];
    levelTitle.text = @"Offset Patch 等级测试（0 / 1 / 2 / 3）";
    levelTitle.textColor = [UIColor colorWithWhite:0.82 alpha:1.0];
    levelTitle.font = [UIFont boldSystemFontOfSize:11.0];
    [panel addSubview:levelTitle];

    CGFloat gap = 6.0;
    CGFloat levelW = (panelW - 32.0 - gap * 3.0) / 4.0;
    for (NSInteger i = 0; i < 4; i++) {
        UIButton *level = [UIButton buttonWithType:UIButtonTypeSystem];
        level.tag = i;
        level.frame = CGRectMake(16.0 + (levelW + gap) * i, 364.0, levelW, 34.0);
        [level setTitle:[NSString stringWithFormat:@"等级 %ld", (long)i] forState:UIControlStateNormal];
        [level setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        level.titleLabel.font = [UIFont boldSystemFontOfSize:11.0];
        level.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.96];
        level.layer.cornerRadius = 7.0;
        [level addTarget:[HFAOffsetPatchTarget shared] action:@selector(setLevel:) forControlEvents:UIControlEventTouchUpInside];
        [panel addSubview:level];
    }

    CGFloat actionY = 410.0;
    CGFloat actionW = (panelW - 38.0) / 2.0;
    UIButton *refresh = [UIButton buttonWithType:UIButtonTypeSystem];
    refresh.frame = CGRectMake(16.0, actionY, actionW, 34.0);
    refresh.layer.cornerRadius = 7.0;
    refresh.backgroundColor = [UIColor colorWithRed:0.23 green:0.36 blue:0.92 alpha:1.0];
    [refresh setTitle:@"刷新地址/状态" forState:UIControlStateNormal];
    [refresh setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    refresh.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
    [refresh addTarget:[HFAOffsetPatchTarget shared] action:@selector(refresh) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:refresh];

    UIButton *restore = [UIButton buttonWithType:UIButtonTypeSystem];
    restore.frame = CGRectMake(22.0 + actionW, actionY, actionW, 34.0);
    restore.layer.cornerRadius = 7.0;
    restore.backgroundColor = [UIColor colorWithRed:0.38 green:0.23 blue:0.20 alpha:1.0];
    [restore setTitle:@"恢复原始指令" forState:UIControlStateNormal];
    [restore setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    restore.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
    [restore addTarget:[HFAOffsetPatchTarget shared] action:@selector(restore) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:restore];

    UILabel *note = [[[UILabel alloc] initWithFrame:CGRectMake(16.0, 452.0, panelW - 32.0, panelH - 460.0)] autorelease];
    note.numberOfLines = 0;
    note.text = @"测试链：main base + RVA → 校验 02 0C 00 F9 → Patch NOP → 写 _status+0x18 → 调用真实 status/isVIP 验证。\n日志：Documents/HFAMap_NVideoVIP_OffsetPatch.log";
    note.textColor = [UIColor colorWithWhite:0.62 alpha:1.0];
    note.font = [UIFont systemFontOfSize:9.0];
    [panel addSubview:note];

    [window addSubview:panel];
    [window addSubview:button];
    [window bringSubviewToFront:panel];
    [window bringSubviewToFront:button];

    gPanel = panel;
    gFloatingButton = button;
    gValueLabel = values;
    gAnchorLabel = anchor;
    gWindow = window;

    [panel release];

    HFARefreshPanel();
    HFALog([NSString stringWithFormat:
        @"[OFFSET_READY] base=0x%llX methodVA=0x%llX writeVA=0x%llX getterVA=0x%llX isVIPVA=0x%llX original=%@ actual=%@",
        (unsigned long long)HFAMainBase(),
        (unsigned long long)HFAAddress(kHFAMethodRVA),
        (unsigned long long)HFAAddress(kHFAWriteRVA),
        (unsigned long long)HFAAddress(kHFAStatusGetterRVA),
        (unsigned long long)HFAAddress(kHFAIsVIPRVA),
        HFABytesString(kHFAWriteOriginal), HFABytesString(HFAReadWriteInstruction())]);
    return YES;
}

__attribute__((constructor))
static void HFAOffsetPatchConstructor(void) {
    @autoreleasepool {
        HFALog(@"[LOAD] HFAMapUniversal fenpingvip v7 offset-patch controller");
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSTimer scheduledTimerWithTimeInterval:0.5
                                             target:[HFAOffsetPatchTarget shared]
                                           selector:@selector(tick:)
                                           userInfo:nil
                                            repeats:YES];
        });
    }
}
