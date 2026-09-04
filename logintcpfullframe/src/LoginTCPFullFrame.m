#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#include <arpa/inet.h>
#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#include "../vendor/fishhook.h"

#define TARGET_IP "118.145.146.208"
#define MAX_TRACKED_FD 4096
#define MAX_BODY_LEN (64U * 1024U * 1024U)
#define MAX_BUFFER_LEN (128U * 1024U * 1024U)

static UIWindow *gWindow;
static UIButton *gFloatButton;
static UIView *gPanel;
static UILabel *gStatusLabel;
static UITextView *gTextView;
static NSMutableArray *gEvents;
static BOOL gUIReady = NO;
static BOOL gHooksInstalled = NO;
static NSInteger gHookDelayTicks = 0;

static unsigned long long gFrameSeq = 0;
static unsigned long long gConnSeq = 0;
static unsigned long long gTxFrames = 0;
static unsigned long long gRxFrames = 0;
static unsigned long long gTxBytes = 0;
static unsigned long long gRxBytes = 0;
static double gStartTime = 0.0;

static char gSessionDir[PATH_MAX] = {0};
static char gManifestPath[PATH_MAX] = {0};

static pthread_mutex_t gCaptureLock = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t gFileLock = PTHREAD_MUTEX_INITIALIZER;
static __thread int gInsideHook = 0;

typedef ssize_t (*SendFn)(int, const void *, size_t, int);
typedef ssize_t (*RecvFn)(int, void *, size_t, int);
typedef ssize_t (*SendToFn)(int, const void *, size_t, int, const struct sockaddr *, socklen_t);
typedef ssize_t (*RecvFromFn)(int, void *, size_t, int, struct sockaddr *, socklen_t *);

static SendFn gOrigSend;
static RecvFn gOrigRecv;
static SendToFn gOrigSendTo;
static RecvFromFn gOrigRecvFrom;

typedef struct {
    unsigned char *data;
    size_t len;
    size_t cap;
} StreamBuffer;

typedef struct {
    int active;
    uint16_t remotePort;
    uint16_t localPort;
    unsigned long long connId;
    StreamBuffer tx;
    StreamBuffer rx;
} FDState;

static FDState gFDState[MAX_TRACKED_FD];

static double NowSeconds(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (double)tv.tv_sec + (double)tv.tv_usec / 1000000.0;
}

static NSString *RelTime(void) {
    double now = NowSeconds();
    if (gStartTime <= 0.0) gStartTime = now;
    return [NSString stringWithFormat:@"+%.3fs", now - gStartTime];
}

static void AppendManifestFmt(const char *fmt, ...) {
    if (!gManifestPath[0] || !fmt) return;
    char line[4096];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(line, sizeof(line), fmt, ap);
    va_end(ap);

    pthread_mutex_lock(&gFileLock);
    FILE *f = fopen(gManifestPath, "a");
    if (f) {
        fwrite(line, 1, strlen(line), f);
        fwrite("\n", 1, 1, f);
        fflush(f);
        fclose(f);
    }
    pthread_mutex_unlock(&gFileLock);
}

static void RefreshUI(void) {
    if (!gStatusLabel || !gTextView) return;
    gStatusLabel.text = [NSString stringWithFormat:@"FullFrame: %@  TX=%llu RX=%llu\n%s :7000-7999",
                         gHooksInstalled ? @"ACTIVE" : @"WAITING",
                         gTxFrames, gRxFrames, TARGET_IP];
    NSString *text = [gEvents componentsJoinedByString:@"\n"];
    gTextView.text = text;
    if (text.length) [gTextView scrollRangeToVisible:NSMakeRange(text.length, 0)];
}

static void PushUIEvent(NSString *line) {
    if (!line.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gEvents) gEvents = [[NSMutableArray alloc] init];
        [gEvents addObject:line];
        if (gEvents.count > 40) [gEvents removeObjectAtIndex:0];
        RefreshUI();
    });
}

static BOOL IsTargetPort(uint16_t port) {
    return port >= 7000 && port <= 7999;
}

static BOOL DecodeSockaddr(const struct sockaddr *sa, socklen_t len, char *ip, size_t ipCap, uint16_t *portOut) {
    if (!sa || len < sizeof(struct sockaddr_in) || sa->sa_family != AF_INET) return NO;
    const struct sockaddr_in *sin = (const struct sockaddr_in *)sa;
    char tmp[INET_ADDRSTRLEN] = {0};
    if (!inet_ntop(AF_INET, &sin->sin_addr, tmp, sizeof(tmp))) return NO;
    if (ip && ipCap) snprintf(ip, ipCap, "%s", tmp);
    if (portOut) *portOut = ntohs(sin->sin_port);
    return YES;
}

static BOOL TargetForFD(int fd, uint16_t *remotePortOut, uint16_t *localPortOut) {
    struct sockaddr_storage peer;
    socklen_t peerLen = sizeof(peer);
    memset(&peer, 0, sizeof(peer));
    if (getpeername(fd, (struct sockaddr *)&peer, &peerLen) != 0) return NO;

    char ip[INET_ADDRSTRLEN] = {0};
    uint16_t remotePort = 0;
    if (!DecodeSockaddr((struct sockaddr *)&peer, peerLen, ip, sizeof(ip), &remotePort)) return NO;
    if (strcmp(ip, TARGET_IP) != 0 || !IsTargetPort(remotePort)) return NO;

    uint16_t localPort = 0;
    struct sockaddr_storage local;
    socklen_t localLen = sizeof(local);
    memset(&local, 0, sizeof(local));
    if (getsockname(fd, (struct sockaddr *)&local, &localLen) == 0 && local.ss_family == AF_INET) {
        const struct sockaddr_in *sin = (const struct sockaddr_in *)&local;
        localPort = ntohs(sin->sin_port);
    }

    if (remotePortOut) *remotePortOut = remotePort;
    if (localPortOut) *localPortOut = localPort;
    return YES;
}

static uint16_t ReadBE16(const unsigned char *p) {
    return (uint16_t)(((uint16_t)p[0] << 8) | p[1]);
}

static uint32_t ReadBE32(const unsigned char *p) {
    return ((uint32_t)p[0] << 24) |
           ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] << 8) |
           (uint32_t)p[3];
}

static void FreeStream(StreamBuffer *b) {
    if (!b) return;
    free(b->data);
    b->data = NULL;
    b->len = 0;
    b->cap = 0;
}

static void ResetFDState(FDState *s, int fd, uint16_t remotePort, uint16_t localPort) {
    if (!s) return;
    FreeStream(&s->tx);
    FreeStream(&s->rx);
    memset(s, 0, sizeof(*s));
    s->active = 1;
    s->remotePort = remotePort;
    s->localPort = localPort;
    s->connId = ++gConnSeq;
    AppendManifestFmt("CONN\t%llu\tfd=%d\tlocal_port=%u\tremote=%s:%u",
                      s->connId, fd, localPort, TARGET_IP, remotePort);
    @autoreleasepool {
        PushUIEvent([NSString stringWithFormat:@"CONN #%llu fd=%d -> %s:%u",
                     s->connId, fd, TARGET_IP, remotePort]);
    }
}

static FDState *StateForFD(int fd, uint16_t remotePort, uint16_t localPort) {
    if (fd < 0 || fd >= MAX_TRACKED_FD) return NULL;
    FDState *s = &gFDState[fd];
    if (!s->active || s->remotePort != remotePort || s->localPort != localPort) {
        ResetFDState(s, fd, remotePort, localPort);
    }
    return s;
}

static BOOL EnsureCapacity(StreamBuffer *b, size_t need) {
    if (!b) return NO;
    if (need > MAX_BUFFER_LEN) return NO;
    if (b->cap >= need) return YES;
    size_t cap = b->cap ? b->cap : 4096;
    while (cap < need) {
        if (cap > MAX_BUFFER_LEN / 2) {
            cap = MAX_BUFFER_LEN;
            break;
        }
        cap *= 2;
    }
    unsigned char *p = (unsigned char *)realloc(b->data, cap);
    if (!p) return NO;
    b->data = p;
    b->cap = cap;
    return YES;
}

static void WriteBinaryFile(const char *path, const void *data, size_t len, BOOL append) {
    if (!path || !data || !len) return;
    FILE *f = fopen(path, append ? "ab" : "wb");
    if (!f) return;
    fwrite(data, 1, len, f);
    fflush(f);
    fclose(f);
}

static void WriteStreamChunk(FDState *s, int fd, BOOL tx, const void *data, size_t len) {
    if (!s || !gSessionDir[0] || !data || !len) return;
    char path[PATH_MAX];
    snprintf(path, sizeof(path), "%s/streams/conn%04llu_fd%d_lp%u_rp%u_%s.stream.bin",
             gSessionDir, s->connId, fd, s->localPort, s->remotePort, tx ? "TX" : "RX");
    WriteBinaryFile(path, data, len, YES);
}

static void WriteFrameFiles(FDState *s, int fd, BOOL tx, const unsigned char *frame, size_t frameLen,
                            uint16_t msgId, uint32_t seq, uint32_t bodyLen) {
    if (!s || !frame || frameLen < 10 || !gSessionDir[0]) return;
    unsigned long long n = ++gFrameSeq;
    const char *dir = tx ? "TX" : "RX";

    char frameRel[256];
    char bodyRel[256];
    snprintf(frameRel, sizeof(frameRel),
             "frames/%06llu_%s_msg%u_seq%u_body%u.frame.bin",
             n, dir, (unsigned)msgId, (unsigned)seq, (unsigned)bodyLen);
    snprintf(bodyRel, sizeof(bodyRel),
             "bodies/%06llu_%s_msg%u_seq%u_body%u.body.bin",
             n, dir, (unsigned)msgId, (unsigned)seq, (unsigned)bodyLen);

    char framePath[PATH_MAX];
    char bodyPath[PATH_MAX];
    snprintf(framePath, sizeof(framePath), "%s/%s", gSessionDir, frameRel);
    snprintf(bodyPath, sizeof(bodyPath), "%s/%s", gSessionDir, bodyRel);

    WriteBinaryFile(framePath, frame, frameLen, NO);
    if (bodyLen) WriteBinaryFile(bodyPath, frame + 10, bodyLen, NO);

    if (tx) {
        gTxFrames++;
        gTxBytes += frameLen;
    } else {
        gRxFrames++;
        gRxBytes += frameLen;
    }

    AppendManifestFmt("FRAME\t%llu\t%.6f\t%s\tconn=%llu\tfd=%d\tport=%u\tmsg=%u\tseq=%u\tbody=%u\tframe=%lu\t%s\t%s",
                      n, NowSeconds(), dir, s->connId, fd, s->remotePort,
                      (unsigned)msgId, (unsigned)seq, (unsigned)bodyLen,
                      (unsigned long)frameLen, frameRel, bodyLen ? bodyRel : "-");

    if (msgId != 1001) {
        @autoreleasepool {
            PushUIEvent([NSString stringWithFormat:@"%@ msg=%u seq=%u body=%u conn=%llu",
                         tx ? @"TX" : @"RX", (unsigned)msgId, (unsigned)seq,
                         (unsigned)bodyLen, s->connId]);
        }
    }
}

static void ParseFrames(FDState *s, int fd, BOOL tx) {
    StreamBuffer *b = tx ? &s->tx : &s->rx;
    while (b->len >= 10) {
        uint32_t bodyLen = ReadBE32(b->data);
        if (bodyLen > MAX_BODY_LEN) {
            AppendManifestFmt("PARSE_ERROR\tconn=%llu\tfd=%d\tdir=%s\tbody_len=%u\tbuffer=%lu\taction=reset-parser-buffer",
                              s->connId, fd, tx ? "TX" : "RX", (unsigned)bodyLen,
                              (unsigned long)b->len);
            b->len = 0;
            return;
        }
        size_t total = 10ULL + (size_t)bodyLen;
        if (b->len < total) return;

        uint16_t msgId = ReadBE16(b->data + 4);
        uint32_t seq = ReadBE32(b->data + 6);
        WriteFrameFiles(s, fd, tx, b->data, total, msgId, seq, bodyLen);

        size_t remain = b->len - total;
        if (remain) memmove(b->data, b->data + total, remain);
        b->len = remain;
    }
}

static void CaptureBytes(BOOL tx, int fd, uint16_t remotePort, uint16_t localPort,
                         const void *data, size_t len, const char *api) {
    if (!data || !len) return;
    pthread_mutex_lock(&gCaptureLock);

    FDState *s = StateForFD(fd, remotePort, localPort);
    if (!s) {
        pthread_mutex_unlock(&gCaptureLock);
        return;
    }

    WriteStreamChunk(s, fd, tx, data, len);

    StreamBuffer *b = tx ? &s->tx : &s->rx;
    if (b->len + len > MAX_BUFFER_LEN || !EnsureCapacity(b, b->len + len)) {
        AppendManifestFmt("BUFFER_ERROR\tconn=%llu\tfd=%d\tdir=%s\tapi=%s\tbuffer=%lu\tappend=%lu\taction=reset-parser-buffer",
                          s->connId, fd, tx ? "TX" : "RX", api ? api : "?",
                          (unsigned long)b->len, (unsigned long)len);
        b->len = 0;
        pthread_mutex_unlock(&gCaptureLock);
        return;
    }

    memcpy(b->data + b->len, data, len);
    b->len += len;
    ParseFrames(s, fd, tx);

    pthread_mutex_unlock(&gCaptureLock);
}

static ssize_t HookSend(int fd, const void *buf, size_t len, int flags) {
    if (!gOrigSend) { errno = ENOSYS; return -1; }
    if (gInsideHook) return gOrigSend(fd, buf, len, flags);
    gInsideHook++;
    ssize_t r = gOrigSend(fd, buf, len, flags);
    int saved = errno;
    if (r > 0) {
        uint16_t remotePort = 0, localPort = 0;
        if (TargetForFD(fd, &remotePort, &localPort)) {
            CaptureBytes(YES, fd, remotePort, localPort, buf, (size_t)r, "send");
        }
    }
    gInsideHook--;
    errno = saved;
    return r;
}

static ssize_t HookRecv(int fd, void *buf, size_t len, int flags) {
    if (!gOrigRecv) { errno = ENOSYS; return -1; }
    if (gInsideHook) return gOrigRecv(fd, buf, len, flags);
    gInsideHook++;
    ssize_t r = gOrigRecv(fd, buf, len, flags);
    int saved = errno;
    if (r > 0) {
        uint16_t remotePort = 0, localPort = 0;
        if (TargetForFD(fd, &remotePort, &localPort)) {
            CaptureBytes(NO, fd, remotePort, localPort, buf, (size_t)r, "recv");
        }
    }
    gInsideHook--;
    errno = saved;
    return r;
}

static ssize_t HookSendTo(int fd, const void *buf, size_t len, int flags,
                          const struct sockaddr *to, socklen_t tolen) {
    if (!gOrigSendTo) { errno = ENOSYS; return -1; }
    if (gInsideHook) return gOrigSendTo(fd, buf, len, flags, to, tolen);
    gInsideHook++;
    ssize_t r = gOrigSendTo(fd, buf, len, flags, to, tolen);
    int saved = errno;
    if (r > 0) {
        uint16_t remotePort = 0, localPort = 0;
        BOOL target = NO;
        char ip[INET_ADDRSTRLEN] = {0};
        if (DecodeSockaddr(to, tolen, ip, sizeof(ip), &remotePort)) {
            target = strcmp(ip, TARGET_IP) == 0 && IsTargetPort(remotePort);
            if (target) {
                struct sockaddr_storage local;
                socklen_t localLen = sizeof(local);
                memset(&local, 0, sizeof(local));
                if (getsockname(fd, (struct sockaddr *)&local, &localLen) == 0 && local.ss_family == AF_INET) {
                    localPort = ntohs(((const struct sockaddr_in *)&local)->sin_port);
                }
            }
        }
        if (!target) target = TargetForFD(fd, &remotePort, &localPort);
        if (target) CaptureBytes(YES, fd, remotePort, localPort, buf, (size_t)r, "sendto");
    }
    gInsideHook--;
    errno = saved;
    return r;
}

static ssize_t HookRecvFrom(int fd, void *buf, size_t len, int flags,
                            struct sockaddr *from, socklen_t *fromlen) {
    if (!gOrigRecvFrom) { errno = ENOSYS; return -1; }
    if (gInsideHook) return gOrigRecvFrom(fd, buf, len, flags, from, fromlen);
    gInsideHook++;
    ssize_t r = gOrigRecvFrom(fd, buf, len, flags, from, fromlen);
    int saved = errno;
    if (r > 0) {
        uint16_t remotePort = 0, localPort = 0;
        BOOL target = NO;
        char ip[INET_ADDRSTRLEN] = {0};
        if (from && fromlen && DecodeSockaddr(from, *fromlen, ip, sizeof(ip), &remotePort)) {
            target = strcmp(ip, TARGET_IP) == 0 && IsTargetPort(remotePort);
        }
        if (!target) target = TargetForFD(fd, &remotePort, &localPort);
        if (target) CaptureBytes(NO, fd, remotePort, localPort, buf, (size_t)r, "recvfrom");
    }
    gInsideHook--;
    errno = saved;
    return r;
}

static void InstallTCPHooks(void) {
    if (gHooksInstalled) return;
    gOrigSend = (SendFn)dlsym(RTLD_DEFAULT, "send");
    gOrigRecv = (RecvFn)dlsym(RTLD_DEFAULT, "recv");
    gOrigSendTo = (SendToFn)dlsym(RTLD_DEFAULT, "sendto");
    gOrigRecvFrom = (RecvFromFn)dlsym(RTLD_DEFAULT, "recvfrom");

    struct rebinding binds[] = {
        {"send", (void *)HookSend, (void **)&gOrigSend},
        {"recv", (void *)HookRecv, (void **)&gOrigRecv},
        {"sendto", (void *)HookSendTo, (void **)&gOrigSendTo},
        {"recvfrom", (void *)HookRecvFrom, (void **)&gOrigRecvFrom},
    };
    int rc = rebind_symbols(binds, sizeof(binds) / sizeof(binds[0]));
    gHooksInstalled = (rc == 0 && gOrigSend && gOrigRecv);
    gStartTime = NowSeconds();
    AppendManifestFmt("HOOKS\trc=%d\tinstalled=%s\ttarget=%s:7000-7999\tmode=read-only-full-frame",
                      rc, gHooksInstalled ? "YES" : "NO", TARGET_IP);
    @autoreleasepool {
        PushUIEvent([NSString stringWithFormat:@"HOOKS rc=%d installed=%@",
                     rc, gHooksInstalled ? @"YES" : @"NO"]);
    }
}

static void SetupSessionDirectory(void) {
    @autoreleasepool {
        NSString *home = NSHomeDirectory();
        if (!home.length) return;

        NSDateFormatter *fmt = [[[NSDateFormatter alloc] init] autorelease];
        fmt.dateFormat = @"yyyyMMdd-HHmmss";
        NSString *stamp = [fmt stringFromDate:[NSDate date]];
        NSString *base = [home stringByAppendingPathComponent:@"Documents/LoginTCPFull_v8"];
        NSString *session = [base stringByAppendingPathComponent:[NSString stringWithFormat:@"Session_%@", stamp]];
        NSString *frames = [session stringByAppendingPathComponent:@"frames"];
        NSString *bodies = [session stringByAppendingPathComponent:@"bodies"];
        NSString *streams = [session stringByAppendingPathComponent:@"streams"];

        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:frames withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtPath:bodies withIntermediateDirectories:YES attributes:nil error:nil];
        [fm createDirectoryAtPath:streams withIntermediateDirectories:YES attributes:nil error:nil];

        snprintf(gSessionDir, sizeof(gSessionDir), "%s", session.fileSystemRepresentation);
        snprintf(gManifestPath, sizeof(gManifestPath), "%s/manifest.tsv", gSessionDir);

        FILE *f = fopen(gManifestPath, "w");
        if (f) {
            const char *header = "TYPE\tFRAME_NO/TAG\tTIME/DETAILS\tDIRECTION...\n";
            fwrite(header, 1, strlen(header), f);
            fclose(f);
        }

        NSString *readmePath = [session stringByAppendingPathComponent:@"README.txt"];
        NSString *readme = @"LoginTCPFullFrame v8\n"
                            @"Target: 118.145.146.208:7000-7999\n"
                            @"Read-only hooks: send/recv/sendto/recvfrom\n"
                            @"700x frame: [body_len:4 BE][msg_id:2 BE][seq:4 BE][body]\n"
                            @"frames/: exact full frame bytes\n"
                            @"bodies/: exact protobuf body bytes\n"
                            @"streams/: raw successful TCP byte stream chunks concatenated per connection/direction\n"
                            @"manifest.tsv: frame index and metadata\n";
        [readme writeToFile:readmePath atomically:YES encoding:NSUTF8StringEncoding error:nil];

        AppendManifestFmt("SESSION\t%s\ttarget=%s:7000-7999\tmax_body=%u",
                          stamp.UTF8String, TARGET_IP, (unsigned)MAX_BODY_LEN);
    }
}

@interface LoginTCPFullFrameTarget : NSObject
+ (instancetype)shared;
- (void)tick:(NSTimer *)timer;
- (void)tap:(id)sender;
- (void)panButton:(UIPanGestureRecognizer *)g;
- (void)panPanel:(UIPanGestureRecognizer *)g;
@end

@implementation LoginTCPFullFrameTarget
+ (instancetype)shared {
    static LoginTCPFullFrameTarget *s;
    if (!s) s = [[self alloc] init];
    return s;
}

- (UIWindow *)currentWindow {
    UIApplication *app = [UIApplication sharedApplication];
    UIWindow *w = app.keyWindow;
    if (w) return w;
    return app.windows.lastObject;
}

- (void)makeUI:(UIWindow *)w {
    if (gUIReady || !w) return;
    gWindow = w;
    gEvents = [[NSMutableArray alloc] init];

    gFloatButton = [UIButton buttonWithType:UIButtonTypeCustom];
    gFloatButton.frame = CGRectMake(18, 165, 62, 52);
    gFloatButton.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.94];
    gFloatButton.layer.cornerRadius = 26;
    [gFloatButton setTitle:@"FF8" forState:UIControlStateNormal];
    gFloatButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [gFloatButton addTarget:self action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *bp = [[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panButton:)] autorelease];
    [gFloatButton addGestureRecognizer:bp];
    [w addSubview:gFloatButton];

    gPanel = [[[UIView alloc] initWithFrame:CGRectMake(44, 76, 380, 410)] autorelease];
    gPanel.backgroundColor = [UIColor colorWithWhite:0.04 alpha:0.97];
    gPanel.layer.cornerRadius = 14;
    UIPanGestureRecognizer *pp = [[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panPanel:)] autorelease];
    pp.cancelsTouchesInView = NO;
    [gPanel addGestureRecognizer:pp];

    UILabel *title = [[[UILabel alloc] initWithFrame:CGRectMake(12, 8, 356, 48)] autorelease];
    title.textColor = [UIColor whiteColor];
    title.numberOfLines = 2;
    title.font = [UIFont boldSystemFontOfSize:16];
    title.text = @"Login TCP FullFrame v8\n700x full frame + raw stream / read-only";
    [gPanel addSubview:title];

    gStatusLabel = [[[UILabel alloc] initWithFrame:CGRectMake(12, 58, 356, 44)] autorelease];
    gStatusLabel.textColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    gStatusLabel.numberOfLines = 2;
    gStatusLabel.font = [UIFont systemFontOfSize:11];
    [gPanel addSubview:gStatusLabel];

    gTextView = [[[UITextView alloc] initWithFrame:CGRectMake(10, 106, 360, 294)] autorelease];
    gTextView.backgroundColor = [UIColor colorWithWhite:0.015 alpha:1.0];
    gTextView.textColor = [UIColor colorWithWhite:0.92 alpha:1.0];
    if (@available(iOS 13.0, *)) gTextView.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    else gTextView.font = [UIFont fontWithName:@"Menlo" size:10] ?: [UIFont systemFontOfSize:10];
    gTextView.editable = NO;
    gTextView.selectable = YES;
    [gPanel addSubview:gTextView];

    gPanel.hidden = YES;
    [w addSubview:gPanel];
    gUIReady = YES;
    gHookDelayTicks = 2;
    PushUIEvent(@"UI READY - hooks install after 2 ticks");
    RefreshUI();
}

- (void)tick:(NSTimer *)timer {
    (void)timer;
    UIWindow *w = [self currentWindow];
    if (!w) return;
    if (!gUIReady) [self makeUI:w];
    if (gUIReady && gWindow != w) {
        [w addSubview:gPanel];
        [w addSubview:gFloatButton];
        gWindow = w;
    }
    if (gUIReady && !gHooksInstalled) {
        if (gHookDelayTicks > 0) gHookDelayTicks--;
        else InstallTCPHooks();
    }
    if (gUIReady) {
        [w bringSubviewToFront:gPanel];
        [w bringSubviewToFront:gFloatButton];
    }
}

- (void)tap:(id)sender {
    (void)sender;
    gPanel.hidden = !gPanel.hidden;
    RefreshUI();
}

- (void)panButton:(UIPanGestureRecognizer *)g {
    if (!gWindow) return;
    CGPoint tr = [g translationInView:gWindow];
    CGPoint c = gFloatButton.center;
    c.x += tr.x;
    c.y += tr.y;
    CGRect b = gWindow.bounds;
    c.x = MAX(31, MIN(b.size.width - 31, c.x));
    c.y = MAX(26, MIN(b.size.height - 26, c.y));
    gFloatButton.center = c;
    [g setTranslation:CGPointZero inView:gWindow];
}

- (void)panPanel:(UIPanGestureRecognizer *)g {
    if (!gWindow) return;
    CGPoint tr = [g translationInView:gWindow];
    CGPoint c = gPanel.center;
    c.x += tr.x;
    c.y += tr.y;
    gPanel.center = c;
    [g setTranslation:CGPointZero inView:gWindow];
}
@end

__attribute__((constructor)) static void LoginTCPFullFrameInit(void) {
    @autoreleasepool {
        SetupSessionDirectory();
        AppendManifestFmt("LOAD\t%.6f\twaiting-for-UI-before-hooks", NowSeconds());
        dispatch_async(dispatch_get_main_queue(), ^{
            LoginTCPFullFrameTarget *t = [LoginTCPFullFrameTarget shared];
            [NSTimer scheduledTimerWithTimeInterval:0.5 target:t selector:@selector(tick:) userInfo:nil repeats:YES];
        });
    }
}
