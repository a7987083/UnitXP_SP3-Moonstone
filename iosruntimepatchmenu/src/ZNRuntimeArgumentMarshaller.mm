#import "ZNRuntimeArgumentMarshaller.h"
#import <dlfcn.h>
#import <limits.h>

typedef const void *(*ZNMARMethodParamFn)(const void *, uint32_t);
typedef void *(*ZNMARClassFromTypeFn)(const void *);
typedef int32_t (*ZNMARClassValueSizeFn)(void *, uint32_t *);

@implementation ZNRuntimeArgumentMarshaller

+ (NSMutableDictionary<NSString *, ZNRuntimeValueTypeEncoder> *)registry {
    static NSMutableDictionary *encoders;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ encoders = [NSMutableDictionary new]; });
    return encoders;
}

+ (NSString *)normalized:(NSString *)name {
    return [name ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

+ (void)registerValueType:(NSString *)managedType encoder:(ZNRuntimeValueTypeEncoder)encoder {
    NSString *key = [self normalized:managedType];
    if (!key.length || !encoder) return;
    @synchronized(self) {
        [self registry][key] = [encoder copy];
    }
}

+ (nullable NSData *)decodeHex:(NSString *)input size:(NSUInteger)size error:(NSString **)error {
    NSString *value = [self normalized:input];
    if (![value.lowercaseString hasPrefix:@"hex:"]) {
        if (error) *error = @"FAILED_CODEC_REQUIRED：请注册该类型的 Codec；或输入 hex: 后接准确的 value-type 字节";
        return nil;
    }
    NSString *hex = [[value substringFromIndex:4] stringByReplacingOccurrencesOfString:@" " withString:@""];
    if (hex.length != size * 2) {
        if (error) *error = [NSString stringWithFormat:@"FAILED_STRUCT_SIZE：期望 %lu 字节，实际 hex 长度为 %lu",
                            (unsigned long)size, (unsigned long)hex.length / 2];
        return nil;
    }
    NSMutableData *data = [NSMutableData dataWithLength:size];
    uint8_t *out = (uint8_t *)data.mutableBytes;
    for (NSUInteger i = 0; i < size; ++i) {
        NSString *pair = [hex substringWithRange:NSMakeRange(i * 2, 2)];
        unsigned value = 0;
        NSScanner *scanner = [NSScanner scannerWithString:pair];
        if (![scanner scanHexInt:&value] || !scanner.isAtEnd) {
            if (error) *error = [NSString stringWithFormat:@"FAILED_STRUCT_HEX：第 %lu 字节不是十六进制", (unsigned long)i];
            return nil;
        }
        out[i] = (uint8_t)value;
    }
    return data;
}

+ (nullable NSMutableData *)encodeValueTypeParameterForMethod:(uintptr_t)methodInfo
                                                        index:(NSUInteger)index
                                                         type:(NSString *)managedType
                                                        input:(NSString *)text
                                                        error:(NSString **)error {
    if (!methodInfo || index > UINT32_MAX) {
        if (error) *error = @"FAILED_STRUCT_ABI：缺少 MethodInfo 或参数序号无效";
        return nil;
    }
    ZNMARMethodParamFn getParam = (ZNMARMethodParamFn)dlsym(RTLD_DEFAULT, "il2cpp_method_get_param");
    ZNMARClassFromTypeFn fromType = (ZNMARClassFromTypeFn)dlsym(RTLD_DEFAULT, "il2cpp_class_from_type");
    if (!fromType) fromType = (ZNMARClassFromTypeFn)dlsym(RTLD_DEFAULT, "il2cpp_class_from_il2cpp_type");
    ZNMARClassValueSizeFn valueSize = (ZNMARClassValueSizeFn)dlsym(RTLD_DEFAULT, "il2cpp_class_value_size");
    if (!getParam || !fromType || !valueSize) {
        if (error) *error = @"FAILED_STRUCT_ABI：IL2CPP value-type metadata API 未导出";
        return nil;
    }
    const void *paramType = getParam((const void *)methodInfo, (uint32_t)index);
    void *klass = paramType ? fromType(paramType) : NULL;
    if (!klass) {
        if (error) *error = @"FAILED_STRUCT_ABI：无法获取参数类型 Class";
        return nil;
    }
    uint32_t alignment = 0;
    int32_t byteSize = valueSize(klass, &alignment);
    // Bounded allocation and conservative alignment guard.
    if (byteSize <= 0 || byteSize > 4096 || alignment == 0 || alignment > 256) {
        if (error) *error = [NSString stringWithFormat:@"FAILED_STRUCT_LAYOUT：无效 size=%d align=%u", byteSize, alignment];
        return nil;
    }
    NSString *key = [self normalized:managedType];
    ZNRuntimeValueTypeEncoder encoder = nil;
    @synchronized(self) {
        encoder = [[self registry][key] copy];
    }
    NSString *localError = nil;
    NSData *payload = encoder ? encoder(text ?: @"", (NSUInteger)byteSize, &localError)
                              : [self decodeHex:text ?: @"" size:(NSUInteger)byteSize error:&localError];
    if (!payload || payload.length != (NSUInteger)byteSize) {
        if (error) *error = localError ?: [NSString stringWithFormat:@"FAILED_STRUCT_SIZE：%@ Codec 输出与 IL2CPP 布局不匹配", key];
        return nil;
    }
    return [payload mutableCopy];
}

@end
