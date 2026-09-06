#include <mach-o/dyld.h>
#include <dlfcn.h>
#include <pthread.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/time.h>
#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <atomic>
#include <string>

#include <objc/runtime.h>
#include <objc/message.h>

#include "dobby.h"

namespace {

// Verified against the supplied UnityFramework (arm64):
//   SHA256 bb0229411aa0b49d99b23619a97108dc8eea70490f65de444397867e01f411a3
constexpr uintptr_t RVA_SEND_10195                    = 0x005A6914;
constexpr uintptr_t RVA_QUICKSDK_BEGIN_INIT           = 0x0107FEBC;
constexpr uintptr_t RVA_HTTP_SYNC_REQUEST2            = 0x01085044;
constexpr uintptr_t RVA_UPDATE_SERVER_LIST            = 0x0109BFBC;

constexpr size_t MAX_OBJC_TEXT = 1536;

std::atomic<bool> gInstalled{false};
std::atomic<uintptr_t> gUnityBase{0};
int gLogFd = -1;
pthread_mutex_t gLogLock = PTHREAD_MUTEX_INITIALIZER;

static uint64_t tid_now() {
    uint64_t tid = 0;
    pthread_threadid_np(nullptr, &tid);
    return tid;
}

static uint64_t now_ms() {
    struct timeval tv{};
    gettimeofday(&tv, nullptr);
    return static_cast<uint64_t>(tv.tv_sec) * 1000ULL + static_cast<uint64_t>(tv.tv_usec / 1000);
}

static void ensure_log_open() {
    if (gLogFd >= 0) return;
    pthread_mutex_lock(&gLogLock);
    if (gLogFd < 0) {
        const char *home = getenv("HOME");
        char path[1024];
        if (home && *home) {
            snprintf(path, sizeof(path), "%s/Documents/Login10195Diag_v0.2.log", home);
        } else {
            snprintf(path, sizeof(path), "/tmp/Login10195Diag_v0.2.log");
        }
        gLogFd = open(path, O_CREAT | O_WRONLY | O_APPEND, 0644);
    }
    pthread_mutex_unlock(&gLogLock);
}

static void log_line(const char *fmt, ...) {
    ensure_log_open();
    if (gLogFd < 0) return;

    struct timeval tv{};
    gettimeofday(&tv, nullptr);
    struct tm tmv{};
    localtime_r(&tv.tv_sec, &tmv);

    char prefix[192];
    int pn = snprintf(prefix, sizeof(prefix),
                      "%04d-%02d-%02d %02d:%02d:%02d.%03d [tid=%llu] ",
                      tmv.tm_year + 1900, tmv.tm_mon + 1, tmv.tm_mday,
                      tmv.tm_hour, tmv.tm_min, tmv.tm_sec,
                      static_cast<int>(tv.tv_usec / 1000),
                      static_cast<unsigned long long>(tid_now()));

    char body[8192];
    va_list ap;
    va_start(ap, fmt);
    int bn = vsnprintf(body, sizeof(body), fmt, ap);
    va_end(ap);
    if (bn < 0) return;
    if (bn >= static_cast<int>(sizeof(body))) bn = static_cast<int>(sizeof(body)) - 1;

    pthread_mutex_lock(&gLogLock);
    if (pn > 0) write(gLogFd, prefix, static_cast<size_t>(pn));
    if (bn > 0) write(gLogFd, body, static_cast<size_t>(bn));
    write(gLogFd, "\n", 1);
    fsync(gLogFd);
    pthread_mutex_unlock(&gLogLock);
}

static uintptr_t find_unity_base() {
    const uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; ++i) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        if (strstr(name, "UnityFramework.framework/UnityFramework") ||
            strstr(name, "/UnityFramework")) {
            const mach_header *h = _dyld_get_image_header(i);
            if (h) return reinterpret_cast<uintptr_t>(h);
        }
    }
    return 0;
}

static inline void *rva_ptr(uintptr_t rva) {
    return reinterpret_cast<void *>(gUnityBase.load() + rva);
}

static void log_address(const char *tag, void *addr) {
    Dl_info di{};
    const uintptr_t ub = gUnityBase.load();
    if (addr && dladdr(addr, &di) && di.dli_fname) {
        const uintptr_t ib = reinterpret_cast<uintptr_t>(di.dli_fbase);
        const uintptr_t io = reinterpret_cast<uintptr_t>(addr) - ib;
        if (ub && strstr(di.dli_fname, "UnityFramework")) {
            log_line("%s addr=%p image=%s imageOff=0x%llX UnityRVA=0x%llX",
                     tag, addr, di.dli_fname,
                     static_cast<unsigned long long>(io),
                     static_cast<unsigned long long>(reinterpret_cast<uintptr_t>(addr) - ub));
        } else {
            log_line("%s addr=%p image=%s imageOff=0x%llX",
                     tag, addr, di.dli_fname,
                     static_cast<unsigned long long>(io));
        }
    } else {
        log_line("%s addr=%p", tag, addr);
    }
}

static const char *class_name_safe(void *obj) {
    if (!obj) return "<nil>";
    Class cls = object_getClass(reinterpret_cast<id>(obj));
    return cls ? class_getName(cls) : "<unknown>";
}

static bool object_has_selector(void *obj, SEL sel) {
    if (!obj || !sel) return false;
    Class cls = object_getClass(reinterpret_cast<id>(obj));
    return cls && class_getInstanceMethod(cls, sel) != nullptr;
}

static std::string objc_text(void *obj) {
    if (!obj) return "<nil>";

    const char *cls = class_name_safe(obj);
    std::string text;

    SEL utf8Sel = sel_registerName("UTF8String");
    if (object_has_selector(obj, utf8Sel)) {
        using MsgUtf8 = const char *(*)(id, SEL);
        const char *s = reinterpret_cast<MsgUtf8>(objc_msgSend)(reinterpret_cast<id>(obj), utf8Sel);
        if (s) text = s;
    }

    if (text.empty()) {
        SEL descSel = sel_registerName("description");
        if (object_has_selector(obj, descSel)) {
            using MsgObj = id (*)(id, SEL);
            id desc = reinterpret_cast<MsgObj>(objc_msgSend)(reinterpret_cast<id>(obj), descSel);
            if (desc && object_has_selector(reinterpret_cast<void *>(desc), utf8Sel)) {
                using MsgUtf8 = const char *(*)(id, SEL);
                const char *s = reinterpret_cast<MsgUtf8>(objc_msgSend)(desc, utf8Sel);
                if (s) text = s;
            }
        }
    }

    if (text.size() > MAX_OBJC_TEXT) {
        text.resize(MAX_OBJC_TEXT);
        text += "...";
    }

    char head[160];
    snprintf(head, sizeof(head), "class=%s ptr=%p text=", cls ? cls : "<unknown>", obj);
    return std::string(head) + (text.empty() ? "<unavailable>" : text);
}

// 0x5A6914 disassembly uses:
//   x0=self, w1=arg1, x2=arg2, x3=arg3, w4=arg4
// and writes message id 0x27D3 (10195) before dispatching slot 0x8E8.
using Fn10195 = void (*)(void *, uint32_t, void *, void *, uint32_t);
Fn10195 orig_10195 = nullptr;

static void hook_10195(void *self, uint32_t a1, void *a2, void *a3, uint32_t a4) {
    void *caller = __builtin_return_address(0);
    log_line("[10195] ENTER self=%p a1=%u/0x%X a2=%p a3=%p a4=%u/0x%X caller=%p",
             self, a1, a1, a2, a3, a4, a4, caller);
    log_address("[10195] CALLER", caller);
    orig_10195(self, a1, a2, a3, a4);
    log_line("[10195] LEAVE");
}

// -[SDKCooperater beginQuickSDKInit]  types: v16@0:8
using FnBeginQuickInit = void (*)(void *, void *);
FnBeginQuickInit orig_BeginQuickInit = nullptr;

static void hook_BeginQuickInit(void *self, void *sel) {
    log_line("[QuickInit] ENTER self=%p class=%s sel=%s",
             self, class_name_safe(self), sel ? sel_getName(reinterpret_cast<SEL>(sel)) : "<null>");
    const uint64_t t0 = now_ms();
    orig_BeginQuickInit(self, sel);
    log_line("[QuickInit] LEAVE elapsed=%llums",
             static_cast<unsigned long long>(now_ms() - t0));
}

// -[SDKNetworkManager updateServerListWithChannelParams:handler:]
// types: v32@0:8@16@?24
using FnUpdateServerList = void (*)(void *, void *, void *, void *);
FnUpdateServerList orig_UpdateServerList = nullptr;

static void hook_UpdateServerList(void *self, void *sel, void *params, void *handler) {
    log_line("[ServerList] ENTER self=%p class=%s sel=%s handler=%p handlerClass=%s",
             self, class_name_safe(self), sel ? sel_getName(reinterpret_cast<SEL>(sel)) : "<null>",
             handler, class_name_safe(handler));
    std::string p = objc_text(params);
    log_line("[ServerList] params %s", p.c_str());
    const uint64_t t0 = now_ms();
    orig_UpdateServerList(self, sel, params, handler);
    log_line("[ServerList] LEAVE elapsed=%llums",
             static_cast<unsigned long long>(now_ms() - t0));
}

// -[DCNetworkInterface addSyncHttpRequest2:param:method:]
// types: @40@0:8@16@24@32
using FnHttpSync2 = void *(*)(void *, void *, void *, void *, void *);
FnHttpSync2 orig_HttpSync2 = nullptr;

static void *hook_HttpSync2(void *self, void *sel, void *url, void *param, void *method) {
    log_line("[HTTP2] ENTER self=%p class=%s sel=%s",
             self, class_name_safe(self), sel ? sel_getName(reinterpret_cast<SEL>(sel)) : "<null>");
    std::string u = objc_text(url);
    std::string p = objc_text(param);
    std::string m = objc_text(method);
    log_line("[HTTP2] url    %s", u.c_str());
    log_line("[HTTP2] method %s", m.c_str());
    log_line("[HTTP2] param  %s", p.c_str());

    const uint64_t t0 = now_ms();
    void *ret = orig_HttpSync2(self, sel, url, param, method);
    const uint64_t elapsed = now_ms() - t0;

    std::string r = objc_text(ret);
    log_line("[HTTP2] LEAVE elapsed=%llums result=%s",
             static_cast<unsigned long long>(elapsed), r.c_str());
    return ret;
}

static bool hook_one(const char *name, uintptr_t rva, void *replacement, void **original) {
    void *target = rva_ptr(rva);
    int rc = DobbyHook(target, replacement, original);
    log_line("[INSTALL] %s RVA=0x%llX target=%p rc=%d original=%p",
             name,
             static_cast<unsigned long long>(rva),
             target,
             rc,
             original ? *original : nullptr);
    return rc == 0;
}

static void install_hooks() {
    if (gInstalled.exchange(true)) return;

    const uintptr_t base = find_unity_base();
    if (!base) {
        log_line("[INSTALL] UnityFramework not found");
        gInstalled.store(false);
        return;
    }
    gUnityBase.store(base);

    log_line("============================================================");
    log_line("Login10195Diag v0.2 start");
    log_line("UnityFramework base=%p", reinterpret_cast<void *>(base));
    log_line("Targets: 10195=0x%llX QuickInit=0x%llX HTTP2=0x%llX ServerList=0x%llX",
             static_cast<unsigned long long>(RVA_SEND_10195),
             static_cast<unsigned long long>(RVA_QUICKSDK_BEGIN_INIT),
             static_cast<unsigned long long>(RVA_HTTP_SYNC_REQUEST2),
             static_cast<unsigned long long>(RVA_UPDATE_SERVER_LIST));

    bool ok = true;
    ok &= hook_one("Send10195", RVA_SEND_10195,
                   reinterpret_cast<void *>(hook_10195), reinterpret_cast<void **>(&orig_10195));
    ok &= hook_one("beginQuickSDKInit", RVA_QUICKSDK_BEGIN_INIT,
                   reinterpret_cast<void *>(hook_BeginQuickInit), reinterpret_cast<void **>(&orig_BeginQuickInit));
    ok &= hook_one("addSyncHttpRequest2:param:method:", RVA_HTTP_SYNC_REQUEST2,
                   reinterpret_cast<void *>(hook_HttpSync2), reinterpret_cast<void **>(&orig_HttpSync2));
    ok &= hook_one("updateServerListWithChannelParams:handler:", RVA_UPDATE_SERVER_LIST,
                   reinterpret_cast<void *>(hook_UpdateServerList), reinterpret_cast<void **>(&orig_UpdateServerList));

    log_line("[INSTALL] complete ok=%d", ok ? 1 : 0);
}

static void *install_thread(void *) {
    for (int i = 0; i < 600; ++i) {
        if (find_unity_base()) {
            install_hooks();
            return nullptr;
        }
        usleep(100 * 1000);
    }
    log_line("[INSTALL] timeout waiting for UnityFramework");
    return nullptr;
}

__attribute__((constructor))
static void entry() {
    ensure_log_open();
    log_line("[BOOT] Login10195Diag v0.2 loaded");
    pthread_t t{};
    if (pthread_create(&t, nullptr, install_thread, nullptr) == 0) {
        pthread_detach(t);
    } else {
        log_line("[BOOT] pthread_create failed");
    }
}

} // namespace
