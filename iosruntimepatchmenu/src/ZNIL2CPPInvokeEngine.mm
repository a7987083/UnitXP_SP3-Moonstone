#import "ZNIL2CPPInvokeEngine.h"
#import "ZNRuntimeActionModel.h"
#import "ZNIL2CPPResolver.h"
#import "ZNPatchCore.h"
#import <dlfcn.h>

// ECMA-335 MethodAttributes.Static. IL2CPP exposes the same bit through
// il2cpp_method_get_flags. We fail closed if the API cannot be resolved.
static const uint32_t kZNMethodAttributeStatic = 0x0010u;

typedef void *(*ZNRuntimeInvokeFn)(const void *method, void *object, void **params, void **exception);
typedef uint32_t (*ZNMethodGetFlagsFn)(const void *method, uint32_t *iflags);

static void *ZNInvokeResolveSymbol(NSString *unityPath, const char *name) {
    if (!name) return NULL;
    void *symbol = dlsym(RTLD_DEFAULT, name);
    if (symbol) return symbol;
    if (!unityPath.length) return NULL;
#ifdef RTLD_NOLOAD
    void *handle = dlopen(unityPath.fileSystemRepresentation, RTLD_LAZY | RTLD_NOLOAD);
#else
    void *handle = dlopen(unityPath.fileSystemRepresentation, RTLD_LAZY);
#endif
    return handle ? dlsym(handle, name) : NULL;
}

@implementation ZNIL2CPPInvokeEngine

+ (instancetype)sharedEngine {
    static ZNIL2CPPInvokeEngine *engine;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ engine = [ZNIL2CPPInvokeEngine new]; });
    return engine;
}

- (NSDictionary<NSString *,id> *)capabilities {
    ZNIL2CPPResolver *resolver = [ZNIL2CPPResolver sharedResolver];
    [resolver refresh];
    ZNRuntimeInvokeFn runtimeInvoke = (ZNRuntimeInvokeFn)ZNInvokeResolveSymbol(resolver.unityPath, "il2cpp_runtime_invoke");
    ZNMethodGetFlagsFn methodGetFlags = (ZNMethodGetFlagsFn)ZNInvokeResolveSymbol(resolver.unityPath, "il2cpp_method_get_flags");
    return @{
        @"resolver": @(resolver.isAvailable),
        @"runtimeInvoke": @(runtimeInvoke != NULL),
        @"methodGetFlags": @(methodGetFlags != NULL),
        @"zeroArgStatic": @(resolver.isAvailable && runtimeInvoke != NULL && methodGetFlags != NULL),
    };
}

- (NSDictionary<NSString *,id> *)executeAction:(ZNRuntimeMethodAction *)action error:(NSString **)error {
    if (!action) {
        if (error) *error = @"Runtime Method Call action 为空";
        return nil;
    }
    return [self executeAssembly:action.assembly
                       namespace:action.namespaceName
                       className:action.className
                          method:action.methodName
                   argumentCount:action.argumentCount
                           error:error];
}

- (NSDictionary<NSString *,id> *)executeAssembly:(NSString *)assembly
                                       namespace:(NSString *)namespaceName
                                       className:(NSString *)className
                                          method:(NSString *)methodName
                                   argumentCount:(NSUInteger)argumentCount
                                           error:(NSString **)error {
    if (argumentCount != 0) {
        if (error) *error = [NSString stringWithFormat:@"FAILED_UNSUPPORTED_ARGUMENT：M4.1 仅支持 0 参数；当前=%lu", (unsigned long)argumentCount];
        return nil;
    }

    ZNIL2CPPResolver *resolver = [ZNIL2CPPResolver sharedResolver];
    [resolver refresh];
    if (!resolver.isAvailable) {
        if (error) *error = [NSString stringWithFormat:@"FAILED_RESOLVE：%@", resolver.lastError ?: @"IL2CPP Resolver unavailable"];
        return nil;
    }

    NSDictionary *resolved = [resolver resolveMethodAssembly:assembly
                                                   namespace:namespaceName ?: @""
                                                   className:className
                                                      method:methodName
                                               argumentCount:(NSInteger)argumentCount];
    uintptr_t methodInfo = [resolved[@"methodInfo"] unsignedLongLongValue];
    if (!resolved || !methodInfo) {
        if (error) *error = [NSString stringWithFormat:@"FAILED_RESOLVE：%@!%@.%@::%@/%lu",
                             assembly ?: @"",
                             namespaceName ?: @"",
                             className ?: @"",
                             methodName ?: @"",
                             (unsigned long)argumentCount];
        return nil;
    }

    ZNRuntimeInvokeFn runtimeInvoke = (ZNRuntimeInvokeFn)ZNInvokeResolveSymbol(resolver.unityPath, "il2cpp_runtime_invoke");
    if (!runtimeInvoke) {
        if (error) *error = @"FAILED_INVOKE_UNAVAILABLE：il2cpp_runtime_invoke 未导出";
        return nil;
    }

    ZNMethodGetFlagsFn methodGetFlags = (ZNMethodGetFlagsFn)ZNInvokeResolveSymbol(resolver.unityPath, "il2cpp_method_get_flags");
    if (!methodGetFlags) {
        if (error) *error = @"FAILED_STATIC_STATE_UNAVAILABLE：无法确认方法是否 static；拒绝以 NULL instance 猜测调用";
        return nil;
    }

    uint32_t implFlags = 0;
    uint32_t methodFlags = methodGetFlags((const void *)methodInfo, &implFlags);
    BOOL isStatic = (methodFlags & kZNMethodAttributeStatic) != 0;
    if (!isStatic) {
        if (error) *error = @"FAILED_INSTANCE_REQUIRED：目标是实例方法；M4.1 尚未实现对象实例解析";
        return nil;
    }

    void *exception = NULL;
    void *result = runtimeInvoke((const void *)methodInfo, NULL, NULL, &exception);
    if (exception) {
        if (error) *error = [NSString stringWithFormat:@"FAILED_EXCEPTION：IL2CPP exception=0x%llX",
                             (unsigned long long)(uintptr_t)exception];
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[runtime-method-call] exception methodInfo=0x%llX exception=0x%llX",
                                             (unsigned long long)methodInfo,
                                             (unsigned long long)(uintptr_t)exception]];
        return nil;
    }

    NSDictionary *output = @{
        @"status": @"SUCCESS",
        @"methodInfo": @(methodInfo),
        @"methodPointer": resolved[@"methodPointer"] ?: @0,
        @"pointerSource": resolved[@"pointerSource"] ?: @"unavailable",
        @"methodFlags": @(methodFlags),
        @"implFlags": @(implFlags),
        @"static": @YES,
        @"result": @((uintptr_t)result),
    };
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[runtime-method-call] SUCCESS %@!%@.%@::%@/0 methodInfo=0x%llX",
                                         assembly ?: @"",
                                         namespaceName ?: @"",
                                         className ?: @"",
                                         methodName ?: @"",
                                         (unsigned long long)methodInfo]];
    return output;
}

@end
