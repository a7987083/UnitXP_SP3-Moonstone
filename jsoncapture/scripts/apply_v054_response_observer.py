#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")

MARKER = "JCG5_RESPONSE_OBSERVER_V054"
if MARKER in s:
    print("v0.5.4 response observer patch already applied")
    raise SystemExit(0)

if "JCG5_RUNTIME_CACHE_V052" not in s:
    raise SystemExit("v0.5.2 runtime cache patch must be applied first")


def rep(old: str, new: str, label: str) -> None:
    global s
    if old not in s:
        raise SystemExit(f"patch anchor missing: {label}")
    s = s.replace(old, new, 1)

rep(
    "#include <dlfcn.h>\n",
    "#include <dlfcn.h>\n#include <mach-o/loader.h>\n",
    "mach-o loader include",
)

observer = r'''
// JCG5_RESPONSE_OBSERVER_V054
// Exact-target diagnostic observer for the user-supplied UnityFramework.
// It is installed synchronously inside JCG5InstallHooks(), after the original
// v0.5.2 Lua hooks, so there is NO second hook-polling queue and NO additional
// constructor / +load entrypoint.
typedef void *(*JCG54DownloadHandlerBufferGetDataFn)(void *self, const void *method);
static JCG54DownloadHandlerBufferGetDataFn gJCG54OrigDownloadHandlerBufferGetData;
static BOOL gJCG54ObserverHookReady = NO;
static BOOL gJCG54TargetMatched = NO;
static unsigned long long gJCG54ObserverHits = 0;
static unsigned long long gJCG54ObserverJSONLike = 0;
static unsigned long long gJCG54ObserverLastBytes = 0;
static NSString *gJCG54ObserverLastState;

#define JCG54_DOWNLOAD_HANDLER_BUFFER_GETDATA_RVA 0x0ECFC0C0ULL
#define JCG54_OBSERVER_MAX_BYTES (256ULL * 1024ULL * 1024ULL)

static const uint8_t gJCG54ExpectedUnityUUID[16] = {
    0xCE,0xF4,0x25,0x2D,0xDC,0xA1,0x34,0x42,
    0xAE,0xD5,0xE5,0x75,0x1D,0x7B,0xF5,0xCD
};

static BOOL JCG54MachOUUIDMatches(const void *base) {
    if (!base) return NO;
    const struct mach_header_64 *mh = (const struct mach_header_64 *)base;
    if (mh->magic != MH_MAGIC_64) return NO;
    const uint8_t *p = (const uint8_t *)(mh + 1);
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)p;
        if (lc->cmdsize < sizeof(struct load_command)) return NO;
        if (lc->cmd == LC_UUID && lc->cmdsize >= sizeof(struct uuid_command)) {
            const struct uuid_command *uc = (const struct uuid_command *)lc;
            return memcmp(uc->uuid, gJCG54ExpectedUnityUUID, 16) == 0;
        }
        p += lc->cmdsize;
    }
    return NO;
}

static BOOL JCG54LooksLikeJSON(const uint8_t *p, NSUInteger n) {
    if (!p || !n) return NO;
    NSUInteger i = 0;
    if (n >= 3 && p[0] == 0xEF && p[1] == 0xBB && p[2] == 0xBF) i = 3;
    while (i < n && i < 128) {
        uint8_t c = p[i++];
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') continue;
        return c == '{' || c == '[';
    }
    return NO;
}

static void *JCG54HookDownloadHandlerBufferGetData(void *self, const void *method) {
    void *ret = gJCG54OrigDownloadHandlerBufferGetData ? gJCG54OrigDownloadHandlerBufferGetData(self, method) : NULL;
    if (!ret) return ret;

    BOOL enabled = NO;
    pthread_mutex_lock(&gJCG5StateLock);
    enabled = gJCG5CaptureEnabled;
    pthread_mutex_unlock(&gJCG5StateLock);
    if (!enabled) return ret;

    JCG5ByteArray *a = (JCG5ByteArray *)ret;
    uintptr_t rawLen = a->max_length;
    if (!rawLen || rawLen > JCG54_OBSERVER_MAX_BYTES) return ret;
    NSUInteger len = (NSUInteger)rawLen;
    BOOL jsonLike = JCG54LooksLikeJSON(a->vector, len);

    unsigned long long hit = 0;
    pthread_mutex_lock(&gJCG5StateLock);
    gJCG54ObserverHits++;
    hit = gJCG54ObserverHits;
    if (jsonLike) gJCG54ObserverJSONLike++;
    gJCG54ObserverLastBytes = len;
    [gJCG54ObserverLastState release];
    gJCG54ObserverLastState = [(jsonLike ? @"JSON前缀" : @"非JSON前缀") copy];
    pthread_mutex_unlock(&gJCG5StateLock);

    // Diagnostic only: do not copy or persist the body yet. Log the first few
    // hits and all JSON-looking hits so real-device validation stays low-cost.
    if (hit <= 8 || jsonLike) {
        JCG5Log([NSString stringWithFormat:@"RESPONSE-OBSERVER hit=%llu bytes=%lu json_like=%d rva=0x%llX",
                 hit, (unsigned long)len, jsonLike,
                 (unsigned long long)JCG54_DOWNLOAD_HANDLER_BUFFER_GETDATA_RVA]);
    }
    return ret;
}

static NSString *JCG54ObserverStatusText(void) {
    pthread_mutex_lock(&gJCG5StateLock);
    BOOL matched = gJCG54TargetMatched;
    BOOL ready = gJCG54ObserverHookReady;
    unsigned long long hits = gJCG54ObserverHits;
    unsigned long long json = gJCG54ObserverJSONLike;
    unsigned long long bytes = gJCG54ObserverLastBytes;
    NSString *state = [[(gJCG54ObserverLastState ?: @"暂无") copy] autorelease];
    pthread_mutex_unlock(&gJCG5StateLock);
    return [NSString stringWithFormat:@"目标：%@  Hook：%@  命中%llu JSON%llu\n最新：%lluB｜%@",
            matched ? @"匹配 ✅" : @"未匹配",
            ready ? @"就绪" : @"等待",
            hits, json, bytes, state];
}

static BOOL JCG54InstallResponseObserver(void *unityExport) {
    pthread_mutex_lock(&gJCG5StateLock);
    BOOL already = gJCG54ObserverHookReady;
    pthread_mutex_unlock(&gJCG5StateLock);
    if (already) return YES;
    if (!unityExport) return NO;

    Dl_info info; memset(&info, 0, sizeof(info));
    if (dladdr(unityExport, &info) == 0 || !info.dli_fbase) return NO;
    if (!JCG54MachOUUIDMatches(info.dli_fbase)) {
        JCG5Log(@"RESPONSE-OBSERVER target UUID mismatch; observer disabled");
        return NO;
    }

    uintptr_t base = (uintptr_t)info.dli_fbase;
    void *target = (void *)(base + (uintptr_t)JCG54_DOWNLOAD_HANDLER_BUFFER_GETDATA_RVA);
    Dl_info ti; memset(&ti, 0, sizeof(ti));
    if (dladdr(target, &ti) == 0 || ti.dli_fbase != info.dli_fbase) {
        JCG5Log(@"RESPONSE-OBSERVER target address validation failed; observer disabled");
        return NO;
    }

    pthread_mutex_lock(&gJCG5StateLock);
    gJCG54TargetMatched = YES;
    pthread_mutex_unlock(&gJCG5StateLock);

    BOOL ok = JCG5Hook(target,
                       (void *)JCG54HookDownloadHandlerBufferGetData,
                       (void **)&gJCG54OrigDownloadHandlerBufferGetData);
    if (ok) {
        pthread_mutex_lock(&gJCG5StateLock);
        gJCG54ObserverHookReady = YES;
        [gJCG54ObserverLastState release];
        gJCG54ObserverLastState = [@"等待响应" copy];
        pthread_mutex_unlock(&gJCG5StateLock);
        JCG5Log([NSString stringWithFormat:@"RESPONSE-OBSERVER ready base=%p target=%p rva=0x%llX UUID=CEF4252D-DCA1-3442-AED5-E5751D7BF5CD",
                 info.dli_fbase, target,
                 (unsigned long long)JCG54_DOWNLOAD_HANDLER_BUFFER_GETDATA_RVA]);
    } else {
        JCG5Log(@"RESPONSE-OBSERVER hook failed");
    }
    return ok;
}

'''

rep(
    "static BOOL JCG5InstallHooks(void) {\n",
    observer + "static BOOL JCG5InstallHooks(void) {\n",
    "observer core insertion",
)

old_install = '''static BOOL JCG5InstallHooks(void) {
    if(gJCG5HooksReady)return YES;
    void *pTolua=JCG5ResolveExport("tolua_loadbuffer"); void *pLuaLX=JCG5ResolveExport("luaL_loadbufferx");
    BOOL a=pTolua?JCG5Hook(pTolua,(void*)JCG5HookTolua,(void**)&gJCG5OrigToluaLoadBuffer):NO;
    BOOL b=pLuaLX?JCG5Hook(pLuaLX,(void*)JCG5HookLuaLX,(void**)&gJCG5OrigLuaLLoadBufferX):NO;
    gJCG5HooksReady=a||b;
    if(gJCG5HooksReady)JCG5Log([NSString stringWithFormat:@"HOOK ready tolua=%d luaL_loadbufferx=%d",a,b]);
    return gJCG5HooksReady;
}
'''
new_install = '''static BOOL JCG5InstallHooks(void) {
    if(gJCG5HooksReady)return YES;
    void *pTolua=JCG5ResolveExport("tolua_loadbuffer"); void *pLuaLX=JCG5ResolveExport("luaL_loadbufferx");
    BOOL a=pTolua?JCG5Hook(pTolua,(void*)JCG5HookTolua,(void**)&gJCG5OrigToluaLoadBuffer):NO;
    BOOL b=pLuaLX?JCG5Hook(pLuaLX,(void*)JCG5HookLuaLX,(void**)&gJCG5OrigLuaLLoadBufferX):NO;
    // IMPORTANT: observer hook installation is serialized in this SAME call.
    // No second utility queue is created, avoiding the v0.5.3 concurrent
    // MSHookFunction race seen in the supplied crash logs.
    void *anchor=pTolua?pTolua:pLuaLX;
    BOOL c=anchor?JCG54InstallResponseObserver(anchor):NO;
    gJCG5HooksReady=a||b;
    if(gJCG5HooksReady)JCG5Log([NSString stringWithFormat:@"HOOK ready tolua=%d luaL_loadbufferx=%d response_observer=%d",a,b,c]);
    return gJCG5HooksReady;
}
'''
rep(old_install, new_install, "serialized observer hook install")

rep(
    'NSArray*spec=@[@[@"capture",@"运行时抓取"],@[@"scan",@"本地扫描"],@[@"decrypt",@"解密"],@[@"recover",@"JSON恢复"],@[@"task",@"当前任务"]];',
    'NSArray*spec=@[@[@"capture",@"运行时抓取"],@[@"capture2",@"响应观察"],@[@"scan",@"本地扫描"],@[@"decrypt",@"解密"],@[@"recover",@"JSON恢复"],@[@"task",@"当前任务"]];',
    "observer UI row",
)

rep(
    '    self.labels[@"scan"].text=',
    '    self.labels[@"capture2"].text=JCG54ObserverStatusText();\n    self.labels[@"scan"].text=',
    "observer UI refresh",
)

p.write_text(s, encoding="utf-8")
print("applied v0.5.4 exact-target response observer on v0.5.2 lifecycle")
