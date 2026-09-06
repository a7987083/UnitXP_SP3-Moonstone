#include <mach-o/dyld.h>
#include <dlfcn.h>
#include <pthread.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <time.h>
#include <execinfo.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <atomic>
#include <string>
#include <vector>

#include "dobby.h"

namespace {

constexpr uintptr_t RVA_SDK_ON_LOGIN_SUCCESS   = 0x2A674D4;
constexpr uintptr_t RVA_SDK_GET_APP_INFO       = 0x2A67980;
constexpr uintptr_t RVA_SDK_GET_BUILD_VERSION  = 0x2A683A4;
constexpr uintptr_t RVA_SDK_GET_VERSION        = 0x2A68540;
constexpr uintptr_t RVA_SDK_GET_CHANNEL_ID     = 0x2A68CBC;
constexpr uintptr_t RVA_SDK_ON_INIT_SUCCESS    = 0x2A68E50;
constexpr uintptr_t RVA_SDK_LOGIN              = 0x2A68F4C;
constexpr uintptr_t RVA_SDK_IS_INIT            = 0x2A69078;
constexpr uintptr_t RVA_TCP_DO_CONNECT         = 0x1CC96B4;
constexpr uintptr_t RVA_TCP_SEND_MESSAGE       = 0x1CCA124;

constexpr uintptr_t NETWORK_IP_OFFSET          = 0x48;
constexpr uintptr_t NETWORK_PORT_OFFSET        = 0x50;

constexpr size_t MAX_PACKET_LOG_BYTES = 128;
constexpr size_t MAX_STRING_PREVIEW = 256;
constexpr size_t MAX_BACKTRACE = 24;

struct Il2CppString {
    void *klass;
    void *monitor;
    int32_t length;
    uint16_t chars[0];
};

struct Il2CppArrayHeader {
    void *klass;
    void *monitor;
    void *bounds;
    uintptr_t max_length;
    uint8_t vector[0];
};

std::atomic<bool> gInstalled{false};
std::atomic<uintptr_t> gUnityBase{0};
int gLogFd = -1;
pthread_mutex_t gLogLock = PTHREAD_MUTEX_INITIALIZER;

static uint64_t tid_now() {
    uint64_t tid = 0;
    pthread_threadid_np(nullptr, &tid);
    return tid;
}

static void ensure_log_open() {
    if (gLogFd >= 0) return;
    pthread_mutex_lock(&gLogLock);
    if (gLogFd < 0) {
        const char *home = getenv("HOME");
        char path[1024];
        if (home && *home) {
            snprintf(path, sizeof(path), "%s/Documents/Login10195Diag.log", home);
        } else {
            snprintf(path, sizeof(path), "/tmp/Login10195Diag.log");
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

    char prefix[160];
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
    if (bn >= static_cast<int>(sizeof(body))) bn = sizeof(body) - 1;

    pthread_mutex_lock(&gLogLock);
    if (pn > 0) write(gLogFd, prefix, static_cast<size_t>(pn));
    if (bn > 0) write(gLogFd, body, static_cast<size_t>(bn));
    write(gLogFd, "\n", 1);
    fsync(gLogFd);
    pthread_mutex_unlock(&gLogLock);
}

static std::string utf16_to_utf8_preview(const Il2CppString *s, size_t maxChars = MAX_STRING_PREVIEW) {
    if (!s) return "<null>";
    int32_t n = s->length;
    if (n < 0 || n > 1024 * 1024) return "<bad-il2cpp-string>";
    size_t count = static_cast<size_t>(n);
    if (count > maxChars) count = maxChars;

    std::string out;
    out.reserve(count * 3 + 32);
    for (size_t i = 0; i < count; ++i) {
        uint32_t c = s->chars[i];
        if (c >= 0xD800 && c <= 0xDBFF && i + 1 < count) {
            uint32_t d = s->chars[i + 1];
            if (d >= 0xDC00 && d <= 0xDFFF) {
                c = 0x10000 + (((c - 0xD800) << 10) | (d - 0xDC00));
                ++i;
            }
        }
        if (c < 0x80) {
            char ch = static_cast<char>(c);
            if (ch == '\n' || ch == '\r' || ch == '\t') ch = ' ';
            out.push_back(ch);
        } else if (c < 0x800) {
            out.push_back(static_cast<char>(0xC0 | (c >> 6)));
            out.push_back(static_cast<char>(0x80 | (c & 0x3F)));
        } else if (c < 0x10000) {
            out.push_back(static_cast<char>(0xE0 | (c >> 12)));
            out.push_back(static_cast<char>(0x80 | ((c >> 6) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | (c & 0x3F)));
        } else {
            out.push_back(static_cast<char>(0xF0 | (c >> 18)));
            out.push_back(static_cast<char>(0x80 | ((c >> 12) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | ((c >> 6) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | (c & 0x3F)));
        }
    }
    if (static_cast<size_t>(n) > count) out += "…";
    return out;
}

static uint64_t fnv1a64(const void *data, size_t len) {
    const uint8_t *p = static_cast<const uint8_t *>(data);
    uint64_t h = 1469598103934665603ULL;
    for (size_t i = 0; i < len; ++i) {
        h ^= p[i];
        h *= 1099511628211ULL;
    }
    return h;
}

static std::string string_summary(const Il2CppString *s) {
    if (!s) return "<null>";
    int32_t n = s->length;
    if (n < 0 || n > 1024 * 1024) return "<bad-il2cpp-string>";
    size_t bytes = static_cast<size_t>(n) * sizeof(uint16_t);
    uint64_t hash = fnv1a64(s->chars, bytes);
    std::string preview = utf16_to_utf8_preview(s);
    char head[128];
    snprintf(head, sizeof(head), "len=%d fnv64=%016llx preview=", n,
             static_cast<unsigned long long>(hash));
    return std::string(head) + preview;
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

struct PacketInfo {
    bool framed = false;
    uint32_t bodyLen = 0;
    uint16_t msgId = 0;
    uint32_t seq = 0;
};

static PacketInfo parse_packet(const uint8_t *p, size_t len) {
    PacketInfo info;
    if (!p || len < 10) return info;
    uint32_t body = read_be32(p);
    uint16_t msg = read_be16(p + 4);
    uint32_t seq = read_be32(p + 6);
    if (body <= len - 10 && (body + 10 == len || len - (body + 10) < 64)) {
        info.framed = true;
        info.bodyLen = body;
        info.msgId = msg;
        info.seq = seq;
    }
    return info;
}

static std::string hex_preview(const uint8_t *p, size_t len) {
    if (!p || !len) return "";
    if (len > MAX_PACKET_LOG_BYTES) len = MAX_PACKET_LOG_BYTES;
    static const char *hex = "0123456789ABCDEF";
    std::string out;
    out.reserve(len * 3);
    for (size_t i = 0; i < len; ++i) {
        if (i) out.push_back(' ');
        out.push_back(hex[p[i] >> 4]);
        out.push_back(hex[p[i] & 0x0F]);
    }
    return out;
}

static void log_address(const char *prefix, void *addr) {
    Dl_info di{};
    uintptr_t ub = gUnityBase.load();
    if (dladdr(addr, &di) && di.dli_fname) {
        uintptr_t imageBase = reinterpret_cast<uintptr_t>(di.dli_fbase);
        uintptr_t off = reinterpret_cast<uintptr_t>(addr) - imageBase;
        log_line("%s addr=%p image=%s imageOff=0x%llX unityOff=%s",
                 prefix, addr, di.dli_fname,
                 static_cast<unsigned long long>(off),
                 (ub && reinterpret_cast<uintptr_t>(addr) >= ub) ? "available" : "n/a");
        if (ub && reinterpret_cast<uintptr_t>(addr) >= ub) {
            log_line("%s unityRVA=0x%llX", prefix,
                     static_cast<unsigned long long>(reinterpret_cast<uintptr_t>(addr) - ub));
        }
    } else {
        log_line("%s addr=%p", prefix, addr);
    }
}

static void log_backtrace_for_10195() {
    void *frames[MAX_BACKTRACE]{};
    int n = backtrace(frames, static_cast<int>(MAX_BACKTRACE));
    log_line("[10195] backtrace count=%d", n);
    uintptr_t ub = gUnityBase.load();
    for (int i = 0; i < n; ++i) {
        Dl_info di{};
        if (dladdr(frames[i], &di) && di.dli_fname) {
            uintptr_t ib = reinterpret_cast<uintptr_t>(di.dli_fbase);
            uintptr_t io = reinterpret_cast<uintptr_t>(frames[i]) - ib;
            if (ub && strstr(di.dli_fname, "UnityFramework")) {
                log_line("[10195] #%02d %p %s +0x%llX UnityRVA=0x%llX",
                         i, frames[i], di.dli_fname,
                         static_cast<unsigned long long>(io),
                         static_cast<unsigned long long>(reinterpret_cast<uintptr_t>(frames[i]) - ub));
            } else {
                log_line("[10195] #%02d %p %s +0x%llX",
                         i, frames[i], di.dli_fname,
                         static_cast<unsigned long long>(io));
            }
        } else {
            log_line("[10195] #%02d %p", i, frames[i]);
        }
    }
}

static uintptr_t find_unity_base() {
    uint32_t count = _dyld_image_count();
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

using FnStaticVoid = void (*)(void *method);
using FnStaticBool = bool (*)(void *method);
using FnStaticString = Il2CppString *(*)(void *method);
using FnInstanceStringVoid = void (*)(void *self, Il2CppString *s, void *method);
using FnInstanceVoid = void (*)(void *self, void *method);
using FnSendMessage = void (*)(void *self, Il2CppArrayHeader *arr, void *method);

FnStaticVoid orig_SDKLogin = nullptr;
FnStaticBool orig_IsSdkInit = nullptr;
FnStaticString orig_GetAppInfoMessage = nullptr;
FnStaticString orig_GetBuildVersionString = nullptr;
FnStaticString orig_GetVersionString = nullptr;
FnStaticString orig_GetChannelID = nullptr;
FnInstanceStringVoid orig_OnLoginSuccess = nullptr;
FnInstanceStringVoid orig_OnInitSuccess = nullptr;
FnInstanceVoid orig_TcpDoConnect = nullptr;
FnSendMessage orig_TcpSendMessage = nullptr;

static void hook_SDKLogin(void *method) {
    log_line("[SDK] SDKLogin enter method=%p", method);
    orig_SDKLogin(method);
    log_line("[SDK] SDKLogin leave");
}

static bool hook_IsSdkInit(void *method) {
    bool r = orig_IsSdkInit(method);
    log_line("[SDK] IsSdkInit -> %d", r ? 1 : 0);
    return r;
}

static Il2CppString *hook_GetAppInfoMessage(void *method) {
    Il2CppString *r = orig_GetAppInfoMessage(method);
    std::string s = string_summary(r);
    log_line("[SDK] GetAppInfoMessage -> %s", s.c_str());
    return r;
}

static Il2CppString *hook_GetBuildVersionString(void *method) {
    Il2CppString *r = orig_GetBuildVersionString(method);
    std::string s = string_summary(r);
    log_line("[SDK] GetBuildVersionString -> %s", s.c_str());
    return r;
}

static Il2CppString *hook_GetVersionString(void *method) {
    Il2CppString *r = orig_GetVersionString(method);
    std::string s = string_summary(r);
    log_line("[SDK] GetVersionString -> %s", s.c_str());
    return r;
}

static Il2CppString *hook_GetChannelID(void *method) {
    Il2CppString *r = orig_GetChannelID(method);
    std::string s = string_summary(r);
    log_line("[SDK] GetChannelID -> %s", s.c_str());
    return r;
}

static void hook_OnLoginSuccess(void *self, Il2CppString *s, void *method) {
    std::string ss = string_summary(s);
    log_line("[SDK] onLoginSuccess self=%p %s", self, ss.c_str());
    orig_OnLoginSuccess(self, s, method);
    log_line("[SDK] onLoginSuccess leave");
}

static void hook_OnInitSuccess(void *self, Il2CppString *s, void *method) {
    std::string ss = string_summary(s);
    log_line("[SDK] onInitSuccess self=%p %s", self, ss.c_str());
    orig_OnInitSuccess(self, s, method);
}

static void hook_TcpDoConnect(void *self, void *method) {
    Il2CppString *ip = nullptr;
    int port = -1;
    if (self) {
        ip = *reinterpret_cast<Il2CppString **>(reinterpret_cast<uint8_t *>(self) + NETWORK_IP_OFFSET);
        port = *reinterpret_cast<int *>(reinterpret_cast<uint8_t *>(self) + NETWORK_PORT_OFFSET);
    }
    std::string ips = string_summary(ip);
    log_line("[NET] TcpNetwork.DoConnect self=%p port=%d ip=%s", self, port, ips.c_str());
    orig_TcpDoConnect(self, method);
}

static void hook_TcpSendMessage(void *self, Il2CppArrayHeader *arr, void *method) {
    size_t len = 0;
    const uint8_t *data = nullptr;
    if (arr) {
        len = static_cast<size_t>(arr->max_length);
        data = arr->vector;
    }

    PacketInfo pi = parse_packet(data, len);
    std::string hx = hex_preview(data, len);
    void *lr = __builtin_return_address(0);

    if (pi.framed) {
        log_line("[NET] TcpNetwork.SendMessage self=%p len=%zu msg=%u seq=%u body=%u lr=%p hex=%s",
                 self, len, static_cast<unsigned>(pi.msgId), pi.seq, pi.bodyLen, lr, hx.c_str());
    } else {
        log_line("[NET] TcpNetwork.SendMessage self=%p len=%zu msg=<unparsed> lr=%p hex=%s",
                 self, len, lr, hx.c_str());
    }

    if (pi.framed && pi.msgId == 10195) {
        log_line("[10195] detected before original SendMessage");
        log_address("[10195] caller", lr);
        log_backtrace_for_10195();
    }

    orig_TcpSendMessage(self, arr, method);
}

static bool install_one(const char *name, uintptr_t rva, void *replacement, void **origin) {
    void *target = rva_ptr(rva);
    int rc = DobbyHook(target, replacement, origin);
    log_line("[HOOK] %s target=%p rva=0x%llX rc=%d orig=%p",
             name, target, static_cast<unsigned long long>(rva), rc, origin ? *origin : nullptr);
    return rc == 0 && origin && *origin;
}

static void install_hooks() {
    if (gInstalled.exchange(true)) return;

    uintptr_t base = find_unity_base();
    if (!base) {
        gInstalled.store(false);
        return;
    }
    gUnityBase.store(base);
    log_line("[INIT] UnityFramework base=%p", reinterpret_cast<void *>(base));

    bool ok = true;
    ok &= install_one("SDKInterface.SDKLogin", RVA_SDK_LOGIN,
                      reinterpret_cast<void *>(hook_SDKLogin), reinterpret_cast<void **>(&orig_SDKLogin));
    ok &= install_one("SDKInterface.IsSdkInit", RVA_SDK_IS_INIT,
                      reinterpret_cast<void *>(hook_IsSdkInit), reinterpret_cast<void **>(&orig_IsSdkInit));
    ok &= install_one("SDKInterface.GetAppInfoMessage", RVA_SDK_GET_APP_INFO,
                      reinterpret_cast<void *>(hook_GetAppInfoMessage), reinterpret_cast<void **>(&orig_GetAppInfoMessage));
    ok &= install_one("SDKInterface.GetBuildVersionString", RVA_SDK_GET_BUILD_VERSION,
                      reinterpret_cast<void *>(hook_GetBuildVersionString), reinterpret_cast<void **>(&orig_GetBuildVersionString));
    ok &= install_one("SDKInterface.GetVersionString", RVA_SDK_GET_VERSION,
                      reinterpret_cast<void *>(hook_GetVersionString), reinterpret_cast<void **>(&orig_GetVersionString));
    ok &= install_one("SDKInterface.GetChannelID", RVA_SDK_GET_CHANNEL_ID,
                      reinterpret_cast<void *>(hook_GetChannelID), reinterpret_cast<void **>(&orig_GetChannelID));
    ok &= install_one("SDKInterface.onLoginSuccess", RVA_SDK_ON_LOGIN_SUCCESS,
                      reinterpret_cast<void *>(hook_OnLoginSuccess), reinterpret_cast<void **>(&orig_OnLoginSuccess));
    ok &= install_one("SDKInterface.onInitSuccess", RVA_SDK_ON_INIT_SUCCESS,
                      reinterpret_cast<void *>(hook_OnInitSuccess), reinterpret_cast<void **>(&orig_OnInitSuccess));
    ok &= install_one("TcpNetwork.DoConnect", RVA_TCP_DO_CONNECT,
                      reinterpret_cast<void *>(hook_TcpDoConnect), reinterpret_cast<void **>(&orig_TcpDoConnect));
    ok &= install_one("TcpNetwork.SendMessage", RVA_TCP_SEND_MESSAGE,
                      reinterpret_cast<void *>(hook_TcpSendMessage), reinterpret_cast<void **>(&orig_TcpSendMessage));

    log_line("[INIT] install complete ok=%d", ok ? 1 : 0);
    log_line("[INIT] intentionally skipped tiny/high-risk stubs: NetworkBase.SetHostPort(12B), NetworkBase.SendMessage(4B), SDKInterface.onLoginFailed(4B), and high-frequency NetworkBase.UpdateNetwork");
}

static void *installer_thread(void *) {
    ensure_log_open();
    log_line("[INIT] Login10195Diag v0.1 loaded");
    for (int i = 0; i < 300 && !gInstalled.load(); ++i) {
        if (find_unity_base()) {
            install_hooks();
            break;
        }
        usleep(100 * 1000);
    }
    if (!gInstalled.load()) {
        log_line("[INIT] UnityFramework not found after 30s; hooks not installed");
    }
    return nullptr;
}

__attribute__((constructor)) static void Login10195Diag_ctor() {
    pthread_t th{};
    if (pthread_create(&th, nullptr, installer_thread, nullptr) == 0) {
        pthread_detach(th);
    }
}

} // namespace
