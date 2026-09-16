#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "OnDeviceLuaRecovery.h"

#include "GenericPersistentSweep.m"

#define JCG4_VERSION @"JSONCapture g4-r2 中文监控 + 手机JSON恢复"
#define JCG4_WORKER_POLL_SECONDS 2.0
#define JCG4_UI_REFRESH_SECONDS 1.0
#define JCG4_CAPTURE_QUIET_SECONDS 0.80

static dispatch_queue_t gJCG4DecryptQueue;
static dispatch_queue_t gJCG4RecoveryQueue;
static BOOL gJCG4Decrypting = NO;
static BOOL gJCG4Recovering = NO;
static BOOL gJCG4ForceDecryptRequested = NO;
static BOOL gJCG4ForceRecoverRequested = NO;
static BOOL gJCG4IncrementalRecoverRequested = YES;
static unsigned long long gJCG4DroppedTasks = 0;
static NSString *gJCG4LastEvent;
static NSDictionary *gJCG4LastDecryptStats;
static NSDictionary *gJCG4LastRecoveryStats;
static NSMutableDictionary *gJCG4InitialVersions;
static BOOL gJCG4InitialVersionsCaptured = NO;
static unsigned long long gJCG4LastLuaCandidatesSeen = 0;

/*
 * Capture priority in r2 is based on actual capture activity, not on the
 * filesystem discovery worker. gDiskWorkerActive can stay true for long
 * recursive scans and is not itself a capture operation.
 */
static pthread_mutex_t gJCG4ActivityLock = PTHREAD_MUTEX_INITIALIZER;
static unsigned long long gJCG4SeenBundlesSwept = 0;
static unsigned long long gJCG4SeenNamesAttempted = 0;
static unsigned long long gJCG4SeenTextAssets = 0;
static unsigned long long gJCG4SeenLoaderCaptured = 0;
static NSTimeInterval gJCG4LastCaptureActivity = 0;

static NSString *JCG4RawDir(void) { return [gRootPath stringByAppendingPathComponent:@"raw_textasset"]; }
static NSString *JCG4DecodedDir(void) { return [gRootPath stringByAppendingPathComponent:@"decoded_lua"]; }
static NSString *JCG4JSONDir(void) { return [gRootPath stringByAppendingPathComponent:@"recovered_json"]; }

static void JCG4SetLastEvent(NSString *text) {
    @synchronized([NSObject class]) {
        [gJCG4LastEvent release];
        gJCG4LastEvent = [(text.length ? text : @"暂无") copy];
    }
}

static BOOL JCG4CaptureBusy(void) {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    BOOL changed = NO;
    pthread_mutex_lock(&gJCG4ActivityLock);
    if (gBundlesSwept != gJCG4SeenBundlesSwept ||
        gNamesAttempted != gJCG4SeenNamesAttempted ||
        gTextAssets != gJCG4SeenTextAssets ||
        gLoaderCaptured != gJCG4SeenLoaderCaptured) {
        gJCG4SeenBundlesSwept = gBundlesSwept;
        gJCG4SeenNamesAttempted = gNamesAttempted;
        gJCG4SeenTextAssets = gTextAssets;
        gJCG4SeenLoaderCaptured = gLoaderCaptured;
        gJCG4LastCaptureActivity = now;
        changed = YES;
    }
    BOOL recent = gJCG4LastCaptureActivity > 0 && (now - gJCG4LastCaptureActivity) < JCG4_CAPTURE_QUIET_SECONDS;
    pthread_mutex_unlock(&gJCG4ActivityLock);
    return changed || recent;
}

static void JCG4CaptureInitialVersionsIfReady(void) {
    if (gJCG4InitialVersionsCaptured || !gJCG3Initialized || !gJCG3Bundles) return;
    gJCG4InitialVersions = [[NSMutableDictionary alloc] initWithCapacity:gJCG3Bundles.count];
    for (NSString *path in gJCG3Bundles) {
        NSDictionary *entry = gJCG3Bundles[path];
        NSString *version = [entry isKindOfClass:[NSDictionary class]] ? entry[@"version"] : nil;
        if (version.length) gJCG4InitialVersions[path] = version;
    }
    gJCG4InitialVersionsCaptured = YES;
}

static void JCG4IncrementalCounts(unsigned long long *newOut, unsigned long long *changedOut) {
    JCG4CaptureInitialVersionsIfReady();
    unsigned long long n = 0, c = 0;
    if (gJCG4InitialVersionsCaptured && gJCG3Bundles) {
        for (NSString *path in gJCG3Bundles) {
            NSDictionary *entry = gJCG3Bundles[path];
            NSString *version = [entry isKindOfClass:[NSDictionary class]] ? entry[@"version"] : nil;
            NSString *old = gJCG4InitialVersions[path];
            if (!old.length) n++;
            else if (version.length && ![old isEqualToString:version]) c++;
        }
    }
    if (newOut) *newOut = n;
    if (changedOut) *changedOut = c;
}

static void JCG4ScheduleWorkers(void);

static void JCG4RunDecryptIfNeeded(void) {
    if (gJCG4Decrypting || !gJCG4ForceDecryptRequested || !gRootPath.length) return;
    if (JCG4CaptureBusy()) return;
    gJCG4Decrypting = YES;
    BOOL force = gJCG4ForceDecryptRequested;
    gJCG4ForceDecryptRequested = NO;
    JCG4SetLastEvent(@"重新解密已进入后台队列");
    dispatch_async(gJCG4DecryptQueue, ^{
        @autoreleasepool {
            NSDictionary *stats = ODLRDecryptRawDirectory(JCG4RawDir(), JCG4DecodedDir(), gRootPath, force,
                ^BOOL{ return JCG4CaptureBusy(); },
                ^(NSDictionary *event){
                    NSNumber *decoded = event[@"decoded"];
                    if (decoded && ([decoded unsignedIntegerValue] % 100 == 0))
                        JCG4SetLastEvent([NSString stringWithFormat:@"后台解密：%@ 个", decoded]);
                });
            @synchronized([NSObject class]) {
                [gJCG4LastDecryptStats release];
                gJCG4LastDecryptStats = [stats copy];
            }
            if ([stats[@"yielded_for_capture"] boolValue]) {
                gJCG4ForceDecryptRequested = YES;
                JCG4SetLastEvent(@"检测到真实抓取活动，解密暂让路");
            } else {
                gJCG4IncrementalRecoverRequested = YES;
                JCG4SetLastEvent([NSString stringWithFormat:@"解密完成：%@，失败：%@", stats[@"decoded"] ?: @0, stats[@"failed"] ?: @0]);
            }
            gJCG4Decrypting = NO;
        }
    });
}

static void JCG4RunRecoveryIfNeeded(void) {
    if (gJCG4Recovering || !gRootPath.length) return;
    if (!gJCG4ForceRecoverRequested && !gJCG4IncrementalRecoverRequested) return;
    if (JCG4CaptureBusy() || gJCG4Decrypting) return;
    gJCG4Recovering = YES;
    BOOL force = gJCG4ForceRecoverRequested;
    gJCG4ForceRecoverRequested = NO;
    gJCG4IncrementalRecoverRequested = NO;
    JCG4SetLastEvent(force ? @"重新恢复JSON已进入后台队列" : @"正在恢复新增JSON");
    dispatch_async(gJCG4RecoveryQueue, ^{
        @autoreleasepool {
            NSDictionary *stats = ODLRRecoverDecodedDirectory(JCG4DecodedDir(), gRootPath, force,
                ^BOOL{ return JCG4CaptureBusy() || gJCG4Decrypting; },
                ^(NSDictionary *event){
                    NSString *group = event[@"group"];
                    if (group.length) JCG4SetLastEvent([NSString stringWithFormat:@"恢复：%@ (%@)", group, event[@"status"] ?: @""]);
                });
            @synchronized([NSObject class]) {
                [gJCG4LastRecoveryStats release];
                gJCG4LastRecoveryStats = [stats copy];
            }
            if ([stats[@"yielded_for_capture"] boolValue]) {
                gJCG4IncrementalRecoverRequested = YES;
                JCG4SetLastEvent(@"检测到真实抓取活动，JSON恢复暂让路");
            } else {
                JCG4SetLastEvent([NSString stringWithFormat:@"JSON恢复完成：完整%@ / 部分%@", stats[@"tables_complete"] ?: @0, stats[@"tables_partial"] ?: @0]);
            }
            gJCG4Recovering = NO;
        }
    });
}

static void JCG4WorkerTick(void) {
    if (!gRootPath.length) { JCG4ScheduleWorkers(); return; }

    /* Only enqueue incremental recovery when new Lua actually appeared. */
    if (gLuaCandidates != gJCG4LastLuaCandidatesSeen) {
        gJCG4LastLuaCandidatesSeen = gLuaCandidates;
        gJCG4IncrementalRecoverRequested = YES;
    }

    JCG4RunDecryptIfNeeded();
    JCG4RunRecoveryIfNeeded();
    JCG4ScheduleWorkers();
}

static void JCG4ScheduleWorkers(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(JCG4_WORKER_POLL_SECONDS * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ JCG4WorkerTick(); });
}

@interface JCG4PassthroughView : UIView @end
@implementation JCG4PassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end

/*
 * UIWindow itself also participates in hit-testing. Returning nil for the
 * transparent root is required so touches continue to the Unity game window.
 */
@interface JCG4PassthroughWindow : UIWindow @end
@implementation JCG4PassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    UIView *root = self.rootViewController.view;
    if (hit == self || hit == root) return nil;
    return hit;
}
@end

@interface JCG4MonitorController : UIViewController
@property(nonatomic, retain) UIButton *bubble;
@property(nonatomic, retain) UIView *panel;
@property(nonatomic, retain) UIScrollView *scroll;
@property(nonatomic, retain) NSMutableDictionary<NSString *, UILabel *> *labels;
@property(nonatomic, assign) BOOL expanded;
@end

static JCG4PassthroughWindow *gJCG4Window;
static JCG4MonitorController *gJCG4Controller;

static UILabel *JCG4MakeLabel(CGRect frame, CGFloat size, BOOL bold) {
    UILabel *label = [[[UILabel alloc] initWithFrame:frame] autorelease];
    label.textColor = [UIColor colorWithWhite:0.95 alpha:1.0];
    label.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    label.numberOfLines = 0;
    return label;
}

static UIButton *JCG4MakeButton(NSString *title, id target, SEL action, CGRect frame) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = frame;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    b.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.96];
    b.layer.cornerRadius = 8.0;
    b.layer.borderWidth = 0.5;
    b.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.15].CGColor;
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

@implementation JCG4MonitorController

- (void)loadView {
    JCG4PassthroughView *v = [[[JCG4PassthroughView alloc] initWithFrame:UIScreen.mainScreen.bounds] autorelease];
    v.backgroundColor = UIColor.clearColor;
    self.view = v;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.labels = [NSMutableDictionary dictionary];
    CGSize screen = self.view.bounds.size;
    CGPoint saved = CGPointMake(screen.width - 42, 120);
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud objectForKey:@"JCG4BubbleX"]) saved.x = [ud doubleForKey:@"JCG4BubbleX"];
    if ([ud objectForKey:@"JCG4BubbleY"]) saved.y = [ud doubleForKey:@"JCG4BubbleY"];

    self.bubble = [UIButton buttonWithType:UIButtonTypeCustom];
    self.bubble.frame = CGRectMake(0,0,58,58);
    self.bubble.center = saved;
    self.bubble.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.11 alpha:0.94];
    self.bubble.layer.cornerRadius = 29;
    self.bubble.layer.borderWidth = 1.0;
    self.bubble.layer.borderColor = [UIColor colorWithRed:0.25 green:0.85 blue:0.48 alpha:0.9].CGColor;
    self.bubble.titleLabel.numberOfLines = 3;
    self.bubble.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.bubble.titleLabel.font = [UIFont boldSystemFontOfSize:10];
    [self.bubble setTitle:@"J4\n启动中" forState:UIControlStateNormal];
    [self.bubble addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan = [[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragBubble:)] autorelease];
    [self.bubble addGestureRecognizer:pan];
    [self.view addSubview:self.bubble];

    CGFloat pw = MIN(310.0, screen.width - 20.0), ph = MIN(445.0, screen.height - 80.0);
    self.panel = [[[UIView alloc] initWithFrame:CGRectMake(MAX(10.0, screen.width - pw - 10.0), 70.0, pw, ph)] autorelease];
    self.panel.backgroundColor = [UIColor colorWithRed:0.055 green:0.06 blue:0.075 alpha:0.96];
    self.panel.layer.cornerRadius = 14;
    self.panel.layer.borderWidth = 0.7;
    self.panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.15].CGColor;
    self.panel.clipsToBounds = YES;
    self.panel.hidden = YES;
    [self.view addSubview:self.panel];

    UILabel *title = JCG4MakeLabel(CGRectMake(14,10,pw-55,27),16,YES);
    title.text = @"JSONCapture g4-r2 中文监控";
    [self.panel addSubview:title];
    UIButton *close = JCG4MakeButton(@"收起", self, @selector(togglePanel), CGRectMake(pw-54,8,46,30));
    [self.panel addSubview:close];

    self.scroll = [[[UIScrollView alloc] initWithFrame:CGRectMake(0,42,pw,ph-42)] autorelease];
    self.scroll.showsVerticalScrollIndicator = YES;
    [self.panel addSubview:self.scroll];

    CGFloat y=4, x=12, w=pw-24;
    NSArray *sections = @[
        @{ @"title":@"核心状态", @"keys":@[@"state",@"lua",@"compile"] },
        @{ @"title":@"JSON恢复", @"keys":@[@"json",@"records",@"recovery"] },
        @{ @"title":@"Bundle扫描", @"keys":@[@"bundle",@"textasset"] },
        @{ @"title":@"持久化增量", @"keys":@[@"persist",@"increment"] },
        @{ @"title":@"任务队列（抓取优先）", @"keys":@[@"queue",@"event"] },
    ];
    for (NSDictionary *sec in sections) {
        UILabel *h=JCG4MakeLabel(CGRectMake(x,y,w,22),13,YES); h.text=sec[@"title"]; h.textColor=[UIColor colorWithRed:0.45 green:0.9 blue:0.62 alpha:1]; [self.scroll addSubview:h]; y+=23;
        for (NSString *key in sec[@"keys"]) { UILabel *l=JCG4MakeLabel(CGRectMake(x,y,w,38),12,NO); l.text=@"读取中…"; self.labels[key]=l; [self.scroll addSubview:l]; y+=39; }
        y+=5;
    }

    UILabel *ops=JCG4MakeLabel(CGRectMake(x,y,w,22),13,YES); ops.text=@"操作"; ops.textColor=[UIColor colorWithRed:0.45 green:0.9 blue:0.62 alpha:1]; [self.scroll addSubview:ops]; y+=26;
    NSArray *buttons = @[
        @[@"暂停扫描",NSStringFromSelector(@selector(toggleScanning))], @[@"强制全扫",NSStringFromSelector(@selector(forceFullScan))],
        @[@"重新解密",NSStringFromSelector(@selector(redecryptAll))], @[@"重新恢复JSON",NSStringFromSelector(@selector(rerecoverAll))],
        @[@"仅恢复新增",NSStringFromSelector(@selector(recoverIncremental))], @[@"打开JSON目录",NSStringFromSelector(@selector(openJSONDirectory))],
        @[@"导出恢复报告",NSStringFromSelector(@selector(exportRecoveryReport))], @[@"打开状态",NSStringFromSelector(@selector(showStatus))],
        @[@"清空持久索引",NSStringFromSelector(@selector(clearPersistentIndex))], @[@"清空恢复索引",NSStringFromSelector(@selector(clearRecoveryIndex))]
    ];
    CGFloat gap=8,bw=(w-gap)/2.0,bh=36;
    for (NSUInteger i=0;i<buttons.count;i++) { NSArray *spec=buttons[i]; CGFloat bx=x+(i%2)*(bw+gap),by=y+(i/2)*(bh+8); UIButton *b=JCG4MakeButton(spec[0],self,NSSelectorFromString(spec[1]),CGRectMake(bx,by,bw,bh)); b.tag=100+i; [self.scroll addSubview:b]; }
    y += ((buttons.count+1)/2)*(bh+8)+8;
    self.scroll.contentSize=CGSizeMake(pw,y);
    self.expanded=NO;
    [self scheduleRefresh];
}

- (void)dealloc { [_bubble release]; [_panel release]; [_scroll release]; [_labels release]; [super dealloc]; }

- (void)dragBubble:(UIPanGestureRecognizer *)pan {
    CGPoint t=[pan translationInView:self.view]; CGPoint c=self.bubble.center; c.x+=t.x; c.y+=t.y; CGFloat r=29;
    c.x=MAX(r+4,MIN(self.view.bounds.size.width-r-4,c.x)); c.y=MAX(r+4,MIN(self.view.bounds.size.height-r-4,c.y)); self.bubble.center=c; [pan setTranslation:CGPointZero inView:self.view];
    if (pan.state==UIGestureRecognizerStateEnded) { NSUserDefaults *ud=[NSUserDefaults standardUserDefaults]; [ud setDouble:c.x forKey:@"JCG4BubbleX"]; [ud setDouble:c.y forKey:@"JCG4BubbleY"]; }
}

- (void)togglePanel { self.expanded=!self.expanded; self.panel.hidden=!self.expanded; self.bubble.hidden=self.expanded; }

- (void)scheduleRefresh {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(JCG4_UI_REFRESH_SECONDS*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ if(gJCG4Controller){[gJCG4Controller refreshUI];[gJCG4Controller scheduleRefresh];} });
}

- (void)refreshUI {
    NSString *src=nil; void *L=JCG2CurrentLuaState(&src); BOOL busy=JCG4CaptureBusy(); NSDictionary *snap=ODLRQueueSnapshot(JCG4RawDir(),JCG4DecodedDir(),gRootPath); NSDictionary *rs=snap[@"recovery_status"]?:@{};
    unsigned long long newCount=0,changedCount=0; JCG4IncrementalCounts(&newCount,&changedCount);
    self.labels[@"state"].text=[NSString stringWithFormat:@"状态：%@  Lua State：%@\n来源：%@",gRunning?@"● 正常运行":@"● 已暂停",L?@"已获取 ✅":@"未获取 ⚠️",src?:@"none"];
    self.labels[@"lua"].text=[NSString stringWithFormat:@"Lua候选：%llu   ENCM解密：%llu\nLoader捕获：%llu",gLuaCandidates,gDecodedENCM,gLoaderCaptured];
    self.labels[@"compile"].text=[NSString stringWithFormat:@"编译成功：%llu   编译失败：%llu\n等待Lua State：%llu",gCompiledOK,gCompileError,gCompileSkippedNoState];
    self.labels[@"json"].text=[NSString stringWithFormat:@"完整JSON：%@   部分JSON：%@\n动态Lua组：%@",snap[@"complete_json_files"]?:@0,snap[@"partial_json_files"]?:@0,rs[@"groups_dynamic"]?:@0];
    self.labels[@"records"].text=[NSString stringWithFormat:@"恢复记录数：%@\n已解密文件：%@",rs[@"records_recovered"]?:@0,snap[@"decoded_files"]?:@0];
    self.labels[@"recovery"].text=[NSString stringWithFormat:@"恢复状态：%@\n完整组%@ / 部分组%@",gJCG4Recovering?@"处理中…":@"空闲",rs[@"groups_complete"]?:@0,rs[@"groups_partial"]?:@0];
    self.labels[@"bundle"].text=[NSString stringWithFormat:@"已发现：%llu   已扫：%llu\n磁盘成功：%llu   失败：%llu",gBundlesDiscovered,gBundlesSwept,gDiskBundlesLoaded,gDiskBundlesFailed];
    self.labels[@"textasset"].text=[NSString stringWithFormat:@"TextAsset：%llu\n磁盘发现：%@",gTextAssets,gDiskWorkerActive?@"扫描中":@"空闲"];
    self.labels[@"persist"].text=[NSString stringWithFormat:@"索引数量：%lu   本次跳过：%llu\n持久化成功：%llu   失败：%llu",(unsigned long)gJCG3Bundles.count,gJCG3UnchangedSeeded,gJCG3PersistedOK,gJCG3PersistedFailed];
    self.labels[@"increment"].text=[NSString stringWithFormat:@"本次新增：%llu   本次变化：%llu\n索引写入：%llu",newCount,changedCount,gJCG3IndexWrites];
    NSString *mode=busy?@"⚡ 正在抓取（后台让路）":(gDiskWorkerActive?@"磁盘发现中（不阻塞后台）":@"抓取优先 / 空闲");
    self.labels[@"queue"].text=[NSString stringWithFormat:@"模式：%@\n解密：%@   JSON恢复：%@   丢失：%llu",mode,gJCG4Decrypting?@"处理中":(gJCG4ForceDecryptRequested?@"排队":@"空闲"),gJCG4Recovering?@"处理中":(gJCG4IncrementalRecoverRequested||gJCG4ForceRecoverRequested?@"排队":@"空闲"),gJCG4DroppedTasks];
    @synchronized([NSObject class]) { self.labels[@"event"].text=[NSString stringWithFormat:@"最新事件：%@",gJCG4LastEvent?:@"暂无"]; }
    [self.bubble setTitle:[NSString stringWithFormat:@"J4\n%@\nJ%@",busy?@"抓取中":(gJCG4Recovering?@"恢复中":@"正常"),snap[@"complete_json_files"]?:@0] forState:UIControlStateNormal];
    UIButton *pause=(UIButton *)[self.scroll viewWithTag:100]; if([pause isKindOfClass:[UIButton class]]) [pause setTitle:(gRunning?@"暂停扫描":@"继续扫描") forState:UIControlStateNormal];
}

- (void)toggleScanning {
    if (gRunning) { gRunning=NO; JCG4SetLastEvent(@"扫描已暂停"); }
    else { gRunning=YES; JCG4SetLastEvent(@"扫描已继续"); JCG2ScheduleLoadedWatch(); JCG2ScheduleDiskWatch(); JCG3ScheduleLogPoll(); }
}

- (void)forceFullScan {
    if (JCG4CaptureBusy()) { JCG4SetLastEvent(@"当前正在抓取，强制全扫稍后再试"); return; }
    pthread_mutex_lock(&gDiskLock); [gDiskSeenVersions removeAllObjects]; pthread_mutex_unlock(&gDiskLock); [gAttemptedAssets removeAllObjects]; JCG4SetLastEvent(@"已请求强制全扫（不删除持久索引）"); JCG2ScanDiskOnce();
}

- (void)redecryptAll { gJCG4ForceDecryptRequested=YES; JCG4SetLastEvent(@"重新解密已排队；真实抓取优先"); JCG4RunDecryptIfNeeded(); }
- (void)rerecoverAll { ODLRResetRecoveryIndex(gRootPath); gJCG4ForceRecoverRequested=YES; JCG4SetLastEvent(@"重新恢复JSON已排队；真实抓取优先"); JCG4RunRecoveryIfNeeded(); }
- (void)recoverIncremental { gJCG4IncrementalRecoverRequested=YES; JCG4SetLastEvent(@"仅恢复新增已排队"); JCG4RunRecoveryIfNeeded(); }

- (void)showAlertTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}

- (void)openJSONDirectory {
    NSString *path=JCG4JSONDir(); NSString *trim=[path hasPrefix:@"/"]?[path substringFromIndex:1]:path; NSString *encoded=[trim stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet]; NSURL *url=[NSURL URLWithString:[@"filza://" stringByAppendingString:encoded?:trim]];
    if (@available(iOS 10.0,*)) { [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success){ if(!success)[self showAlertTitle:@"JSON目录" message:[NSString stringWithFormat:@"未能打开 Filza。目录路径：\n%@",path]]; }]; }
    else { BOOL ok=[[UIApplication sharedApplication] openURL:url]; if(!ok)[self showAlertTitle:@"JSON目录" message:path]; }
}

- (void)exportRecoveryReport {
    NSString *path=[gRootPath stringByAppendingPathComponent:@"MobileRecovery.report.json"]; if(![[NSFileManager defaultManager] fileExistsAtPath:path]){[self showAlertTitle:@"恢复报告" message:@"报告还没有生成。先等待自动恢复或点“仅恢复新增”。"];return;} NSURL *url=[NSURL fileURLWithPath:path]; UIActivityViewController *vc=[[[UIActivityViewController alloc]initWithActivityItems:@[url] applicationActivities:nil]autorelease]; if(vc.popoverPresentationController){vc.popoverPresentationController.sourceView=self.panel;vc.popoverPresentationController.sourceRect=CGRectMake(self.panel.bounds.size.width/2,20,1,1);}[self presentViewController:vc animated:YES completion:nil];
}

- (void)showStatus {
    NSDictionary *snap=ODLRQueueSnapshot(JCG4RawDir(),JCG4DecodedDir(),gRootPath); NSString *m=[NSString stringWithFormat:@"根目录：\n%@\n\nLua：%llu\nJSON：%@ + %@\nBundle成功/失败：%llu / %llu\n持久索引：%lu",gRootPath,gLuaCandidates,snap[@"complete_json_files"]?:@0,snap[@"partial_json_files"]?:@0,gDiskBundlesLoaded,gDiskBundlesFailed,(unsigned long)gJCG3Bundles.count]; [self showAlertTitle:JCG4_VERSION message:m];
}

- (void)clearPersistentIndex {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"清空持久索引" message:@"只删除 bundle_index.json 和内存已见版本；不会删除已抓文件。随后会重新扫描磁盘 Bundle。" preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [a addAction:[UIAlertAction actionWithTitle:@"确认清空" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x){ [[NSFileManager defaultManager] removeItemAtPath:gJCG3IndexPath error:nil]; [gJCG3Bundles removeAllObjects]; pthread_mutex_lock(&gDiskLock); [gDiskSeenVersions removeAllObjects]; pthread_mutex_unlock(&gDiskLock); gJCG3IndexLoadedEntries=0; gJCG3UnchangedSeeded=0; gJCG4InitialVersionsCaptured=NO; [gJCG4InitialVersions release]; gJCG4InitialVersions=nil; JCG3WriteStatus(); JCG4SetLastEvent(@"持久索引已清空"); }]]; [self presentViewController:a animated:YES completion:nil];
}

- (void)clearRecoveryIndex {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"清空恢复索引" message:@"不会删除 raw/decoded Lua；下次会重新恢复 JSON。" preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [a addAction:[UIAlertAction actionWithTitle:@"确认" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction*x){ ODLRResetRecoveryIndex(gRootPath); gJCG4ForceRecoverRequested=YES; JCG4SetLastEvent(@"恢复索引已清空，重新恢复已排队"); }]]; [self presentViewController:a animated:YES completion:nil];
}
@end

static UIWindowScene *JCG4ForegroundScene(void) API_AVAILABLE(ios(13.0)) {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        if (scene.activationState == UISceneActivationStateForegroundActive || scene.activationState == UISceneActivationStateForegroundInactive) return (UIWindowScene *)scene;
    }
    return nil;
}

static void JCG4InstallUI(void) {
    if (gJCG4Window) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gJCG4Window) return;
        CGRect bounds=UIScreen.mainScreen.bounds;
        if (@available(iOS 13.0,*)) { UIWindowScene *scene=JCG4ForegroundScene(); if(scene) gJCG4Window=[[JCG4PassthroughWindow alloc]initWithWindowScene:scene]; else gJCG4Window=[[JCG4PassthroughWindow alloc]initWithFrame:bounds]; }
        else gJCG4Window=[[JCG4PassthroughWindow alloc]initWithFrame:bounds];
        gJCG4Window.frame=bounds; gJCG4Window.backgroundColor=UIColor.clearColor; gJCG4Window.windowLevel=UIWindowLevelAlert+20; gJCG4Controller=[[JCG4MonitorController alloc]init]; gJCG4Window.rootViewController=gJCG4Controller; gJCG4Window.hidden=NO;
        JCG4SetLastEvent(@"g4-r2 中文监控已启动");
    });
}

__attribute__((constructor)) static void JCG4Entry(void) {
    @autoreleasepool {
        gJCG4DecryptQueue=dispatch_queue_create("com.openai.jsoncapture.g4r2.decrypt",DISPATCH_QUEUE_SERIAL);
        gJCG4RecoveryQueue=dispatch_queue_create("com.openai.jsoncapture.g4r2.recovery",DISPATCH_QUEUE_SERIAL);
        gJCG4LastLuaCandidatesSeen = gLuaCandidates;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.2*NSEC_PER_SEC)),dispatch_get_main_queue(),^{JCG4InstallUI();JCG4CaptureInitialVersionsIfReady();});
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2.0*NSEC_PER_SEC)),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{JCG4WorkerTick();});
        JCG2Log([NSString stringWithFormat:@"%@ loaded; touch-passthrough fixed; actual-capture activity gates background recovery",JCG4_VERSION]);
    }
}
