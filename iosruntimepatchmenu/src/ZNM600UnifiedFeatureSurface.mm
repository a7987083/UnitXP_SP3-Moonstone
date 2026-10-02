#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <os/lock.h>
#include <atomic>
#include <math.h>
#include <string.h>
#include "dobby.h"

#import "ZNFeatureControlModel.h"
#import "ZNFeatureMetadataCodec.h"
#import "ZNIL2CPPOwningMethodResolver.h"
#import "ZNStaticDispatchRuntime.h"
#import "ZNStaticPatchFormat.h"
#import "ZNValueTypeModel.h"
#import "ZNPatchCore.h"

// M6.0 Phase 1 — Unified Feature Surface + safe Offset Hook ABI.
// IMPORTANT: this does not create a second UI hierarchy. It post-processes the
// existing Feature surface into one vertical list and replaces only the unsafe
// Offset Hook register writer installed by M5.9.1.

static const NSInteger kZNM600RuntimeCardBase = 895000;
static const NSInteger kZNM600RuntimeCardLimit = 895512;
static const NSInteger kZNM600RuntimeSectionTitle = 902100;
static const NSInteger kZNM600RuntimeSectionLine = 902101;
static const NSUInteger kZNM600MaxHooks = 512;
static const uint32_t kZNM600MethodAttrStatic = 0x0010u;

typedef uint32_t (*ZNM600MethodGetFlagsFn)(const void *method, uint32_t *iflags);

@interface ZNStaticPatchRecord (ZNM600Private)
@property(nonatomic,assign) uintptr_t imageBase;
@property(nonatomic,assign) ZN44StaticEntry *entry;
@property(nonatomic,copy) NSString *target;
@property(nonatomic,copy) NSString *title;
@property(nonatomic,copy) NSString *group;
@property(nonatomic,assign) uint32_t patchID;
@end

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
- (void)zn51_renderRuntime:(BOOL)compact;
- (void)zn40_updateContentHeight:(CGFloat)y;
@end

@interface ZNM56StaticValueCellBinder : NSObject
- (BOOL)applyText:(NSString *)text info:(NSDictionary *)info error:(NSString **)error;
@end

static NSString *ZNM600Trim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL ZNM600RecordMatches(ZNStaticPatchRecord *record, NSDictionary *info) {
    uint64_t wantedID=[info[@"featureID"] unsignedLongLongValue];
    NSDictionary *meta=record.entry?ZNFeatureMetadataDecodeEntry(record.entry):nil;
    uint64_t recordID=[meta[@"featureID"] unsignedLongLongValue];
    if(wantedID&&recordID)return wantedID==recordID;
    NSString *wanted=[info[@"title"] isKindOfClass:NSString.class]?info[@"title"]:@"";
    NSString *recordName=[meta[@"title"] isKindOfClass:NSString.class]?meta[@"title"]:(record.group.length?record.group:record.title);
    return wanted.length&&[wanted caseInsensitiveCompare:recordName?:@""]==NSOrderedSame;
}

static BOOL ZNM600RawValue(NSString *text, ZNValueType type, uint64_t *out, NSString **error) {
    NSString *s=ZNM600Trim(text);
    if(type==ZNValueTypeF32){double d=s.doubleValue;if(!s.length||!isfinite(d)){if(error)*error=@"无效 F32";return NO;}float f=(float)d;if(!isfinite(f)){if(error)*error=@"F32 超出可表示范围";return NO;}uint32_t u=0;memcpy(&u,&f,4);if(out)*out=u;return YES;}
    if(type==ZNValueTypeF64){double d=s.doubleValue;if(!s.length||!isfinite(d)){if(error)*error=@"无效 F64";return NO;}uint64_t u=0;memcpy(&u,&d,8);if(out)*out=u;return YES;}
    if(type==ZNValueTypeI32||type==ZNValueTypeI64){NSScanner *sc=[NSScanner scannerWithString:s];long long v=0;if(![sc scanLongLong:&v]||!sc.isAtEnd){if(error)*error=@"无效有符号整数";return NO;}if(type==ZNValueTypeI32&&(v<INT32_MIN||v>INT32_MAX)){if(error)*error=@"超出 I32";return NO;}if(out)*out=(uint64_t)v;return YES;}
    if(type==ZNValueTypeU32||type==ZNValueTypeU64){if([s hasPrefix:@"-"]){if(error)*error=@"无效无符号整数";return NO;}NSScanner *sc=[NSScanner scannerWithString:s];unsigned long long v=0;if(![sc scanUnsignedLongLong:&v]||!sc.isAtEnd){if(error)*error=@"无效无符号整数";return NO;}if(type==ZNValueTypeU32&&v>UINT32_MAX){if(error)*error=@"超出 U32";return NO;}if(out)*out=v;return YES;}
    if(error)*error=@"Offset Hook Value Type 无效";return NO;
}

static BOOL ZNM600ResolveIntegerRegister(uint64_t rva, uint32_t *registerIndex, NSString **error) {
    NSString *resolveError=nil;
    NSArray<NSDictionary<NSString *,id> *> *candidates=[[ZNIL2CPPOwningMethodResolver sharedResolver] resolveRVA:rva limit:8 error:&resolveError];
    NSMutableArray<NSDictionary *> *exact=[NSMutableArray array];
    for(NSDictionary *candidate in candidates?:@[]){
        if([candidate[@"intraMethodOffset"] unsignedLongLongValue]==0 &&
           [candidate[@"methodRVA"] unsignedLongLongValue]==rva) [exact addObject:candidate];
    }
    if(!exact.count){
        if(error)*error=[NSString stringWithFormat:@"Offset Hook 为避免崩溃仅支持确切方法入口：0x%llX（%@）",rva,resolveError?:@"未解析到方法入口"];
        return NO;
    }

    ZNM600MethodGetFlagsFn getFlags=(ZNM600MethodGetFlagsFn)dlsym(RTLD_DEFAULT,"il2cpp_method_get_flags");
    if(!getFlags){if(error)*error=@"IL2CPP 缺少 il2cpp_method_get_flags，无法安全判断整数参数寄存器";return NO;}

    NSNumber *resolvedStatic=nil;
    for(NSDictionary *candidate in exact){
        const void *method=(const void *)(uintptr_t)[candidate[@"methodInfo"] unsignedLongLongValue];
        if(!method)continue;
        uint32_t iflags=0;uint32_t flags=getFlags(method,&iflags);
        BOOL isStatic=(flags&kZNM600MethodAttrStatic)!=0;
        if(!resolvedStatic)resolvedStatic=@(isStatic);
        else if(resolvedStatic.boolValue!=isStatic){if(error)*error=@"该 RVA 对应共享方法且 static/instance 语义冲突，拒绝猜测 ABI";return NO;}
    }
    if(!resolvedStatic){if(error)*error=@"无法读取 IL2CPP Method flags";return NO;}

    // AArch64 IL2CPP instance methods consume X0 for `this`; their first
    // integer/pointer managed argument therefore starts at X1. Static methods
    // have no hidden `this`, so argument #1 starts at X0.
    if(registerIndex)*registerIndex=resolvedStatic.boolValue?0u:1u;
    return YES;
}

static BOOL ZNM600RequireExactMethodEntry(uint64_t rva, NSString **error) {
    NSString *resolveError=nil;
    NSArray<NSDictionary<NSString *,id> *> *candidates=[[ZNIL2CPPOwningMethodResolver sharedResolver] resolveRVA:rva limit:4 error:&resolveError];
    for(NSDictionary *candidate in candidates?:@[]){
        if([candidate[@"intraMethodOffset"] unsignedLongLongValue]==0 && [candidate[@"methodRVA"] unsignedLongLongValue]==rva)return YES;
    }
    if(error)*error=[NSString stringWithFormat:@"Offset Hook 为避免在函数内部改寄存器导致闪退，仅支持确切方法入口：0x%llX（%@）",rva,resolveError?:@"未找到 Owning Method"];
    return NO;
}

struct ZNM600HookState {
    uintptr_t address;
    uint32_t type;
    uint32_t integerRegister;
    std::atomic<uint64_t> raw;
};
static ZNM600HookState gZNM600Hooks[kZNM600MaxHooks];
static std::atomic<uint32_t> gZNM600HookCount{0};
static os_unfair_lock gZNM600HookLock=OS_UNFAIR_LOCK_INIT;

static void ZNM600InstrumentCallback(void *address,DobbyRegisterContext *ctx) {
    if(!ctx)return;
    uintptr_t a=(uintptr_t)address;
    uint32_t count=gZNM600HookCount.load(std::memory_order_acquire);
    for(uint32_t i=0;i<count;i++){
        ZNM600HookState &s=gZNM600Hooks[i];
        if(s.address!=a)continue;
        uint64_t raw=s.raw.load(std::memory_order_relaxed);
        switch((ZNValueType)s.type){
            case ZNValueTypeF32:{uint32_t u=(uint32_t)raw;float f=0;memcpy(&f,&u,4);ctx->floating.regs.q0.f.f1=f;break;}
            case ZNValueTypeF64:{double d=0;memcpy(&d,&raw,8);ctx->floating.regs.q0.d.d1=d;break;}
            case ZNValueTypeI32:case ZNValueTypeU32:
                if(s.integerRegister==0)ctx->general.regs.x0=(uint32_t)raw;
                else ctx->general.regs.x1=(uint32_t)raw;
                break;
            case ZNValueTypeI64:case ZNValueTypeU64:
                if(s.integerRegister==0)ctx->general.regs.x0=raw;
                else ctx->general.regs.x1=raw;
                break;
            default:break;
        }
        return;
    }
}

static BOOL ZNM600InstallOrUpdate(uintptr_t address, ZNValueType type, uint32_t integerRegister, uint64_t raw, NSString **error) {
    os_unfair_lock_lock(&gZNM600HookLock);
    uint32_t count=gZNM600HookCount.load(std::memory_order_relaxed);
    for(uint32_t i=0;i<count;i++){
        if(gZNM600Hooks[i].address==address){
            gZNM600Hooks[i].type=(uint32_t)type;
            gZNM600Hooks[i].integerRegister=integerRegister;
            gZNM600Hooks[i].raw.store(raw,std::memory_order_release);
            os_unfair_lock_unlock(&gZNM600HookLock);
            return YES;
        }
    }
    if(count>=kZNM600MaxHooks){os_unfair_lock_unlock(&gZNM600HookLock);if(error)*error=@"Offset Hook 数量超过 512";return NO;}
    gZNM600Hooks[count].address=address;
    gZNM600Hooks[count].type=(uint32_t)type;
    gZNM600Hooks[count].integerRegister=integerRegister;
    gZNM600Hooks[count].raw.store(raw,std::memory_order_release);
    int rc=DobbyInstrument((void *)address,ZNM600InstrumentCallback);
    if(rc!=0){gZNM600Hooks[count].address=0;os_unfair_lock_unlock(&gZNM600HookLock);if(error)*error=[NSString stringWithFormat:@"DobbyInstrument 失败 rc=%d",rc];return NO;}
    gZNM600HookCount.store(count+1,std::memory_order_release);
    os_unfair_lock_unlock(&gZNM600HookLock);
    [[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[m6.0-offset-hook] installed address=%p type=%ld integerReg=X%u",(void *)address,(long)type,integerRegister]];
    return YES;
}


static BOOL ZNM600DestroyHook(uintptr_t address, NSString **error) {
    if (!address) { if (error) *error = @"Offset Hook 地址无效"; return NO; }
    os_unfair_lock_lock(&gZNM600HookLock);
    uint32_t count=gZNM600HookCount.load(std::memory_order_relaxed);
    uint32_t found=UINT32_MAX;
    for(uint32_t i=0;i<count;i++) if(gZNM600Hooks[i].address==address){found=i;break;}
    if(found==UINT32_MAX){os_unfair_lock_unlock(&gZNM600HookLock);return YES;}

    int rc=DobbyDestroy((void *)address);
    if(rc!=0){
        os_unfair_lock_unlock(&gZNM600HookLock);
        if(error)*error=[NSString stringWithFormat:@"DobbyDestroy 失败 rc=%d",rc];
        return NO;
    }
    for(uint32_t i=found;i+1<count;i++){
        gZNM600Hooks[i].address=gZNM600Hooks[i+1].address;
        gZNM600Hooks[i].type=gZNM600Hooks[i+1].type;
        gZNM600Hooks[i].integerRegister=gZNM600Hooks[i+1].integerRegister;
        gZNM600Hooks[i].raw.store(gZNM600Hooks[i+1].raw.load(std::memory_order_relaxed),std::memory_order_relaxed);
    }
    if(count){
        uint32_t last=count-1;
        gZNM600Hooks[last].address=0;
        gZNM600Hooks[last].type=0;
        gZNM600Hooks[last].integerRegister=0;
        gZNM600Hooks[last].raw.store(0,std::memory_order_relaxed);
        gZNM600HookCount.store(last,std::memory_order_release);
    }
    os_unfair_lock_unlock(&gZNM600HookLock);
    [[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[m6.2-temp-value] restored address=%p",(void *)address]];
    return YES;
}

// M6.2 authoring-only test API. It reuses the proven M6.0 safe Offset Hook ABI
// but does not change Runtime/IL2CPP authoring. ValueType must come from imported
// metadata or an explicit user choice; Auto is never guessed.
extern "C" BOOL ZNM620TemporaryApplyOffsetValue(NSString *target,
                                                 uint64_t rva,
                                                 ZNValueType type,
                                                 NSString *text,
                                                 uintptr_t *outAddress,
                                                 NSString **error) {
    if(type==ZNValueTypeAuto){if(error)*error=@"请选择 ValueType；M6.2 不根据字节猜测类型";return NO;}
    uint64_t raw=0;NSString *local=nil;
    if(!ZNM600RawValue(text,type,&raw,&local)){if(error)*error=local;return NO;}
    if(!ZNM600RequireExactMethodEntry(rva,&local)){if(error)*error=local;return NO;}

    uint32_t integerRegister=0;
    if(type==ZNValueTypeI32||type==ZNValueTypeU32||type==ZNValueTypeI64||type==ZNValueTypeU64){
        if(!ZNM600ResolveIntegerRegister(rva,&integerRegister,&local)){if(error)*error=local;return NO;}
    }
    NSString *module=ZNM600Trim(target);
    if(!module.length)module=@"main";
    uintptr_t address=[[ZNModuleManager sharedManager] runtimeAddressForModule:module rva:rva];
    if(!address){if(error)*error=[NSString stringWithFormat:@"%@+0x%llX 无法解析运行时地址",module,rva];return NO;}
    if(!ZNM600InstallOrUpdate(address,type,integerRegister,raw,&local)){if(error)*error=local;return NO;}
    if(outAddress)*outAddress=address;
    [[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[m6.2-temp-value] applied %@+0x%llX value=%@ type=%@",module,rva,text?:@"",ZNValueTypeName(type)]];
    return YES;
}

extern "C" BOOL ZNM620TemporaryRestoreOffsetValue(uintptr_t address, NSString **error) {
    return ZNM600DestroyHook(address,error);
}

@interface ZNM56StaticValueCellBinder (ZNM600SafeOffsetABI)
- (BOOL)znm600_applyText:(NSString *)text info:(NSDictionary *)info error:(NSString **)error;
@end
@implementation ZNM56StaticValueCellBinder (ZNM600SafeOffsetABI)
- (BOOL)znm600_applyText:(NSString *)text info:(NSDictionary *)info error:(NSString **)error {
    ZNStaticDispatchRuntime *runtime=[ZNStaticDispatchRuntime sharedRuntime];[runtime refresh];
    NSMutableArray<ZNStaticPatchRecord *> *hooks=[NSMutableArray array];
    for(ZNStaticPatchRecord *r in runtime.records){
        if(ZNM600RecordMatches(r,info)&&r.entry&&(r.entry->flags&ZN44_STATIC_ENTRY_FLAG_OFFSET_HOOK_V1))[hooks addObject:r];
    }
    if(!hooks.count)return [self znm600_applyText:text info:info error:error];

    ZNValueType type=(ZNValueType)[info[@"valueType"] integerValue];
    ZNFeatureControlType control=(ZNFeatureControlType)[info[@"controlType"] integerValue];
    if(type==ZNValueTypeAuto)type=(control==ZNFeatureControlTypeSlider)?ZNValueTypeF32:ZNValueTypeI32;
    uint64_t raw=0;NSString *local=nil;
    if(!ZNM600RawValue(text,type,&raw,&local)){if(error)*error=local;return NO;}

    for(ZNStaticPatchRecord *r in hooks){
        uint64_t rva=r.entry->siteRVA;
        if(!ZNM600RequireExactMethodEntry(rva,&local)){if(error)*error=local;return NO;}
        uint32_t integerRegister=0;
        if(type==ZNValueTypeI32||type==ZNValueTypeU32||type==ZNValueTypeI64||type==ZNValueTypeU64){
            if(!ZNM600ResolveIntegerRegister(rva,&integerRegister,&local)){if(error)*error=local;return NO;}
        }
        uintptr_t address=r.imageBase+(uintptr_t)rva;
        if(!address){if(error)*error=@"Offset Hook 地址无效";return NO;}
        if(!ZNM600InstallOrUpdate(address,type,integerRegister,raw,&local)){if(error)*error=local;return NO;}
    }
    [[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[m6.0-offset-hook] value=%@ records=%lu safeABI=1",text?:@"",(unsigned long)hooks.count]];
    return YES;
}
@end

static BOOL ZNM600IsRuntimeView(UIView *view) {
    return (view.tag>=kZNM600RuntimeCardBase&&view.tag<kZNM600RuntimeCardLimit)||view.tag==kZNM600RuntimeSectionTitle||view.tag==kZNM600RuntimeSectionLine;
}

@interface ZNRuntimeMenuControllerV040 (ZNM600UnifiedFeatureSurface)
- (void)znm600_renderRuntime:(BOOL)compact;
@end
@implementation ZNRuntimeMenuControllerV040 (ZNM600UnifiedFeatureSurface)
- (void)znm600_renderRuntime:(BOOL)compact {
    [self znm600_renderRuntime:compact];

    UIView *sectionTitle=[self.contentView viewWithTag:kZNM600RuntimeSectionTitle];
    UIView *sectionLine=[self.contentView viewWithTag:kZNM600RuntimeSectionLine];
    [sectionTitle removeFromSuperview];
    [sectionLine removeFromSuperview];

    NSMutableArray<UIView *> *runtimeCards=[NSMutableArray array];
    CGFloat staticMaxY=0;
    for(UIView *view in self.contentView.subviews){
        if(view.tag>=kZNM600RuntimeCardBase&&view.tag<kZNM600RuntimeCardLimit)[runtimeCards addObject:view];
        else if(!ZNM600IsRuntimeView(view))staticMaxY=MAX(staticMaxY,CGRectGetMaxY(view.frame));
    }
    if(!runtimeCards.count)return;
    [runtimeCards sortUsingComparator:^NSComparisonResult(UIView *a,UIView *b){
        CGFloat ay=CGRectGetMinY(a.frame),by=CGRectGetMinY(b.frame);
        return ay<by?NSOrderedAscending:(ay>by?NSOrderedDescending:NSOrderedSame);
    }];
    CGFloat desiredFirst=staticMaxY>0?staticMaxY+(compact?6.0:8.0):(compact?7.0:9.0);
    CGFloat delta=desiredFirst-CGRectGetMinY(runtimeCards.firstObject.frame);
    CGFloat maxY=staticMaxY;
    for(UIView *card in runtimeCards){CGRect f=card.frame;f.origin.y+=delta;card.frame=f;maxY=MAX(maxY,CGRectGetMaxY(f));}
    [self zn40_updateContentHeight:maxY+(compact?6.0:8.0)];
    [[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[m6.0-surface] unified static/runtime layout staticMaxY=%.1f runtime=%lu",staticMaxY,(unsigned long)runtimeCards.count]];
}
@end

static void ZNM600Swap(Class cls,SEL a,SEL b){Method ma=class_getInstanceMethod(cls,a),mb=class_getInstanceMethod(cls,b);if(ma&&mb)method_exchangeImplementations(ma,mb);}

extern "C" void ZNInstallM600UnifiedFeatureSurfaceDeferred(void) {
    static dispatch_once_t once;dispatch_once(&once,^{
        Class binder=NSClassFromString(@"ZNM56StaticValueCellBinder");
        if(binder)ZNM600Swap(binder,@selector(applyText:info:error:),@selector(znm600_applyText:info:error:));
        Class controller=NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if(controller)ZNM600Swap(controller,@selector(zn51_renderRuntime:),@selector(znm600_renderRuntime:));
        [[ZNRuntimeLogger sharedLogger]log:@"[m6.0] Unified Feature Surface installed; safe Offset Hook ABI + single vertical feature layout"];
    });
}
