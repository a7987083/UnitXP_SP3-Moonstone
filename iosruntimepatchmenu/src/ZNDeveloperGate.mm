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
    _lastError = @"尚未检测";
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
    if (lines.count < 1 || ![[self trimLine:lines[0]] isEqualToString:@"g"]) {
        _lastError = @"标记文件第一行必须为 g";
        return NO;
    }

    // v0.4: line 2 is optional. If present it is display-only metadata.
    if (lines.count >= 2) {
        NSString *udid = [self trimLine:lines[1]];
        if (udid.length) _authorizedUDID = udid;
    }
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
            [[ZNRuntimeLogger sharedLogger] log:@"开发者权限已关闭：标记文件无效或已移除"];
        }
        return;
    }

    _authorized = YES;
    _observedUDID = _authorizedUDID ?: @"";
    _identitySource = ZNIdentitySourceMarkerFile;
    _lastError = @"";

    if (!wasAuthorized) {
        [[ZNRuntimeLogger sharedLogger] log:@"开发者权限已通过标记文件启用；不再获取外部 UDID"];
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
    return [NSString stringWithFormat:@"开发者状态: %@\n标记文件: %@\n标记附加值: %@\n来源: %@\n外部 UDID 获取: 已禁用\nHost Bridge: 已禁用\nLocal Ticket: 已禁用\n错误: %@\n",
            self.authorized ? @"已启用" : @"未启用",
            self.markerPath.length ? self.markerPath : @"未找到",
            [self maskedUDID:self.authorizedUDID],
            [self sourceDescription],
            self.lastError.length ? self.lastError : @"无"];
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
