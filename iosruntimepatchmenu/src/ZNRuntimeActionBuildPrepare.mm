#import "ZNRuntimeActionBuildPrepare.h"

#import "ZNDirectNativeCallEngine.h"
#import "ZNIL2CPPMethodSignature.h"
#import "ZNIL2CPPResolver.h"
#import "ZNRuntimeActionModel.h"

#import <dlfcn.h>
#import <mach-o/loader.h>
#import <stdint.h>
#import <uuid/uuid.h>
#include <string.h>

static const uint32_t kZNM614MethodAttributeStatic = 0x0010u;
typedef uint32_t (*ZNM614MethodGetFlagsFn)(const void *, uint32_t *);

static NSString *ZNM614UUIDForHeader(const struct mach_header_64 *mh) {
    if(!mh || mh->magic!=MH_MAGIC_64)return @"";
    const uint8_t *cursor=(const uint8_t *)(mh+1);
    const uint8_t *limit=cursor+mh->sizeofcmds;
    if(mh->ncmds>4096 || mh->sizeofcmds>16*1024*1024)return @"";
    for(uint32_t i=0;i<mh->ncmds;i++){
        if(cursor+sizeof(struct load_command)>limit)return @"";
        const struct load_command *lc=(const struct load_command *)cursor;
        if(lc->cmdsize<sizeof(*lc)||cursor+lc->cmdsize>limit)return @"";
        if(lc->cmd==LC_UUID && lc->cmdsize>=sizeof(struct uuid_command)){
            const struct uuid_command *uc=(const struct uuid_command *)cursor;
            uuid_t bytes={0}; memcpy(bytes,uc->uuid,sizeof(bytes));
            NSUUID *uuid=[[NSUUID alloc] initWithUUIDBytes:bytes];
            return uuid.UUIDString.uppercaseString ?: @"";
        }
        cursor+=lc->cmdsize;
    }
    return @"";
}

static NSDictionary *ZNM614ResolveAction(ZNRuntimeMethodAction *action, NSString **error) {
    if(action.signatureAvailable && action.parameterTypeNames.count==action.argumentCount){
        return [[ZNIL2CPPFullSignatureResolver sharedResolver]
            resolveAssembly:action.assembly
                   namespace:action.namespaceName ?: @""
                   className:action.className
                      method:action.methodName
          parameterTypeNames:action.parameterTypeNames
                       error:error];
    }
    ZNIL2CPPResolver *resolver=[ZNIL2CPPResolver sharedResolver];
    NSDictionary *resolved=[resolver resolveMethodAssembly:action.assembly
                                                  namespace:action.namespaceName ?: @""
                                                  className:action.className
                                                     method:action.methodName
                                              argumentCount:(NSInteger)action.argumentCount];
    if(!resolved && error)*error=resolver.lastError ?: @"Runtime Action resolve 失败";
    return resolved;
}

static NSDictionary *ZNM614DescriptorForAction(ZNRuntimeMethodAction *action,
                                                ZNM614MethodGetFlagsFn getFlags,
                                                NSString **error) {
    NSString *resolveError=nil;
    NSDictionary *resolved=ZNM614ResolveAction(action,&resolveError);
    uintptr_t methodInfo=[resolved[@"methodInfo"] unsignedLongLongValue];
    uintptr_t pointer=[resolved[@"methodPointer"] unsignedLongLongValue];
    if(!methodInfo || !pointer){
        if(error)*error=resolveError ?: [NSString stringWithFormat:@"%@：缺少 MethodInfo/methodPointer",action.canonicalIdentity];
        return nil;
    }

    Dl_info info={0};
    if(dladdr((const void *)pointer,&info)==0 || !info.dli_fbase){
        if(error)*error=@"Prepared Runtime 无法定位 methodPointer 所属 Mach-O";
        return nil;
    }
    NSString *path=info.dli_fname?[NSString stringWithUTF8String:info.dli_fname]:@"";
    BOOL unity=[path.lastPathComponent isEqualToString:@"UnityFramework"] ||
               [path rangeOfString:@"UnityFramework.framework/UnityFramework"
                           options:NSCaseInsensitiveSearch].location!=NSNotFound;
    if(!unity){
        if(error)*error=[NSString stringWithFormat:@"Prepared Runtime target 不在 UnityFramework：%@",path.lastPathComponent?:@"unknown"];
        return nil;
    }

    uintptr_t base=(uintptr_t)info.dli_fbase;
    if(pointer<=base){
        if(error)*error=@"Prepared Runtime RVA 无效";
        return nil;
    }
    uint64_t rva=(uint64_t)(pointer-base);
    if((rva&3ULL)!=0){
        if(error)*error=[NSString stringWithFormat:@"Prepared Runtime RVA 未按 ARM64 对齐：0x%llX",(unsigned long long)rva];
        return nil;
    }
    NSString *uuid=ZNM614UUIDForHeader((const struct mach_header_64 *)base);
    if(!uuid.length){
        if(error)*error=@"Prepared Runtime 无法读取 UnityFramework UUID";
        return nil;
    }

    uint32_t implFlags=0;
    uint32_t flags=getFlags((const void *)methodInfo,&implFlags);
    BOOL isStatic=(flags&kZNM614MethodAttributeStatic)!=0;

    if(action.executionKind==ZNRuntimeExecutionKindDirectNativeCall){
        NSMutableDictionary *candidate=[resolved mutableCopy]?:[NSMutableDictionary dictionary];
        candidate[@"assembly"]=action.assembly?:@"";
        candidate[@"namespace"]=action.namespaceName?:@"";
        candidate[@"class"]=action.className?:@"";
        candidate[@"method"]=action.methodName?:@"";
        candidate[@"argumentCount"]=@(action.argumentCount);
        candidate[@"canonical"]=action.canonicalIdentity?:@"";
        NSString *why=nil;
        if(![[ZNDirectNativeCallEngine sharedEngine] supportsCandidate:candidate reason:&why]){
            if(error)*error=why?:@"Direct Native Call build-time ABI 校验失败";
            return nil;
        }
    }

    return @{@"rva":@(rva),
             @"uuid":uuid,
             @"staticKnown":@YES,
             @"isStatic":@(isStatic),
             @"methodFlags":@(flags),
             @"implFlags":@(implFlags)};
}

BOOL ZNBuildPrepareRuntimeActionDescriptorsV1(NSString **report, NSString **error) {
    ZNRuntimeActionStore *store=[ZNRuntimeActionStore sharedStore];
    NSArray<ZNRuntimeMethodAction *> *actions=[store actionsSnapshot];
    if(!actions.count){
        if(report)*report=@"Prepared Runtime：无待处理 action";
        return YES;
    }

    ZNIL2CPPResolver *resolver=[ZNIL2CPPResolver sharedResolver];
    [resolver refresh];
    if(!resolver.isAvailable){
        if(error)*error=@"生成客户端前 IL2CPP Runtime 必须已 Ready";
        return NO;
    }

    void *handle=NULL;
#ifdef RTLD_NOLOAD
    if(resolver.unityPath.length)handle=dlopen(resolver.unityPath.fileSystemRepresentation,RTLD_LAZY|RTLD_NOLOAD);
#else
    if(resolver.unityPath.length)handle=dlopen(resolver.unityPath.fileSystemRepresentation,RTLD_LAZY);
#endif
    ZNM614MethodGetFlagsFn getFlags=(ZNM614MethodGetFlagsFn)(handle?dlsym(handle,"il2cpp_method_get_flags"):NULL);
    if(!getFlags)getFlags=(ZNM614MethodGetFlagsFn)dlsym(RTLD_DEFAULT,"il2cpp_method_get_flags");
    if(!getFlags){
        if(handle)dlclose(handle);
        if(error)*error=@"Prepared Runtime 无法读取 il2cpp_method_get_flags";
        return NO;
    }

    NSMutableArray<NSDictionary *> *prepared=[NSMutableArray arrayWithCapacity:actions.count];
    for(ZNRuntimeMethodAction *action in actions){
        NSString *local=nil;
        NSDictionary *descriptor=ZNM614DescriptorForAction(action,getFlags,&local);
        if(!descriptor){
            if(handle)dlclose(handle);
            if(error)*error=local ?: [NSString stringWithFormat:@"%@：Prepared descriptor 失败",action.canonicalIdentity];
            return NO;
        }
        [prepared addObject:descriptor];
    }
    if(handle)dlclose(handle);

    for(NSUInteger i=0;i<prepared.count;i++){
        NSString *local=nil;
        if(![store updatePreparedDescriptor:prepared[i] atIndex:i error:&local]){
            if(error)*error=local?:@"Prepared Runtime descriptor 持久化失败";
            return NO;
        }
    }

    NSUInteger direct=0;
    for(ZNRuntimeMethodAction *a in actions)if(a.executionKind==ZNRuntimeExecutionKindDirectNativeCall)direct++;
    if(report)*report=[NSString stringWithFormat:@"Prepared Runtime：%lu actions · Direct=%lu · RVA/UUID/static",
                       (unsigned long)actions.count,(unsigned long)direct];
    return YES;
}
