#include <mach-o/dyld.h>
#include <dlfcn.h>
#include <pthread.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/time.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <execinfo.h>
#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <atomic>
#include <string>

#include <objc/runtime.h>
#include <objc/message.h>

#include "dobby.h"

namespace {

// Verified against the supplied UnityFramework (arm64):
// SHA256 bb0229411aa0b49d99b23619a97108dc8eea70490f65de444397867e01f411a3
constexpr uintptr_t RVA_SEND_10195          = 0x005A6914;
constexpr uintptr_t RVA_QUICKSDK_BEGIN_INIT = 0x0107FEBC;
constexpr uintptr_t RVA_HTTP_SYNC_REQUEST2  = 0x01085044;
constexpr uintptr_t RVA_UPDATE_SERVER_LIST  = 0x0109BFBC;

constexpr uint16_t MSG_BOOTSTRAP = 0x2713; // 10003
constexpr uint16_t MSG_ZONE_LIST = 0x27D3; // 10195
constexpr size_t MAX_OBJC_TEXT = 1536;
constexpr size_t MAX_SCAN_BYTES = 4096;
constexpr size_t MAX_HEX_BYTES = 96;
constexpr int MAX_TRACE_FRAMES = 20;

std::atomic<bool> gInstalled{false};
std::atomic<uintptr_t> gUnityBase{0};
int gLogFd = -1;
pthread_mutex_t gLogLock = PTHREAD_MUTEX_INITIALIZER;
thread_local int gNetHookDepth = 0;

using FnWrite = ssize_t (*)(int, const void *, size_t);
FnWrite orig_Write = nullptr;

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

static ssize_t log_write_raw(int fd, const void *buf, size_t len) {
    if (orig_Write) return orig_Write(fd, buf, len);
    return ::write(fd, buf, len);
}

static void ensure_log_open() {
    if (gLogFd >= 0) return;
    pthread_mutex_lock(&gLogLock);
    if (gLogFd < 0) {
        const char *home = getenv("HOME");
        char path[1024];
        if (home && *home) {
            snprintf(path, sizeof(path), "%s/Documents/Login10195Diag_v0.3.log", home);
        } else {
            snprintf(path, sizeof(path), "/tmp/Login10195Diag_v0.3.log");
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
    if (pn > 0) log_write_raw(gLogFd, prefix, static_cast<size_t>(pn));
    if (bn > 0) log_write_raw(gLogFd, body, static_cast<size_t>(bn));
    log_write_raw(gLogFd, "\n", 1);
    fsync(gLogFd);
    pthread_mutex_unlock(&gLogLock);
}

static uintptr_t find_unity_base() {
    const uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; ++i) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        if (strstr(name, "UnityFramework.framework/UnityFramework") || strstr(name, "/UnityFramework")) {
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
            log_line("%s addr=%p image=%s imageOff=0x%llX", tag, addr, di.dli_fname,
                     static_cast<unsigned long long>(io));
        }
    } else {
        log_line("%s addr=%p", tag, addr);
    }
}

static void log_trace(const char *tag) {
    void *frames[MAX_TRACE_FRAMES]{};
    int n = backtrace(frames, MAX_TRACE_FRAMES);
    log_line("%s backtrace count=%d", tag, n);
    for (int i = 0; i < n; ++i) {
        char lineTag[96];
        snprintf(lineTag, sizeof(lineTag), "%s #%02d", tag, i);
        log_address(lineTag, frames[i]);
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

static uint16_t read_be16(const uint8_t *p) {
    return static_cast<uint16_t>((static_cast<uint16_t>(p[0]) << 8) | p[1]);
}

static uint32_t read_be32(const uint8_t *p) {
    return (static_cast<uint32_t>(p[0]) << 24) |
           (static_cast<uint32_t>(p[1]) << 16) |
           (static_cast<uint32_t>(p[2]) << 8) |
           static_cast<uint32_t>(p[3]);
}

static std::string hex_preview(const uint8_t *p, size_t len) {
    if (!p || !len) return "";
    if (len > MAX_HEX_BYTES) len = MAX_HEX_BYTES;
    static const char hex[] = "0123456789ABCDEF";
    std::string out;
    out.reserve(len * 3);
    for (size_t i = 0; i < len; ++i) {
        if (i) out.push_back(' ');
        out.push_back(hex[p[i] >> 4]);
        out.push_back(hex[p[i] & 0xF]);
    }
    return out;
}

static std::string peer_text(int fd) {
    sockaddr_storage ss{};
    socklen_t sl = sizeof(ss);
    if (getpeername(fd, reinterpret_cast<sockaddr *>(&ss), &sl) != 0) return "<not-socket-or-unconnected>";
    char ip[INET6_ADDRSTRLEN]{};
    uint16_t port = 0;
    if (ss.ss_family == AF_INET) {
        auto *a = reinterpret_cast<sockaddr_in *>(&ss);
        inet_ntop(AF_INET, &a->sin_addr, ip, sizeof(ip));
        port = ntohs(a->sin_port);
    } else if (ss.ss_family == AF_INET6) {
        auto *a = reinterpret_cast<sockaddr_in6 *>(&ss);
        inet_ntop(AF_INET6, &a->sin6_addr, ip, sizeof(ip));
        port = ntohs(a->sin6_port);
    } else {
        return "<non-ip-socket>";
    }
    char out[160];
    snprintf(out, sizeof(out), "%s:%u", ip[0] ? ip : "?", port);
    return out;
}

static void inspect_outbound(const char *api, int fd, const void *buf, size_t len, void *caller) {
    if (!buf || len < 10) return;
    const uint8_t *p = static_cast<const uint8_t *>(buf);
    size_t scanLen = len > MAX_SCAN_BYTES ? MAX_SCAN_BYTES : len;

    for (size_t off = 0; off + 10 <= scanLen; ++off) {
        const uint16_t msg = read_be16(p + off + 4);
        if (msg != MSG_BOOTSTRAP && msg != MSG_ZONE_LIST) continue;

        const uint32_t bodyLen = read_be32(p + off);
        const uint32_t seq = read_be32(p + off + 6);
        // Avoid accidental 0x2713/0x27D3 byte matches in arbitrary file data.
        const bool framePlausible = bodyLen <= (16U * 1024U * 1024U) &&
                                    (bodyLen == 0 || bodyLen + 10 <= (len - off) || len - off < 4096);
        if (!framePlausible) continue;

        std::string peer = peer_text(fd);
        size_t previewLen = len - off;
        if (previewLen > MAX_HEX_BYTES) previewLen = MAX_HEX_BYTES;
        std::string hx = hex_preview(p + off, previewLen);
        log_line("[SOCKET] MATCH api=%s fd=%d peer=%s off=%zu len=%zu msg=%u/0x%04X body=%u seq=%u caller=%p",
                 api, fd, peer.c_str(), off, len, static_cast<unsigned>(msg), static_cast<unsigned>(msg),
                 bodyLen, seq, caller);
        log_line("[SOCKET] HEX %s", hx.c_str());
        log_address("[SOCKET] CALLER", caller);
        log_trace(msg == MSG_ZONE_LIST ? "[SOCKET-10195]" : "[SOCKET-10003]");
        return;
    }
}

using FnSend = ssize_t (*)(int, const void *, size_t, int);
using FnSendTo = ssize_t (*)(int, const void *, size_t, int, const struct sockaddr *, socklen_t);
using FnSendMsg = ssize_t (*)(int, const struct msghdr *, int);
using FnWritev = ssize_t (*)(int, const struct iovec *, int);
FnSend orig_Send = nullptr;
FnSendTo orig_SendTo = nullptr;
FnSendMsg orig_SendMsg = nullptr;
FnWritev orig_Writev = nullptr;

static ssize_t hook_Send(int fd, const void *buf, size_t len, int flags) {
    if (gNetHookDepth++ == 0) inspect_outbound("send", fd, buf, len, __builtin_return_address(0));
    --gNetHookDepth;
    return orig_Send(fd, buf, len, flags);
}

static ssize_t hook_SendTo(int fd, const void *buf, size_t len, int flags, const struct sockaddr *to, socklen_t tolen) {
    if (gNetHookDepth++ == 0) inspect_outbound("sendto", fd, buf, len, __builtin_return_address(0));
    --gNetHookDepth;
    return orig_SendTo(fd, buf, len, flags, to, tolen);
}

static size_t merge_iov(const struct iovec *iov, int iovcnt, uint8_t *out, size_t cap) {
    if (!iov || iovcnt <= 0 || !out || cap == 0) return 0;
    size_t used = 0;
    for (int i = 0; i < iovcnt && used < cap; ++i) {
        if (!iov[i].iov_base || !iov[i].iov_len) continue;
        size_t n = iov[i].iov_len;
        if (n > cap - used) n = cap - used;
        memcpy(out + used, iov[i].iov_base, n);
        used += n;
    }
    return used;
}

static ssize_t hook_SendMsg(int fd, const struct msghdr *msg, int flags) {
    if (gNetHookDepth++ == 0 && msg) {
        uint8_t merged[MAX_SCAN_BYTES];
        size_t n = merge_iov(msg->msg_iov, static_cast<int>(msg->msg_iovlen), merged, sizeof(merged));
        inspect_outbound("sendmsg", fd, merged, n, __builtin_return_address(0));
    }
    --gNetHookDepth;
    return orig_SendMsg(fd, msg, flags);
}

static ssize_t hook_Write(int fd, const void *buf, size_t len) {
    if (fd == gLogFd) return orig_Write(fd, buf, len);
    if (gNetHookDepth++ == 0) inspect_outbound("write", fd, buf, len, __builtin_return_address(0));
    --gNetHookDepth;
    return orig_Write(fd, buf, len);
}

static ssize_t hook_Writev(int fd, const struct iovec *iov, int iovcnt) {
    if (gNetHookDepth++ == 0) {
        uint8_t merged[MAX_SCAN_BYTES];
        size_t n = merge_iov(iov, iovcnt, merged, sizeof(merged));
        inspect_outbound("writev", fd, merged, n, __builtin_return_address(0));
    }
    --gNetHookDepth;
    return orig_Writev(fd, iov, iovcnt);
}

// Static business-level 10195 hook retained as a secondary signal.
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

using FnBeginQuickInit = void (*)(void *, void *);
FnBeginQuickInit orig_BeginQuickInit = nullptr;
static void hook_BeginQuickInit(void *self, void *sel) {
    log_line("[QuickInit] ENTER self=%p class=%s sel=%s", self, class_name_safe(self),
             sel ? sel_getName(reinterpret_cast<SEL>(sel)) : "<null>");
    const uint64_t t0 = now_ms();
    orig_BeginQuickInit(self, sel);
    log_line("[QuickInit] LEAVE elapsed=%llums", static_cast<unsigned long long>(now_ms() - t0));
}

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
    log_line("[ServerList] LEAVE elapsed=%llums", static_cast<unsigned long long>(now_ms() - t0));
}

using FnHttpSync2 = void *(*)(void *, void *, void *, void *, void *);
FnHttpSync2 orig_HttpSync2 = nullptr;
static void *hook_HttpSync2(void *self, void *sel, void *url, void *param, void *method) {
    log_line("[HTTP2] ENTER self=%p class=%s sel=%s", self, class_name_safe(self),
             sel ? sel_getName(reinterpret_cast<SEL>(sel)) : "<null>");
    std::string u = objc_text(url), p = objc_text(param), m = objc_text(method);
    log_line("[HTTP2] url    %s", u.c_str());
    log_line("[HTTP2] method %s", m.c_str());
    log_line("[HTTP2] param  %s", p.c_str());
    const uint64_t t0 = now_ms();
    void *ret = orig_HttpSync2(self, sel, url, param, method);
    std::string r = objc_text(ret);
    log_line("[HTTP2] LEAVE elapsed=%llums result=%s",
             static_cast<unsigned long long>(now_ms() - t0), r.c_str());
    return ret;
}

static bool hook_rva(const char *name, uintptr_t rva, void *replacement, void **original) {
    void *target = rva_ptr(rva);
    int rc = DobbyHook(target, replacement, original);
    log_line("[INSTALL] %s RVA=0x%llX target=%p rc=%d original=%p", name,
             static_cast<unsigned long long>(rva), target, rc, original ? *original : nullptr);
    return rc == 0;
}

static bool hook_symbol(const char *name, void *replacement, void **original) {
    void *target = dlsym(RTLD_DEFAULT, name);
    if (!target) {
        log_line("[INSTALL] symbol %s not found", name);
        return false;
    }
    int rc = DobbyHook(target, replacement, original);
    log_line("[INSTALL] symbol %s target=%p rc=%d original=%p", name, target, rc,
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
    log_line("Login10195Diag v0.3 start");
    log_line("UnityFramework base=%p", reinterpret_cast<void *>(base));
    log_line("Protocol watch: 10003=0x2713 10195=0x27D3");

    bool ok = true;
    ok &= hook_rva("Send10195", RVA_SEND_10195,
                   reinterpret_cast<void *>(hook_10195), reinterpret_cast<void **>(&orig_10195));
    ok &= hook_rva("beginQuickSDKInit", RVA_QUICKSDK_BEGIN_INIT,
                   reinterpret_cast<void *>(hook_BeginQuickInit), reinterpret_cast<void **>(&orig_BeginQuickInit));
    ok &= hook_rva("addSyncHttpRequest2:param:method:", RVA_HTTP_SYNC_REQUEST2,
                   reinterpret_cast<void *>(hook_HttpSync2), reinterpret_cast<void **>(&orig_HttpSync2));
    ok &= hook_rva("updateServerListWithChannelParams:handler:", RVA_UPDATE_SERVER_LIST,
                   reinterpret_cast<void *>(hook_UpdateServerList), reinterpret_cast<void **>(&orig_UpdateServerList));

    // Socket-level trace. Install write before subsequent log lines so logger immediately switches to trampoline.
    ok &= hook_symbol("write", reinterpret_cast<void *>(hook_Write), reinterpret_cast<void **>(&orig_Write));
    ok &= hook_symbol("writev", reinterpret_cast<void *>(hook_Writev), reinterpret_cast<void **>(&orig_Writev));
    ok &= hook_symbol("send", reinterpret_cast<void *>(hook_Send), reinterpret_cast<void **>(&orig_Send));
    ok &= hook_symbol("sendto", reinterpret_cast<void *>(hook_SendTo), reinterpret_cast<void **>(&orig_SendTo));
    ok &= hook_symbol("sendmsg", reinterpret_cast<void *>(hook_SendMsg), reinterpret_cast<void **>(&orig_SendMsg));

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
    log_line("[BOOT] Login10195Diag v0.3 loaded");
    pthread_t t{};
    if (pthread_create(&t, nullptr, install_thread, nullptr) == 0) {
        pthread_detach(t);
    } else {
        log_line("[BOOT] pthread_create failed");
    }
}

} // namespace
