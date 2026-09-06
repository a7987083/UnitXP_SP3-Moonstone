#import "ZNPatchCore.h"
#import <mach-o/dyld.h>

static NSString *ZNEnabledKey(NSString *featureID) {
    return [NSString stringWithFormat:@"ZonoePatch.Feature.%@.Enabled", featureID];
}

static NSString *ZNValueKey(NSString *featureID) {
    return [NSString stringWithFormat:@"ZonoePatch.Feature.%@.Value", featureID];
}

NSString *ZNStringForPatchState(ZNPatchState state) {
    switch (state) {
        case ZNPatchStateReady: return @"Ready";
        case ZNPatchStateEnabled: return @"Enabled";
        case ZNPatchStateDisabled: return @"Disabled";
        case ZNPatchStateUnsupported: return @"Unsupported";
        case ZNPatchStateFailed: return @"Failed";
        default: return @"Uninitialized";
    }
}

@implementation ZNPatchDescriptor
- (instancetype)initWithIdentifier:(NSString *)identifier
                              name:(NSString *)name
                          category:(NSString *)category
                           backend:(NSString *)backend
                             value:(double)value {
    self = [super init];
    if (!self) return nil;
    _identifier = [identifier copy];
    _name = [name copy];
    _category = [category copy];
    _backend = [backend copy];
    _value = value;
    _enabled = NO;
    _state = ZNPatchStateReady;
    return self;
}
@end

@implementation ZNRuntimeLogger {
    NSMutableArray<NSString *> *_lines;
}
+ (instancetype)sharedLogger {
    static ZNRuntimeLogger *s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ s = [ZNRuntimeLogger new]; });
    return s;
}
- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _lines = [NSMutableArray array];
    return self;
}
- (void)log:(NSString *)message {
    if (!message.length) return;
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.dateFormat = @"HH:mm:ss";
    NSString *line = [NSString stringWithFormat:@"[%@] %@", [fmt stringFromDate:[NSDate date]], message];
    @synchronized (self) {
        [_lines addObject:line];
        if (_lines.count > 200) [_lines removeObjectsInRange:NSMakeRange(0, _lines.count - 200)];
    }
    NSLog(@"[ZonoePatch] %@", message);
}
- (NSArray<NSString *> *)recentLines:(NSUInteger)limit {
    @synchronized (self) {
        if (limit == 0 || _lines.count <= limit) return [_lines copy];
        return [_lines subarrayWithRange:NSMakeRange(_lines.count-limit, limit)];
    }
}
- (void)clear {
    @synchronized (self) { [_lines removeAllObjects]; }
}
@end

@implementation ZNModuleManager
+ (instancetype)sharedManager {
    static ZNModuleManager *s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ s = [ZNModuleManager new]; });
    return s;
}
- (NSArray<NSDictionary<NSString *,id> *> *)loadedImages {
    NSMutableArray *items = [NSMutableArray array];
    uint32_t count = _dyld_image_count();
    for (uint32_t i=0; i<count; i++) {
        const char *cname = _dyld_get_image_name(i);
        NSString *path = cname ? [NSString stringWithUTF8String:cname] : @"";
        uintptr_t base = (uintptr_t)_dyld_get_image_header(i);
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        [items addObject:@{
            @"index": @(i),
            @"name": path.lastPathComponent ?: @"",
            @"path": path ?: @"",
            @"base": @(base),
            @"slide": @((long long)slide),
        }];
    }
    return items;
}
- (NSDictionary<NSString *,id> *)mainExecutable {
    return self.loadedImages.firstObject;
}
- (NSDictionary<NSString *,id> *)unityFramework {
    for (NSDictionary *item in self.loadedImages) {
        NSString *name = item[@"name"];
        if ([name caseInsensitiveCompare:@"UnityFramework"] == NSOrderedSame ||
            [name caseInsensitiveCompare:@"UnityFramework.framework"] == NSOrderedSame ||
            [item[@"path"] rangeOfString:@"UnityFramework.framework/UnityFramework" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return item;
        }
    }
    return nil;
}
- (NSString *)diagnosticReport {
    NSDictionary *main = self.mainExecutable;
    NSDictionary *unity = self.unityFramework;
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"Images: %lu\n", (unsigned long)self.loadedImages.count];
    if (main) [s appendFormat:@"Main: %@ base=0x%llx slide=0x%llx\n", main[@"name"], [main[@"base"] unsignedLongLongValue], [main[@"slide"] unsignedLongLongValue]];
    if (unity) [s appendFormat:@"UnityFramework: Loaded base=0x%llx slide=0x%llx\n", [unity[@"base"] unsignedLongLongValue], [unity[@"slide"] unsignedLongLongValue]];
    else [s appendString:@"UnityFramework: Not Loaded\n"];
    return s;
}
@end

@implementation ZNPatchManager {
    NSMutableDictionary<NSString *, ZNPatchDescriptor *> *_descriptors;
}
+ (instancetype)sharedManager {
    static ZNPatchManager *s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ s = [ZNPatchManager new]; });
    return s;
}
- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _descriptors = [NSMutableDictionary dictionary];
    [self registerDescriptor:@"ui_test" name:@"UI 测试开关" category:@"首页" value:0];
    [self registerDescriptor:@"invincible" name:@"无敌" category:@"玩家" value:0];
    [self registerDescriptor:@"speed" name:@"移速修改" category:@"移动" value:2.5];
    [self registerDescriptor:@"damage" name:@"伤害倍率" category:@"战斗" value:5.0];
    [self registerDescriptor:@"jump" name:@"跳跃高度" category:@"移动" value:1.5];
    [self registerDescriptor:@"attack_speed" name:@"攻速修改" category:@"战斗" value:1.8];
    [self registerDescriptor:@"other_test" name:@"测试功能" category:@"其他" value:0];
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"PatchManager initialized: %lu descriptors", (unsigned long)_descriptors.count]];
    return self;
}
- (void)registerDescriptor:(NSString *)identifier name:(NSString *)name category:(NSString *)category value:(double)defaultValue {
    ZNPatchDescriptor *d = [[ZNPatchDescriptor alloc] initWithIdentifier:identifier name:name category:category backend:@"Mock" value:defaultValue];
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    id ev = [ud objectForKey:ZNEnabledKey(identifier)];
    id vv = [ud objectForKey:ZNValueKey(identifier)];
    d.enabled = ev ? [ud boolForKey:ZNEnabledKey(identifier)] : NO;
    d.value = vv ? [ud doubleForKey:ZNValueKey(identifier)] : defaultValue;
    d.state = d.enabled ? ZNPatchStateEnabled : ZNPatchStateDisabled;
    _descriptors[identifier] = d;
}
- (BOOL)enabledForFeature:(NSString *)identifier {
    ZNPatchDescriptor *d = _descriptors[identifier];
    return d ? d.enabled : [NSUserDefaults.standardUserDefaults boolForKey:ZNEnabledKey(identifier)];
}
- (void)setFeature:(NSString *)identifier enabled:(BOOL)enabled {
    if (!identifier.length) return;
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:ZNEnabledKey(identifier)];
    ZNPatchDescriptor *d = _descriptors[identifier];
    if (d) {
        d.enabled = enabled;
        d.state = enabled ? ZNPatchStateEnabled : ZNPatchStateDisabled;
    }
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"%@ -> %@ (Mock)", identifier, enabled?@"Enabled":@"Disabled"]];
}
- (double)valueForFeature:(NSString *)identifier fallback:(double)fallback {
    ZNPatchDescriptor *d = _descriptors[identifier];
    if (d) return d.value;
    id obj = [NSUserDefaults.standardUserDefaults objectForKey:ZNValueKey(identifier)];
    return obj ? [NSUserDefaults.standardUserDefaults doubleForKey:ZNValueKey(identifier)] : fallback;
}
- (void)setFeature:(NSString *)identifier value:(double)value {
    if (!identifier.length) return;
    [NSUserDefaults.standardUserDefaults setDouble:value forKey:ZNValueKey(identifier)];
    ZNPatchDescriptor *d = _descriptors[identifier];
    if (d) d.value = value;
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"%@ value -> %.3f (Mock)", identifier, value]];
}
- (ZNPatchDescriptor *)descriptorForIdentifier:(NSString *)identifier { return _descriptors[identifier]; }
- (NSArray<ZNPatchDescriptor *> *)allDescriptors {
    return [[_descriptors allValues] sortedArrayUsingComparator:^NSComparisonResult(ZNPatchDescriptor *a, ZNPatchDescriptor *b) {
        return [a.identifier compare:b.identifier];
    }];
}
- (NSDictionary<NSString *,NSNumber *> *)stateCounts {
    NSInteger ready=0, enabled=0, disabled=0, unsupported=0, failed=0;
    for (ZNPatchDescriptor *d in _descriptors.allValues) {
        switch (d.state) {
            case ZNPatchStateReady: ready++; break;
            case ZNPatchStateEnabled: enabled++; break;
            case ZNPatchStateDisabled: disabled++; break;
            case ZNPatchStateUnsupported: unsupported++; break;
            case ZNPatchStateFailed: failed++; break;
            default: break;
        }
    }
    return @{@"registered":@(_descriptors.count),@"ready":@(ready),@"enabled":@(enabled),@"disabled":@(disabled),@"unsupported":@(unsupported),@"failed":@(failed)};
}
- (BOOL)runSelfTest {
    NSString *key = @"ZonoePatch.SelfTest.Value";
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    id old = [ud objectForKey:key];
    [ud setObject:@"ok" forKey:key];
    BOOL defaultsOK = [[ud stringForKey:key] isEqualToString:@"ok"];
    if (old) [ud setObject:old forKey:key]; else [ud removeObjectForKey:key];
    BOOL descriptorsOK = (_descriptors.count >= 7 && _descriptors[@"speed"] != nil && _descriptors[@"damage"] != nil);
    BOOL modulesOK = ([ZNModuleManager sharedManager].loadedImages.count > 0);
    BOOL ok = defaultsOK && descriptorsOK && modulesOK;
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"Self Test %@ defaults=%d descriptors=%d modules=%d", ok?@"PASS":@"FAIL", defaultsOK, descriptorsOK, modulesOK]];
    return ok;
}
- (NSString *)diagnosticReport {
    NSDictionary *counts = self.stateCounts;
    NSMutableString *s = [NSMutableString string];
    [s appendString:@"ZonoePatch Patch Core 0.3.0\n"];
    [s appendFormat:@"Registered: %@  Enabled: %@  Disabled: %@  Unsupported: %@  Failed: %@\n", counts[@"registered"], counts[@"enabled"], counts[@"disabled"], counts[@"unsupported"], counts[@"failed"]];
    [s appendString:[[ZNModuleManager sharedManager] diagnosticReport]];
    for (ZNPatchDescriptor *d in self.allDescriptors) {
        [s appendFormat:@"%@ [%@] backend=%@ enabled=%d value=%.3f\n", d.identifier, ZNStringForPatchState(d.state), d.backend, d.enabled, d.value];
    }
    return s;
}
@end
