#import "ZNDeveloperGate.h"
#import "ZNPatchCore.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>

typedef const char *(*ZNHostGetUDIDFn)(void);
typedef bool (*ZNHostIsAuthorizedFn)(void);

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
    BOOL _lastRequestUsedCallback;
    NSString *_submittedHostUDID;
    BOOL _submittedHostAuthorized;
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
- (BOOL)lastRequestUsedCallback { return _lastRequestUsedCallback; }

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
    if (!path) {
        _lastError = @"Developer marker file not found";
        return NO;
    }
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
    if (!udid.length) {
        _lastError = @"Marker line 2 UDID is empty";
        return NO;
    }
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
    ZNIdentitySource oldSource = _identitySource;
    _authorized = NO;
    _observedUDID = @"";
    _identitySource = ZNIdentitySourceNone;

    if (![self loadMarker]) {
        if (wasAuthorized) [[ZNRuntimeLogger sharedLogger] log:@"Developer Gate revoked: marker invalid or removed"];
        return;
    }

    if ([self tryHostBridge]) return;

    if (_awaitingZonoe && NSThread.isMainThread) {
        NSString *clipboard = UIPasteboard.generalPasteboard.string ?: @"";
        ZNIdentitySource source = _lastRequestUsedCallback ? ZNIdentitySourceZonoeCallback : ZNIdentitySourceClipboardFallback;
        if ([self acceptCandidate:clipboard source:source]) {
            _awaitingZonoe = NO;
            return;
        }
        _awaitingZonoe = NO;
        _lastError = clipboard.length ? @"Clipboard UDID does not match marker" : @"Clipboard does not contain UDID";
    } else {
        _lastError = _hostBridgeAvailable ? @"Host dylib is not authorized yet" : @"Waiting for Host dylib or zonoe validation";
    }

    if (wasAuthorized && !_authorized) {
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"Developer Gate no longer authorized (previous source=%ld)", (long)oldSource]];
    }
}

- (void)applicationDidBecomeActive:(NSNotification *)note {
    (void)note;
    if (!_awaitingZonoe) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self refresh];
    });
}

- (NSString *)callbackScheme {
    NSString *dedicated = [NSBundle.mainBundle objectForInfoDictionaryKey:@"ZonoePatchCallbackScheme"];
    if ([dedicated isKindOfClass:NSString.class] && dedicated.length) return dedicated;
    return @"";
}

- (void)requestZonoeValidation {
    if (![self loadMarker]) {
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"UDID validation not started: %@", self.lastError]];
        return;
    }
    NSString *scheme = [self callbackScheme];
    NSURLComponents *request = [NSURLComponents componentsWithString:@"zonoe://udid"];
    if (scheme.length) {
        NSString *callback = [NSString stringWithFormat:@"%@://udid", scheme];
        request.queryItems = @[[NSURLQueryItem queryItemWithName:@"callback" value:callback]];
    }
    NSURL *url = request.URL;
    if (!url) {
        _lastError = @"Unable to build zonoe UDID URL";
        return;
    }
    _awaitingZonoe = YES;
    _lastRequestUsedCallback = scheme.length > 0;
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"Open zonoe UDID validation (%@)", _lastRequestUsedCallback?@"callback":@"manual return + clipboard"]];
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication.sharedApplication openURL:url options:@{} completionHandler:^(BOOL success) {
            if (!success) {
                self->_awaitingZonoe = NO;
                self->_lastError = @"Unable to open zonoe://udid";
                [[ZNRuntimeLogger sharedLogger] log:self->_lastError];
            }
        }];
    });
}

- (void)submitHostUDID:(NSString *)udid authorized:(BOOL)authorized {
    _submittedHostUDID = [udid copy] ?: @"";
    _submittedHostAuthorized = authorized;
    [self refresh];
}

- (NSString *)sourceDescription {
    switch (_identitySource) {
        case ZNIdentitySourceHostDylib: return @"Host Dylib";
        case ZNIdentitySourceZonoeCallback: return @"Zonoe Callback";
        case ZNIdentitySourceClipboardFallback: return @"Clipboard Fallback";
        case ZNIdentitySourceSubmittedHost: return @"Host Submitted";
        default: return @"None";
    }
}

- (NSString *)maskedUDID:(NSString *)udid {
    if (udid.length <= 8) return udid.length ? @"********" : @"";
    return [NSString stringWithFormat:@"%@****%@", [udid substringToIndex:4], [udid substringFromIndex:udid.length-4]];
}

- (NSString *)diagnosticReport {
    return [NSString stringWithFormat:@"Developer Gate: %@\nMarker: %@\nMarker UDID: %@\nObserved UDID: %@\nSource: %@\nHost Bridge: %@\nAwaiting zonoe: %@\nError: %@\n",
            self.authorized?@"Authorized":@"Locked",
            self.markerPath.length?self.markerPath:@"Not Found",
            [self maskedUDID:self.authorizedUDID],
            [self maskedUDID:self.observedUDID],
            [self sourceDescription],
            self.hostBridgeAvailable?@"Available":@"Unavailable",
            self.awaitingZonoe?@"YES":@"NO",
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
