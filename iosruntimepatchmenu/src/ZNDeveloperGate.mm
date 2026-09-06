#import "ZNDeveloperGate.h"
#import "ZNPatchCore.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <sys/socket.h>
#import <arpa/inet.h>
#import <unistd.h>

typedef const char *(*ZNHostGetUDIDFn)(void);
typedef bool (*ZNHostIsAuthorizedFn)(void);

static const uint16_t kZNLocalTicketPort = 14302;
static const NSTimeInterval kZNTicketMaxClockSkew = 3.0;

static NSData *ZNReadLocalTicket(NSString *path, NSString **errorText) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) { if (errorText) *errorText = @"socket failed"; return nil; }

    struct timeval tv; tv.tv_sec = 1; tv.tv_usec = 0;
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    struct sockaddr_in addr; memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(kZNLocalTicketPort);
    inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);
    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        close(fd); if (errorText) *errorText = @"local bridge not reachable"; return nil;
    }

    NSString *request = [NSString stringWithFormat:@"GET %@ HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n", path];
    NSData *requestData = [request dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *bytes = (const uint8_t *)requestData.bytes;
    size_t sent = 0;
    while (sent < requestData.length) {
        ssize_t n = send(fd, bytes + sent, requestData.length - sent, 0);
        if (n <= 0) { close(fd); if (errorText) *errorText = @"local bridge send failed"; return nil; }
        sent += (size_t)n;
    }

    NSMutableData *response = [NSMutableData data];
    uint8_t buffer[4096];
    while (response.length < 65536) {
        ssize_t n = recv(fd, buffer, sizeof(buffer), 0);
        if (n <= 0) break;
        [response appendBytes:buffer length:(NSUInteger)n];
    }
    close(fd);
    if (!response.length) { if (errorText) *errorText = @"empty local bridge response"; return nil; }

    NSData *separator = [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    NSRange split = [response rangeOfData:separator options:0 range:NSMakeRange(0, response.length)];
    if (split.location == NSNotFound) { if (errorText) *errorText = @"invalid HTTP response"; return nil; }
    NSData *headerData = [response subdataWithRange:NSMakeRange(0, split.location)];
    NSString *headers = [[NSString alloc] initWithData:headerData encoding:NSUTF8StringEncoding] ?: @"";
    if (![headers hasPrefix:@"HTTP/1.1 200"] && ![headers hasPrefix:@"HTTP/1.0 200"]) {
        if (errorText) *errorText = @"ticket not ready";
        return nil;
    }
    NSUInteger bodyOffset = NSMaxRange(split);
    return [response subdataWithRange:NSMakeRange(bodyOffset, response.length - bodyOffset)];
}

@implementation ZNDeveloperGate {
    BOOL _markerPresent;
    BOOL _authorized;
    BOOL _hostBridgeAvailable;
    NSString *_markerPath;
    NSString *_authorizedUDID;
    NSString *_observedUDID;
    ZNIdentitySource _identitySource;
    NSString *_lastError;
    BOOL _awaitingZonoe;
    NSString *_submittedHostUDID;
    BOOL _submittedHostAuthorized;
    NSString *_pendingSession;
    NSString *_pendingNonce;
    NSString *_pendingBundle;
    NSUInteger _ticketGeneration;
}

+ (instancetype)sharedGate {
    static ZNDeveloperGate *s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ s = [ZNDeveloperGate new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _markerPath = @"";
    _authorizedUDID = @"";
    _observedUDID = @"";
    _lastError = @"Not validated";
    _identitySource = ZNIdentitySourceNone;
    _pendingSession = @"";
    _pendingNonce = @"";
    _pendingBundle = @"";
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [self refresh];
    return self;
}

- (BOOL)markerPresent { return _markerPresent; }
- (BOOL)authorized { return _authorized; }
- (BOOL)hostBridgeAvailable { return _hostBridgeAvailable; }
- (NSString *)markerPath { return _markerPath ?: @""; }
- (NSString *)authorizedUDID { return _authorizedUDID ?: @""; }
- (NSString *)observedUDID { return _observedUDID ?: @""; }
- (ZNIdentitySource)identitySource { return _identitySource; }
- (NSString *)lastError { return _lastError ?: @""; }
- (BOOL)awaitingZonoe { return _awaitingZonoe; }

- (NSString *)trimLine:(NSString *)line {
    return [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (BOOL)loadMarker {
    NSString *documents = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/1"];
    NSString *root = [NSHomeDirectory() stringByAppendingPathComponent:@"1"];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *path = [fm fileExistsAtPath:documents] ? documents : ([fm fileExistsAtPath:root] ? root : nil);
    _markerPresent = (path != nil);
    _markerPath = path ?: @"";
    _authorizedUDID = @"";
    if (!path) { _lastError = @"Developer marker file not found"; return NO; }

    NSError *error = nil;
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    if (!text) {
        _lastError = [NSString stringWithFormat:@"Marker read failed: %@", error.localizedDescription ?: @"unknown"];
        return NO;
    }
    if ([text hasPrefix:@"\uFEFF"]) text = [text substringFromIndex:1];
    text = [text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    text = [text stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    if (lines.count < 2 || ![[self trimLine:lines[0]] isEqualToString:@"g"]) {
        _lastError = @"Marker line 1 must be g";
        return NO;
    }
    NSString *udid = [self trimLine:lines[1]];
    if (!udid.length) { _lastError = @"Marker line 2 UDID is empty"; return NO; }
    _authorizedUDID = udid;
    return YES;
}

- (BOOL)acceptCandidate:(NSString *)candidate source:(ZNIdentitySource)source {
    if (!candidate.length || !_authorizedUDID.length) return NO;
    NSString *clean = [self trimLine:candidate];
    if (![clean isEqualToString:_authorizedUDID]) return NO;
    BOOL changed = !_authorized || _identitySource != source || ![_observedUDID isEqualToString:clean];
    _authorized = YES;
    _observedUDID = clean;
    _identitySource = source;
    _lastError = @"";
    if (changed) [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"Developer Gate authorized via %@", [self sourceDescription]]];
    return YES;
}

- (BOOL)tryHostBridge {
    if (_submittedHostAuthorized && _submittedHostUDID.length) {
        if ([self acceptCandidate:_submittedHostUDID source:ZNIdentitySourceSubmittedHost]) return YES;
    }
    ZNHostGetUDIDFn getUDID = (ZNHostGetUDIDFn)dlsym(RTLD_DEFAULT, "ZonoeHostGetUDID");
    ZNHostIsAuthorizedFn isAuthorized = (ZNHostIsAuthorizedFn)dlsym(RTLD_DEFAULT, "ZonoeHostIsAuthorized");
    _hostBridgeAvailable = (getUDID != NULL && isAuthorized != NULL);
    if (!_hostBridgeAvailable || !isAuthorized()) return NO;
    const char *value = getUDID();
    if (!value || !value[0]) return NO;
    NSString *udid = [NSString stringWithUTF8String:value];
    return [self acceptCandidate:udid source:ZNIdentitySourceHostDylib];
}

- (void)refresh {
    BOOL wasAuthorized = _authorized;
    NSString *previousUDID = [_observedUDID copy] ?: @"";
    ZNIdentitySource previousSource = _identitySource;
    _authorized = NO;
    _observedUDID = @"";
    _identitySource = ZNIdentitySourceNone;

    if (![self loadMarker]) {
        if (wasAuthorized) [[ZNRuntimeLogger sharedLogger] log:@"Developer Gate revoked: marker invalid or removed"];
        return;
    }
    if ([self tryHostBridge]) return;

    if (wasAuthorized && previousSource == ZNIdentitySourceZonoeLocalTicket && [previousUDID isEqualToString:_authorizedUDID]) {
        _authorized = YES;
        _observedUDID = previousUDID;
        _identitySource = previousSource;
        _lastError = @"";
        return;
    }

    if (_awaitingZonoe) _lastError = @"等待 zonoe 本地票据，返回游戏后自动验证";
    else _lastError = _hostBridgeAvailable ? @"Host dylib is not authorized yet" : @"等待 Host dylib 或 zonoe 本地票据验证";

    if (wasAuthorized) [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"Developer Gate no longer authorized (previous source=%ld)",(long)previousSource]];
}

- (NSString *)newNonce {
    NSString *a = NSUUID.UUID.UUIDString.lowercaseString;
    NSString *b = NSUUID.UUID.UUIDString.lowercaseString;
    return [[a stringByAppendingString:b] stringByReplacingOccurrencesOfString:@"-" withString:@""];
}

- (NSString *)ticketPath {
    NSURLComponents *c = [NSURLComponents new];
    c.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"session" value:_pendingSession],
        [NSURLQueryItem queryItemWithName:@"nonce" value:_pendingNonce],
        [NSURLQueryItem queryItemWithName:@"bundle" value:_pendingBundle]
    ];
    return [NSString stringWithFormat:@"/device-ticket?%@",c.percentEncodedQuery ?: @""];
}

- (void)fetchLocalTicketAttempt:(NSUInteger)attempt generation:(NSUInteger)generation {
    if (!_awaitingZonoe || generation != _ticketGeneration || !_pendingSession.length) return;
    NSString *path = [self ticketPath];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *transportError = nil;
        NSData *data = ZNReadLocalTicket(path, &transportError);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self->_awaitingZonoe || generation != self->_ticketGeneration) return;
            NSDictionary *ticket = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            NSString *session = [ticket[@"session"] isKindOfClass:NSString.class] ? ticket[@"session"] : @"";
            NSString *nonce = [ticket[@"nonce"] isKindOfClass:NSString.class] ? ticket[@"nonce"] : @"";
            NSString *bundle = [ticket[@"bundle"] isKindOfClass:NSString.class] ? ticket[@"bundle"] : @"";
            NSString *udid = [ticket[@"udid"] isKindOfClass:NSString.class] ? ticket[@"udid"] : @"";
            NSTimeInterval expiresAt = [ticket[@"expiresAt"] respondsToSelector:@selector(doubleValue)] ? [ticket[@"expiresAt"] doubleValue] : 0;
            BOOL envelopeOK = [session isEqualToString:self->_pendingSession] && [nonce isEqualToString:self->_pendingNonce] && [bundle isEqualToString:self->_pendingBundle] && expiresAt + kZNTicketMaxClockSkew >= NSDate.date.timeIntervalSince1970;
            if (envelopeOK && [self acceptCandidate:udid source:ZNIdentitySourceZonoeLocalTicket]) {
                self->_awaitingZonoe = NO;
                self->_pendingSession = @""; self->_pendingNonce = @""; self->_pendingBundle = @"";
                [[ZNRuntimeLogger sharedLogger] log:@"Zonoe local device ticket accepted"];
                return;
            }
            if (data && ticket && envelopeOK && udid.length) {
                self->_awaitingZonoe = NO;
                self->_lastError = @"zonoe 返回的 UDID 与 1 文件第二行不一致";
                [[ZNRuntimeLogger sharedLogger] log:self->_lastError];
                return;
            }
            if (attempt < 6) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self fetchLocalTicketAttempt:attempt+1 generation:generation];
                });
            } else {
                self->_awaitingZonoe = NO;
                self->_lastError = transportError.length ? [NSString stringWithFormat:@"本地票据获取失败：%@",transportError] : @"zonoe 本地票据无效或已过期";
                [[ZNRuntimeLogger sharedLogger] log:self->_lastError];
            }
        });
    });
}

- (void)applicationDidBecomeActive:(NSNotification *)note {
    (void)note;
    if (!_awaitingZonoe) return;
    NSUInteger generation = _ticketGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.20 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self fetchLocalTicketAttempt:0 generation:generation];
    });
}

- (void)requestZonoeValidation {
    [self refresh];
    if (![self loadMarker]) {
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"UDID validation not started: %@",self.lastError]];
        return;
    }
    if ([self tryHostBridge]) return;

    _authorized = NO;
    _observedUDID = @"";
    _identitySource = ZNIdentitySourceNone;
    _pendingSession = NSUUID.UUID.UUIDString.lowercaseString;
    _pendingNonce = [self newNonce];
    _pendingBundle = NSBundle.mainBundle.bundleIdentifier ?: @"unknown";
    _ticketGeneration += 1;
    _awaitingZonoe = YES;
    _lastError = @"正在打开 zonoe…";

    NSURLComponents *request = [NSURLComponents componentsWithString:@"zonoe://device-auth"];
    request.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"session" value:_pendingSession],
        [NSURLQueryItem queryItemWithName:@"nonce" value:_pendingNonce],
        [NSURLQueryItem queryItemWithName:@"bundle" value:_pendingBundle],
        [NSURLQueryItem queryItemWithName:@"protocol" value:@"1"]
    ];
    NSURL *url = request.URL;
    if (!url) { _awaitingZonoe = NO; _lastError = @"Unable to build zonoe device-auth URL"; return; }

    [[ZNRuntimeLogger sharedLogger] log:@"Open zonoe local device-ticket validation"];
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:^(BOOL success) {
        if (!success) {
            self->_awaitingZonoe = NO;
            self->_lastError = @"无法打开 zonoe://device-auth，请安装支持本地票据的 zonoe";
            [[ZNRuntimeLogger sharedLogger] log:self->_lastError];
        }
    }];
}

- (void)submitHostUDID:(NSString *)udid authorized:(BOOL)authorized {
    _submittedHostUDID = [udid copy] ?: @"";
    _submittedHostAuthorized = authorized;
    [self refresh];
}

- (NSString *)sourceDescription {
    switch (_identitySource) {
        case ZNIdentitySourceHostDylib: return @"Host Dylib";
        case ZNIdentitySourceZonoeLocalTicket: return @"Zonoe Local Ticket";
        case ZNIdentitySourceSubmittedHost: return @"Host Submitted";
        default: return @"None";
    }
}

- (NSString *)maskedUDID:(NSString *)udid {
    if (udid.length <= 8) return udid.length ? @"********" : @"";
    return [NSString stringWithFormat:@"%@****%@",[udid substringToIndex:4],[udid substringFromIndex:udid.length-4]];
}

- (NSString *)diagnosticReport {
    return [NSString stringWithFormat:@"Developer Gate: %@\nMarker: %@\nMarker UDID: %@\nObserved UDID: %@\nSource: %@\nHost Bridge: %@\nLocal Ticket: %@\nError: %@\n",
            self.authorized?@"Authorized":@"Locked",
            self.markerPath.length?self.markerPath:@"Not Found",
            [self maskedUDID:self.authorizedUDID],
            [self maskedUDID:self.observedUDID],
            [self sourceDescription],
            self.hostBridgeAvailable?@"Available":@"Unavailable",
            self.awaitingZonoe?@"Pending":@"Idle",
            self.lastError.length?self.lastError:@"None"];
}
@end

extern "C" __attribute__((visibility("default"))) bool ZonoePatchDeveloperAuthorized(void) {
    return [ZNDeveloperGate sharedGate].authorized;
}

extern "C" __attribute__((visibility("default"))) void ZonoePatchRequestUDIDValidation(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [[ZNDeveloperGate sharedGate] requestZonoeValidation]; });
}

extern "C" __attribute__((visibility("default"))) void ZonoePatchSubmitHostIdentity(const char *udid, bool authorized) {
    NSString *value = (udid && udid[0]) ? [NSString stringWithUTF8String:udid] : @"";
    dispatch_async(dispatch_get_main_queue(), ^{ [[ZNDeveloperGate sharedGate] submitHostUDID:value authorized:authorized]; });
}
