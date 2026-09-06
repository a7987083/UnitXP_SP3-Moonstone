#import "ZNIL2CPPResolver.h"
#import <mach-o/dyld.h>
#import <dlfcn.h>

typedef void *(*ZNIl2CppDomainGetFn)(void);
typedef const void **(*ZNIl2CppDomainGetAssembliesFn)(const void *, size_t *);
typedef const void *(*ZNIl2CppAssemblyGetImageFn)(const void *);
typedef const char *(*ZNIl2CppImageGetNameFn)(const void *);
typedef void *(*ZNIl2CppClassFromNameFn)(const void *, const char *, const char *);
typedef const void *(*ZNIl2CppClassGetMethodFromNameFn)(void *, const char *, int);
typedef void *(*ZNIl2CppClassGetFieldFromNameFn)(void *, const char *);
typedef size_t (*ZNIl2CppFieldGetOffsetFn)(void *);
typedef void *(*ZNIl2CppMethodGetPointerFn)(const void *);
typedef void *(*ZNIl2CppRuntimeInvokeFn)(const void *, void *, void **, void **);

@interface ZNIL2CPPResolver ()
@property(nonatomic,assign,readwrite,getter=isAvailable) BOOL available;
@property(nonatomic,copy,readwrite) NSString *unityPath;
@property(nonatomic,copy,readwrite) NSString *lastError;
@end

@implementation ZNIL2CPPResolver {
    void *_handle;
    ZNIl2CppDomainGetFn _domainGet;
    ZNIl2CppDomainGetAssembliesFn _domainGetAssemblies;
    ZNIl2CppAssemblyGetImageFn _assemblyGetImage;
    ZNIl2CppImageGetNameFn _imageGetName;
    ZNIl2CppClassFromNameFn _classFromName;
    ZNIl2CppClassGetMethodFromNameFn _classGetMethodFromName;
    ZNIl2CppClassGetFieldFromNameFn _classGetFieldFromName;
    ZNIl2CppFieldGetOffsetFn _fieldGetOffset;
    ZNIl2CppMethodGetPointerFn _methodGetPointer;
    ZNIl2CppRuntimeInvokeFn _runtimeInvoke;
}

+ (instancetype)sharedResolver {
    static ZNIL2CPPResolver *s;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ s = [ZNIL2CPPResolver new]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _unityPath = @"";
    _lastError = @"尚未解析";
    [self refresh];
    return self;
}

- (NSString *)findUnityPath {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *cpath = _dyld_get_image_name(i);
        if (!cpath) continue;
        NSString *path = [NSString stringWithUTF8String:cpath];
        NSString *name = path.lastPathComponent;
        if ([name isEqualToString:@"UnityFramework"] ||
            [path rangeOfString:@"UnityFramework.framework/UnityFramework" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return path;
        }
    }
    return @"";
}

- (void *)resolveSymbol:(const char *)name {
    if (!name) return NULL;
    void *p = _handle ? dlsym(_handle, name) : NULL;
    if (!p) p = dlsym(RTLD_DEFAULT, name);
    return p;
}

- (void)clearFunctions {
    _domainGet = NULL;
    _domainGetAssemblies = NULL;
    _assemblyGetImage = NULL;
    _imageGetName = NULL;
    _classFromName = NULL;
    _classGetMethodFromName = NULL;
    _classGetFieldFromName = NULL;
    _fieldGetOffset = NULL;
    _methodGetPointer = NULL;
    _runtimeInvoke = NULL;
}

- (void)refresh {
    self.available = NO;
    self.lastError = @"";
    [self clearFunctions];

    NSString *path = [self findUnityPath];
    self.unityPath = path ?: @"";
    if (!path.length) {
        self.lastError = @"UnityFramework 尚未加载";
        return;
    }

#ifdef RTLD_NOLOAD
    _handle = dlopen(path.fileSystemRepresentation, RTLD_LAZY | RTLD_NOLOAD);
#else
    _handle = dlopen(path.fileSystemRepresentation, RTLD_LAZY);
#endif
    if (!_handle) _handle = NULL;

    _domainGet = (ZNIl2CppDomainGetFn)[self resolveSymbol:"il2cpp_domain_get"];
    _domainGetAssemblies = (ZNIl2CppDomainGetAssembliesFn)[self resolveSymbol:"il2cpp_domain_get_assemblies"];
    _assemblyGetImage = (ZNIl2CppAssemblyGetImageFn)[self resolveSymbol:"il2cpp_assembly_get_image"];
    _imageGetName = (ZNIl2CppImageGetNameFn)[self resolveSymbol:"il2cpp_image_get_name"];
    _classFromName = (ZNIl2CppClassFromNameFn)[self resolveSymbol:"il2cpp_class_from_name"];
    _classGetMethodFromName = (ZNIl2CppClassGetMethodFromNameFn)[self resolveSymbol:"il2cpp_class_get_method_from_name"];
    _classGetFieldFromName = (ZNIl2CppClassGetFieldFromNameFn)[self resolveSymbol:"il2cpp_class_get_field_from_name"];
    _fieldGetOffset = (ZNIl2CppFieldGetOffsetFn)[self resolveSymbol:"il2cpp_field_get_offset"];
    _methodGetPointer = (ZNIl2CppMethodGetPointerFn)[self resolveSymbol:"il2cpp_method_get_pointer"];
    _runtimeInvoke = (ZNIl2CppRuntimeInvokeFn)[self resolveSymbol:"il2cpp_runtime_invoke"];

    BOOL core = _domainGet && _domainGetAssemblies && _assemblyGetImage && _imageGetName &&
                _classFromName && _classGetMethodFromName;
    self.available = core;
    if (!core) self.lastError = @"IL2CPP Runtime API 不完整或已被隐藏";
}

- (NSDictionary<NSString *,NSNumber *> *)capabilities {
    return @{
        @"core": @(self.available),
        @"method": @(_classGetMethodFromName != NULL),
        @"methodPointer": @(_methodGetPointer != NULL),
        @"field": @(_classGetFieldFromName != NULL && _fieldGetOffset != NULL),
        @"invoke": @(_runtimeInvoke != NULL),
    };
}

- (const void *)imageForAssembly:(NSString *)assembly {
    if (!self.available || !assembly.length) return NULL;
    void *domain = _domainGet ? _domainGet() : NULL;
    if (!domain) return NULL;

    size_t count = 0;
    const void **assemblies = _domainGetAssemblies(domain, &count);
    if (!assemblies || count == 0) return NULL;

    NSString *wanted = assembly.lowercaseString;
    NSString *wantedNoDLL = [wanted hasSuffix:@".dll"] ? [wanted substringToIndex:wanted.length - 4] : wanted;

    for (size_t i = 0; i < count; i++) {
        const void *image = _assemblyGetImage(assemblies[i]);
        const char *cname = image ? _imageGetName(image) : NULL;
        if (!cname) continue;
        NSString *name = [[NSString stringWithUTF8String:cname] lowercaseString];
        NSString *nameNoDLL = [name hasSuffix:@".dll"] ? [name substringToIndex:name.length - 4] : name;
        if ([name isEqualToString:wanted] || [nameNoDLL isEqualToString:wantedNoDLL]) return image;
    }
    return NULL;
}

- (NSDictionary<NSString *,id> *)resolveMethodAssembly:(NSString *)assembly
                                              namespace:(NSString *)namespaceName
                                              className:(NSString *)className
                                                 method:(NSString *)methodName
                                          argumentCount:(NSInteger)argumentCount {
    [self refresh];
    if (!self.available) return nil;
    const void *image = [self imageForAssembly:assembly];
    if (!image) {
        self.lastError = [NSString stringWithFormat:@"找不到程序集：%@", assembly ?: @""];
        return nil;
    }

    void *klass = _classFromName(image,
                                 (namespaceName ?: @"").UTF8String,
                                 (className ?: @"").UTF8String);
    if (!klass) {
        self.lastError = [NSString stringWithFormat:@"找不到类：%@.%@", namespaceName ?: @"", className ?: @""];
        return nil;
    }

    const void *method = _classGetMethodFromName(klass, (methodName ?: @"").UTF8String, (int)argumentCount);
    if (!method) {
        self.lastError = [NSString stringWithFormat:@"找不到方法：%@/%ld", methodName ?: @"", (long)argumentCount];
        return nil;
    }

    uintptr_t methodPointer = 0;
    if (_methodGetPointer) methodPointer = (uintptr_t)_methodGetPointer(method);
    self.lastError = @"";
    return @{
        @"image": @((uintptr_t)image),
        @"class": @((uintptr_t)klass),
        @"methodInfo": @((uintptr_t)method),
        @"methodPointer": @(methodPointer),
    };
}

- (NSDictionary<NSString *,id> *)resolveFieldAssembly:(NSString *)assembly
                                             namespace:(NSString *)namespaceName
                                             className:(NSString *)className
                                                  field:(NSString *)fieldName {
    [self refresh];
    if (!self.available) return nil;
    if (!_classGetFieldFromName || !_fieldGetOffset) {
        self.lastError = @"当前 IL2CPP 未导出字段解析 API";
        return nil;
    }

    const void *image = [self imageForAssembly:assembly];
    if (!image) {
        self.lastError = [NSString stringWithFormat:@"找不到程序集：%@", assembly ?: @""];
        return nil;
    }

    void *klass = _classFromName(image,
                                 (namespaceName ?: @"").UTF8String,
                                 (className ?: @"").UTF8String);
    if (!klass) {
        self.lastError = [NSString stringWithFormat:@"找不到类：%@.%@", namespaceName ?: @"", className ?: @""];
        return nil;
    }

    void *field = _classGetFieldFromName(klass, (fieldName ?: @"").UTF8String);
    if (!field) {
        self.lastError = [NSString stringWithFormat:@"找不到字段：%@", fieldName ?: @""];
        return nil;
    }

    size_t offset = _fieldGetOffset(field);
    self.lastError = @"";
    return @{
        @"image": @((uintptr_t)image),
        @"class": @((uintptr_t)klass),
        @"fieldInfo": @((uintptr_t)field),
        @"offset": @((unsigned long long)offset),
    };
}

- (NSString *)diagnosticReport {
    NSDictionary *caps = self.capabilities;
    return [NSString stringWithFormat:
            @"IL2CPP 解析器: %@\nUnityFramework: %@\n类/方法解析: %@\n方法指针 API: %@\n字段解析: %@\nRuntime Invoke: %@\nJIT: 不依赖\n错误: %@\n",
            self.available ? @"可用" : @"不可用",
            self.unityPath.length ? self.unityPath.lastPathComponent : @"未加载",
            [caps[@"method"] boolValue] ? @"可用" : @"不可用",
            [caps[@"methodPointer"] boolValue] ? @"可用" : @"未导出",
            [caps[@"field"] boolValue] ? @"可用" : @"不可用",
            [caps[@"invoke"] boolValue] ? @"可用" : @"不可用",
            self.lastError.length ? self.lastError : @"无"];
}
@end
