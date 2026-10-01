#import "ZNH5GGValueBackend.h"
#import "ZNPatchCore.h"
#import <objc/runtime.h>

@implementation ZNH5GGValueBackend {
    id _engine;
}

+ (instancetype)sharedBackend {
    static ZNH5GGValueBackend *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [ZNH5GGValueBackend new]; });
    return shared;
}

+ (NSSet<NSString *> *)supportedTypes {
    static NSSet<NSString *> *types;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ types = [NSSet setWithArray:@[@"I8",@"U8",@"I16",@"U16",@"I32",@"U32",@"I64",@"U64",@"F32",@"F64"]]; });
    return types;
}

+ (BOOL)isSupportedType:(NSString *)type {
    return [[self supportedTypes] containsObject:type.uppercaseString ?: @""];
}

+ (NSUInteger)sizeForType:(NSString *)type {
    NSString *t = type.uppercaseString ?: @"";
    if ([t isEqualToString:@"I8"] || [t isEqualToString:@"U8"]) return 1;
    if ([t isEqualToString:@"I16"] || [t isEqualToString:@"U16"]) return 2;
    if ([t isEqualToString:@"I32"] || [t isEqualToString:@"U32"] || [t isEqualToString:@"F32"]) return 4;
    if ([t isEqualToString:@"I64"] || [t isEqualToString:@"U64"] || [t isEqualToString:@"F64"]) return 8;
    return 0;
}

- (id)engineIfAvailable {
    @synchronized (self) {
        if (_engine) return _engine;
        Class cls = NSClassFromString(@"h5ggEngine");
        if (!cls) return nil;
        id obj = [[cls alloc] init];
        SEL getSel = NSSelectorFromString(@"getValue:param2:");
        SEL setSel = NSSelectorFromString(@"setValue:param2:param3:");
        if (![obj respondsToSelector:getSel] || ![obj respondsToSelector:setSel]) return nil;
        _engine = obj;
        [[ZNRuntimeLogger sharedLogger] log:@"[m5.11-value] H5GG h5ggEngine detected; typed read/write backend ready"];
        return _engine;
    }
}

- (BOOL)isAvailable { return [self engineIfAvailable] != nil; }

- (NSString *)availabilityText {
    return self.available ? @"H5GG typed backend ready" : @"H5GG backend unavailable in current process";
}

- (NSString *)readAddress:(uint64_t)address type:(NSString *)type error:(NSString **)error {
    NSString *t = type.uppercaseString ?: @"";
    if (![[self class] isSupportedType:t]) {
        if (error) *error = [NSString stringWithFormat:@"Unsupported value type: %@", type ?: @""];
        return nil;
    }
    id engine = [self engineIfAvailable];
    if (!engine) { if (error) *error = @"H5GG h5ggEngine not found"; return nil; }
    SEL sel = NSSelectorFromString(@"getValue:param2:");
    typedef id (*Fn)(id, SEL, NSString *, NSString *);
    Fn fn = (Fn)[engine methodForSelector:sel];
    NSString *addr = [NSString stringWithFormat:@"0x%llX", address];
    id out = fn ? fn(engine, sel, addr, t) : nil;
    if (![out isKindOfClass:NSString.class] || ![(NSString *)out length]) {
        if (error) *error = [NSString stringWithFormat:@"H5GG read failed at %@ (%@)", addr, t];
        return nil;
    }
    return out;
}

- (BOOL)writeAddress:(uint64_t)address value:(NSString *)value type:(NSString *)type error:(NSString **)error {
    NSString *t = type.uppercaseString ?: @"";
    if (![[self class] isSupportedType:t]) {
        if (error) *error = [NSString stringWithFormat:@"Unsupported value type: %@", type ?: @""];
        return NO;
    }
    id engine = [self engineIfAvailable];
    if (!engine) { if (error) *error = @"H5GG h5ggEngine not found"; return NO; }
    SEL sel = NSSelectorFromString(@"setValue:param2:param3:");
    typedef BOOL (*Fn)(id, SEL, NSString *, NSString *, NSString *);
    Fn fn = (Fn)[engine methodForSelector:sel];
    NSString *addr = [NSString stringWithFormat:@"0x%llX", address];
    BOOL ok = fn ? fn(engine, sel, addr, value ?: @"", t) : NO;
    if (!ok && error) *error = [NSString stringWithFormat:@"H5GG write failed at %@ (%@=%@)", addr, t, value ?: @""];
    return ok;
}

@end
