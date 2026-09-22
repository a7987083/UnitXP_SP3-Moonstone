#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <errno.h>
#import <ctype.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNIL2CPPABIMetadata.h"
#import "ZNIL2CPPHybridFinder.h"
#import "ZNIL2CPPInstanceResolver.h"
#import "ZNIL2CPPInvokeEngine.h"
#import "ZNIL2CPPResolver.h"
#import "ZNPatchCore.h"

// M4.4.1 hotfix
// 1) Finder keyboard Search and visible Search button share one submit handler.
// 2) Finder accepts bare HEX / 0x / rva: forms and va: runtime addresses.
// 3) Patch Offset accepts bare HEX and normalizes to 0x... on Done.
// 4) /1 Unity value structs Vector2/Vector3/Quaternion/Color are supported as
//    comma/space separated float components; unsupported /1 fields show why.

static const NSInteger kZNM441LimitTag = 643001;
static const uint32_t kZNM441MethodAttributeStatic = 0x0010u;

typedef void *(*ZNM441RuntimeInvokeFn)(const void *method, void *object, void **params, void **exception);
typedef uint32_t (*ZNM441MethodGetFlagsFn)(const void *method, uint32_t *iflags);

typedef struct { float x, y; } ZNM441Vector2;
typedef struct { float x, y, z; } ZNM441Vector3;
typedef struct { float x, y, z, w; } ZNM441Quaternion;
typedef struct { float r, g, b, a; } ZNM441Color;

static NSString *ZNM441Trim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL ZNM441AllHex(NSString *value, BOOL *hasDigit) {
    NSString *s = ZNM441Trim(value);
    if (!s.length) return NO;
    BOOL digit = NO;
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) return NO;
        if (c >= '0' && c <= '9') digit = YES;
    }
    if (hasDigit) *hasDigit = digit;
    return YES;
}

static BOOL ZNM441ParseHexBody(NSString *body, uint64_t *outValue) {
    NSString *s = ZNM441Trim(body);
    if ([s.lowercaseString hasPrefix:@"0x"]) s = [s substringFromIndex:2];
    if (!s.length || !ZNM441AllHex(s, NULL)) return NO;
    const char *raw = s.UTF8String;
    if (!raw) return NO;
    errno = 0;
    char *end = NULL;
    unsigned long long value = strtoull(raw, &end, 16);
    if (errno || end == raw || (end && *end)) return NO;
    if (outValue) *outValue = (uint64_t)value;
    return YES;
}

static uintptr_t ZNM441UnityRuntimeBase(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *raw = _dyld_get_image_name(i);
        if (!raw) continue;
        NSString *path = [NSString stringWithUTF8String:raw] ?: @"";
        if ([path.lastPathComponent isEqualToString:@"UnityFramework"] ||
            [path rangeOfString:@"UnityFramework.framework/UnityFramework" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

static NSString *ZNM441NormalizeFinderQuery(NSString *raw, BOOL *isAddress, NSString **error) {
    NSString *s = ZNM441Trim(raw);
    if (isAddress) *isAddress = NO;
    if (!s.length) return s;

    NSString *lower = s.lowercaseString;
    BOOL explicitRVA = [lower hasPrefix:@"rva:"];
    BOOL explicitVA = [lower hasPrefix:@"va:"];
    BOOL explicit0x = [lower hasPrefix:@"0x"];
    BOOL hasDigit = NO;
    BOOL bareHex = ZNM441AllHex(s, &hasDigit) && hasDigit && s.length >= 5;
    if (!explicitRVA && !explicitVA && !explicit0x && !bareHex) return s;

    NSString *body = s;
    if (explicitRVA) body = [s substringFromIndex:4];
    else if (explicitVA) body = [s substringFromIndex:3];

    uint64_t value = 0;
    if (!ZNM441ParseHexBody(body, &value)) {
        if (error) *error = [NSString stringWithFormat:@"地址格式无效：%@", raw ?: @""];
        return nil;
    }
    if (explicitVA) {
        uintptr_t base = ZNM441UnityRuntimeBase();
        if (!base || value < (uint64_t)base) {
            if (error) *error = [NSString stringWithFormat:@"Runtime VA 无法换算 UnityFramework RVA：0x%llX", (unsigned long long)value];
            return nil;
        }
        value -= (uint64_t)base;
    }
    if (isAddress) *isAddress = YES;
    return [NSString stringWithFormat:@"rva:0x%llX", (unsigned long long)value];
}

static NSString *ZNM441NormalizePatchOffset(NSString *raw) {
    NSString *s = ZNM441Trim(raw);
    if (!s.length) return @"";
    NSString *lower = s.lowercaseString;
    if ([lower hasPrefix:@"rva:"]) s = [s substringFromIndex:4];
    uint64_t value = 0;
    if (!ZNM441ParseHexBody(s, &value)) return raw ?: @"";
    return [NSString stringWithFormat:@"0x%llX", (unsigned long long)value];
}

static NSString *ZNM441SimpleTypeName(NSString *typeName) {
    NSString *t = ZNM441Trim(typeName);
    NSArray<NSString *> *parts = [t componentsSeparatedByString:@"."];
    return parts.lastObject.length ? parts.lastObject : t;
}

static NSUInteger ZNM441StructComponentCount(NSString *typeName) {
    NSString *n = ZNM441Trim(typeName).lowercaseString;
    if ([n isEqualToString:@"unityengine.vector2"] || [n isEqualToString:@"vector2"]) return 2;
    if ([n isEqualToString:@"unityengine.vector3"] || [n isEqualToString:@"vector3"]) return 3;
    if ([n isEqualToString:@"unityengine.quaternion"] || [n isEqualToString:@"quaternion"]) return 4;
    if ([n isEqualToString:@"unityengine.color"] || [n isEqualToString:@"color"]) return 4;
    return 0;
}

static BOOL ZNM441ParseFloatComponents(NSString *text, NSUInteger expected, float outValues[4], NSString **error) {
    NSMutableCharacterSet *separators = [[NSCharacterSet whitespaceAndNewlineCharacterSet] mutableCopy];
    [separators addCharactersInString:@",，;；"];
    NSArray<NSString *> *rawParts = [ZNM441Trim(text) componentsSeparatedByCharactersInSet:separators];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *part in rawParts) if (ZNM441Trim(part).length) [parts addObject:ZNM441Trim(part)];
    if (parts.count != expected) {
        if (error) *error = [NSString stringWithFormat:@"需要 %lu 个浮点分量，当前=%lu", (unsigned long)expected, (unsigned long)parts.count];
        return NO;
    }
    for (NSUInteger i = 0; i < expected; i++) {
        const char *raw = parts[i].UTF8String;
        if (!raw) return NO;
        errno = 0;
        char *end = NULL;
        double value = strtod(raw, &end);
        while (end && *end && isspace((unsigned char)*end)) end++;
        if (errno || end == raw || (end && *end)) {
            if (error) *error = [NSString stringWithFormat:@"第 %lu 个分量不是有效浮点数：%@", (unsigned long)i + 1, parts[i]];
            return NO;
        }
        outValues[i] = (float)value;
    }
    return YES;
}

static void *ZNM441ResolveSymbol(NSString *unityPath, const char *name) {
    void *symbol = dlsym(RTLD_DEFAULT, name);
    if (symbol || !unityPath.length) return symbol;
#ifdef RTLD_NOLOAD
    void *handle = dlopen(unityPath.fileSystemRepresentation, RTLD_LAZY | RTLD_NOLOAD);
#else
    void *handle = dlopen(unityPath.fileSystemRepresentation, RTLD_LAZY);
#endif
    return handle ? dlsym(handle, name) : NULL;
}

static void ZNM441Walk(UIView *root, void (^block)(UIView *view)) {
    if (!root || !block) return;
    block(root);
    for (UIView *child in root.subviews) ZNM441Walk(child, block);
}

static void ZNM441EnableCardActions(UIView *root) {
    if (!root) return;
    for (UIView *view in root.subviews) {
        if ([view isKindOfClass:UIButton.class]) {
            UIButton *button = (UIButton *)view;
            NSString *title = [button titleForState:UIControlStateNormal] ?: @"";
            if ([title isEqualToString:@"测试执行"] || [title isEqualToString:@"创建方法"]) {
                button.enabled = YES;
                button.alpha = 1.0;
            }
        }
    }
}

static NSString *ZNM441UnsupportedFieldReason(NSString *placeholder) {
    NSString *p = placeholder ?: @"";
    NSString *lower = p.lowercaseString;
    if ([p containsString:@"&"]) return @"ref/out 暂不支持";
    if ([p containsString:@"*"]) return @"pointer 暂不支持";
    if ([lower containsString:@"?"]) return @"ABI 类型不可用";
    if ([lower containsString:@"list"] || [lower containsString:@"dictionary"] || [lower containsString:@"[]"] ||
        [lower containsString:@"gameobject"] || [lower containsString:@"component"] || [lower containsString:@"transform"]) {
        return @"对象参数暂不支持";
    }
    return @"对象/复杂值类型暂不支持";
}

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIWindow *hostWindow;
- (void)renderPage;
- (NSString *)zn57mf_query;
- (void)zn57mf_setQuery:(NSString *)value;
- (NSUInteger)zn60v3_limit;
- (void)zn60v3_setLimit:(NSUInteger)value;
- (void)zn60v3_setCandidates:(NSArray<NSDictionary *> *)items;
- (void)zn60v3_setSelected:(NSDictionary * _Nullable)candidate;
- (void)zn60v3_setPage:(NSInteger)page;
- (void)zn60v3_setStatus:(NSString *)status;
- (NSString *)znm43_selectedAssembly;
- (void)zn60v3_renderSearchAtWidth:(CGFloat)width;
- (void)zn60v3_renderResultsAtWidth:(CGFloat)width;
- (void)zn44_endEditing:(UITextField *)field;
@end

@interface ZNRuntimeMenuControllerV040 (ZNM441Hotfix)
- (void)znm441_renderSearchAtWidth:(CGFloat)width;
- (void)znm441_renderResultsAtWidth:(CGFloat)width;
- (void)znm441_submitSearch:(id)sender;
- (void)znm441_endEditing:(UITextField *)field;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM441Hotfix)

- (void)znm441_renderSearchAtWidth:(CGFloat)width {
    [self znm441_renderSearchAtWidth:width];

    __block UITextField *queryField = nil;
    __block UIButton *searchButton = nil;
    ZNM441Walk(self.contentView, ^(UIView *view) {
        if ([view isKindOfClass:UITextField.class]) {
            UITextField *field = (UITextField *)view;
            if (field.tag != kZNM441LimitTag && field.returnKeyType == UIReturnKeySearch) queryField = field;
        } else if ([view isKindOfClass:UIButton.class]) {
            UIButton *button = (UIButton *)view;
            if ([[button titleForState:UIControlStateNormal] isEqualToString:@"搜索"]) searchButton = button;
        }
    });

    if (queryField) {
        [queryField removeTarget:nil action:NULL forControlEvents:UIControlEventEditingDidEndOnExit];
        [queryField addTarget:self action:@selector(znm441_submitSearch:) forControlEvents:UIControlEventEditingDidEndOnExit];
    }
    if (searchButton) {
        [searchButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        [searchButton addTarget:self action:@selector(znm441_submitSearch:) forControlEvents:UIControlEventTouchUpInside];
    }
}

- (void)znm441_submitSearch:(id)sender {
    (void)sender;
    [self.hostWindow endEditing:YES];

    UITextField *limitField = (UITextField *)[self.contentView viewWithTag:kZNM441LimitTag];
    if ([limitField isKindOfClass:UITextField.class] && limitField.text.length) {
        NSInteger rawLimit = limitField.text.integerValue;
        NSUInteger value = (NSUInteger)MAX(1, MIN(1024, rawLimit));
        [self zn60v3_setLimit:value];
    }

    NSString *rawQuery = ZNM441Trim([self zn57mf_query]);
    if (!rawQuery.length) {
        [self zn60v3_setStatus:@"请输入方法名或地址"];
        [self renderPage];
        return;
    }

    BOOL addressQuery = NO;
    NSString *normalizeError = nil;
    NSString *query = ZNM441NormalizeFinderQuery(rawQuery, &addressQuery, &normalizeError);
    if (!query) {
        [self zn60v3_setStatus:normalizeError ?: @"地址格式无效"];
        [self renderPage];
        return;
    }
    if (addressQuery && ![query isEqualToString:rawQuery]) [self zn57mf_setQuery:query];

    NSString *assembly = [self znm43_selectedAssembly] ?: @"";
    NSString *expression = query;
    if (assembly.length && !addressQuery && [query rangeOfString:@"!"].location == NSNotFound) {
        expression = [NSString stringWithFormat:@"%@!%@", assembly, query];
    }

    NSString *searchError = nil;
    NSArray<NSDictionary *> *items = [[ZNIL2CPPHybridFinder sharedFinder] zn60_searchCandidates:expression
                                                                                           limit:[self zn60v3_limit]
                                                                                           error:&searchError];
    if (!items.count) {
        [self zn60v3_setStatus:searchError ?: @"没有搜索结果"];
        [self zn60v3_setPage:0];
        [self renderPage];
        return;
    }

    [self zn60v3_setCandidates:items];
    [self zn60v3_setSelected:nil];
    NSDictionary *stats = items.firstObject[@"searchStats"] ?: @{};
    NSString *scope = addressQuery ? @"地址反查" : (assembly.length ? ZNM441SimpleTypeName([assembly stringByDeletingPathExtension]) : @"全部 Assembly");
    [self zn60v3_setStatus:[NSString stringWithFormat:@"%@ · %@：%lu 个候选 · %@ classes · %.1fms",
                              scope,
                              query,
                              (unsigned long)items.count,
                              stats[@"classesScanned"] ?: @0,
                              [stats[@"elapsedMs"] doubleValue]]];
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.4.1-search] scope=%@ raw=%@ normalized=%@ limit=%lu -> %lu",
                                         scope, rawQuery, query, (unsigned long)[self zn60v3_limit], (unsigned long)items.count]];
    [self zn60v3_setPage:1];
    [self renderPage];
}

- (void)znm441_renderResultsAtWidth:(CGFloat)width {
    [self znm441_renderResultsAtWidth:width];
    ZNM441Walk(self.contentView, ^(UIView *view) {
        if (![view isKindOfClass:UITextField.class]) return;
        UITextField *field = (UITextField *)view;
        if (field.enabled) return;
        NSString *placeholder = field.placeholder ?: @"";
        NSString *lower = placeholder.lowercaseString;
        NSUInteger components = 0;
        NSString *componentHint = nil;
        if ([lower containsString:@"vector2"]) { components = 2; componentHint = @"x,y"; }
        else if ([lower containsString:@"vector3"]) { components = 3; componentHint = @"x,y,z"; }
        else if ([lower containsString:@"quaternion"]) { components = 4; componentHint = @"x,y,z,w"; }
        else if ([lower containsString:@"color"]) { components = 4; componentHint = @"r,g,b,a"; }

        if (components) {
            field.enabled = YES;
            field.alpha = 1.0;
            field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
            field.returnKeyType = UIReturnKeyDone;
            if (![placeholder containsString:componentHint]) {
                field.placeholder = placeholder.length ? [NSString stringWithFormat:@"%@ · %@", placeholder, componentHint] : componentHint;
            }
            ZNM441EnableCardActions(field.superview);
        } else if (![placeholder containsString:@"暂不支持"]) {
            NSString *reason = ZNM441UnsupportedFieldReason(placeholder);
            field.placeholder = placeholder.length ? [NSString stringWithFormat:@"%@ · %@", placeholder, reason] : reason;
        }
    });
}

- (void)znm441_endEditing:(UITextField *)field {
    if (field.tag >= 441000 && field.tag < 442000) {
        NSString *normalized = ZNM441NormalizePatchOffset(field.text ?: @"");
        field.text = normalized;
        [[ZNBinaryPatchWorkspace sharedWorkspace] updateOffset:normalized row:(NSUInteger)(field.tag - 441000)];
    }
    [self znm441_endEditing:field];
}

@end

@interface ZNIL2CPPInvokeEngine (ZNM441CommonStruct)
- (NSDictionary<NSString *, id> * _Nullable)znm441_executeAssembly:(NSString *)assembly
                                                          namespace:(NSString *)namespaceName
                                                          className:(NSString *)className
                                                             method:(NSString *)methodName
                                                      argumentCount:(NSUInteger)argumentCount
                                                     argumentValues:(NSArray<NSString *> *)argumentValues
                                                              error:(NSString * _Nullable * _Nullable)error;
@end

@implementation ZNIL2CPPInvokeEngine (ZNM441CommonStruct)

- (NSDictionary<NSString *,id> *)znm441_executeAssembly:(NSString *)assembly
                                               namespace:(NSString *)namespaceName
                                               className:(NSString *)className
                                                  method:(NSString *)methodName
                                           argumentCount:(NSUInteger)argumentCount
                                          argumentValues:(NSArray<NSString *> *)argumentValues
                                                   error:(NSString **)error {
    if (argumentCount != 1 || argumentValues.count != 1) {
        return [self znm441_executeAssembly:assembly namespace:namespaceName className:className method:methodName argumentCount:argumentCount argumentValues:argumentValues error:error];
    }

    ZNIL2CPPResolver *resolver = [ZNIL2CPPResolver sharedResolver];
    [resolver refresh];
    if (!resolver.isAvailable) {
        return [self znm441_executeAssembly:assembly namespace:namespaceName className:className method:methodName argumentCount:argumentCount argumentValues:argumentValues error:error];
    }
    NSDictionary *resolved = [resolver resolveMethodAssembly:assembly namespace:namespaceName ?: @"" className:className method:methodName argumentCount:1];
    uintptr_t methodInfo = [resolved[@"methodInfo"] unsignedLongLongValue];
    if (!methodInfo) {
        return [self znm441_executeAssembly:assembly namespace:namespaceName className:className method:methodName argumentCount:argumentCount argumentValues:argumentValues error:error];
    }

    NSMutableDictionary *candidate = [NSMutableDictionary dictionaryWithDictionary:resolved ?: @{}];
    candidate[@"methodInfo"] = @(methodInfo);
    candidate[@"assembly"] = assembly ?: @"";
    candidate[@"namespace"] = namespaceName ?: @"";
    candidate[@"class"] = className ?: @"";
    candidate[@"method"] = methodName ?: @"";
    candidate[@"argumentCount"] = @1;
    NSDictionary *abi = ZNIL2CPPDescribeMethodABI(candidate);
    NSDictionary *param = [abi[@"parameters"] firstObject];
    NSString *typeName = [param[@"name"] isKindOfClass:NSString.class] ? param[@"name"] : @"";
    NSUInteger componentCount = ZNM441StructComponentCount(typeName);
    if (!componentCount || [param[@"byRef"] boolValue] || [param[@"pointer"] boolValue]) {
        return [self znm441_executeAssembly:assembly namespace:namespaceName className:className method:methodName argumentCount:argumentCount argumentValues:argumentValues error:error];
    }
    if ([abi[@"genericStatusKnown"] boolValue] && [abi[@"generic"] boolValue]) {
        if (error) *error = @"FAILED_ARGUMENT_ABI：generic definition 暂不执行 Unity struct 参数";
        return nil;
    }

    float components[4] = {0, 0, 0, 0};
    NSString *parseError = nil;
    if (!ZNM441ParseFloatComponents(argumentValues.firstObject, componentCount, components, &parseError)) {
        if (error) *error = [NSString stringWithFormat:@"FAILED_ARGUMENT_VALUE：%@ %@", ZNM441SimpleTypeName(typeName), parseError ?: @"格式错误"];
        return nil;
    }

    ZNM441RuntimeInvokeFn runtimeInvoke = (ZNM441RuntimeInvokeFn)ZNM441ResolveSymbol(resolver.unityPath, "il2cpp_runtime_invoke");
    ZNM441MethodGetFlagsFn methodGetFlags = (ZNM441MethodGetFlagsFn)ZNM441ResolveSymbol(resolver.unityPath, "il2cpp_method_get_flags");
    if (!runtimeInvoke || !methodGetFlags) {
        if (error) *error = @"FAILED_INVOKE_UNAVAILABLE：Unity struct invoke 所需 IL2CPP API 不完整";
        return nil;
    }

    uint32_t implFlags = 0;
    uint32_t methodFlags = methodGetFlags((const void *)methodInfo, &implFlags);
    BOOL isStatic = (methodFlags & kZNM441MethodAttributeStatic) != 0;
    void *targetObject = NULL;
    NSString *instanceDiagnostics = @"";
    if (!isStatic) {
        NSString *instanceError = nil;
        targetObject = [[ZNIL2CPPInstanceResolver sharedResolver] resolveUniqueInstanceForAssembly:assembly
                                                                                        namespace:namespaceName ?: @""
                                                                                        className:className
                                                                                      diagnostics:&instanceDiagnostics
                                                                                            error:&instanceError];
        if (!targetObject) {
            if (error) *error = instanceError ?: @"FAILED_INSTANCE_REQUIRED：无法解析对象实例";
            return nil;
        }
    }

    ZNM441Vector2 v2 = { components[0], components[1] };
    ZNM441Vector3 v3 = { components[0], components[1], components[2] };
    ZNM441Quaternion q = { components[0], components[1], components[2], components[3] };
    ZNM441Color color = { components[0], components[1], components[2], components[3] };
    void *valuePtr = NULL;
    NSString *simple = ZNM441SimpleTypeName(typeName).lowercaseString;
    if ([simple isEqualToString:@"vector2"]) valuePtr = &v2;
    else if ([simple isEqualToString:@"vector3"]) valuePtr = &v3;
    else if ([simple isEqualToString:@"quaternion"]) valuePtr = &q;
    else if ([simple isEqualToString:@"color"]) valuePtr = &color;
    if (!valuePtr) {
        return [self znm441_executeAssembly:assembly namespace:namespaceName className:className method:methodName argumentCount:argumentCount argumentValues:argumentValues error:error];
    }

    void *params[1] = { valuePtr };
    void *exception = NULL;
    void *result = runtimeInvoke((const void *)methodInfo, targetObject, params, &exception);
    if (exception) {
        if (error) *error = [NSString stringWithFormat:@"FAILED_EXCEPTION：IL2CPP exception=0x%llX", (unsigned long long)(uintptr_t)exception];
        return nil;
    }

    NSDictionary *output = @{
        @"status": @"SUCCESS",
        @"methodInfo": @(methodInfo),
        @"methodPointer": resolved[@"methodPointer"] ?: @0,
        @"pointerSource": resolved[@"pointerSource"] ?: @"unavailable",
        @"methodFlags": @(methodFlags),
        @"implFlags": @(implFlags),
        @"static": @(isStatic),
        @"instance": @((uintptr_t)targetObject),
        @"instanceDiagnostics": instanceDiagnostics ?: @"",
        @"argumentCount": @1,
        @"argumentValues": argumentValues ?: @[],
        @"parameterType": typeName ?: @"",
        @"result": @((uintptr_t)result),
        @"m441CommonStruct": @YES,
    };
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.4.1-struct] SUCCESS %@!%@.%@::%@/1 type=%@ value=%@ static=%@ object=0x%llX",
                                         assembly ?: @"", namespaceName ?: @"", className ?: @"", methodName ?: @"",
                                         typeName ?: @"", argumentValues.firstObject ?: @"", isStatic ? @"YES" : @"NO",
                                         (unsigned long long)(uintptr_t)targetObject]];
    if (error) *error = nil;
    return output;
}

@end

static void ZNM441Swap(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

extern "C" void ZNInstallM441HotfixDeferred(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class menu = NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if (menu) {
            ZNM441Swap(menu, @selector(zn60v3_renderSearchAtWidth:), @selector(znm441_renderSearchAtWidth:));
            ZNM441Swap(menu, @selector(zn60v3_renderResultsAtWidth:), @selector(znm441_renderResultsAtWidth:));
            ZNM441Swap(menu, @selector(zn44_endEditing:), @selector(znm441_endEditing:));
        }
        Class engine = ZNIL2CPPInvokeEngine.class;
        ZNM441Swap(engine,
                   @selector(executeAssembly:namespace:className:method:argumentCount:argumentValues:error:),
                   @selector(znm441_executeAssembly:namespace:className:method:argumentCount:argumentValues:error:));
        [[ZNRuntimeLogger sharedLogger] log:@"[m4.4.1-hotfix] unified search route + hex normalization + common Unity /1 structs installed"];
    });
}
