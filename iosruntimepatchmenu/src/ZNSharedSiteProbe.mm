#import "ZNSharedSiteProbe.h"
#import "ZNPatchCore.h"
#import <objc/runtime.h>
#import <dlfcn.h>

static const uint64_t kZNSSPPostersOnlyRVA  = 0x2E1BCA0ULL;
static const uint64_t kZNSSPSharedRVA       = 0x2E25904ULL;
static const uint64_t kZNSSPPrestigeOnlyRVA = 0x2E257E4ULL;
static NSString * const kZNSSPModule = @"UnityFramework";

typedef void (*ZNSSPSetActiveIMP)(id, SEL, BOOL);
static ZNSSPSetActiveIMP gZNSSPOriginalSetActive = NULL;
static IMP gZNSSPReplacementIMP = NULL;

@interface ZNSharedSiteProbe ()
@property(nonatomic,assign,readwrite,getter=isInstalled) BOOL installed;
@property(nonatomic,assign,readwrite,getter=isLoggingEnabled) BOOL loggingEnabled;
@property(nonatomic,copy,readwrite) NSString *targetClassName;
@property(nonatomic,copy,readwrite) NSString *lastStatus;
@property(nonatomic,copy,readwrite) NSString *logPath;
- (void)recordObject:(id)obj requestedActive:(BOOL)active phase:(NSString *)phase;
- (NSString *)siteSnapshot;
- (void)appendLine:(NSString *)line;
@end

@implementation ZNSharedSiteProbe

+ (instancetype)sharedProbe {
    static ZNSharedSiteProbe *probe;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ probe=[ZNSharedSiteProbe new]; });
    return probe;
}

- (instancetype)init {
    if ((self=[super init])) {
        NSString *documents=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
        _logPath=[documents stringByAppendingPathComponent:@"ZonoePatch_SharedSiteProbe.log"];
        _targetClassName=@"未安装";
        _lastStatus=@"等待启用 Probe";
    }
    return self;
}

static NSString *ZNSSPStringValue(id obj, NSString *key) {
    if (!obj || !key.length) return @"";
    @try {
        id value=[obj valueForKey:key];
        if ([value isKindOfClass:NSString.class]) return value;
        if ([value respondsToSelector:@selector(stringValue)]) return [value stringValue] ?: @"";
        return value ? [value description] : @"";
    } @catch (__unused NSException *e) {
        return @"";
    }
}

static BOOL ZNSSPClassLooksLikePatchObject(Class cls) {
    if (!cls) return NO;
    if (!class_getInstanceMethod(cls,@selector(setActive:))) return NO;
    if (!class_getInstanceMethod(cls,@selector(identifier))) return NO;
    if (!class_getInstanceMethod(cls,@selector(address))) return NO;
    return YES;
}

static Class ZNSSPFindTargetClass(void) {
    Class exact=NSClassFromString(@"MdhpNuX");
    if (ZNSSPClassLooksLikePatchObject(exact)) return exact;

    int count=objc_getClassList(NULL,0);
    if (count<=0) return Nil;
    Class *classes=(Class *)calloc((size_t)count,sizeof(Class));
    if (!classes) return Nil;
    count=objc_getClassList(classes,count);
    Class found=Nil;
    for (int i=0;i<count;i++) {
        Class cls=classes[i];
        if (!ZNSSPClassLooksLikePatchObject(cls)) continue;
        Method m=class_getInstanceMethod(cls,@selector(setActive:));
        Dl_info info={0};
        if (m && dladdr((const void *)method_getImplementation(m),&info) && info.dli_fname) {
            NSString *image=[NSString stringWithUTF8String:info.dli_fname] ?: @"";
            if ([image.lastPathComponent isEqualToString:@"EarntoDieRogue.dylib"]) {
                found=cls;
                break;
            }
        }
    }
    free(classes);
    return found;
}

static NSString *ZNSSPHexAt(uintptr_t address, NSUInteger length) {
    if (!address || !length) return @"<unresolved>";
    const uint8_t *bytes=(const uint8_t *)address;
    NSMutableString *hex=[NSMutableString stringWithCapacity:length*2];
    for (NSUInteger i=0;i<length;i++) [hex appendFormat:@"%02X",bytes[i]];
    return hex;
}

- (NSString *)siteSnapshot {
    ZNModuleManager *modules=[ZNModuleManager sharedManager];
    uintptr_t posters=[modules runtimeAddressForModule:kZNSSPModule rva:kZNSSPPostersOnlyRVA];
    uintptr_t shared=[modules runtimeAddressForModule:kZNSSPModule rva:kZNSSPSharedRVA];
    uintptr_t prestige=[modules runtimeAddressForModule:kZNSSPModule rva:kZNSSPPrestigeOnlyRVA];
    return [NSString stringWithFormat:@"posters@0x%llX=%@ shared@0x%llX=%@ prestige@0x%llX=%@",
            kZNSSPPostersOnlyRVA,ZNSSPHexAt(posters,16),
            kZNSSPSharedRVA,ZNSSPHexAt(shared,16),
            kZNSSPPrestigeOnlyRVA,ZNSSPHexAt(prestige,16)];
}

- (void)appendLine:(NSString *)line {
    if (!line.length) return;
    @synchronized (self) {
        NSString *dir=[self.logPath stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        if (![[NSFileManager defaultManager] fileExistsAtPath:self.logPath]) {
            [[NSData data] writeToFile:self.logPath atomically:YES];
        }
        NSFileHandle *fh=[NSFileHandle fileHandleForWritingAtPath:self.logPath];
        if (fh) {
            [fh seekToEndOfFile];
            NSString *full=[line stringByAppendingString:@"\n"];
            [fh writeData:[full dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        }
        self.lastStatus=line;
        [[ZNRuntimeLogger sharedLogger] log:line];
    }
}

- (BOOL)installAndEnable:(NSString **)error {
    if (self.installed) {
        self.loggingEnabled=YES;
        [self appendLine:[NSString stringWithFormat:@"[SSP-RESUME] class=%@ %@",self.targetClassName,[self siteSnapshot]]];
        return YES;
    }

    Class cls=ZNSSPFindTargetClass();
    if (!cls) {
        NSString *msg=@"未找到 EarntoDieRogue Patch 对象类（需要 MdhpNuX/-setActive: 或等价类已加载）";
        self.lastStatus=msg;
        if (error) *error=msg;
        return NO;
    }

    Method method=class_getInstanceMethod(cls,@selector(setActive:));
    if (!method) {
        NSString *msg=@"目标类不存在 -setActive:";
        self.lastStatus=msg;
        if (error) *error=msg;
        return NO;
    }

    IMP original=method_getImplementation(method);
    if (!original) {
        NSString *msg=@"无法取得 setActive: 原始 IMP";
        self.lastStatus=msg;
        if (error) *error=msg;
        return NO;
    }
    gZNSSPOriginalSetActive=(ZNSSPSetActiveIMP)original;

    __weak ZNSharedSiteProbe *weakProbe=self;
    id block=^void(id obj, BOOL active) {
        ZNSharedSiteProbe *probe=weakProbe;
        NSString *identifier=ZNSSPStringValue(obj,@"identifier");
        NSString *switchKey=ZNSSPStringValue(obj,@"HlkuHDyxft");
        BOOL relevant=[identifier isEqualToString:@"5"] || [identifier isEqualToString:@"10"] ||
                      [switchKey isEqualToString:@"5-switch"] || [switchKey isEqualToString:@"10-switch"];
        BOOL shouldLog=probe.isLoggingEnabled && relevant;
        if (shouldLog) [probe recordObject:obj requestedActive:active phase:@"BEGIN"];

        if (gZNSSPOriginalSetActive) gZNSSPOriginalSetActive(obj,@selector(setActive:),active);

        if (shouldLog) {
            [probe recordObject:obj requestedActive:active phase:@"END"];
            __weak id weakObject=obj;
            dispatch_async(dispatch_get_main_queue(), ^{
                id strongObject=weakObject;
                if (probe.isLoggingEnabled && strongObject) {
                    [probe recordObject:strongObject requestedActive:active phase:@"DEFERRED"];
                }
            });
        }
    };
    gZNSSPReplacementIMP=imp_implementationWithBlock(block);
    method_setImplementation(method,gZNSSPReplacementIMP);

    self.targetClassName=NSStringFromClass(cls) ?: @"?";
    self.installed=YES;
    self.loggingEnabled=YES;
    [self appendLine:[NSString stringWithFormat:@"[SSP-INSTALL] class=%@ selector=setActive: module=%@ shared=0x%llX",
                      self.targetClassName,kZNSSPModule,kZNSSPSharedRVA]];
    [self captureCurrentStateWithLabel:@"probe-enabled"];
    return YES;
}

- (void)setLoggingEnabled:(BOOL)enabled {
    if (!self.installed && enabled) {
        NSString *error=nil;
        [self installAndEnable:&error];
        return;
    }
    _loggingEnabled=enabled;
    if (self.installed) {
        [self appendLine:[NSString stringWithFormat:@"[SSP-%@] class=%@",enabled?@"RESUME":@"PAUSE",self.targetClassName]];
    }
}

- (void)recordObject:(id)obj requestedActive:(BOOL)active phase:(NSString *)phase {
    NSString *identifier=ZNSSPStringValue(obj,@"identifier");
    NSString *switchKey=ZNSSPStringValue(obj,@"HlkuHDyxft");
    NSString *objectClass=NSStringFromClass([obj class]) ?: @"?";
    NSString *line=[NSString stringWithFormat:@"[SSP-%@] id=%@ key=%@ requested=%d object=%p class=%@ %@",
                    phase,identifier.length?identifier:@"?",switchKey.length?switchKey:@"?",active?1:0,obj,objectClass,[self siteSnapshot]];
    [self appendLine:line];
}

- (void)captureCurrentStateWithLabel:(NSString *)label {
    NSString *clean=label.length?label:@"manual";
    [self appendLine:[NSString stringWithFormat:@"[SSP-SNAPSHOT] label=%@ %@",clean,[self siteSnapshot]]];
}

- (void)clearLog {
    @synchronized (self) {
        [[NSFileManager defaultManager] removeItemAtPath:self.logPath error:nil];
        self.lastStatus=@"Probe 日志已清除";
    }
    if (self.installed && self.loggingEnabled) [self captureCurrentStateWithLabel:@"after-clear"];
}

- (NSString *)logText {
    NSError *error=nil;
    NSString *text=[NSString stringWithContentsOfFile:self.logPath encoding:NSUTF8StringEncoding error:&error];
    return text.length?text:(error.localizedDescription?:@"Probe 日志为空");
}

- (NSArray<NSString *> *)diagnosticLines {
    return @[
        [NSString stringWithFormat:@"Hook：%@ · Logging：%@",self.installed?@"Installed":@"Not installed",self.loggingEnabled?@"ON":@"OFF"],
        [NSString stringWithFormat:@"Class：%@ · -setActive:",self.targetClassName.length?self.targetClassName:@"?"],
        [NSString stringWithFormat:@"Shared Site：%@ + 0x%llX",kZNSSPModule,kZNSSPSharedRVA],
        [NSString stringWithFormat:@"Posters-only：0x%llX · Prestige-only：0x%llX",kZNSSPPostersOnlyRVA,kZNSSPPrestigeOnlyRVA],
        [NSString stringWithFormat:@"Log：Documents/%@",self.logPath.lastPathComponent],
        [NSString stringWithFormat:@"Last：%@",self.lastStatus.length?self.lastStatus:@"-"]
    ];
}

@end
