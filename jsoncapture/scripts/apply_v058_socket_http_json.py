#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")

MARKER = "JCG5_SOCKET_HTTP_JSON_V058"
if MARKER in s:
    print("v0.5.8 SocketTCP HTTP JSON patch already applied")
    raise SystemExit(0)

for required in (
    "JCG5_RUNTIME_CACHE_V052",
    "JCG5_RESPONSE_OBSERVER_V054",
    "JCG5_RESPONSE_CAPTURE_V055",
    "JCG5_RESPONSE_METADATA_V056",
    "JCG5_RESPONSE_METADATA_V056_HARDENED",
    "JCG5_UNITY_ALL_JSON_V057",
    "JCG5_UNITY_ALL_JSON_V057_COMPILE_COMPAT",
):
    if required not in s:
        raise SystemExit(f"required prior patch missing: {required}")


def rep(old: str, new: str, label: str) -> None:
    global s
    if old not in s:
        raise SystemExit(f"v0.5.8 patch anchor missing: {label}")
    s = s.replace(old, new, 1)


insert = r'''
// JCG5_SOCKET_HTTP_JSON_V058
// Wrap the game's global g_requestHttpServer on the Lua VM thread. The wrapper
// replaces only the per-request callback, allowing capture of the final
// MSG_HTTP_RESPONE.body AFTER the game's optional AES Decode/DecodeNew step.
// No socket.receive hook, no AES hook, no new polling queue, no new constructor.
typedef int (*JCG58LuaCFunction)(void *L);
typedef int (*JCG58LuaGetTopFn)(void *L);
typedef int (*JCG58LuaGetGlobalFn)(void *L, const char *name);
typedef void (*JCG58LuaSetGlobalFn)(void *L, const char *name);
typedef int (*JCG58LuaTypeFn)(void *L, int idx);
typedef void (*JCG58LuaPushValueFn)(void *L, int idx);
typedef void (*JCG58LuaPushCClosureFn)(void *L, JCG58LuaCFunction fn, int n);
typedef const char *(*JCG58LuaToLStringFn)(void *L, int idx, size_t *len);
typedef int (*JCG58LuaToBooleanFn)(void *L, int idx);
typedef int64_t (*JCG58LuaToIntegerXFn)(void *L, int idx, int *isnum);
typedef JCG58LuaCFunction (*JCG58LuaToCFunctionFn)(void *L, int idx);
typedef void (*JCG58LuaCallKFn)(void *L, int nargs, int nresults, intptr_t ctx, void *k);
typedef void (*JCG58LuaSetTopFn)(void *L, int idx);
typedef void (*JCG58LuaPushBooleanFn)(void *L, int value);

static JCG58LuaGetTopFn gJCG58LuaGetTop;
static JCG58LuaGetGlobalFn gJCG58LuaGetGlobal;
static JCG58LuaSetGlobalFn gJCG58LuaSetGlobal;
static JCG58LuaTypeFn gJCG58LuaType;
static JCG58LuaPushValueFn gJCG58LuaPushValue;
static JCG58LuaPushCClosureFn gJCG58LuaPushCClosure;
static JCG58LuaToLStringFn gJCG58LuaToLString;
static JCG58LuaToBooleanFn gJCG58LuaToBoolean;
static JCG58LuaToIntegerXFn gJCG58LuaToIntegerX;
static JCG58LuaToCFunctionFn gJCG58LuaToCFunction;
static JCG58LuaCallKFn gJCG58LuaCallK;
static JCG58LuaSetTopFn gJCG58LuaSetTop;
static JCG58LuaPushBooleanFn gJCG58LuaPushBoolean;

static BOOL gJCG58LuaAPIReady = NO;
static BOOL gJCG58SocketWrapperReady = NO;
static unsigned long long gJCG58SocketCallbacks = 0;
static unsigned long long gJCG58SocketBodiesQueued = 0;
static unsigned long long gJCG58SocketOverflow = 0;
static unsigned long long gJCG58SocketBytes = 0;
static NSString *gJCG58SocketLastURL;

#define JCG58_LUA_TSTRING 4
#define JCG58_LUA_TFUNCTION 6
#define JCG58_LUA_REGISTRYINDEX (-1001000)
#define JCG58_LUA_UPVALUEINDEX(i) (JCG58_LUA_REGISTRYINDEX - (i))
#define JCG58_SOCKET_JSON_MAX_BYTES (64ULL * 1024ULL * 1024ULL)
#define JCG58_ORIGINAL_REQUEST_GLOBAL "__jcg58_orig_g_requestHttpServer"

static void *JCG5ResolveExport(const char *name);
static BOOL JCG54MachOUUIDMatches(const void *base);
static void JCG55QueueValidatedResponse(NSData *body, unsigned long long hit, NSDictionary *requestMeta);
static void JCG58TryInstallSocketHTTP(void *L);

static BOOL JCG58ResolveLuaAPI(void *L) {
    if (gJCG58LuaAPIReady) return YES;
    if (!L) return NO;

    gJCG58LuaGetTop = (JCG58LuaGetTopFn)JCG5ResolveExport("lua_gettop");
    gJCG58LuaGetGlobal = (JCG58LuaGetGlobalFn)JCG5ResolveExport("lua_getglobal");
    gJCG58LuaSetGlobal = (JCG58LuaSetGlobalFn)JCG5ResolveExport("lua_setglobal");
    gJCG58LuaType = (JCG58LuaTypeFn)JCG5ResolveExport("lua_type");
    gJCG58LuaPushValue = (JCG58LuaPushValueFn)JCG5ResolveExport("lua_pushvalue");
    gJCG58LuaPushCClosure = (JCG58LuaPushCClosureFn)JCG5ResolveExport("lua_pushcclosure");
    gJCG58LuaToLString = (JCG58LuaToLStringFn)JCG5ResolveExport("lua_tolstring");
    gJCG58LuaToBoolean = (JCG58LuaToBooleanFn)JCG5ResolveExport("lua_toboolean");
    gJCG58LuaToIntegerX = (JCG58LuaToIntegerXFn)JCG5ResolveExport("lua_tointegerx");
    gJCG58LuaToCFunction = (JCG58LuaToCFunctionFn)JCG5ResolveExport("lua_tocfunction");
    gJCG58LuaCallK = (JCG58LuaCallKFn)JCG5ResolveExport("lua_callk");
    gJCG58LuaSetTop = (JCG58LuaSetTopFn)JCG5ResolveExport("lua_settop");
    gJCG58LuaPushBoolean = (JCG58LuaPushBooleanFn)JCG5ResolveExport("lua_pushboolean");

    if (!gJCG58LuaGetTop || !gJCG58LuaGetGlobal || !gJCG58LuaSetGlobal ||
        !gJCG58LuaType || !gJCG58LuaPushValue || !gJCG58LuaPushCClosure ||
        !gJCG58LuaToLString || !gJCG58LuaToBoolean || !gJCG58LuaToIntegerX ||
        !gJCG58LuaToCFunction || !gJCG58LuaCallK || !gJCG58LuaSetTop ||
        !gJCG58LuaPushBoolean) {
        return NO;
    }

    Dl_info info; memset(&info, 0, sizeof(info));
    if (dladdr((void *)gJCG58LuaGetGlobal, &info) == 0 || !info.dli_fbase ||
        !JCG54MachOUUIDMatches(info.dli_fbase)) {
        JCG5Log(@"SOCKET-HTTP target UUID mismatch; Lua wrapper disabled");
        return NO;
    }

    gJCG58LuaAPIReady = YES;
    JCG5Log(@"SOCKET-HTTP Lua API ready; waiting for g_requestHttpServer");
    return YES;
}

static NSString *JCG58StringAt(void *L, int idx, NSUInteger maxLen) {
    if (!L || !gJCG58LuaToLString) return @"";
    size_t n = 0;
    const char *p = gJCG58LuaToLString(L, idx, &n);
    if (!p || !n || n > maxLen) return @"";
    NSString *s = [[[NSString alloc] initWithBytes:p length:n encoding:NSUTF8StringEncoding] autorelease];
    return s ?: @"";
}

static int JCG58ResponseWrapper(void *L) {
    int nargs = gJCG58LuaGetTop ? gJCG58LuaGetTop(L) : 0;
    BOOL enabled = NO;
    pthread_mutex_lock(&gJCG5StateLock);
    enabled = gJCG5CaptureEnabled;
    pthread_mutex_unlock(&gJCG5StateLock);

    if (enabled && nargs >= 2 && gJCG58LuaToLString && gJCG58LuaType &&
        gJCG58LuaType(L, 2) == JCG58_LUA_TSTRING) {
        size_t len = 0;
        const char *bodyPtr = gJCG58LuaToLString(L, 2, &len);
        if (bodyPtr && len > 0 && len <= JCG58_SOCKET_JSON_MAX_BYTES) {
            NSData *body = [NSData dataWithBytes:bodyPtr length:len];
            NSString *url = JCG58StringAt(L, JCG58_LUA_UPVALUEINDEX(2), 2 * 1024 * 1024);
            BOOL decrypt = gJCG58LuaToBoolean ? (gJCG58LuaToBoolean(L, JCG58_LUA_UPVALUEINDEX(3)) != 0) : NO;
            int isnum = 0;
            int64_t msgid = gJCG58LuaToIntegerX ? gJCG58LuaToIntegerX(L, 1, &isnum) : 0;

            unsigned long long hit = 0;
            pthread_mutex_lock(&gJCG5StateLock);
            gJCG58SocketCallbacks++;
            hit = gJCG58SocketCallbacks;
            gJCG58SocketBytes += (unsigned long long)len;
            [gJCG58SocketLastURL release];
            gJCG58SocketLastURL = [(url ?: @"") copy];
            pthread_mutex_unlock(&gJCG5StateLock);

            NSDictionary *meta = @{
                @"source": @"SocketTCP.MSG_HTTP_RESPONE.responseFunc",
                @"capture_layer": @"sockettcp_protobuf_post_decrypt",
                @"url": url ?: @"",
                @"method": @"SOCKET_HTTP",
                @"http_status": @0,
                @"metadata_matched": @YES,
                @"socket_decrypt": @(decrypt),
                @"socket_msg_id": isnum ? @(msgid) : @0
            };
            JCG5Log([NSString stringWithFormat:@"SOCKET-HTTP callback hit=%llu bytes=%lu decrypt=%d msgid=%@ url=%@",
                     hit, (unsigned long)len, decrypt,
                     isnum ? [NSString stringWithFormat:@"%lld", (long long)msgid] : @"n/a",
                     url ?: @""]);
            JCG55QueueValidatedResponse(body, hit, meta);
            pthread_mutex_lock(&gJCG5StateLock);
            gJCG58SocketBodiesQueued++;
            pthread_mutex_unlock(&gJCG5StateLock);
        } else if (bodyPtr && len > JCG58_SOCKET_JSON_MAX_BYTES) {
            pthread_mutex_lock(&gJCG5StateLock);
            gJCG58SocketOverflow++;
            pthread_mutex_unlock(&gJCG5StateLock);
            JCG5Log([NSString stringWithFormat:@"SOCKET-HTTP overflow bytes=%llu max=%llu",
                     (unsigned long long)len,
                     (unsigned long long)JCG58_SOCKET_JSON_MAX_BYTES]);
        }
    }

    // Preserve direct Lua callback semantics and error propagation.
    if (gJCG58LuaPushValue && gJCG58LuaCallK) {
        gJCG58LuaPushValue(L, JCG58_LUA_UPVALUEINDEX(1));
        for (int i = 1; i <= nargs; i++) gJCG58LuaPushValue(L, i);
        gJCG58LuaCallK(L, nargs, 0, (intptr_t)0, NULL);
    }
    return 0;
}

static int JCG58RequestWrapper(void *L) {
    int nargs = gJCG58LuaGetTop ? gJCG58LuaGetTop(L) : 0;
    if (!gJCG58LuaGetGlobal || !gJCG58LuaPushValue || !gJCG58LuaCallK) return 0;

    int t = gJCG58LuaGetGlobal(L, JCG58_ORIGINAL_REQUEST_GLOBAL);
    if (t != JCG58_LUA_TFUNCTION) {
        if (gJCG58LuaSetTop) gJCG58LuaSetTop(L, nargs);
        JCG5Log(@"SOCKET-HTTP original g_requestHttpServer missing");
        return 0;
    }

    for (int i = 1; i <= nargs; i++) {
        if (i == 2 && gJCG58LuaType && gJCG58LuaType(L, 2) == JCG58_LUA_TFUNCTION) {
            // response wrapper upvalues: original callback, request URL, decrypt flag
            gJCG58LuaPushValue(L, 2);
            if (nargs >= 1) gJCG58LuaPushValue(L, 1); else gJCG58LuaPushBoolean(L, 0);
            if (nargs >= 3) gJCG58LuaPushValue(L, 3); else gJCG58LuaPushBoolean(L, 0);
            gJCG58LuaPushCClosure(L, JCG58ResponseWrapper, 3);
        } else {
            gJCG58LuaPushValue(L, i);
        }
    }

    // Recovered g_requestHttpServer bytecode has no meaningful return values.
    gJCG58LuaCallK(L, nargs, 0, (intptr_t)0, NULL);
    return 0;
}

static void JCG58TryInstallSocketHTTP(void *L) {
    if (!L || !JCG58ResolveLuaAPI(L)) return;
    int top = gJCG58LuaGetTop(L);
    int t = gJCG58LuaGetGlobal(L, "g_requestHttpServer");
    if (t != JCG58_LUA_TFUNCTION) {
        gJCG58LuaSetTop(L, top);
        return;
    }

    JCG58LuaCFunction current = gJCG58LuaToCFunction(L, -1);
    if (current == JCG58RequestWrapper) {
        gJCG58LuaSetTop(L, top);
        if (!gJCG58SocketWrapperReady) {
            pthread_mutex_lock(&gJCG5StateLock);
            gJCG58SocketWrapperReady = YES;
            pthread_mutex_unlock(&gJCG5StateLock);
        }
        return;
    }

    gJCG58LuaSetGlobal(L, JCG58_ORIGINAL_REQUEST_GLOBAL);
    gJCG58LuaPushCClosure(L, JCG58RequestWrapper, 0);
    gJCG58LuaSetGlobal(L, "g_requestHttpServer");
    gJCG58LuaSetTop(L, top);

    pthread_mutex_lock(&gJCG5StateLock);
    gJCG58SocketWrapperReady = YES;
    pthread_mutex_unlock(&gJCG5StateLock);
    JCG5Log(@"SOCKET-HTTP wrapper ready global=g_requestHttpServer capture=post_decrypt responseFunc");
}

static NSString *JCG58SocketStatusText(void) {
    pthread_mutex_lock(&gJCG5StateLock);
    BOOL ready = gJCG58SocketWrapperReady;
    unsigned long long callbacks = gJCG58SocketCallbacks;
    unsigned long long queued = gJCG58SocketBodiesQueued;
    unsigned long long overflow = gJCG58SocketOverflow;
    unsigned long long bytes = gJCG58SocketBytes;
    NSString *url = [[(gJCG58SocketLastURL ?: @"") copy] autorelease];
    pthread_mutex_unlock(&gJCG5StateLock);
    if (url.length > 80) url = [[url substringToIndex:80] stringByAppendingString:@"…"];
    return [NSString stringWithFormat:@"SocketHTTP：%@ 回调%llu 提交%llu 溢出%llu 累计%lluB\n%@",
            ready ? @"就绪" : @"等待", callbacks, queued, overflow, bytes,
            url.length ? url : @"暂无"];
}

'''

rep(
    "#pragma mark - Dynamic symbols / loader hooks\n",
    insert + "#pragma mark - Dynamic symbols / loader hooks\n",
    "SocketHTTP helper insertion",
)

rep(
    "static int JCG5HookTolua(void *L, const char *buffer, int size, const char *name) {\n"
    "    BOOL enabled;",
    "static int JCG5HookTolua(void *L, const char *buffer, int size, const char *name) {\n"
    "    JCG58TryInstallSocketHTTP(L);\n"
    "    BOOL enabled;",
    "tolua same-thread wrapper install",
)

rep(
    "static int JCG5HookLuaLX(void *L, const char *buffer, size_t size, const char *name, const char *mode) {\n"
    "    BOOL enabled;",
    "static int JCG5HookLuaLX(void *L, const char *buffer, size_t size, const char *name, const char *mode) {\n"
    "    JCG58TryInstallSocketHTTP(L);\n"
    "    BOOL enabled;",
    "luaL_loadbufferx same-thread wrapper install",
)

rep(
    'NSArray*spec=@[@[@"capture",@"运行时抓取"],@[@"capture2",@"响应观察"],@[@"scan",@"本地扫描"],@[@"decrypt",@"解密"],@[@"recover",@"JSON恢复"],@[@"task",@"当前任务"]];',
    'NSArray*spec=@[@[@"capture",@"运行时抓取"],@[@"capture2",@"响应观察"],@[@"socket",@"SocketHTTP"],@[@"scan",@"本地扫描"],@[@"decrypt",@"解密"],@[@"recover",@"JSON恢复"],@[@"task",@"当前任务"]];',
    "SocketHTTP UI row",
)

rep(
    '    self.labels[@"capture2"].text=JCG54ObserverStatusText();\n    self.labels[@"scan"].text=',
    '    self.labels[@"capture2"].text=JCG54ObserverStatusText();\n    self.labels[@"socket"].text=JCG58SocketStatusText();\n    self.labels[@"scan"].text=',
    "SocketHTTP UI refresh",
)

p.write_text(s, encoding="utf-8")
print("applied v0.5.8 SocketTCP/protobuf post-decrypt JSON capture")
