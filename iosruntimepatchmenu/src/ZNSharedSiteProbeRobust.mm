#import "ZNSharedSiteProbe.h"
#import "ZNPatchCore.h"
#import <objc/runtime.h>
#import <dlfcn.h>
#import <stdlib.h>

static const uint64_t kZNSSPPostersOnlyRVA  = 0x2E1BCA0ULL;
static const uint64_t kZNSSPSharedRVA       = 0x2E25904ULL;
static const uint64_t kZNSSPPrestigeOnlyRVA = 0x2E257E4ULL;
static NSString * const kZNSSPModule = @"UnityFramework";
static NSString * const kZNSSPExactClassName = @"MdhpNuX";

typedef void (*ZNSSPSetActiveIMP)(id, SEL, BOOL);
static ZNSSPSetActiveIMP gZNSSPOriginalSetActive = NULL;
static IMP gZNSSPReplacementIMP = NULL;

@interface ZNSharedSiteProbe ()
@property(nonatomic,assign,readwrite,getter=isInstalled) BOOL installed;
@property(nonatomic,assign,readwrite,getter=isLoggingEnabled) BOOL loggingEnabled;
@property(nonatomic,copy,readwrite) NSString *targetClassName;
@property(nonatomic,copy,readwrite) NSString *lastStatus;
@property(nonatomic,copy,readwrite) NSString *logPath;
@property(nonatomic,assign) BOOL arming;
@property(nonatomic,assign) NSUInteger armToken;
- (void)recordObject:(id)obj requestedActive:(BOOL)active phase:(NSString *)phase;
- (NSString *)siteSnapshot;
- (void)appendLine:(NSString *)line;
- (BOOL)installOnClass:(Class)cls error:(NSString **)error;
- (void)retryInstallToken:(NSUInteger)token remaining:(NSUInteger)remaining;
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

static BOOL ZNSSPHasSelector(Class cls, SEL sel) {
    return cls && class_getInstanceMethod(cls,sel) != NULL;
}

static BOOL ZNSSPClassLooksLikePatchObject(Class cls) {
    if (!cls) return NO;
    return ZNSSPHasSelector(cls,@selector(setActive:)) &&
           ZNSSPHasSelector(cls,@selector(identifier)) &&
           ZNSSPHasSelector(cls,@selector(address));
}

static NSString *ZNSSPIMPImage(Method method) {
    if (!method) return @"";
    Dl_info info={0};
    IMP imp=method_getImplementation(method);
    if (!imp || !dladdr((const void *)imp,&info) || !info.dli_fname) return @"";
    return [[NSString stringWithUTF8String:info.dli_fname] lastPathComponent] ?: @"";
}

static Class ZNSSPFindTargetClass(NSString **detail) {
    Class exact=objc_lookUpClass(kZNSSPExactClassName.UTF8String);
    if (!exact) exact=NSClassFromString(kZNSSPExactClassName);
    if (exact && ZNSSPHasSelector(exact,@selector(setActive:))) {
        if (detail) {
            Method m=class_getInstanceMethod(exact,@selector(setActive:));
            *detail=[NSString stringWithFormat:@"exact=%@ setActive=YES identifier=%@ address=%@ impImage=%@",
                     NSStringFromClass(exact) ?: @"?",
                     ZNSSPHasSelector(exact,@selector(identifier))?@"YES":@"NO",
                     ZNSSPHasSelector(exact,@selector(address))?@"YES":@"NO",
                     ZNSSPIMPImage(m).length?ZNSSPIMPImage(m):@"?"];
        }
        return exact;
    }

    int count=objc_getClassList(NULL,0);
    if (count<=0) {
        if (detail) *detail=@"objc_getClassList returned 0";
        return Nil;
    }
    Class *classes=(Class *)calloc((size_t)count,sizeof(Class));
    if (!classes) {
        if (detail) *detail=@"class buffer allocation failed";
        return Nil;
    }
    count=objc_getClassList(classes,count);

    Class namedFallback=Nil;
    Class imageFallback=Nil;
    NSString *imageFallbackName=@"";
    for (int i=0;i<count;i++) {
        Class cls=classes[i];
        NSString *name=NSStringFromClass(cls) ?: @"";
        if ([name isEqualToString:kZNSSPExactClassName] && ZNSSPHasSelector(cls,@selector(setActive:))) {
            namedFallback=cls;
            break;
        }
        if (!ZNSSPClassLooksLikePatchObject(cls)) continue;
        Method m=class_getInstanceMethod(cls,@selector(setActive:));
        NSString *image=ZNSSPIMPImage(m);
        if ([image rangeOfString:@"EarntoDieRogue" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            imageFallback=cls;
            imageFallbackName=image;
            break;
        }
    }
    free(classes);

    Class found=namedFallback ?: imageFallback;
    if (detail) {
        if (found) {
            *detail=[NSString stringWithFormat:@"scan=%@ impImage=%@ classCount=%d",
                     NSStringFromClass(found) ?: @"?",
                     imageFallbackName.length?imageFallbackName:ZNSSPIMPImage(class_getInstanceMethod(found,@selector(setActive:))),
                     count];
        } else {
            *detail=[NSString stringWithFormat:@"exactPresent=%@ exactSetActive=%@ classCount=%d",
                     exact?@"YES":@"NO",
                     (exact&&ZNSSPHasSelector(exact,@selector(setActive:)))?@"YES":@"NO",
                     count];
        }
    }
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

- (BOOL)installOnClass:(Class)cls error:(NSString **)error {
    if (!cls) {
        if (error) *error=@"目标类为空";
        return NO;
    }
    Method resolved=class_getInstanceMethod(cls,@selector(setActive:));
    if (!resolved) {
        if (error) *error=@"目标类不存在 -setActive:";
        return NO;
    }
    IMP original=method_getImplementation(resolved);
    const char *types=method_getTypeEncoding(resolved);
    if (!original || !types) {
        if (error) *error=@"无法取得 setActive: 原始 IMP/类型编码";
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
    if (!gZNSSPReplacementIMP) {
        if (error) *error=@"imp_implementationWithBlock 失败";
        return NO;
    }

    // If setActive: is inherited, add an override to MdhpNuX rather than
    // modifying the superclass Method globally. If it is directly implemented,
    // class_addMethod fails and we replace only the direct implementation.
    BOOL added=class_addMethod(cls,@selector(setActive:),gZNSSPReplacementIMP,types);
    NSString *hookMode=nil;
    if (added) {
        hookMode=@"class-override(inherited)";
    } else {
        Method direct=class_getInstanceMethod(cls,@selector(setActive:));
        if (!direct) {
            if (error) *error=@"无法取得直接 setActive: Method";
            return NO;
        }
        method_setImplementation(direct,gZNSSPReplacementIMP);
        hookMode=@"direct-replace";
    }

    self.targetClassName=NSStringFromClass(cls) ?: @"?";
    self.installed=YES;
    self.arming=NO;
    self.loggingEnabled=YES;
    [self appendLine:[NSString stringWithFormat:@"[SSP-INSTALL] class=%@ selector=setActive: mode=%@ original=%p impImage=%@ module=%@ shared=0x%llX",
                      self.targetClassName,hookMode,(void *)original,
                      ZNSSPIMPImage(resolved).length?ZNSSPIMPImage(resolved):@"?",
                      kZNSSPModule,kZNSSPSharedRVA]];
    [self captureCurrentStateWithLabel:@"probe-enabled"];
    return YES;
}

- (void)retryInstallToken:(NSUInteger)token remaining:(NSUInteger)remaining {
    if (token != self.armToken || self.installed || !self.arming) return;

    NSString *detail=nil;
    Class cls=ZNSSPFindTargetClass(&detail);
    if (cls) {
        NSString *e=nil;
        if ([self installOnClass:cls error:&e]) return;
        self.lastStatus=[NSString stringWithFormat:@"[SSP-RETRY] class found but install failed: %@",e ?: @"unknown"];
    }

    if (remaining == 0) {
        self.arming=NO;
        self.loggingEnabled=NO;
        [self appendLine:[NSString stringWithFormat:@"[SSP-FAIL] 10s 内未发现可 Hook Patch 类 · %@",detail ?: @"no detail"]];
        return;
    }

    self.lastStatus=[NSString stringWithFormat:@"[SSP-WAIT] 等待 Patch 类加载 · %@",detail ?: @"scanning"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.25*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        [self retryInstallToken:token remaining:remaining-1];
    });
}

- (BOOL)installAndEnable:(NSString **)error {
    if (self.installed) {
        self.loggingEnabled=YES;
        [self appendLine:[NSString stringWithFormat:@"[SSP-RESUME] class=%@ %@",self.targetClassName,[self siteSnapshot]]];
        return YES;
    }

    NSString *detail=nil;
    Class cls=ZNSSPFindTargetClass(&detail);
    if (cls) {
        NSString *e=nil;
        BOOL ok=[self installOnClass:cls error:&e];
        if (!ok && error) *error=e;
        return ok;
    }

    // Do not fail permanently just because EarntoDieRogue registers its patch
    // class after ZonoPatch's menu is already visible. Arm a bounded retry loop.
    self.arming=YES;
    self.loggingEnabled=YES;
    self.armToken += 1;
    NSUInteger token=self.armToken;
    [self appendLine:[NSString stringWithFormat:@"[SSP-ARM] 等待 MdhpNuX/-setActive: 加载 · %@",detail ?: @"scanning"]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.25*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        [self retryInstallToken:token remaining:39];
    });
    return YES;
}

- (void)setLoggingEnabled:(BOOL)enabled {
    if (!self.installed && enabled) {
        NSString *error=nil;
        [self installAndEnable:&error];
        return;
    }
    _loggingEnabled=enabled;
    if (!enabled && self.arming) {
        self.arming=NO;
        self.armToken += 1;
    }
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
    NSString *hook=self.installed?@"Installed":(self.arming?@"Waiting":@"Not installed");
    return @[
        [NSString stringWithFormat:@"Hook：%@ · Logging：%@",hook,self.loggingEnabled?@"ON":@"OFF"],
        [NSString stringWithFormat:@"Class：%@ · -setActive:",self.targetClassName.length?self.targetClassName:@"?"],
        [NSString stringWithFormat:@"Shared Site：%@ + 0x%llX",kZNSSPModule,kZNSSPSharedRVA],
        [NSString stringWithFormat:@"Posters-only：0x%llX · Prestige-only：0x%llX",kZNSSPPostersOnlyRVA,kZNSSPPrestigeOnlyRVA],
        [NSString stringWithFormat:@"Log：Documents/%@",self.logPath.lastPathComponent],
        [NSString stringWithFormat:@"Last：%@",self.lastStatus.length?self.lastStatus:@"-"]
    ];
}

@end
