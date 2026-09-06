#import "ZNDeveloperGate.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/socket.h>
#import <sys/select.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <errno.h>

static const NSTimeInterval kZNLocalTicketV2ListenTimeout = 12.0;
static const NSTimeInterval kZNLocalTicketV2MaxClockSkew = 3.0;
static const uint32_t kZNLocalTicketV2MaxPayload = 4096;

static BOOL gZNV2HasState = NO;
static BOOL gZNV2Awaiting = NO;
static NSUInteger gZNV2Generation = 0;
static int gZNV2ListenFD = -1;
static uint16_t gZNV2ListenPort = 0;
static UIBackgroundTaskIdentifier gZNV2BackgroundTask = UIBackgroundTaskInvalid;
static NSString *gZNV2Session = @"";
static NSString *gZNV2Nonce = @"";
static NSString *gZNV2Bundle = @"";
static NSString *gZNV2State = @"Idle";
static NSString *gZNV2LastError = @"";
static NSUInteger gZNV2Bytes = 0;

@interface ZNDeveloperGate (LocalTicketV2PrivateAccess)
- (BOOL)loadMarker;
- (BOOL)tryHostBridge;
- (BOOL)acceptCandidate:(NSString *)candidate source:(ZNIdentitySource)source;
@end

static NSString *ZNLocalTicketV2Errno(NSString *prefix) {
    int value = errno;
    const char *text = strerror(value);
    return [NSString stringWithFormat:@"%@ errno=%d (%s)", prefix, value, text ?: "unknown"];
}

static NSString *ZNLocalTicketV2Nonce(void) {
    NSString *a = NSUUID.UUID.UUIDString.lowercaseString;
    NSString *b = NSUUID.UUID.UUIDString.lowercaseString;
    return [[a stringByAppendingString:b] stringByReplacingOccurrencesOfString:@"-" withString:@""];
}

static void ZNLocalTicketV2EndBackgroundTask(void) {
    if (gZNV2BackgroundTask == UIBackgroundTaskInvalid) return;
    UIBackgroundTaskIdentifier task = gZNV2BackgroundTask;
    gZNV2BackgroundTask = UIBackgroundTaskInvalid;
    [UIApplication.sharedApplication endBackgroundTask:task];
}

static BOOL ZNLocalTicketV2RecvExact(int fd, void *buffer, size_t length, NSString **errorText) {
    uint8_t *cursor = (uint8_t *)buffer;
    size_t done = 0;
    while (done < length) {
        ssize_t n = recv(fd, cursor + done, length - done, 0);
        if (n > 0) {
            done += (size_t)n;
            continue;
        }
        if (n < 0 && errno == EINTR) continue;
        if (errorText) *errorText = n == 0 ? @"PEER_CLOSED" : ZNLocalTicketV2Errno(@"RECV_FAILED");
        return NO;
    }
    return YES;
}

static int ZNLocalTicketV2CreateListener(uint16_t *portOut, NSString **errorText) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        if (errorText) *errorText = ZNLocalTicketV2Errno(@"LISTEN_SOCKET_FAILED");
        return -1;
    }

    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
#ifdef SO_NOSIGPIPE
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
#endif

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
#if defined(__APPLE__)
    address.sin_len = sizeof(address);
#endif
    address.sin_family = AF_INET;
    address.sin_port = htons(0);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
        if (errorText) *errorText = ZNLocalTicketV2Errno(@"LISTEN_BIND_FAILED");
        close(fd);
        return -1;
    }
    if (listen(fd, 1) != 0) {
        if (errorText) *errorText = ZNLocalTicketV2Errno(@"LISTEN_START_FAILED");
        close(fd);
        return -1;
    }

    socklen_t length = sizeof(address);
    if (getsockname(fd, (struct sockaddr *)&address, &length) != 0) {
        if (errorText) *errorText = ZNLocalTicketV2Errno(@"LISTEN_PORT_FAILED");
        close(fd);
        return -1;
    }
    if (portOut) *portOut = ntohs(address.sin_port);
    return fd;
}

static void ZNLocalTicketV2Swap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

@interface ZNDeveloperGate (LocalTicketV2)
- (void)znv2_requestZonoeValidation;
- (void)znv2_applicationDidBecomeActive:(NSNotification *)notification;
- (NSString *)znv2_lastError;
- (BOOL)znv2_awaitingZonoe;
- (NSString *)znv2_diagnosticReport;
@end

@implementation ZNDeveloperGate (LocalTicketV2)

- (void)znv2_finishFailure:(NSString *)error generation:(NSUInteger)generation {
    if (generation != gZNV2Generation) return;
    gZNV2Awaiting = NO;
    gZNV2ListenFD = -1;
    gZNV2ListenPort = 0;
    gZNV2State = @"Failed";
    gZNV2LastError = error.length ? error : @"LOCAL_TICKET_V2_FAILED";
    ZNLocalTicketV2EndBackgroundTask();
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"LocalTicketV2 failed: %@", gZNV2LastError]];
}

- (void)znv2_acceptWorkerFD:(int)listenFD
                 generation:(NSUInteger)generation
                    session:(NSString *)session
                      nonce:(NSString *)nonce
                     bundle:(NSString *)bundle {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        fd_set readSet;
        FD_ZERO(&readSet);
        FD_SET(listenFD, &readSet);
        struct timeval timeout;
        timeout.tv_sec = (int)kZNLocalTicketV2ListenTimeout;
        timeout.tv_usec = 0;

        int ready = select(listenFD + 1, &readSet, NULL, NULL, &timeout);
        if (ready <= 0) {
            NSString *error = ready == 0 ? @"ACCEPT_TIMEOUT" : ZNLocalTicketV2Errno(@"ACCEPT_SELECT_FAILED");
            close(listenFD);
            dispatch_async(dispatch_get_main_queue(), ^{ [self znv2_finishFailure:error generation:generation]; });
            return;
        }

        struct sockaddr_in peer;
        socklen_t peerLength = sizeof(peer);
        int client = accept(listenFD, (struct sockaddr *)&peer, &peerLength);
        close(listenFD);
        if (client < 0) {
            NSString *error = ZNLocalTicketV2Errno(@"ACCEPT_FAILED");
            dispatch_async(dispatch_get_main_queue(), ^{ [self znv2_finishFailure:error generation:generation]; });
            return;
        }

        struct timeval ioTimeout;
        ioTimeout.tv_sec = 4;
        ioTimeout.tv_usec = 0;
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &ioTimeout, sizeof(ioTimeout));

        NSString *readError = nil;
        uint32_t networkLength = 0;
        if (!ZNLocalTicketV2RecvExact(client, &networkLength, sizeof(networkLength), &readError)) {
            close(client);
            dispatch_async(dispatch_get_main_queue(), ^{ [self znv2_finishFailure:readError generation:generation]; });
            return;
        }

        uint32_t payloadLength = ntohl(networkLength);
        if (payloadLength == 0 || payloadLength > kZNLocalTicketV2MaxPayload) {
            close(client);
            dispatch_async(dispatch_get_main_queue(), ^{ [self znv2_finishFailure:@"FRAME_TOO_LARGE_OR_EMPTY" generation:generation]; });
            return;
        }

        NSMutableData *payload = [NSMutableData dataWithLength:payloadLength];
        if (!ZNLocalTicketV2RecvExact(client, payload.mutableBytes, payloadLength, &readError)) {
            close(client);
            dispatch_async(dispatch_get_main_queue(), ^{ [self znv2_finishFailure:readError generation:generation]; });
            return;
        }
        close(client);

        NSError *jsonError = nil;
        id object = [NSJSONSerialization JSONObjectWithData:payload options:0 error:&jsonError];
        NSDictionary *ticket = [object isKindOfClass:NSDictionary.class] ? object : nil;
        if (!ticket) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self znv2_finishFailure:@"JSON_INVALID" generation:generation]; });
            return;
        }

        NSInteger version = [ticket[@"version"] respondsToSelector:@selector(integerValue)] ? [ticket[@"version"] integerValue] : 0;
        NSString *ticketSession = [ticket[@"session"] isKindOfClass:NSString.class] ? ticket[@"session"] : @"";
        NSString *ticketNonce = [ticket[@"nonce"] isKindOfClass:NSString.class] ? ticket[@"nonce"] : @"";
        NSString *ticketBundle = [ticket[@"bundle"] isKindOfClass:NSString.class] ? ticket[@"bundle"] : @"";
        NSString *udid = [ticket[@"udid"] isKindOfClass:NSString.class] ? ticket[@"udid"] : @"";
        NSTimeInterval issuedAt = [ticket[@"issuedAt"] respondsToSelector:@selector(doubleValue)] ? [ticket[@"issuedAt"] doubleValue] : 0;
        NSTimeInterval expiresAt = [ticket[@"expiresAt"] respondsToSelector:@selector(doubleValue)] ? [ticket[@"expiresAt"] doubleValue] : 0;
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];

        NSString *envelopeError = nil;
        if (version != 2) envelopeError = @"PROTOCOL_MISMATCH";
        else if (![ticketSession isEqualToString:session]) envelopeError = @"SESSION_MISMATCH";
        else if (![ticketNonce isEqualToString:nonce]) envelopeError = @"NONCE_MISMATCH";
        else if (![ticketBundle isEqualToString:bundle]) envelopeError = @"BUNDLE_MISMATCH";
        else if (issuedAt <= 0 || issuedAt > now + kZNLocalTicketV2MaxClockSkew) envelopeError = @"ISSUED_AT_INVALID";
        else if (expiresAt < now || expiresAt < issuedAt || expiresAt - issuedAt > 30.0) envelopeError = @"TICKET_EXPIRED_OR_INVALID";
        else if (!udid.length) envelopeError = @"UDID_EMPTY";

        if (envelopeError) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self znv2_finishFailure:envelopeError generation:generation]; });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != gZNV2Generation || !gZNV2Awaiting) return;
            gZNV2Bytes = payload.length + sizeof(uint32_t);
            gZNV2ListenFD = -1;
            gZNV2ListenPort = 0;
            if (![self acceptCandidate:udid source:ZNIdentitySourceZonoeLocalTicket]) {
                [self znv2_finishFailure:@"UDID_MISMATCH" generation:generation];
                return;
            }
            gZNV2Awaiting = NO;
            gZNV2State = @"Authorized";
            gZNV2LastError = @"";
            ZNLocalTicketV2EndBackgroundTask();
            [[ZNRuntimeLogger sharedLogger] log:@"Zonoe LocalTicketV2 accepted"];
        });
    });
}

- (void)znv2_requestZonoeValidation {
    [self refresh];
    if (![self loadMarker]) {
        gZNV2HasState = YES;
        gZNV2State = @"MarkerInvalid";
        gZNV2LastError = [self znv2_lastError];
        return;
    }
    if ([self tryHostBridge]) {
        gZNV2HasState = NO;
        return;
    }
    if (gZNV2Awaiting) {
        gZNV2LastError = @"LOCAL_TICKET_V2_ALREADY_PENDING";
        return;
    }

    NSString *listenerError = nil;
    uint16_t port = 0;
    int listenFD = ZNLocalTicketV2CreateListener(&port, &listenerError);
    if (listenFD < 0 || port == 0) {
        gZNV2HasState = YES;
        gZNV2State = @"ListenFailed";
        gZNV2LastError = listenerError.length ? listenerError : @"LISTEN_FAILED";
        [[ZNRuntimeLogger sharedLogger] log:gZNV2LastError];
        return;
    }

    gZNV2Generation += 1;
    NSUInteger generation = gZNV2Generation;
    gZNV2Session = NSUUID.UUID.UUIDString.lowercaseString;
    gZNV2Nonce = ZNLocalTicketV2Nonce();
    gZNV2Bundle = NSBundle.mainBundle.bundleIdentifier ?: @"unknown";
    gZNV2ListenFD = listenFD;
    gZNV2ListenPort = port;
    gZNV2Bytes = 0;
    gZNV2HasState = YES;
    gZNV2Awaiting = YES;
    gZNV2State = @"Listening";
    gZNV2LastError = @"";

    if (gZNV2BackgroundTask == UIBackgroundTaskInvalid) {
        gZNV2BackgroundTask = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"zonoe.localticket.v2" expirationHandler:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation == gZNV2Generation && gZNV2Awaiting) {
                    gZNV2State = @"BackgroundExpired";
                    gZNV2LastError = @"BACKGROUND_TASK_EXPIRED";
                }
                ZNLocalTicketV2EndBackgroundTask();
            });
        }];
    }

    [self znv2_acceptWorkerFD:listenFD generation:generation session:gZNV2Session nonce:gZNV2Nonce bundle:gZNV2Bundle];

    NSURLComponents *request = [NSURLComponents componentsWithString:@"zonoe://device-auth"];
    request.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"protocol" value:@"2"],
        [NSURLQueryItem queryItemWithName:@"session" value:gZNV2Session],
        [NSURLQueryItem queryItemWithName:@"nonce" value:gZNV2Nonce],
        [NSURLQueryItem queryItemWithName:@"bundle" value:gZNV2Bundle],
        [NSURLQueryItem queryItemWithName:@"port" value:[NSString stringWithFormat:@"%u", port]]
    ];
    NSURL *url = request.URL;
    if (!url) {
        close(listenFD);
        [self znv2_finishFailure:@"OPEN_URL_BUILD_FAILED" generation:generation];
        return;
    }

    gZNV2State = @"OpeningZonoe";
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"Open zonoe LocalTicketV2 listener=127.0.0.1:%u", port]];
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:^(BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != gZNV2Generation || !gZNV2Awaiting) return;
            if (!success) {
                [self znv2_finishFailure:@"OPEN_ZONOE_FAILED" generation:generation];
            } else {
                gZNV2State = @"WaitingForPush";
            }
        });
    }];
}

- (void)znv2_applicationDidBecomeActive:(NSNotification *)notification {
    [self znv2_applicationDidBecomeActive:notification];
    if (gZNV2Awaiting) gZNV2State = @"ReturnedWaitingForPush";
}

- (NSString *)znv2_lastError {
    if (gZNV2HasState && (gZNV2Awaiting || gZNV2LastError.length)) return gZNV2LastError ?: @"";
    return [self znv2_lastError];
}

- (BOOL)znv2_awaitingZonoe {
    return gZNV2Awaiting || [self znv2_awaitingZonoe];
}

- (NSString *)znv2_diagnosticReport {
    NSString *base = [self znv2_diagnosticReport];
    if (!gZNV2HasState) return base;
    NSString *session = gZNV2Session.length >= 8 ? [NSString stringWithFormat:@"%@****", [gZNV2Session substringToIndex:4]] : @"";
    NSString *nonce = gZNV2Nonce.length >= 8 ? [NSString stringWithFormat:@"%@****", [gZNV2Nonce substringToIndex:4]] : @"";
    return [base stringByAppendingFormat:@"LocalTicket.Protocol: 2\nLocalTicket.State: %@\nLocalTicket.Port: %u\nLocalTicket.Session: %@\nLocalTicket.Nonce: %@\nLocalTicket.Bytes: %lu\nLocalTicket.Error: %@\n",
            gZNV2State ?: @"Idle", gZNV2ListenPort, session, nonce, (unsigned long)gZNV2Bytes, gZNV2LastError.length ? gZNV2LastError : @"None"];
}

@end

__attribute__((constructor(102))) static void ZNInstallLocalTicketV2(void) {
    @autoreleasepool {
        Class cls = ZNDeveloperGate.class;
        ZNLocalTicketV2Swap(cls, @selector(requestZonoeValidation), @selector(znv2_requestZonoeValidation));
        ZNLocalTicketV2Swap(cls, @selector(applicationDidBecomeActive:), @selector(znv2_applicationDidBecomeActive:));
        ZNLocalTicketV2Swap(cls, @selector(lastError), @selector(znv2_lastError));
        ZNLocalTicketV2Swap(cls, @selector(awaitingZonoe), @selector(znv2_awaitingZonoe));
        ZNLocalTicketV2Swap(cls, @selector(diagnosticReport), @selector(znv2_diagnosticReport));
        [[ZNRuntimeLogger sharedLogger] log:@"LocalTicketV2 transport installed"];
    }
}
