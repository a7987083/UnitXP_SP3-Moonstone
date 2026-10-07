#import "ZNNativeRedirectRuntime.h"
#import "ZNNativeHookBackend.h"
#import "ZNPatchCore.h"

#import <mach/mach.h>
#import <libkern/OSCacheControl.h>

@interface ZNNativeRedirectRuntime ()
@property(nonatomic,copy,readwrite) NSString *lastStatus;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSData *> *originalBySource;
@property(nonatomic,strong) NSMutableSet<NSString *> *dobbyInstalledSources;
@property(nonatomic,strong) NSMutableDictionary<NSString *,ZNNativeRedirectAction *> *installedBySource;
@end

static NSString *ZNRDSourceKey(NSString *image,uint64_t rva) {
    NSString *name=[image ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!name.length)name=@"UnityFramework";
    return [NSString stringWithFormat:@"%@+0x%llX",name,(unsigned long long)rva];
}

static BOOL ZNRDEncodeBranch(uintptr_t from,uintptr_t to,BOOL link,uint32_t *out) {
    int64_t delta=(int64_t)to-(int64_t)from;
    if((delta&3LL)!=0||delta<=-(1LL<<27)||delta>=(1LL<<27))return NO;
    int64_t imm=delta>>2;
    if(out)*out=(link?0x94000000u:0x14000000u)|((uint32_t)imm&0x03FFFFFFu);
    return YES;
}
static BOOL ZNRDRead(uintptr_t address,void *out,size_t size) {
    vm_size_t copied=0;
    return vm_read_overwrite(mach_task_self(),(vm_address_t)address,(vm_size_t)size,
                             (vm_address_t)out,&copied)==KERN_SUCCESS&&copied==size;
}
static BOOL ZNRDWrite(uintptr_t address,const void *bytes,size_t size,NSString **error) {
    vm_address_t page=(vm_address_t)(address&~((uintptr_t)vm_page_size-1u));
    vm_address_t end=(vm_address_t)((address+size+vm_page_size-1u)&~((uintptr_t)vm_page_size-1u));
    vm_size_t length=end-page;
    kern_return_t kr=vm_protect(mach_task_self(),page,length,NO,VM_PROT_READ|VM_PROT_WRITE|VM_PROT_COPY);
    if(kr!=KERN_SUCCESS)kr=vm_protect(mach_task_self(),page,length,NO,VM_PROT_READ|VM_PROT_WRITE|VM_PROT_EXECUTE);
    if(kr!=KERN_SUCCESS){if(error)*error=[NSString stringWithFormat:@"Native Redirect vm_protect 失败 kr=%d",kr];return NO;}
    memcpy((void *)address,bytes,size);
    sys_icache_invalidate((void *)address,size);
    (void)vm_protect(mach_task_self(),page,length,NO,VM_PROT_READ|VM_PROT_EXECUTE);
    return YES;
}

@implementation ZNNativeRedirectRuntime
+ (instancetype)sharedRuntime {
    static ZNNativeRedirectRuntime *r;static dispatch_once_t once;
    dispatch_once(&once,^{r=[ZNNativeRedirectRuntime new];r.originalBySource=[NSMutableDictionary dictionary];r.dobbyInstalledSources=[NSMutableSet set];r.installedBySource=[NSMutableDictionary dictionary];r.lastStatus=@"Native Redirect idle";});
    return r;
}
- (BOOL)installAction:(ZNNativeRedirectAction *)action error:(NSString **)error {
    if(!action){if(error)*error=@"Native Redirect action 为空";return NO;}
    NSString *sourceKey=ZNRDSourceKey(action.sourceImage,action.sourceRVA);
    ZNNativeRedirectAction *existing=nil;
    @synchronized(self){existing=[self.installedBySource[sourceKey] copy];}
    if(existing){
        NSString *inner=nil;
        if(![self restoreInstalledForSourceImage:action.sourceImage sourceRVA:action.sourceRVA error:&inner]){
            if(error)*error=inner?:@"Native Redirect 无法替换已有临时 redirect";
            return NO;
        }
    }
    uintptr_t source=[[ZNModuleManager sharedManager] runtimeAddressForModule:action.sourceImage rva:action.sourceRVA];
    uintptr_t target=[[ZNModuleManager sharedManager] runtimeAddressForModule:action.targetImage rva:action.targetRVA];
    if(!source||!target){if(error)*error=@"Native Redirect source/target runtime address 无法解析";return NO;}
    if(action.kind==ZNNativeRedirectKindFunction){
        NSString *inner=nil;void *original=NULL;
        if(![[ZNNativeHookBackend sharedBackend] installReplacementAtAddress:source replacement:(void *)target original:&original error:&inner]){
            if(error)*error=inner?:@"Dobby function redirect 失败";return NO;
        }
        @synchronized(self){
            [self.dobbyInstalledSources addObject:sourceKey];
            self.installedBySource[sourceKey]=[action copy];
        }
        self.lastStatus=[NSString stringWithFormat:@"INSTALLED · Function Redirect · 0x%llX → 0x%llX",(unsigned long long)action.sourceRVA,(unsigned long long)action.targetRVA];
        return YES;
    }
    uint32_t original=0,branch=0;
    if(!ZNRDRead(source,&original,sizeof(original))){if(error)*error=@"Native Redirect 无法读取 source 指令";return NO;}
    if(!ZNRDEncodeBranch(source,target,action.kind==ZNNativeRedirectKindBranchLink,&branch)){
        if(error)*error=@"B/BL 超出 ARM64 ±128MB；请改用 Function Redirect";return NO;
    }
    if(!ZNRDWrite(source,&branch,sizeof(branch),error))return NO;
    @synchronized(self){
        self.originalBySource[sourceKey]=[NSData dataWithBytes:&original length:sizeof(original)];
        self.installedBySource[sourceKey]=[action copy];
    }
    self.lastStatus=[NSString stringWithFormat:@"INSTALLED · %@ · 0x%llX → 0x%llX",ZNNativeRedirectKindKey(action.kind),(unsigned long long)action.sourceRVA,(unsigned long long)action.targetRVA];
    return YES;
}
- (BOOL)restoreAction:(ZNNativeRedirectAction *)action error:(NSString **)error {
    if(!action)return YES;
    return [self restoreInstalledForSourceImage:action.sourceImage sourceRVA:action.sourceRVA error:error];
}
- (ZNNativeRedirectAction *)installedActionForSourceImage:(NSString *)sourceImage sourceRVA:(uint64_t)sourceRVA {
    NSString *key=ZNRDSourceKey(sourceImage,sourceRVA);
    @synchronized(self){return [self.installedBySource[key] copy];}
}
- (BOOL)restoreInstalledForSourceImage:(NSString *)sourceImage sourceRVA:(uint64_t)sourceRVA error:(NSString **)error {
    NSString *key=ZNRDSourceKey(sourceImage,sourceRVA);
    ZNNativeRedirectAction *installed=nil;
    BOOL dobby=NO;
    NSData *original=nil;
    @synchronized(self){
        installed=[self.installedBySource[key] copy];
        dobby=[self.dobbyInstalledSources containsObject:key];
        original=self.originalBySource[key];
    }
    if(!installed){
        self.lastStatus=@"RESTORE skipped · 当前 Source 没有临时 Redirect";
        return YES;
    }
    uintptr_t source=[[ZNModuleManager sharedManager] runtimeAddressForModule:installed.sourceImage rva:installed.sourceRVA];
    if(!source){if(error)*error=@"Native Redirect source runtime address 无法解析";return NO;}
    if(dobby){
        NSString *inner=nil;
        if(![[ZNNativeHookBackend sharedBackend] destroyHookAtAddress:source error:&inner]){if(error)*error=inner;return NO;}
        @synchronized(self){
            [self.dobbyInstalledSources removeObject:key];
            [self.installedBySource removeObjectForKey:key];
        }
        self.lastStatus=@"RESTORED · Function Redirect";
        return YES;
    }
    if(!original.length){if(error)*error=@"Native Redirect 原始指令快照不存在";return NO;}
    if(!ZNRDWrite(source,original.bytes,original.length,error))return NO;
    @synchronized(self){
        [self.originalBySource removeObjectForKey:key];
        [self.installedBySource removeObjectForKey:key];
    }
    self.lastStatus=@"RESTORED · original instruction";
    return YES;
}
- (NSData *)currentBytesForAction:(ZNNativeRedirectAction *)action count:(NSUInteger)count error:(NSString **)error {
    if(!action||!count)return nil;
    uintptr_t source=[[ZNModuleManager sharedManager] runtimeAddressForModule:action.sourceImage rva:action.sourceRVA];
    if(!source){if(error)*error=@"Native Redirect source runtime address 无法解析";return nil;}
    NSMutableData *data=[NSMutableData dataWithLength:count];
    if(!ZNRDRead(source,data.mutableBytes,count)){if(error)*error=@"Native Redirect 无法读取 source bytes";return nil;}
    return data;
}
@end
