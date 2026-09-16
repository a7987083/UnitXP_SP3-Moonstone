#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CommonCrypto/CommonDigest.h>
#import "OnDeviceLuaRecovery.h"

#include <dlfcn.h>
#include <pthread.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>

#define JCG5_VERSION @"JSONCapture v0.5 Manual Task Engine"
#define JCG5_MAX_BUFFER (512ULL * 1024ULL * 1024ULL)
#define JCG5_MAX_ARRAY_ITEMS 2000000ULL
#define JCG5_ENCM_XOR_KEY 0x4D
#define JCG5_CAPTURE_QUIET_SECONDS 0.75
#define JCG5_UI_REFRESH_SECONDS 1.0

typedef struct { void *klass; void *monitor; int32_t length; uint16_t chars[0]; } JCG5Il2CppString;
typedef struct { void *klass; void *monitor; void *bounds; uintptr_t max_length; void *vector[0]; } JCG5PtrArray;
typedef struct { void *klass; void *monitor; void *bounds; uintptr_t max_length; uint8_t vector[0]; } JCG5ByteArray;

typedef void *(*JCG5DomainGetFn)(void);
typedef const void **(*JCG5DomainGetAssembliesFn)(const void *domain, size_t *size);
typedef void *(*JCG5AssemblyGetImageFn)(const void *assembly);
typedef void *(*JCG5ClassFromNameFn)(const void *image, const char *namespaze, const char *name);
typedef const void *(*JCG5ClassGetMethodFromNameFn)(void *klass, const char *name, int argsCount);
typedef const void *(*JCG5ClassGetTypeFn)(void *klass);
typedef void *(*JCG5TypeGetObjectFn)(const void *type);
typedef void *(*JCG5StringNewFn)(const char *str);

typedef void *(*JCG5AssetBundleGetAllNamesFn)(void *self, const void *method);
typedef void *(*JCG5AssetBundleLoadAssetFn)(void *self, void *name, void *typeObj, const void *method);
typedef void *(*JCG5AssetBundleLoadFromFileFn)(void *managedPath, const void *method);
typedef void (*JCG5AssetBundleUnloadFn)(void *self, BOOL unloadAllLoadedObjects, const void *method);
typedef void *(*JCG5TextAssetGetBytesFn)(void *self, const void *method);

typedef int (*JCG5ToluaLoadBufferFn)(void *L, const char *buffer, int size, const char *name);
typedef int (*JCG5LuaLLoadBufferXFn)(void *L, const char *buffer, size_t size, const char *name, const char *mode);
typedef void (*JCG5MSHookFunctionFn)(void *symbol, void *replace, void **result);
typedef int (*JCG5DobbyHookFn)(void *address, void *replace, void **origin);

typedef NS_ENUM(NSInteger, JCG5TaskKind) {
    JCG5TaskIdle = 0,
    JCG5TaskLocalScan = 1,
    JCG5TaskDecrypt = 2,
    JCG5TaskRecover = 3,
};

static NSString *gJCG5Root;
static NSString *gJCG5BundleDir;
static NSString *gJCG5RawDir;
static NSString *gJCG5DecodedDir;
static NSString *gJCG5LoaderDir;
static NSString *gJCG5RecoveredDir;
static NSString *gJCG5PartialDir;
static NSString *gJCG5StateDir;
static NSString *gJCG5LogPath;

static dispatch_queue_t gJCG5CaptureQueue;
static dispatch_queue_t gJCG5TaskQueue;
static NSMutableSet *gJCG5CaptureHashes;
static pthread_mutex_t gJCG5StateLock = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t gJCG5LogLock = PTHREAD_MUTEX_INITIALIZER;

static BOOL gJCG5CaptureEnabled = YES;
static BOOL gJCG5HooksReady = NO;
static BOOL gJCG5UnityReady = NO;
static JCG5TaskKind gJCG5Task = JCG5TaskIdle;
static JCG5TaskKind gJCG5PendingTask = JCG5TaskIdle;
static BOOL gJCG5PendingRetry = NO;
static BOOL gJCG5Cancel = NO;
static BOOL gJCG5PreemptedByCapture = NO;
static NSTimeInterval gJCG5LastCaptureAt = 0;
static NSString *gJCG5LastEvent;
static NSString *gJCG5LastCaptureChunk;
static unsigned long long gJCG5CaptureCount = 0;

static unsigned long long gJCG5ScanTotal = 0;
static unsigned long long gJCG5ScanDone = 0;
static unsigned long long gJCG5ScanSuccess = 0;
static unsigned long long gJCG5ScanFailed = 0;
static unsigned long long gJCG5ScanIgnored = 0;
static unsigned long long gJCG5ScanTextAssets = 0;
static NSString *gJCG5ScanState;

static unsigned long long gJCG5DecryptTotal = 0;
static unsigned long long gJCG5DecryptDone = 0;
static unsigned long long gJCG5DecryptSuccess = 0;
static unsigned long long gJCG5DecryptFailed = 0;
static unsigned long long gJCG5DecryptSkipped = 0;
static NSString *gJCG5DecryptState;

static unsigned long long gJCG5RecoverComplete = 0;
static unsigned long long gJCG5RecoverPartial = 0;
static unsigned long long gJCG5RecoverFailed = 0;
static unsigned long long gJCG5RecoverRecords = 0;
static NSString *gJCG5RecoverState;

static JCG5ToluaLoadBufferFn gJCG5OrigToluaLoadBuffer;
static JCG5LuaLLoadBufferXFn gJCG5OrigLuaLLoadBufferX;

static JCG5AssetBundleGetAllNamesFn gJCG5GetAllAssetNames;
static const void *gJCG5GetAllAssetNamesMethod;
static JCG5AssetBundleLoadAssetFn gJCG5LoadAsset;
static const void *gJCG5LoadAssetMethod;
static JCG5AssetBundleLoadFromFileFn gJCG5LoadFromFile;
static const void *gJCG5LoadFromFileMethod;
static JCG5AssetBundleUnloadFn gJCG5Unload;
static const void *gJCG5UnloadMethod;
static JCG5TextAssetGetBytesFn gJCG5TextAssetGetBytes;
static const void *gJCG5TextAssetGetBytesMethod;
static void *gJCG5TextAssetTypeObject;
static JCG5StringNewFn gJCG5StringNew;

#pragma mark - Basic helpers

static NSString *JCG5Documents(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return paths.count ? paths[0] : NSTemporaryDirectory();
}

static void JCG5EnsureDir(NSString *path) {
    if (!path.length) return;
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
}

static void JCG5SetupPaths(void) {
    if (gJCG5Root.length) return;
    NSString *docs = JCG5Documents();
    gJCG5Root = [[[docs stringByAppendingPathComponent:@"JSONCapture"] stringByAppendingPathComponent:@"ManualV05"] retain];
    gJCG5BundleDir = [[docs stringByAppendingPathComponent:@"Bundle"] retain];
    gJCG5RawDir = [[gJCG5Root stringByAppendingPathComponent:@"raw_textasset"] retain];
    gJCG5DecodedDir = [[gJCG5Root stringByAppendingPathComponent:@"decoded_lua"] retain];
    gJCG5LoaderDir = [[gJCG5Root stringByAppendingPathComponent:@"lua_loader"] retain];
    gJCG5RecoveredDir = [[gJCG5Root stringByAppendingPathComponent:@"recovered_json"] retain];
    gJCG5PartialDir = [[gJCG5Root stringByAppendingPathComponent:@"recovered_partial"] retain];
    gJCG5StateDir = [[gJCG5Root stringByAppendingPathComponent:@"state"] retain];
    gJCG5LogPath = [[gJCG5Root stringByAppendingPathComponent:@"ManualV05.log"] retain];
    for (NSString *dir in @[gJCG5Root,gJCG5RawDir,gJCG5DecodedDir,gJCG5LoaderDir,gJCG5RecoveredDir,gJCG5PartialDir,gJCG5StateDir]) JCG5EnsureDir(dir);
}

static void JCG5Log(NSString *text) {
    if (!text.length) return;
    JCG5SetupPaths();
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], text];
    pthread_mutex_lock(&gJCG5LogLock);
    FILE *f = fopen(gJCG5LogPath.fileSystemRepresentation, "a");
    if (f) {
        NSData *d = [line dataUsingEncoding:NSUTF8StringEncoding];
        fwrite(d.bytes, 1, d.length, f); fflush(f); fclose(f);
    }
    pthread_mutex_unlock(&gJCG5LogLock);
}

static NSString *JCG5Safe(NSString *text, NSUInteger limit) {
    if (!text.length) return @"unnamed";
    NSMutableString *out = [NSMutableString stringWithCapacity:MIN(text.length, limit)];
    NSCharacterSet *ok = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.@+"];
    for (NSUInteger i=0; i<text.length && out.length<limit; i++) {
        unichar c = [text characterAtIndex:i];
        if ([ok characterIsMember:c]) [out appendFormat:@"%C", c]; else [out appendString:@"_"];
    }
    return out.length ? out : @"unnamed";
}

static NSString *JCG5SHA256(NSData *data) {
    if (!data.length) return @"";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *s = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH*2];
    for (NSUInteger i=0; i<CC_SHA256_DIGEST_LENGTH; i++) [s appendFormat:@"%02x", digest[i]];
    return s;
}

static BOOL JCG5HasLua53(NSData *data) {
    if (data.length < 5) return NO;
    const uint8_t *p = data.bytes;
    return p[0]==0x1B && p[1]=='L' && p[2]=='u' && p[3]=='a' && p[4]==0x53;
}

static NSInteger JCG5FindLua53(NSData *data) {
    if (data.length < 5) return NSNotFound;
    const uint8_t *p = data.bytes;
    NSUInteger max = MIN((NSUInteger)4096, data.length - 5);
    for (NSUInteger i=0; i<=max; i++) if (p[i]==0x1B && p[i+1]=='L' && p[i+2]=='u' && p[i+3]=='a' && p[i+4]==0x53) return (NSInteger)i;
    return NSNotFound;
}

static NSString *JCG5CanonicalStem(NSString *asset) {
    NSString *norm = [asset ?: @"unnamed" stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    NSString *base = norm.lastPathComponent.length ? norm.lastPathComponent : norm;
    BOOL changed = YES;
    while (changed && base.length) {
        changed = NO;
        NSString *lower = base.lowercaseString;
        for (NSString *ext in @[@".luac",@".lua",@".bytes",@".txt",@".bin"]) {
            if ([lower hasSuffix:ext]) { base=[base substringToIndex:base.length-ext.length]; changed=YES; break; }
        }
    }
    return JCG5Safe(base.length?base:@"unnamed", 120);
}

static NSString *JCG5GroupFromDecodedFilename(NSString *name) {
    NSString *base = name.lastPathComponent ?: name;
    NSRegularExpression *hashRe = [NSRegularExpression regularExpressionWithPattern:@"_[0-9a-fA-F]{12,64}\\.luac$" options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *m = [hashRe firstMatchInString:base options:0 range:NSMakeRange(0, base.length)];
    if (m) base = [base substringToIndex:m.range.location];
    BOOL changed=YES;
    while (changed && base.length) {
        changed=NO; NSString *lower=base.lowercaseString;
        for (NSString *ext in @[@".luac",@".lua",@".bytes",@".txt",@".bin"]) if ([lower hasSuffix:ext]) { base=[base substringToIndex:base.length-ext.length]; changed=YES; break; }
    }
    NSRegularExpression *tab = [NSRegularExpression regularExpressionWithPattern:@"^(TAB_[A-Za-z0-9][A-Za-z0-9_-]*?)(?:[_-](\\d{1,4}))?$" options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *tm=[tab firstMatchInString:base options:0 range:NSMakeRange(0,base.length)];
    if (tm && [tm rangeAtIndex:1].location!=NSNotFound) return [base substringWithRange:[tm rangeAtIndex:1]];
    NSRegularExpression *generic=[NSRegularExpression regularExpressionWithPattern:@"^(.*?)[_-](\\d{1,3})$" options:0 error:nil];
    NSTextCheckingResult *gm=[generic firstMatchInString:base options:0 range:NSMakeRange(0,base.length)];
    if (gm) {
        NSString *prefix=[base substringWithRange:[gm rangeAtIndex:1]]; NSString *pl=prefix.lowercaseString;
        if ([pl containsString:@"data"]||[pl containsString:@"config"]||[pl containsString:@"table"]||[pl containsString:@"list"]) return prefix;
    }
    return base.length?base:@"unnamed";
}

static BOOL JCG5WriteJSON(id obj, NSString *path) {
    if (!obj || !path.length) return NO;
    NSData *d=[NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingPrettyPrinted error:nil];
    return d && [d writeToFile:path options:NSDataWritingAtomic error:nil];
}

static NSDictionary *JCG5ReadJSON(NSString *path) {
    NSData *d=[NSData dataWithContentsOfFile:path]; if(!d.length)return nil;
    id o=[NSJSONSerialization JSONObjectWithData:d options:NSJSONReadingMutableContainers error:nil];
    return [o isKindOfClass:[NSDictionary class]]?o:nil;
}

static void JCG5ResetDirectory(NSString *dir) {
    NSFileManager *fm=[NSFileManager defaultManager];
    [fm removeItemAtPath:dir error:nil];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
}

static void JCG5SetEvent(NSString *text) {
    pthread_mutex_lock(&gJCG5StateLock);
    [gJCG5LastEvent release]; gJCG5LastEvent=[(text.length?text:@"暂无") copy];
    pthread_mutex_unlock(&gJCG5StateLock);
}

static BOOL JCG5ShouldStop(void) {
    pthread_mutex_lock(&gJCG5StateLock); BOOL v=gJCG5Cancel; pthread_mutex_unlock(&gJCG5StateLock); return v;
}

static NSString *JCG5TaskName(JCG5TaskKind task) {
    switch(task){case JCG5TaskLocalScan:return @"本地扫描";case JCG5TaskDecrypt:return @"解密";case JCG5TaskRecover:return @"JSON恢复";default:return @"空闲";}
}

static NSString *JCG5FailurePath(NSString *name) { return [gJCG5StateDir stringByAppendingPathComponent:name]; }

static NSArray *JCG5ReadFailureItems(NSString *name) {
    NSDictionary *root=JCG5ReadJSON(JCG5FailurePath(name)); id items=root[@"failures"];
    return [items isKindOfClass:[NSArray class]]?items:@[];
}

static void JCG5WriteFailureItems(NSString *name, NSArray *items, NSString *stage) {
    JCG5WriteJSON(@{ @"version":JCG5_VERSION,@"stage":stage?:@"unknown",@"failures":items?:@[],@"count":@((items?:@[]).count),@"updated_at":@([[NSDate date] timeIntervalSince1970]) },JCG5FailurePath(name));
}

#pragma mark - Dynamic symbols / loader hooks

static void *JCG5ResolveExport(const char *name) {
    void *p=dlsym(RTLD_DEFAULT,name); if(p)return p;
    const char *paths[]={"@rpath/UnityFramework.framework/UnityFramework","UnityFramework.framework/UnityFramework"};
    for(size_t i=0;i<sizeof(paths)/sizeof(paths[0]);i++){void*h=dlopen(paths[i],RTLD_LAZY|RTLD_GLOBAL);if(!h)continue;p=dlsym(h,name);if(p)return p;}
    return NULL;
}

static void *JCG5ResolveHookSymbol(const char *symbol) {
    void *p=dlsym(RTLD_DEFAULT,symbol);if(p)return p;
    const char *libs[]={"/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate","/var/jb/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate","/usr/lib/libsubstrate.dylib","/var/jb/usr/lib/libsubstrate.dylib","/usr/lib/libhooker.dylib","/var/jb/usr/lib/libhooker.dylib","/usr/lib/libellekit.dylib","/var/jb/usr/lib/libellekit.dylib"};
    for(size_t i=0;i<sizeof(libs)/sizeof(libs[0]);i++){void*h=dlopen(libs[i],RTLD_LAZY|RTLD_GLOBAL);if(!h)continue;p=dlsym(h,symbol);if(p)return p;}
    return NULL;
}

static BOOL JCG5Hook(void *address, void *replacement, void **original) {
    if(!address)return NO;
    JCG5MSHookFunctionFn ms=(JCG5MSHookFunctionFn)JCG5ResolveHookSymbol("MSHookFunction");
    if(ms){ms(address,replacement,original);if(original&&*original)return YES;}
    JCG5DobbyHookFn dobby=(JCG5DobbyHookFn)JCG5ResolveHookSymbol("DobbyHook");
    if(dobby){int rc=dobby(address,replacement,original);if(rc==0&&original&&*original)return YES;}
    return NO;
}

static void JCG5NotifyRuntimeCapture(void) {
    BOOL preempt=NO;
    pthread_mutex_lock(&gJCG5StateLock);
    if(gJCG5CaptureEnabled){
        gJCG5LastCaptureAt=[NSDate timeIntervalSinceReferenceDate];
        if(gJCG5Task!=JCG5TaskIdle){gJCG5Cancel=YES;gJCG5PendingTask=JCG5TaskIdle;gJCG5PendingRetry=NO;gJCG5PreemptedByCapture=YES;preempt=YES;}
    }
    pthread_mutex_unlock(&gJCG5StateLock);
    if(preempt) dispatch_async(dispatch_get_main_queue(),^{JCG5SetEvent(@"检测到运行时抓取：当前手动任务已停止");});
}

static void JCG5AppendLoaderManifest(NSString *file, NSString *source, NSString *chunk, NSString *sha, NSUInteger bytes) {
    NSDictionary *obj=@{ @"file":file?:@"",@"source":source?:@"",@"chunk":chunk?:@"",@"sha256":sha?:@"",@"bytes":@(bytes),@"time":@([[NSDate date] timeIntervalSince1970]) };
    NSData*d=[NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];if(!d)return;NSString*line=[[[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding]autorelease];
    NSString*path=[gJCG5Root stringByAppendingPathComponent:@"loader_manifest.jsonl"];
    pthread_mutex_lock(&gJCG5LogLock);FILE*f=fopen(path.fileSystemRepresentation,"a");if(f){NSData*ld=[[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];fwrite(ld.bytes,1,ld.length,f);fclose(f);}pthread_mutex_unlock(&gJCG5LogLock);
}

static void JCG5QueueLoaderCapture(NSData *data, NSString *source, NSString *chunkName) {
    if(!data.length||data.length>JCG5_MAX_BUFFER||!gJCG5CaptureQueue)return;
    NSData *snapshot=[NSData dataWithData:data]; NSString *src=[(source?:@"loader") copy]; NSString *chunk=[(chunkName?:@"unnamed") copy];
    dispatch_async(gJCG5CaptureQueue, ^{@autoreleasepool{
        NSString *hash=JCG5SHA256(snapshot);
        if(!hash.length||[gJCG5CaptureHashes containsObject:hash]){[src release];[chunk release];return;}
        [gJCG5CaptureHashes addObject:hash];
        pthread_mutex_lock(&gJCG5StateLock);gJCG5CaptureCount++;unsigned long long seq=gJCG5CaptureCount;[gJCG5LastCaptureChunk release];gJCG5LastCaptureChunk=[chunk copy];pthread_mutex_unlock(&gJCG5StateLock);
        NSString *shortHash=hash.length>12?[hash substringToIndex:12]:hash;
        NSString *ext=JCG5HasLua53(snapshot)?@"luac":@"bin";
        NSString *file=[NSString stringWithFormat:@"%06llu_%@_%@_%@.%@",seq,JCG5Safe(src,24),JCG5Safe(chunk,96),shortHash,ext];
        NSString *path=[gJCG5LoaderDir stringByAppendingPathComponent:file];
        [snapshot writeToFile:path atomically:YES];
        JCG5AppendLoaderManifest(file,src,chunk,hash,snapshot.length);
        [src release];[chunk release];
    }});
}

static int JCG5HookTolua(void *L, const char *buffer, int size, const char *name) {
    BOOL enabled; pthread_mutex_lock(&gJCG5StateLock);enabled=gJCG5CaptureEnabled;pthread_mutex_unlock(&gJCG5StateLock);
    if(enabled&&buffer&&size>0&&(uint64_t)size<=JCG5_MAX_BUFFER){JCG5NotifyRuntimeCapture();NSData*d=[NSData dataWithBytes:buffer length:(NSUInteger)size];NSString*chunk=name?[NSString stringWithUTF8String:name]:@"unnamed";JCG5QueueLoaderCapture(d,@"tolua_loadbuffer",chunk);}
    return gJCG5OrigToluaLoadBuffer?gJCG5OrigToluaLoadBuffer(L,buffer,size,name):-1;
}

static int JCG5HookLuaLX(void *L, const char *buffer, size_t size, const char *name, const char *mode) {
    BOOL enabled; pthread_mutex_lock(&gJCG5StateLock);enabled=gJCG5CaptureEnabled;pthread_mutex_unlock(&gJCG5StateLock);
    if(enabled&&buffer&&size>0&&size<=JCG5_MAX_BUFFER){JCG5NotifyRuntimeCapture();NSData*d=[NSData dataWithBytes:buffer length:size];NSString*chunk=name?[NSString stringWithUTF8String:name]:@"unnamed";JCG5QueueLoaderCapture(d,@"luaL_loadbufferx",chunk);}
    return gJCG5OrigLuaLLoadBufferX?gJCG5OrigLuaLLoadBufferX(L,buffer,size,name,mode):-1;
}

static BOOL JCG5InstallHooks(void) {
    if(gJCG5HooksReady)return YES;
    void *pTolua=JCG5ResolveExport("tolua_loadbuffer"); void *pLuaLX=JCG5ResolveExport("luaL_loadbufferx");
    BOOL a=pTolua?JCG5Hook(pTolua,(void*)JCG5HookTolua,(void**)&gJCG5OrigToluaLoadBuffer):NO;
    BOOL b=pLuaLX?JCG5Hook(pLuaLX,(void*)JCG5HookLuaLX,(void**)&gJCG5OrigLuaLLoadBufferX):NO;
    gJCG5HooksReady=a||b;
    if(gJCG5HooksReady)JCG5Log([NSString stringWithFormat:@"HOOK ready tolua=%d luaL_loadbufferx=%d",a,b]);
    return gJCG5HooksReady;
}

static void JCG5PollHooks(NSUInteger attempt) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{if(JCG5InstallHooks())return;if(attempt<120)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.25*NSEC_PER_SEC)),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{JCG5PollHooks(attempt+1);});else JCG5SetEvent(@"运行时抓取Hook未就绪");});
}

#pragma mark - Unity resolver and raw-only local scan

static NSString *JCG5ManagedString(void *ptr) {
    if(!ptr)return nil;JCG5Il2CppString*s=(JCG5Il2CppString*)ptr;if(s->length<=0||s->length>(4*1024*1024))return nil;
    @try{return [[[NSString alloc]initWithCharacters:(const unichar*)s->chars length:(NSUInteger)s->length]autorelease];}@catch(__unused NSException*e){return nil;}
}

static NSData *JCG5ByteData(void *ptr) {
    if(!ptr)return nil;JCG5ByteArray*a=(JCG5ByteArray*)ptr;if(!a->max_length||a->max_length>JCG5_MAX_BUFFER)return nil;
    @try{return [NSData dataWithBytes:a->vector length:(NSUInteger)a->max_length];}@catch(__unused NSException*e){return nil;}
}

static void *JCG5MethodPointer(const void *methodInfo) {
    if(!methodInfo)return NULL;@try{void*p=*(void*const*)methodInfo;if(!p)return NULL;Dl_info info;memset(&info,0,sizeof(info));if(dladdr(p,&info)==0)return NULL;return p;}@catch(__unused NSException*e){return NULL;}
}

static void *JCG5FindClass(JCG5DomainGetAssembliesFn assembliesFn,JCG5AssemblyGetImageFn imageFn,JCG5ClassFromNameFn classFn,void*domain,const char*ns,const char*name) {
    size_t count=0;const void**assemblies=assembliesFn(domain,&count);if(!assemblies||!count)return NULL;
    for(size_t i=0;i<count;i++){void*image=imageFn(assemblies[i]);if(!image)continue;void*klass=classFn(image,ns,name);if(klass)return klass;}return NULL;
}

static BOOL JCG5ResolveUnity(void) {
    if(gJCG5UnityReady)return YES;
    JCG5DomainGetFn domainGet=(JCG5DomainGetFn)JCG5ResolveExport("il2cpp_domain_get");
    JCG5DomainGetAssembliesFn assembliesFn=(JCG5DomainGetAssembliesFn)JCG5ResolveExport("il2cpp_domain_get_assemblies");
    JCG5AssemblyGetImageFn imageFn=(JCG5AssemblyGetImageFn)JCG5ResolveExport("il2cpp_assembly_get_image");
    JCG5ClassFromNameFn classFn=(JCG5ClassFromNameFn)JCG5ResolveExport("il2cpp_class_from_name");
    JCG5ClassGetMethodFromNameFn methodFn=(JCG5ClassGetMethodFromNameFn)JCG5ResolveExport("il2cpp_class_get_method_from_name");
    JCG5ClassGetTypeFn classGetType=(JCG5ClassGetTypeFn)JCG5ResolveExport("il2cpp_class_get_type");
    JCG5TypeGetObjectFn typeGetObject=(JCG5TypeGetObjectFn)JCG5ResolveExport("il2cpp_type_get_object");
    gJCG5StringNew=(JCG5StringNewFn)JCG5ResolveExport("il2cpp_string_new");
    if(!domainGet||!assembliesFn||!imageFn||!classFn||!methodFn||!classGetType||!typeGetObject||!gJCG5StringNew)return NO;
    void*domain=domainGet();if(!domain)return NO;
    void*bundleClass=JCG5FindClass(assembliesFn,imageFn,classFn,domain,"UnityEngine","AssetBundle");
    void*textClass=JCG5FindClass(assembliesFn,imageFn,classFn,domain,"UnityEngine","TextAsset");
    if(!bundleClass||!textClass)return NO;
    gJCG5GetAllAssetNamesMethod=methodFn(bundleClass,"GetAllAssetNames",0);
    gJCG5LoadAssetMethod=methodFn(bundleClass,"LoadAsset",2);
    gJCG5LoadFromFileMethod=methodFn(bundleClass,"LoadFromFile",1);
    gJCG5UnloadMethod=methodFn(bundleClass,"Unload",1);
    gJCG5TextAssetGetBytesMethod=methodFn(textClass,"get_bytes",0);
    gJCG5GetAllAssetNames=(JCG5AssetBundleGetAllNamesFn)JCG5MethodPointer(gJCG5GetAllAssetNamesMethod);
    gJCG5LoadAsset=(JCG5AssetBundleLoadAssetFn)JCG5MethodPointer(gJCG5LoadAssetMethod);
    gJCG5LoadFromFile=(JCG5AssetBundleLoadFromFileFn)JCG5MethodPointer(gJCG5LoadFromFileMethod);
    gJCG5Unload=(JCG5AssetBundleUnloadFn)JCG5MethodPointer(gJCG5UnloadMethod);
    gJCG5TextAssetGetBytes=(JCG5TextAssetGetBytesFn)JCG5MethodPointer(gJCG5TextAssetGetBytesMethod);
    const void*textType=classGetType(textClass);gJCG5TextAssetTypeObject=textType?typeGetObject(textType):NULL;
    gJCG5UnityReady=gJCG5GetAllAssetNames&&gJCG5LoadAsset&&gJCG5LoadFromFile&&gJCG5TextAssetGetBytes&&gJCG5TextAssetTypeObject;
    return gJCG5UnityReady;
}

static BOOL JCG5HasUnityMagic(NSString *path) {
    NSFileHandle*h=[NSFileHandle fileHandleForReadingAtPath:path];if(!h)return NO;NSData*d=nil;@try{d=[h readDataOfLength:16];[h closeFile];}@catch(__unused NSException*e){@try{[h closeFile];}@catch(__unused NSException*x){}return NO;}if(d.length<7)return NO;const uint8_t*p=d.bytes;return(d.length>=7&&memcmp(p,"UnityFS",7)==0)||(d.length>=8&&memcmp(p,"UnityRaw",8)==0)||(d.length>=8&&memcmp(p,"UnityWeb",8)==0);
}

static NSString *JCG5WriteRaw(NSData *data, NSString *asset) {
    NSString*hash=JCG5SHA256(data);NSString*shortHash=hash.length>12?[hash substringToIndex:12]:hash;NSString*file=[NSString stringWithFormat:@"%@_%@.bin",JCG5Safe(asset,150),shortHash];NSString*path=[gJCG5RawDir stringByAppendingPathComponent:file];if(![[NSFileManager defaultManager]fileExistsAtPath:path])[data writeToFile:path atomically:YES];return file;
}

static void JCG5AppendRawManifest(NSString *bundlePath, NSString *asset, NSString *rawFile, NSString *sha, NSUInteger bytes) {
    NSDictionary*obj=@{ @"origin":@"manual-local-scan",@"bundle":bundlePath?:@"",@"asset":asset?:@"",@"raw_file":rawFile?:@"",@"sha256":sha?:@"",@"bytes":@(bytes),@"time":@([[NSDate date]timeIntervalSince1970])};NSData*d=[NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];if(!d)return;NSString*line=[[[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding]autorelease];NSString*path=[gJCG5Root stringByAppendingPathComponent:@"manifest.jsonl"];pthread_mutex_lock(&gJCG5LogLock);FILE*f=fopen(path.fileSystemRepresentation,"a");if(f){NSData*ld=[[line stringByAppendingString:@"\n"]dataUsingEncoding:NSUTF8StringEncoding];fwrite(ld.bytes,1,ld.length,f);fclose(f);}pthread_mutex_unlock(&gJCG5LogLock);
}

static NSUInteger JCG5SweepRawOnly(void *bundle, NSString *bundlePath) {
    if(!bundle||!gJCG5GetAllAssetNames||!gJCG5LoadAsset||!gJCG5TextAssetGetBytes)return 0;
    void*namesObj=gJCG5GetAllAssetNames(bundle,gJCG5GetAllAssetNamesMethod);JCG5PtrArray*names=(JCG5PtrArray*)namesObj;if(!names||names->max_length>JCG5_MAX_ARRAY_ITEMS)return 0;NSUInteger count=0;
    for(NSUInteger i=0;i<(NSUInteger)names->max_length;i++){@autoreleasepool{if(JCG5ShouldStop())break;NSString*assetName=JCG5ManagedString(names->vector[i]);if(!assetName.length)continue;void*managedName=gJCG5StringNew(assetName.UTF8String);void*asset=managedName?gJCG5LoadAsset(bundle,managedName,gJCG5TextAssetTypeObject,gJCG5LoadAssetMethod):NULL;if(!asset)continue;void*bytesObj=gJCG5TextAssetGetBytes(asset,gJCG5TextAssetGetBytesMethod);NSData*raw=JCG5ByteData(bytesObj);if(!raw.length)continue;NSString*sha=JCG5SHA256(raw);NSString*rawFile=JCG5WriteRaw(raw,assetName);JCG5AppendRawManifest(bundlePath,assetName,rawFile,sha,raw.length);count++;}}
    return count;
}

static BOOL JCG5ProcessBundleOnMain(NSString *path, NSUInteger *textCount) {
    if(!JCG5ResolveUnity())return NO;void*managed=gJCG5StringNew(path.UTF8String);void*bundle=managed?gJCG5LoadFromFile(managed,gJCG5LoadFromFileMethod):NULL;if(!bundle)return NO;NSUInteger c=JCG5SweepRawOnly(bundle,path);if(textCount)*textCount=c;if(gJCG5Unload){@try{gJCG5Unload(bundle,YES,gJCG5UnloadMethod);}@catch(__unused NSException*e){}}return YES;
}

#pragma mark - Manual task engine

static void JCG5RequestTask(JCG5TaskKind kind, BOOL retry);

static NSArray *JCG5FilesRecursively(NSString *root) {
    NSFileManager*fm=[NSFileManager defaultManager];NSMutableArray*out=[NSMutableArray array];BOOL isDir=NO;if(![fm fileExistsAtPath:root isDirectory:&isDir]||!isDir)return out;NSDirectoryEnumerator*en=[fm enumeratorAtPath:root];for(NSString*rel in en){NSString*path=[root stringByAppendingPathComponent:rel];BOOL d=NO;if([fm fileExistsAtPath:path isDirectory:&d]&&!d)[out addObject:path];}return out;
}

static NSDictionary *JCG5ManifestMap(NSString *manifestPath, NSString *fileKey, NSString *assetKey) {
    NSData*d=[NSData dataWithContentsOfFile:manifestPath options:NSDataReadingMappedIfSafe error:nil];if(!d.length)return @{};NSString*t=[[[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding]autorelease];if(!t.length)return @{};NSMutableDictionary*m=[NSMutableDictionary dictionary];for(NSString*line in [t componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]){@autoreleasepool{if(line.length<2)continue;NSData*ld=[line dataUsingEncoding:NSUTF8StringEncoding];NSDictionary*o=[NSJSONSerialization JSONObjectWithData:ld options:0 error:nil];if(![o isKindOfClass:[NSDictionary class]])continue;NSString*f=o[fileKey],*a=o[assetKey];if(f.length&&a.length)m[f]=a;}}return m;
}

static NSData *JCG5DecodeCandidate(NSData *raw, NSString **kindOut, BOOL *candidateOut) {
    if(kindOut)*kindOut=@"none";if(candidateOut)*candidateOut=NO;if(!raw.length)return nil;
    if(JCG5HasLua53(raw)){if(kindOut)*kindOut=@"plain-luac53";if(candidateOut)*candidateOut=YES;return raw;}
    const uint8_t*p=raw.bytes;if(raw.length>4&&memcmp(p,"ENCM",4)==0){if(candidateOut)*candidateOut=YES;NSMutableData*out=[NSMutableData dataWithLength:raw.length-4];uint8_t*dst=out.mutableBytes;for(NSUInteger i=0;i<out.length;i++)dst[i]=p[i+4]^JCG5_ENCM_XOR_KEY;if(JCG5HasLua53(out)){if(kindOut)*kindOut=@"encm-xor4d";return out;}if(kindOut)*kindOut=@"encm-invalid";return nil;}
    NSInteger off=JCG5FindLua53(raw);if(off>0&&(NSUInteger)off<raw.length){if(candidateOut)*candidateOut=YES;if(kindOut)*kindOut=[NSString stringWithFormat:@"wrapped+%ld",(long)off];return [raw subdataWithRange:NSMakeRange((NSUInteger)off,raw.length-(NSUInteger)off)];}
    return nil;
}

static void JCG5FinishTask(NSString *finalState) {
    JCG5TaskKind pending=JCG5TaskIdle;BOOL retry=NO;BOOL preempted=NO;
    pthread_mutex_lock(&gJCG5StateLock);preempted=gJCG5PreemptedByCapture;if(!preempted){pending=gJCG5PendingTask;retry=gJCG5PendingRetry;}gJCG5Task=JCG5TaskIdle;gJCG5PendingTask=JCG5TaskIdle;gJCG5PendingRetry=NO;gJCG5Cancel=NO;gJCG5PreemptedByCapture=NO;pthread_mutex_unlock(&gJCG5StateLock);
    if(finalState.length)JCG5SetEvent(finalState);
    if(pending!=JCG5TaskIdle)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.20*NSEC_PER_SEC)),dispatch_get_main_queue(),^{JCG5RequestTask(pending,retry);});
}

static void JCG5RunLocalScan(BOOL retryOnly) {
    @autoreleasepool{
        NSMutableArray*failures=[NSMutableArray array];NSArray*paths=nil;
        if(retryOnly){NSMutableArray*p=[NSMutableArray array];for(id item in JCG5ReadFailureItems(@"LocalScan.failures.json")){if([item isKindOfClass:[NSDictionary class]]&&[item[@"path"] length])[p addObject:item[@"path"]];}paths=p;}else paths=JCG5FilesRecursively(gJCG5BundleDir);
        pthread_mutex_lock(&gJCG5StateLock);gJCG5ScanTotal=paths.count;gJCG5ScanDone=gJCG5ScanSuccess=gJCG5ScanFailed=gJCG5ScanIgnored=gJCG5ScanTextAssets=0;[gJCG5ScanState release];gJCG5ScanState=[(retryOnly?@"重试失败中":@"扫描中") copy];pthread_mutex_unlock(&gJCG5StateLock);
        if(!paths.count){pthread_mutex_lock(&gJCG5StateLock);[gJCG5ScanState release];gJCG5ScanState=[@"无可扫描文件" copy];pthread_mutex_unlock(&gJCG5StateLock);JCG5FinishTask(@"本地扫描：没有可处理文件");return;}
        __block BOOL unityReady=NO;dispatch_sync(dispatch_get_main_queue(),^{unityReady=JCG5ResolveUnity();});if(!unityReady){pthread_mutex_lock(&gJCG5StateLock);[gJCG5ScanState release];gJCG5ScanState=[@"Unity接口未就绪" copy];pthread_mutex_unlock(&gJCG5StateLock);JCG5FinishTask(@"本地扫描停止：Unity接口未就绪");return;}
        for(NSString*path in paths){@autoreleasepool{if(JCG5ShouldStop())break;BOOL magic=JCG5HasUnityMagic(path);if(!magic){pthread_mutex_lock(&gJCG5StateLock);gJCG5ScanDone++;gJCG5ScanIgnored++;pthread_mutex_unlock(&gJCG5StateLock);continue;}__block BOOL ok=NO;__block NSUInteger text=0;dispatch_sync(dispatch_get_main_queue(),^{ok=JCG5ProcessBundleOnMain(path,&text);});pthread_mutex_lock(&gJCG5StateLock);gJCG5ScanDone++;if(ok){gJCG5ScanSuccess++;gJCG5ScanTextAssets+=text;}else gJCG5ScanFailed++;pthread_mutex_unlock(&gJCG5StateLock);if(!ok)[failures addObject:@{ @"path":path,@"reason":@"AssetBundle.LoadFromFile failed" }];usleep(2000);}}
        JCG5WriteFailureItems(@"LocalScan.failures.json",failures,@"local-scan");BOOL stopped=JCG5ShouldStop();pthread_mutex_lock(&gJCG5StateLock);[gJCG5ScanState release];gJCG5ScanState=[(stopped?(gJCG5PreemptedByCapture?@"被抓取停止":@"已停止"):@"已完成") copy];pthread_mutex_unlock(&gJCG5StateLock);JCG5FinishTask(stopped?@"本地扫描已停止":@"本地扫描完成");
    }
}

static NSArray *JCG5BuildDecryptInputs(BOOL retryOnly) {
    if(retryOnly)return JCG5ReadFailureItems(@"Decrypt.failures.json");
    NSDictionary*rawMap=JCG5ManifestMap([gJCG5Root stringByAppendingPathComponent:@"manifest.jsonl"],@"raw_file",@"asset");NSDictionary*loaderMap=JCG5ManifestMap([gJCG5Root stringByAppendingPathComponent:@"loader_manifest.jsonl"],@"file",@"chunk");NSMutableArray*out=[NSMutableArray array];NSFileManager*fm=[NSFileManager defaultManager];
    for(NSString*dir in @[gJCG5RawDir,gJCG5LoaderDir]){NSDictionary*map=[dir isEqualToString:gJCG5RawDir]?rawMap:loaderMap;for(NSString*name in [fm contentsOfDirectoryAtPath:dir error:nil]){NSString*path=[dir stringByAppendingPathComponent:name];BOOL isDir=NO;if(![fm fileExistsAtPath:path isDirectory:&isDir]||isDir)continue;NSString*asset=map[name]?:name;[out addObject:@{ @"path":path,@"asset":asset }];}}
    return out;
}

static void JCG5RunDecrypt(BOOL retryOnly) {
    @autoreleasepool{
        NSArray*inputs=JCG5BuildDecryptInputs(retryOnly);if(!retryOnly)JCG5ResetDirectory(gJCG5DecodedDir);NSMutableArray*failures=[NSMutableArray array];pthread_mutex_lock(&gJCG5StateLock);gJCG5DecryptTotal=inputs.count;gJCG5DecryptDone=gJCG5DecryptSuccess=gJCG5DecryptFailed=gJCG5DecryptSkipped=0;[gJCG5DecryptState release];gJCG5DecryptState=[(retryOnly?@"重试失败中":@"解密中") copy];pthread_mutex_unlock(&gJCG5StateLock);
        for(NSDictionary*item in inputs){@autoreleasepool{if(JCG5ShouldStop())break;NSString*path=item[@"path"],*asset=item[@"asset"]?:path.lastPathComponent;NSData*raw=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];BOOL candidate=NO;NSString*kind=nil;NSData*out=raw.length?JCG5DecodeCandidate(raw,&kind,&candidate):nil;BOOL ok=NO,skip=NO;if(out.length&&JCG5HasLua53(out)){NSString*dh=JCG5SHA256(out);NSString*stem=JCG5CanonicalStem(asset);NSString*file=[NSString stringWithFormat:@"%@_%@.luac",stem,[dh substringToIndex:MIN((NSUInteger)12,dh.length)]];NSString*dest=[gJCG5DecodedDir stringByAppendingPathComponent:file];ok=[[NSFileManager defaultManager]fileExistsAtPath:dest]||[out writeToFile:dest atomically:YES];}else if(!candidate){skip=YES;}
            pthread_mutex_lock(&gJCG5StateLock);gJCG5DecryptDone++;if(ok)gJCG5DecryptSuccess++;else if(skip)gJCG5DecryptSkipped++;else gJCG5DecryptFailed++;pthread_mutex_unlock(&gJCG5StateLock);if(!ok&&!skip)[failures addObject:@{ @"path":path?:@"",@"asset":asset?:@"",@"reason":kind?:@"decode failed" }];}}
        JCG5WriteFailureItems(@"Decrypt.failures.json",failures,@"decrypt");BOOL stopped=JCG5ShouldStop();pthread_mutex_lock(&gJCG5StateLock);[gJCG5DecryptState release];gJCG5DecryptState=[(stopped?(gJCG5PreemptedByCapture?@"被抓取停止":@"已停止"):@"已完成") copy];pthread_mutex_unlock(&gJCG5StateLock);JCG5FinishTask(stopped?@"解密已停止":@"解密完成");
    }
}

static NSArray *JCG5FailureGroupsFromReport(void) {
    NSDictionary*report=JCG5ReadJSON([gJCG5Root stringByAppendingPathComponent:@"MobileRecovery.report.json"]);id groups=report[@"groups"];NSMutableArray*out=[NSMutableArray array];
    void (^inspect)(NSDictionary*)=^(NSDictionary*r){NSString*s=r[@"status"],*g=r[@"group"];if(g.length&&!([s isEqualToString:@"complete"]||[s isEqualToString:@"partial"]))[out addObject:g];};
    if([groups isKindOfClass:[NSArray class]]){for(id r in groups)if([r isKindOfClass:[NSDictionary class]])inspect(r);}else if([groups isKindOfClass:[NSDictionary class]]){for(id k in groups){id r=groups[k];if([r isKindOfClass:[NSDictionary class]])inspect(r);}}return out;
}

static NSString *JCG5BuildRetryRecoveryDir(NSArray *groups) {
    NSString*dir=[gJCG5StateDir stringByAppendingPathComponent:@"recovery_retry_input"];JCG5ResetDirectory(dir);NSSet*wanted=[NSSet setWithArray:groups];NSFileManager*fm=[NSFileManager defaultManager];for(NSString*name in [fm contentsOfDirectoryAtPath:gJCG5DecodedDir error:nil]){NSString*group=JCG5GroupFromDecodedFilename(name);if(![wanted containsObject:group])continue;NSString*src=[gJCG5DecodedDir stringByAppendingPathComponent:name],*dst=[dir stringByAppendingPathComponent:name];NSError*err=nil;if(![fm linkItemAtPath:src toPath:dst error:&err]){err=nil;[fm copyItemAtPath:src toPath:dst error:&err];}}return dir;
}

static void JCG5RunRecover(BOOL retryOnly) {
    @autoreleasepool{
        NSString*input=gJCG5DecodedDir;if(retryOnly){NSArray*groups=JCG5ReadFailureItems(@"Recovery.failures.json");NSMutableArray*names=[NSMutableArray array];for(id x in groups){if([x isKindOfClass:[NSDictionary class]]&&[x[@"group"] length])[names addObject:x[@"group"]];else if([x isKindOfClass:[NSString class]])[names addObject:x];}if(!names.count){JCG5FinishTask(@"JSON恢复：没有失败组可重试");return;}input=JCG5BuildRetryRecoveryDir(names);}else{JCG5ResetDirectory(gJCG5RecoveredDir);JCG5ResetDirectory(gJCG5PartialDir);[[NSFileManager defaultManager]removeItemAtPath:[gJCG5Root stringByAppendingPathComponent:@"dynamic_lua"] error:nil];ODLRResetRecoveryIndex(gJCG5Root);}
        pthread_mutex_lock(&gJCG5StateLock);[gJCG5RecoverState release];gJCG5RecoverState=[(retryOnly?@"重试失败中":@"恢复中") copy];gJCG5RecoverComplete=gJCG5RecoverPartial=gJCG5RecoverFailed=gJCG5RecoverRecords=0;pthread_mutex_unlock(&gJCG5StateLock);
        NSDictionary*stats=ODLRRecoverDecodedDirectory(input,gJCG5Root,YES,^BOOL{return JCG5ShouldStop();},^(NSDictionary*event){NSString*g=event[@"group"];if(g.length)JCG5SetEvent([NSString stringWithFormat:@"恢复：%@",g]);});
        NSArray*failedGroups=JCG5FailureGroupsFromReport();NSMutableArray*failItems=[NSMutableArray array];for(NSString*g in failedGroups)[failItems addObject:@{ @"group":g }];JCG5WriteFailureItems(@"Recovery.failures.json",failItems,@"recovery");
        pthread_mutex_lock(&gJCG5StateLock);gJCG5RecoverComplete=[stats[@"tables_complete"] unsignedLongLongValue];gJCG5RecoverPartial=[stats[@"tables_partial"] unsignedLongLongValue];gJCG5RecoverFailed=failedGroups.count;gJCG5RecoverRecords=[stats[@"records_recovered"] unsignedLongLongValue];BOOL stopped=JCG5ShouldStop()||[stats[@"yielded_for_capture"] boolValue];[gJCG5RecoverState release];gJCG5RecoverState=[(stopped?(gJCG5PreemptedByCapture?@"被抓取停止":@"已停止"):@"已完成") copy];pthread_mutex_unlock(&gJCG5StateLock);JCG5FinishTask(stopped?@"JSON恢复已停止":@"JSON恢复完成");
    }
}

static void JCG5RequestTask(JCG5TaskKind kind, BOOL retry) {
    if(kind==JCG5TaskIdle)return;NSTimeInterval now=[NSDate timeIntervalSinceReferenceDate];
    pthread_mutex_lock(&gJCG5StateLock);
    if(gJCG5Task!=JCG5TaskIdle){gJCG5PendingTask=kind;gJCG5PendingRetry=retry;gJCG5Cancel=YES;pthread_mutex_unlock(&gJCG5StateLock);JCG5SetEvent([NSString stringWithFormat:@"正在停止%@，随后启动%@",JCG5TaskName(gJCG5Task),JCG5TaskName(kind)]);return;}
    if(gJCG5CaptureEnabled&&gJCG5LastCaptureAt>0&&(now-gJCG5LastCaptureAt)<JCG5_CAPTURE_QUIET_SECONDS){pthread_mutex_unlock(&gJCG5StateLock);JCG5SetEvent(@"刚发生运行时抓取，请稍后再启动手动任务");return;}
    gJCG5Task=kind;gJCG5Cancel=NO;gJCG5PreemptedByCapture=NO;pthread_mutex_unlock(&gJCG5StateLock);JCG5SetEvent([NSString stringWithFormat:@"开始%@%@",JCG5TaskName(kind),retry?@"（重试失败）":@""]);
    dispatch_async(gJCG5TaskQueue, ^{@autoreleasepool{if(kind==JCG5TaskLocalScan)JCG5RunLocalScan(retry);else if(kind==JCG5TaskDecrypt)JCG5RunDecrypt(retry);else if(kind==JCG5TaskRecover)JCG5RunRecover(retry);}});
}

static void JCG5StopCurrentTask(void) {
    pthread_mutex_lock(&gJCG5StateLock);if(gJCG5Task!=JCG5TaskIdle){gJCG5Cancel=YES;gJCG5PendingTask=JCG5TaskIdle;gJCG5PendingRetry=NO;}pthread_mutex_unlock(&gJCG5StateLock);JCG5SetEvent(@"已请求停止当前手动任务");
}

#pragma mark - UI

@interface JCG5PassthroughView : UIView @end
@implementation JCG5PassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event { UIView *hit=[super hitTest:point withEvent:event]; return hit==self?nil:hit; }
@end

@interface JCG5PassthroughWindow : UIWindow @end
@implementation JCG5PassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event { UIView*hit=[super hitTest:point withEvent:event];UIView*root=self.rootViewController.view;return(hit==self||hit==root)?nil:hit; }
@end

@interface JCG5Controller : UIViewController
@property(nonatomic,retain) UIButton *bubble;
@property(nonatomic,retain) UIView *panel;
@property(nonatomic,retain) NSMutableDictionary *labels;
@property(nonatomic,assign) BOOL expanded;
@end

static JCG5PassthroughWindow *gJCG5Window;
static JCG5Controller *gJCG5Controller;

static UILabel *JCG5Label(CGRect f, CGFloat size, BOOL bold) { UILabel*l=[[[UILabel alloc]initWithFrame:f]autorelease];l.textColor=[UIColor colorWithWhite:0.95 alpha:1];l.font=bold?[UIFont boldSystemFontOfSize:size]:[UIFont systemFontOfSize:size];l.numberOfLines=0;return l; }
static UIButton *JCG5Button(NSString *title,id target,SEL action,CGRect f){UIButton*b=[UIButton buttonWithType:UIButtonTypeSystem];b.frame=f;[b setTitle:title forState:UIControlStateNormal];[b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];b.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];b.backgroundColor=[UIColor colorWithWhite:0.18 alpha:0.96];b.layer.cornerRadius=8;[b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];return b;}

@implementation JCG5Controller
- (void)loadView { JCG5PassthroughView*v=[[[JCG5PassthroughView alloc]initWithFrame:UIScreen.mainScreen.bounds]autorelease];v.backgroundColor=UIColor.clearColor;self.view=v; }
- (void)viewDidLoad {
    [super viewDidLoad];self.labels=[NSMutableDictionary dictionary];CGSize s=self.view.bounds.size;self.bubble=[UIButton buttonWithType:UIButtonTypeCustom];self.bubble.frame=CGRectMake(s.width-62,110,52,52);self.bubble.layer.cornerRadius=26;self.bubble.backgroundColor=[UIColor colorWithWhite:0.08 alpha:0.94];self.bubble.layer.borderWidth=1;self.bubble.layer.borderColor=[UIColor colorWithRed:0.25 green:0.9 blue:0.5 alpha:0.9].CGColor;self.bubble.titleLabel.numberOfLines=3;self.bubble.titleLabel.textAlignment=NSTextAlignmentCenter;self.bubble.titleLabel.font=[UIFont boldSystemFontOfSize:10];[self.bubble setTitle:@"J5\n空闲" forState:UIControlStateNormal];[self.bubble addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];UIPanGestureRecognizer*pan=[[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(drag:)]autorelease];[self.bubble addGestureRecognizer:pan];[self.view addSubview:self.bubble];
    CGFloat pw=MIN(306.0,s.width-20),ph=MIN(520.0,s.height-40);self.panel=[[[UIView alloc]initWithFrame:CGRectMake(MAX(10,s.width-pw-10),55,pw,ph)]autorelease];self.panel.backgroundColor=[UIColor colorWithWhite:0.055 alpha:0.97];self.panel.layer.cornerRadius=14;self.panel.hidden=YES;[self.view addSubview:self.panel];UILabel*t=JCG5Label(CGRectMake(12,8,pw-62,26),15,YES);t.text=@"JSONCapture v0.5 手动任务";[self.panel addSubview:t];[self.panel addSubview:JCG5Button(@"收起",self,@selector(togglePanel),CGRectMake(pw-54,7,46,30))];
    CGFloat x=12,y=42,w=pw-24;NSArray*spec=@[@[@"capture",@"运行时抓取"],@[@"scan",@"本地扫描"],@[@"decrypt",@"解密"],@[@"recover",@"JSON恢复"],@[@"task",@"当前任务"]];for(NSArray*a in spec){UILabel*h=JCG5Label(CGRectMake(x,y,w,18),12,YES);h.text=a[1];h.textColor=[UIColor colorWithRed:0.45 green:0.9 blue:0.62 alpha:1];[self.panel addSubview:h];y+=18;UILabel*l=JCG5Label(CGRectMake(x,y,w,38),11.5,NO);l.text=@"读取中…";self.labels[a[0]]=l;[self.panel addSubview:l];y+=40;}
    NSArray*buttons=@[@[@"抓取：开",NSStringFromSelector(@selector(toggleCapture))],@[@"停止当前任务",NSStringFromSelector(@selector(stopTask))],@[@"开始本地扫描",NSStringFromSelector(@selector(startScan))],@[@"重试扫描失败",NSStringFromSelector(@selector(retryScan))],@[@"开始解密",NSStringFromSelector(@selector(startDecrypt))],@[@"重试解密失败",NSStringFromSelector(@selector(retryDecrypt))],@[@"开始JSON恢复",NSStringFromSelector(@selector(startRecover))],@[@"重试恢复失败",NSStringFromSelector(@selector(retryRecover))]];CGFloat gap=8,bw=(w-gap)/2,bh=34;for(NSUInteger i=0;i<buttons.count;i++){NSArray*b=buttons[i];UIButton*btn=JCG5Button(b[0],self,NSSelectorFromString(b[1]),CGRectMake(x+(i%2)*(bw+gap),y+(i/2)*(bh+7),bw,bh));btn.tag=200+i;[self.panel addSubview:btn];}
    self.expanded=NO;[self scheduleRefresh];
}
- (void)dealloc { [_bubble release];[_panel release];[_labels release];[super dealloc]; }
- (void)drag:(UIPanGestureRecognizer*)p { CGPoint t=[p translationInView:self.view],c=self.bubble.center;c.x=MAX(30,MIN(self.view.bounds.size.width-30,c.x+t.x));c.y=MAX(30,MIN(self.view.bounds.size.height-30,c.y+t.y));self.bubble.center=c;[p setTranslation:CGPointZero inView:self.view]; }
- (void)togglePanel { self.expanded=!self.expanded;self.panel.hidden=!self.expanded;self.bubble.hidden=self.expanded; }
- (void)scheduleRefresh { dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(JCG5_UI_REFRESH_SECONDS*NSEC_PER_SEC)),dispatch_get_main_queue(),^{if(gJCG5Controller){[gJCG5Controller refresh];[gJCG5Controller scheduleRefresh];}}); }
- (void)refresh {
    pthread_mutex_lock(&gJCG5StateLock);BOOL cap=gJCG5CaptureEnabled,hooks=gJCG5HooksReady;JCG5TaskKind task=gJCG5Task;unsigned long long cc=gJCG5CaptureCount,st=gJCG5ScanTotal,sd=gJCG5ScanDone,ss=gJCG5ScanSuccess,sf=gJCG5ScanFailed,si=gJCG5ScanIgnored,sta=gJCG5ScanTextAssets,dt=gJCG5DecryptTotal,dd=gJCG5DecryptDone,ds=gJCG5DecryptSuccess,df=gJCG5DecryptFailed,dsk=gJCG5DecryptSkipped,rc=gJCG5RecoverComplete,rp=gJCG5RecoverPartial,rf=gJCG5RecoverFailed,rr=gJCG5RecoverRecords;NSString*chunk=[[(gJCG5LastCaptureChunk?:@"暂无") copy] autorelease],*scan=[[(gJCG5ScanState?:@"未运行") copy] autorelease],*dec=[[(gJCG5DecryptState?:@"未运行") copy] autorelease],*rec=[[(gJCG5RecoverState?:@"未运行") copy] autorelease],*event=[[(gJCG5LastEvent?:@"暂无") copy] autorelease];pthread_mutex_unlock(&gJCG5StateLock);
    self.labels[@"capture"].text=[NSString stringWithFormat:@"状态：%@  Hook：%@  捕获：%llu\n最新：%@",cap?@"开启 ✅":@"关闭",hooks?@"就绪":@"等待",cc,chunk.lastPathComponent?:chunk];
    self.labels[@"scan"].text=[NSString stringWithFormat:@"Documents/Bundle｜%@ %llu/%llu\n成功%llu 失败%llu 忽略%llu TextAsset%llu",scan,sd,st,ss,sf,si,sta];
    self.labels[@"decrypt"].text=[NSString stringWithFormat:@"%@  %llu/%llu  成功%llu 失败%llu\n非Lua跳过%llu",dec,dd,dt,ds,df,dsk];
    self.labels[@"recover"].text=[NSString stringWithFormat:@"%@  完整%llu 部分%llu 失败%llu\n记录%llu",rec,rc,rp,rf,rr];
    self.labels[@"task"].text=[NSString stringWithFormat:@"%@\n%@",JCG5TaskName(task),event];
    [self.bubble setTitle:[NSString stringWithFormat:@"J5\n%@",task==JCG5TaskIdle?(cap?@"抓取开":@"空闲"):JCG5TaskName(task)] forState:UIControlStateNormal];UIButton*b=(UIButton*)[self.panel viewWithTag:200];if([b isKindOfClass:[UIButton class]])[b setTitle:(cap?@"抓取：开":@"抓取：关") forState:UIControlStateNormal];
}
- (void)toggleCapture { pthread_mutex_lock(&gJCG5StateLock);gJCG5CaptureEnabled=!gJCG5CaptureEnabled;BOOL on=gJCG5CaptureEnabled;pthread_mutex_unlock(&gJCG5StateLock);JCG5SetEvent(on?@"运行时抓取已开启":@"运行时抓取已关闭"); }
- (void)stopTask { JCG5StopCurrentTask(); }
- (void)startScan { JCG5RequestTask(JCG5TaskLocalScan,NO); }
- (void)retryScan { JCG5RequestTask(JCG5TaskLocalScan,YES); }
- (void)startDecrypt { JCG5RequestTask(JCG5TaskDecrypt,NO); }
- (void)retryDecrypt { JCG5RequestTask(JCG5TaskDecrypt,YES); }
- (void)startRecover { JCG5RequestTask(JCG5TaskRecover,NO); }
- (void)retryRecover { JCG5RequestTask(JCG5TaskRecover,YES); }
@end

static void JCG5InstallUI(void) {
    if(gJCG5Window)return;CGRect frame=UIScreen.mainScreen.bounds;gJCG5Window=[[JCG5PassthroughWindow alloc]initWithFrame:frame];gJCG5Window.windowLevel=UIWindowLevelAlert+6;gJCG5Controller=[[JCG5Controller alloc]init];gJCG5Window.rootViewController=gJCG5Controller;gJCG5Window.backgroundColor=UIColor.clearColor;gJCG5Window.hidden=NO;
}

__attribute__((constructor)) static void JCG5Entry(void) {
    @autoreleasepool{
        JCG5SetupPaths();gJCG5CaptureQueue=dispatch_queue_create("com.openai.jsoncapture.v05.capture",DISPATCH_QUEUE_SERIAL);gJCG5TaskQueue=dispatch_queue_create("com.openai.jsoncapture.v05.manualtask",DISPATCH_QUEUE_SERIAL);gJCG5CaptureHashes=[[NSMutableSet alloc]init];gJCG5ScanState=[@"未运行" copy];gJCG5DecryptState=[@"未运行" copy];gJCG5RecoverState=[@"未运行" copy];gJCG5LastEvent=[@"空闲；所有任务均为手动启动" copy];JCG5Log([NSString stringWithFormat:@"%@ loaded; no bundle watcher, no disk watcher, no auto decrypt, no auto recovery",JCG5_VERSION]);JCG5PollHooks(0);dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.0*NSEC_PER_SEC)),dispatch_get_main_queue(),^{JCG5InstallUI();});
    }
}
