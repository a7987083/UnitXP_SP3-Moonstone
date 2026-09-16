#import "JCG53RuntimeCapture2.h"
#import <CommonCrypto/CommonDigest.h>

#include <dlfcn.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>

#define JCG53_VERSION @"JSONCapture v0.5.3 Runtime Capture 2"
#define JCG53_MAX_JSON_BYTES (128ULL * 1024ULL * 1024ULL)

typedef const char *(*JCG53LuaPushLStringFn)(void *L, const char *s, size_t len);
typedef void (*JCG53MSHookFunctionFn)(void *symbol, void *replace, void **result);
typedef int (*JCG53DobbyHookFn)(void *address, void *replace, void **origin);

static JCG53LuaPushLStringFn gOrigLuaPushLString;
static dispatch_queue_t gQueue;
static NSMutableSet *gMD5s;
static NSMutableSet *gSHA256s;
static NSString *gRoot;
static NSString *gJSONDir;
static NSString *gCachePath;
static NSString *gManifestPath;
static NSString *gLogPath;
static pthread_mutex_t gStateLock = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t gLogLock = PTHREAD_MUTEX_INITIALIZER;
static _Atomic(int) gEnabled = 1;
static BOOL gStarted = NO;
static BOOL gHookReady = NO;
static unsigned long long gCaptured = 0;
static unsigned long long gSkipped = 0;
static unsigned long long gCacheLoaded = 0;
static NSString *gLastItem;
static NSString *gLastStatus;

static NSString *JCG53Documents(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return paths.count ? [paths objectAtIndex:0] : NSTemporaryDirectory();
}

static void JCG53EnsureDir(NSString *path) {
    if (!path.length) return;
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
}

static void JCG53SetupPaths(void) {
    if (gRoot.length) return;
    gRoot = [[[[JCG53Documents() stringByAppendingPathComponent:@"JSONCapture"] stringByAppendingPathComponent:@"ManualV05"] stringByStandardizingPath] retain];
    gJSONDir = [[gRoot stringByAppendingPathComponent:@"runtime_json"] retain];
    NSString *state = [gRoot stringByAppendingPathComponent:@"state"];
    gCachePath = [[state stringByAppendingPathComponent:@"RuntimeCapture2.cache.jsonl"] retain];
    gManifestPath = [[gRoot stringByAppendingPathComponent:@"runtime_json_manifest.jsonl"] retain];
    gLogPath = [[gRoot stringByAppendingPathComponent:@"RuntimeCapture2.log"] retain];
    JCG53EnsureDir(gRoot); JCG53EnsureDir(gJSONDir); JCG53EnsureDir(state);
}

static void JCG53Log(NSString *text) {
    if (!text.length) return;
    JCG53SetupPaths();
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], text];
    pthread_mutex_lock(&gLogLock);
    FILE *f = fopen(gLogPath.fileSystemRepresentation, "a");
    if (f) { NSData *d = [line dataUsingEncoding:NSUTF8StringEncoding]; fwrite(d.bytes,1,d.length,f); fflush(f); fclose(f); }
    pthread_mutex_unlock(&gLogLock);
}

static void JCG53AppendJSONL(NSString *path, NSDictionary *obj) {
    NSData *d = obj ? [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil] : nil;
    if (!path.length || !d.length) return;
    pthread_mutex_lock(&gLogLock);
    FILE *f = fopen(path.fileSystemRepresentation, "a");
    if (f) { fwrite(d.bytes,1,d.length,f); fwrite("\n",1,1,f); fflush(f); fclose(f); }
    pthread_mutex_unlock(&gLogLock);
}

static NSString *JCG53MD5(NSData *data) {
    if (!data.length) return @"";
    unsigned char digest[CC_MD5_DIGEST_LENGTH]; CC_MD5(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *s=[NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH*2];
    for(NSUInteger i=0;i<CC_MD5_DIGEST_LENGTH;i++) [s appendFormat:@"%02x",digest[i]];
    return s;
}

static NSString *JCG53SHA256(NSData *data) {
    if (!data.length) return @"";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *s=[NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH*2];
    for(NSUInteger i=0;i<CC_SHA256_DIGEST_LENGTH;i++) [s appendFormat:@"%02x",digest[i]];
    return s;
}

static void JCG53LoadHashFile(NSString *path) {
    NSData *data=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil]; if(!data.length)return;
    NSString *text=[[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding]autorelease]; if(!text.length)return;
    for(NSString *line in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]){@autoreleasepool{
        if(line.length<2)continue; NSData *ld=[line dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *o=[NSJSONSerialization JSONObjectWithData:ld options:0 error:nil]; if(![o isKindOfClass:[NSDictionary class]])continue;
        NSString *md5=o[@"md5"],*sha=o[@"sha256"]; if(md5.length)[gMD5s addObject:md5.lowercaseString]; if(sha.length)[gSHA256s addObject:sha.lowercaseString];
    }}
}

static void JCG53LoadCache(void) {
    JCG53LoadHashFile(gCachePath); JCG53LoadHashFile(gManifestPath);
    pthread_mutex_lock(&gStateLock); gCacheLoaded=gMD5s.count; pthread_mutex_unlock(&gStateLock);
    JCG53Log([NSString stringWithFormat:@"RUNTIME2-CACHE ready md5=%lu sha256=%lu path=%@",(unsigned long)gMD5s.count,(unsigned long)gSHA256s.count,gCachePath]);
}

static void JCG53AppendCache(NSString *md5,NSString *sha,NSUInteger bytes,NSString *status) {
    JCG53AppendJSONL(gCachePath,@{@"schema":@1,@"algorithm":@"md5",@"md5":md5?:@"",@"sha256":sha?:@"",@"source":@"lua_pushlstring-json",@"bytes":@(bytes),@"status":status?:@"captured",@"time":@([[NSDate date]timeIntervalSince1970])});
}

static void JCG53AppendManifest(NSString *file,NSString *md5,NSString *sha,NSUInteger bytes) {
    JCG53AppendJSONL(gManifestPath,@{@"file":file?:@"",@"source":@"lua_pushlstring-json",@"md5":md5?:@"",@"sha256":sha?:@"",@"bytes":@(bytes),@"time":@([[NSDate date]timeIntervalSince1970])});
}

BOOL JCG53Runtime2IsEnabled(void) { return atomic_load_explicit(&gEnabled,memory_order_relaxed)!=0; }
void JCG53Runtime2SetEnabled(BOOL enabled) { atomic_store_explicit(&gEnabled,enabled?1:0,memory_order_relaxed); }

static void JCG53SetLast(NSString *item,NSString *status) {
    pthread_mutex_lock(&gStateLock); [gLastItem release];[gLastStatus release];
    gLastItem=[(item.length?item:@"暂无") copy]; gLastStatus=[(status.length?status:@"暂无") copy]; pthread_mutex_unlock(&gStateLock);
}

NSString *JCG53Runtime2StatusText(void) {
    pthread_mutex_lock(&gStateLock); BOOL hook=gHookReady; unsigned long long captured=gCaptured,skipped=gSkipped,cache=gCacheLoaded;
    NSString *last=[[(gLastItem?:@"暂无") copy]autorelease],*status=[[(gLastStatus?:@"暂无") copy]autorelease]; pthread_mutex_unlock(&gStateLock);
    return [NSString stringWithFormat:@"状态：%@  Hook：%@  新抓%llu 跳过%llu\n缓存MD5：%llu  最新：%@｜%@",JCG53Runtime2IsEnabled()?@"开启 ✅":@"关闭",hook?@"就绪":@"等待",captured,skipped,cache,last.lastPathComponent?:last,status];
}

static BOOL JCG53PrefixLooksJSON(const char *bytes,size_t length) {
    if(!bytes||!length||length>JCG53_MAX_JSON_BYTES)return NO; const unsigned char *p=(const unsigned char*)bytes; size_t i=0;
    if(length>=3&&p[0]==0xEF&&p[1]==0xBB&&p[2]==0xBF)i=3;
    while(i<length){unsigned char c=p[i++];if(c==' '||c=='\t'||c=='\r'||c=='\n')continue;return c=='{'||c=='[';}return NO;
}

static BOOL JCG53CompleteJSON(NSData *data) {
    if(!data.length||data.length>JCG53_MAX_JSON_BYTES)return NO; NSError *err=nil; id obj=[NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    return obj&&err==nil&&([obj isKindOfClass:[NSDictionary class]]||[obj isKindOfClass:[NSArray class]]);
}

static void JCG53Queue(NSData *data) {
    if(!data.length||data.length>JCG53_MAX_JSON_BYTES||!gQueue)return; NSData *snapshot=[NSData dataWithData:data];
    dispatch_async(gQueue, ^{@autoreleasepool{
        if(!JCG53Runtime2IsEnabled()||!JCG53CompleteJSON(snapshot))return;
        NSString *md5=JCG53MD5(snapshot).lowercaseString,*sha=JCG53SHA256(snapshot).lowercaseString; if(!md5.length||!sha.length)return;
        BOOL duplicate=[gMD5s containsObject:md5]||[gSHA256s containsObject:sha]; NSString *shortHash=sha.length>12?[sha substringToIndex:12]:sha; NSString *display=[NSString stringWithFormat:@"JSON_%@",shortHash];
        if(duplicate){BOOL migrate=![gMD5s containsObject:md5];if(migrate){[gMD5s addObject:md5];JCG53AppendCache(md5,sha,snapshot.length,@"migrated-duplicate");}
            pthread_mutex_lock(&gStateLock);gSkipped++;gCacheLoaded=gMD5s.count;pthread_mutex_unlock(&gStateLock);JCG53SetLast(display,@"已抓过");return;}
        pthread_mutex_lock(&gStateLock);unsigned long long seq=++gCaptured;pthread_mutex_unlock(&gStateLock);
        NSString *file=[NSString stringWithFormat:@"%06llu_xhr_%@.json",seq,shortHash],*path=[gJSONDir stringByAppendingPathComponent:file];NSError *writeErr=nil;
        if(![snapshot writeToFile:path options:NSDataWritingAtomic error:&writeErr]){JCG53SetLast(display,@"写入失败");JCG53Log([NSString stringWithFormat:@"RUNTIME2 WRITE-FAIL sha256=%@ err=%@",sha,writeErr]);return;}
        [gMD5s addObject:md5];[gSHA256s addObject:sha];pthread_mutex_lock(&gStateLock);gCacheLoaded=gMD5s.count;pthread_mutex_unlock(&gStateLock);
        JCG53AppendManifest(file,md5,sha,snapshot.length);JCG53AppendCache(md5,sha,snapshot.length,@"captured");JCG53SetLast(file,@"新抓取");
        JCG53Log([NSString stringWithFormat:@"RUNTIME2 CAPTURE file=%@ bytes=%lu md5=%@ sha256=%@",file,(unsigned long)snapshot.length,md5,sha]);
    }});
}

static void *JCG53ResolveExport(const char *name) {
    void *p=dlsym(RTLD_DEFAULT,name);if(p)return p;const char *paths[]={"@rpath/UnityFramework.framework/UnityFramework","UnityFramework.framework/UnityFramework"};
    for(size_t i=0;i<sizeof(paths)/sizeof(paths[0]);i++){void*h=dlopen(paths[i],RTLD_LAZY|RTLD_GLOBAL);if(!h)continue;p=dlsym(h,name);if(p)return p;}return NULL;
}

static void *JCG53ResolveHookSymbol(const char *symbol) {
    void *p=dlsym(RTLD_DEFAULT,symbol);if(p)return p;const char *libs[]={"/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate","/var/jb/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate","/usr/lib/libsubstrate.dylib","/var/jb/usr/libsubstrate.dylib","/usr/lib/libhooker.dylib","/var/jb/usr/lib/libhooker.dylib","/usr/lib/libellekit.dylib","/var/jb/usr/lib/libellekit.dylib"};
    for(size_t i=0;i<sizeof(libs)/sizeof(libs[0]);i++){void*h=dlopen(libs[i],RTLD_LAZY|RTLD_GLOBAL);if(!h)continue;p=dlsym(h,symbol);if(p)return p;}return NULL;
}

static BOOL JCG53HookAddress(void *address,void *replacement,void **original) {
    if(!address)return NO;JCG53MSHookFunctionFn ms=(JCG53MSHookFunctionFn)JCG53ResolveHookSymbol("MSHookFunction");if(ms){ms(address,replacement,original);if(original&&*original)return YES;}
    JCG53DobbyHookFn dobby=(JCG53DobbyHookFn)JCG53ResolveHookSymbol("DobbyHook");if(dobby){int rc=dobby(address,replacement,original);if(rc==0&&original&&*original)return YES;}return NO;
}

static const char *JCG53HookLuaPushLString(void *L,const char *s,size_t len) {
    if(JCG53Runtime2IsEnabled()&&s&&len&&len<=JCG53_MAX_JSON_BYTES&&JCG53PrefixLooksJSON(s,len)){@autoreleasepool{NSData*d=[NSData dataWithBytes:s length:len];if(d.length)JCG53Queue(d);}}
    return gOrigLuaPushLString?gOrigLuaPushLString(L,s,len):NULL;
}

static BOOL JCG53InstallHook(void) {
    pthread_mutex_lock(&gStateLock);BOOL ready=gHookReady;pthread_mutex_unlock(&gStateLock);if(ready)return YES;
    void *symbol=JCG53ResolveExport("lua_pushlstring");BOOL ok=symbol&&JCG53HookAddress(symbol,(void*)JCG53HookLuaPushLString,(void**)&gOrigLuaPushLString);
    if(ok){pthread_mutex_lock(&gStateLock);gHookReady=YES;pthread_mutex_unlock(&gStateLock);JCG53Log([NSString stringWithFormat:@"RUNTIME2-HOOK ready lua_pushlstring=%p",symbol]);}return ok;
}

static void JCG53PollHook(NSUInteger attempt) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{if(JCG53InstallHook())return;if(attempt<120)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.25*NSEC_PER_SEC)),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{JCG53PollHook(attempt+1);});else JCG53Log(@"RUNTIME2-HOOK unavailable/timeout lua_pushlstring");});
}

void JCG53Runtime2Start(void) {
    pthread_mutex_lock(&gStateLock);if(gStarted){pthread_mutex_unlock(&gStateLock);return;}gStarted=YES;pthread_mutex_unlock(&gStateLock);
    JCG53SetupPaths();gQueue=dispatch_queue_create("com.openai.jsoncapture.v053.runtime2",DISPATCH_QUEUE_SERIAL);gMD5s=[[NSMutableSet alloc]init];gSHA256s=[[NSMutableSet alloc]init];gLastItem=[@"暂无" copy];gLastStatus=[@"暂无" copy];
    JCG53LoadCache();JCG53Log([NSString stringWithFormat:@"%@ loaded; complete JSON only; master switch shared with runtime capture",JCG53_VERSION]);JCG53PollHook(0);
}
