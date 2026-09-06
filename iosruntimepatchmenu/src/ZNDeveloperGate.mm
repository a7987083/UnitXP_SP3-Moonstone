#import "ZNDeveloperGate.h"
#import "ZNPatchCore.h"
#import <UIKit/UIKit.h>

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
    _hostBridgeAvailable = NO;
    _awaitingZonoe = NO;
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

- (void)refresh {
    BOOL wasAuthorized = _authorized;

    _authorized = NO;
    _observedUDID = @"";
    _identitySource = ZNIdentitySourceNone;
    _hostBridgeAvailable = NO;
    _awaitingZonoe = NO;

    if (![self loadMarker]) {
        if (wasAuthorized) {
            [[ZNRuntimeLogger sharedLogger] log:@"Developer Gate revoked: marker invalid or removed"];
        }
        return;
    }

    _authorized = YES;
    _observedUDID = _authorizedUDID ?: @"";
    _identitySource = ZNIdentitySourceMarkerFile;
    _lastError = @"";

    if (!wasAuthorized) {
        [[ZNRuntimeLogger sharedLogger] log:@"Developer Gate authorized via marker file; external UDID acquisition disabled"];
    }
}

- (void)requestZonoeValidation {
    [self refresh];
    [[ZNRuntimeLogger sharedLogger] log:@"UDID acquisition disabled; developer gate uses marker file only"];
}

- (void)submitHostUDID:(NSString *)udid authorized:(BOOL)authorized {
    (void)udid;
    (void)authorized;
    [self refresh];
}

- (NSString *)sourceDescription {
    switch (_identitySource) {
        case ZNIdentitySourceMarkerFile: return @"Marker File";
        case ZNIdentitySourceHostDylib: return @"Host Dylib (Disabled)";
        case ZNIdentitySourceZonoeLocalTicket: return @"Zonoe Local Ticket (Disabled)";
        case ZNIdentitySourceSubmittedHost: return @"Host Submitted (Disabled)";
        default: return @"None";
    }
}

- (NSString *)maskedUDID:(NSString *)udid {
    if (udid.length <= 8) return udid.length ? @"********" : @"";
    return [NSString stringWithFormat:@"%@****%@", [udid substringToIndex:4], [udid substringFromIndex:udid.length-4]];
}

- (NSString *)diagnosticReport {
    return [NSString stringWithFormat:@"Developer Gate: %@\nMarker: %@\nMarker UDID: %@\nSource: %@\nUDID Acquisition: Disabled\nHost Bridge: Disabled\nLocal Ticket: Disabled\nError: %@\n",
            self.authorized ? @"Authorized" : @"Locked",
            self.markerPath.length ? self.markerPath : @"Not Found",
            [self maskedUDID:self.authorizedUDID],
            [self sourceDescription],
            self.lastError.length ? self.lastError : @"None"];
}
@end

extern "C" __attribute__((visibility("default"))) bool ZonoePatchDeveloperAuthorized(void) {
    return [ZNDeveloperGate sharedGate].authorized;
}

extern "C" __attribute__((visibility("default"))) void ZonoePatchRequestUDIDValidation(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[ZNDeveloperGate sharedGate] requestZonoeValidation];
    });
}

extern "C" __attribute__((visibility("default"))) void ZonoePatchSubmitHostIdentity(const char *udid, bool authorized) {
    (void)udid;
    (void)authorized;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[ZNDeveloperGate sharedGate] refresh];
    });
}
