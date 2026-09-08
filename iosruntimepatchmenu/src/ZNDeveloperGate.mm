#import "ZNDeveloperGate.h"
#import "ZNPatchCore.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@implementation ZNDeveloperGate {
    BOOL _markerPresent;
    BOOL _authorized;
    BOOL _otherAuthorized;
    BOOL _hostBridgeAvailable;
    NSString *_markerPath;
    NSString *_authorizedUDID;
    NSString *_observedUDID;
    ZNIdentitySource _identitySource;
    NSString *_lastError;
    BOOL _awaitingZonoe;
    BOOL _markerHasG;
    BOOL _markerHasQ;
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
    _lastError = @"尚未检测";
    _identitySource = ZNIdentitySourceNone;
    _hostBridgeAvailable = NO;
    _awaitingZonoe = NO;
    _otherAuthorized = NO;
    _markerHasG = NO;
    _markerHasQ = NO;
    [self refresh];
    return self;
}

- (BOOL)markerPresent { return _markerPresent; }
- (BOOL)authorized { return _authorized; }
- (BOOL)otherAuthorized { return _otherAuthorized; }
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
    _markerHasG = NO;
    _markerHasQ = NO;

    if (!path) {
        _lastError = @"未找到开发者标记文件 1";
        return NO;
    }

    NSError *error = nil;
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    if (!text) {
        _lastError = [NSString stringWithFormat:@"读取标记文件失败：%@", error.localizedDescription ?: @"未知错误"];
        return NO;
    }

    if ([text hasPrefix:@"\uFEFF"]) text = [text substringFromIndex:1];
    text = [text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    text = [text stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];

    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    for (NSString *raw in lines) {
        NSString *line = [self trimLine:raw];
        if (!line.length) continue;
        if ([line isEqualToString:@"g"]) {
            _markerHasG = YES;
            continue;
        }
        if ([line isEqualToString:@"q"]) {
            _markerHasQ = YES;
            continue;
        }
        // First non-token line is optional display-only metadata (normally UDID).
        if (!_authorizedUDID.length) _authorizedUDID = line;
    }

    // Historical CI marker retained from the previous format: line 2 is optional.
    // v0.4.4 no longer assigns permission by line number: q and g are independent tokens.
    if (!_markerHasG && !_markerHasQ) {
        _lastError = @"标记文件存在，但未找到 q/g 权限标记";
    } else {
        _lastError = @"";
    }
    return YES;
}

- (void)refresh {
    BOOL wasAuthorized = _authorized;
    BOOL wasOtherAuthorized = _otherAuthorized;

    _authorized = NO;
    _otherAuthorized = NO;
    _observedUDID = @"";
    _identitySource = ZNIdentitySourceNone;
    _hostBridgeAvailable = NO;
    _awaitingZonoe = NO;

    if (![self loadMarker]) {
        if (wasAuthorized || wasOtherAuthorized) {
            [[ZNRuntimeLogger sharedLogger] log:@"开发者权限已关闭：标记文件无效或已移除"];
        }
        return;
    }

    _authorized = _markerHasG;
    _otherAuthorized = _markerHasQ;
    BOOL anyAuthorized = (_authorized || _otherAuthorized);
    if (anyAuthorized) {
        _observedUDID = _authorizedUDID ?: @"";
        _identitySource = ZNIdentitySourceMarkerFile;
    }

    if (wasAuthorized != _authorized) {
        [[ZNRuntimeLogger sharedLogger] log:_authorized ? @"g 权限已启用：显示诊断 / Debug" : @"g 权限已关闭：隐藏诊断 / Debug"];
    }
    if (wasOtherAuthorized != _otherAuthorized) {
        [[ZNRuntimeLogger sharedLogger] log:_otherAuthorized ? @"q 权限已启用：显示其他" : @"q 权限已关闭：隐藏其他"];
    }
}

- (void)requestZonoeValidation {
    [self refresh];
    [[ZNRuntimeLogger sharedLogger] log:@"已重新检测标记文件 1"];
}

- (void)submitHostUDID:(NSString *)udid authorized:(BOOL)authorized {
    (void)udid;
    (void)authorized;
    [self refresh];
}

- (NSString *)sourceDescription {
    switch (_identitySource) {
        case ZNIdentitySourceMarkerFile: return @"标记文件";
        case ZNIdentitySourceHostDylib: return @"Host Dylib（已禁用）";
        case ZNIdentitySourceZonoeLocalTicket: return @"Local Ticket（已禁用）";
        case ZNIdentitySourceSubmittedHost: return @"Host Submitted（已禁用）";
        default: return @"无";
    }
}

- (NSString *)maskedUDID:(NSString *)udid {
    if (!udid.length) return @"";
    if (udid.length <= 8) return @"********";
    return [NSString stringWithFormat:@"%@****%@", [udid substringToIndex:4], [udid substringFromIndex:udid.length-4]];
}

- (NSString *)diagnosticReport {
    return [NSString stringWithFormat:@"开发者标记: %@\n诊断/Debug(g): %@\n其他(q): %@\n标记文件: %@\n标记附加值: %@\n来源: %@\n外部 UDID 获取: 已禁用\nHost Bridge: 已禁用\nLocal Ticket: 已禁用\n错误: %@\n",
            self.markerPresent ? @"已找到" : @"未找到",
            self.authorized ? @"显示" : @"隐藏",
            self.otherAuthorized ? @"显示" : @"隐藏",
            self.markerPath.length ? self.markerPath : @"未找到",
            [self maskedUDID:self.authorizedUDID],
            [self sourceDescription],
            self.lastError.length ? self.lastError : @"无"];
}
@end

extern "C" __attribute__((visibility("default"))) bool ZonoePatchDeveloperAuthorized(void) {
    return [ZNDeveloperGate sharedGate].authorized;
}

extern "C" __attribute__((visibility("default"))) bool ZonoePatchOtherAuthorized(void) {
    return [ZNDeveloperGate sharedGate].otherAuthorized;
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

// Sidebar/UI ownership intentionally lives only in ZonoeRuntimeMenu.mm.
// ZNDeveloperGate exposes q/g permission state and marker metadata only.
