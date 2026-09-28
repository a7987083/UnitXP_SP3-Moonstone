#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach/mach.h>
#import <os/lock.h>
#include <atomic>
#include <math.h>
#include <string.h>
#include "dobby.h"

#import "ZNBinaryPatchWorkspace.h"
#import "ZNFeatureControlModel.h"
#import "ZNFeatureMetadataCodec.h"
#import "ZNPatchRuntimeValidator.h"
#import "ZNStaticBinaryBuilder.h"
#import "ZNStaticDispatchRuntime.h"
#import "ZNStaticPatchFormat.h"
#import "ZNValueTypeModel.h"
#import "ZNPatchCore.h"

// M5.9.1 — Offset Hook Controls
// No second UI hierarchy is created. Existing Builder controls are rewired in place.
// Number/Slider rows no longer require the user-facing Read/Validate step and do
// not require MOVZ/MOVK/FMOV source instructions. Generation uses a 4-byte
// equivalent-original variant; runtime DobbyInstrument changes the first value
// register according to the authored Value Type.

static NSString * const kZNM591SliderMaxDefaults = @"zonoe.m5.8.5.static-slider-max.v1";
static const NSUInteger kZNM591MaxHooks = 512;

static NSString *ZNM591Trim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *ZNM591FeatureNameForRow(ZNBinaryPatchRow *row) {
    NSString *group=ZNM591Trim(row.group);
    if(group.length && [group caseInsensitiveCompare:@"Imported"]!=NSOrderedSame) return group;
    NSString *title=ZNM591Trim(row.title);
    return title.length?title:@"功能";
}

static NSString *ZNM591SliderKey(NSString *name) {
    return [NSString stringWithFormat:@"%@.%@",kZNM591SliderMaxDefaults,ZNM591Trim(name).lowercaseString];
}

static BOOL ZNM591ParseRVA(NSString *text,uint64_t *out) {
    NSString *s=ZNM591Trim(text).lowercaseString;
    if(!s.length)return NO;
    const char *c=s.UTF8String;char *end=NULL;errno=0;
    unsigned long long v=strtoull(c,&end,0);
    if(errno||end==c||(end&&*end)){errno=0;end=NULL;v=strtoull(c,&end,16);}
    if(errno||end==c||(end&&*end))return NO;
    if(out)*out=(uint64_t)v;
    return YES;
}

static NSString *ZNM591Hex(NSData *data) {
    const uint8_t *p=(const uint8_t *)data.bytes;
    NSMutableString *s=[NSMutableString stringWithCapacity:data.length*2];
    for(NSUInteger i=0;i<data.length;i++)[s appendFormat:@"%02X",p[i]];
    return s;
}

@interface ZNM591SyntheticValidator : ZNPatchRuntimeValidator
@property(nonatomic,copy) NSString *mTarget;
@property(nonatomic,assign) uint64_t mRVA;
@property(nonatomic,copy) NSData *mBytes;
@property(nonatomic,assign) uintptr_t mAddress;
@end
@implementation ZNM591SyntheticValidator
- (NSString *)target{return self.mTarget?:@"";}
- (uint64_t)rva{return self.mRVA;}
- (NSData *)patchBytes{return self.mBytes;}
- (NSData *)capturedOriginalBytes{return self.mBytes;}
- (NSData *)currentBytes{return self.mBytes;}
- (uintptr_t)runtimeAddress{return self.mAddress;}
- (BOOL)isConfigured{return YES;}
- (BOOL)isValidated{return YES;}
- (BOOL)isApplied{return NO;}
- (NSString *)lastResult{return @"M5.9.1 Offset Hook auto-prepared";}
@end

static BOOL ZNM591PrepareOffsetHookRows(ZNBinaryPatchWorkspace *workspace,NSString **error) {
    for(ZNBinaryPatchRow *row in workspace.rows){
        if(!row.offsetText.length)continue;
        ZNFeatureControlType control=row.featureControlType;
        if(control!=ZNFeatureControlTypeSlider&&control!=ZNFeatureControlTypeNumber)continue;
        if(control==ZNFeatureControlTypeSlider){
            NSString *name=ZNM591FeatureNameForRow(row);
            id stored=[NSUserDefaults.standardUserDefaults objectForKey:ZNM591SliderKey(name)];
            double max=[stored isKindOfClass:NSNumber.class]?[stored doubleValue]:0.0;
            if(!isfinite(max)||max<=0.0){if(error)*error=[NSString stringWithFormat:@"%@：滑块最大值必须大于 0",name];return NO;}
        }
        uint64_t rva=0;
        if(!ZNM591ParseRVA(row.offsetText,&rva)){if(error)*error=[NSString stringWithFormat:@"Offset 格式无效：%@",row.offsetText?:@""];return NO;}
        NSString *target=(row.explicitTarget&&row.target.length)?row.target:workspace.defaultTarget;
        uintptr_t address=[[ZNModuleManager sharedManager] runtimeAddressForModule:target rva:rva];
        if(!address){if(error)*error=[NSString stringWithFormat:@"%@+0x%llX 无法解析运行时地址",target,rva];return NO;}
        uint8_t bytes[4]={0};vm_size_t copied=0;
        kern_return_t kr=vm_read_overwrite(mach_task_self(),(vm_address_t)address,sizeof(bytes),(vm_address_t)bytes,&copied);
        if(kr!=KERN_SUCCESS||copied!=sizeof(bytes)){if(error)*error=[NSString stringWithFormat:@"%@+0x%llX 无法读取最小 4-byte 原始窗口 kr=%d",target,rva,kr];return NO;}
        NSData *data=[NSData dataWithBytes:bytes length:sizeof(bytes)];
        ZNM591SyntheticValidator *v=[ZNM591SyntheticValidator new];
        v.mTarget=target;v.mRVA=rva;v.mBytes=data;v.mAddress=address;
        row.validator=v;row.validated=YES;row.originalHex=ZNM591Hex(data);
        row.statusText=@"Offset Hook · 自动准备";
    }
    return YES;
}

@interface ZNStaticBinaryBuilder (ZNM591OffsetHookBuild)
+ (BOOL)znm591_buildWorkspace:(ZNBinaryPatchWorkspace *)workspace outputs:(NSArray<NSString *> **)outputs report:(NSString **)report error:(NSString **)error;
@end
@implementation ZNStaticBinaryBuilder (ZNM591OffsetHookBuild)
+ (BOOL)znm591_buildWorkspace:(ZNBinaryPatchWorkspace *)workspace outputs:(NSArray<NSString *> **)outputs report:(NSString **)report error:(NSString **)error {
    NSString *prepareError=nil;
    if(!ZNM591PrepareOffsetHookRows(workspace,&prepareError)){if(error)*error=prepareError?:@"Offset Hook 自动准备失败";return NO;}
    return [self znm591_buildWorkspace:workspace outputs:outputs report:report error:error];
}
@end

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
@property(nonatomic,strong) UIWindow *hostWindow;
- (void)zn64fb_renderOther;
@end

static UIButton *ZNM591FindButton(UIView *root,NSString *prefix) {
    for(UIView *v in root.subviews){
        if([v isKindOfClass:UIButton.class]){
            UIButton *b=(UIButton *)v;NSString *t=[b titleForState:UIControlStateNormal]?:@"";
            if([t hasPrefix:prefix])return b;
        }
        UIButton *nested=ZNM591FindButton(v,prefix);if(nested)return nested;
    }
    return nil;
}

@interface ZNRuntimeMenuControllerV040 (ZNM591BuilderUI)
- (void)znm591_renderOther;
@end
@implementation ZNRuntimeMenuControllerV040 (ZNM591BuilderUI)
- (void)znm591_renderOther {
    [self znm591_renderOther];
    ZNBinaryPatchWorkspace *workspace=[ZNBinaryPatchWorkspace sharedWorkspace];
    UIButton *validate=ZNM591FindButton(self.contentView,@"读取验证");
    UIView *actions=validate.superview;
    [validate removeFromSuperview];
    UIButton *apply=ZNM591FindButton(self.contentView,@"临时应用");
    if(apply&&actions&&apply.superview==actions){CGRect f=apply.frame;f.origin.x=13.0;f.size.width=CGRectGetWidth(actions.bounds)-26.0;apply.frame=f;}
    UIButton *build=ZNM591FindButton(self.contentView,@"生成新二进制");
    if(!build)build=ZNM591FindButton(self.contentView,@"正在生成");
    if(build)build.enabled=!workspace.isBuilding&&!workspace.hasAnyApplied&&workspace.filledCount>0;
}
@end

@interface ZNStaticPatchRecord (ZNM591Private)
@property(nonatomic,assign) uintptr_t imageBase;
@property(nonatomic,assign) ZN44StaticEntry *entry;
@property(nonatomic,copy) NSString *target;
@property(nonatomic,copy) NSString *title;
@property(nonatomic,copy) NSString *group;
@property(nonatomic,assign) uint32_t patchID;
@end

static BOOL ZNM591RecordMatches(ZNStaticPatchRecord *record,NSDictionary *info) {
    uint64_t wantedID=[info[@"featureID"] unsignedLongLongValue];
    NSDictionary *meta=record.entry?ZNFeatureMetadataDecodeEntry(record.entry):nil;
    uint64_t recordID=[meta[@"featureID"] unsignedLongLongValue];
    if(wantedID&&recordID)return wantedID==recordID;
    NSString *wanted=[info[@"title"] isKindOfClass:NSString.class]?info[@"title"]:@"";
    NSString *recordName=[meta[@"title"] isKindOfClass:NSString.class]?meta[@"title"]:(record.group.length?record.group:record.title);
    return wanted.length&&[wanted caseInsensitiveCompare:recordName?:@""]==NSOrderedSame;
}

struct ZNM591HookState {
    uintptr_t address;
    uint32_t type;
    std::atomic<uint64_t> raw;
};
static ZNM591HookState gZNM591Hooks[kZNM591MaxHooks];
static std::atomic<uint32_t> gZNM591HookCount{0};
static os_unfair_lock gZNM591HookLock=OS_UNFAIR_LOCK_INIT;

static void ZNM591InstrumentCallback(void *address,DobbyRegisterContext *ctx) {
    if(!ctx)return;
    uintptr_t a=(uintptr_t)address;
    uint32_t count=gZNM591HookCount.load(std::memory_order_acquire);
    for(uint32_t i=0;i<count;i++){
        ZNM591HookState &s=gZNM591Hooks[i];
        if(s.address!=a)continue;
        uint64_t raw=s.raw.load(std::memory_order_relaxed);
        switch((ZNValueType)s.type){
            case ZNValueTypeF32:{uint32_t u=(uint32_t)raw;float f=0;memcpy(&f,&u,4);ctx->floating.regs.q0.f.f1=f;break;}
            case ZNValueTypeF64:{double d=0;memcpy(&d,&raw,8);ctx->floating.regs.q0.d.d1=d;break;}
            case ZNValueTypeI32:case ZNValueTypeU32:ctx->general.regs.x0=(uint32_t)raw;break;
            case ZNValueTypeI64:case ZNValueTypeU64:ctx->general.regs.x0=raw;break;
            default:break;
        }
        return;
    }
}

static BOOL ZNM591RawValue(NSString *text,ZNValueType type,uint64_t *out,NSString **error) {
    NSString *s=ZNM591Trim(text);
    if(type==ZNValueTypeF32){double d=s.doubleValue;if(!s.length||!isfinite(d)){if(error)*error=@"无效 F32";return NO;}float f=(float)d;uint32_t u=0;memcpy(&u,&f,4);if(out)*out=u;return YES;}
    if(type==ZNValueTypeF64){double d=s.doubleValue;if(!s.length||!isfinite(d)){if(error)*error=@"无效 F64";return NO;}uint64_t u=0;memcpy(&u,&d,8);if(out)*out=u;return YES;}
    if(type==ZNValueTypeI32||type==ZNValueTypeI64){NSScanner *sc=[NSScanner scannerWithString:s];long long v=0;if(![sc scanLongLong:&v]||!sc.isAtEnd){if(error)*error=@"无效有符号整数";return NO;}if(type==ZNValueTypeI32&&(v<INT32_MIN||v>INT32_MAX)){if(error)*error=@"超出 I32";return NO;}if(out)*out=(uint64_t)v;return YES;}
    if(type==ZNValueTypeU32||type==ZNValueTypeU64){if([s hasPrefix:@"-"]){if(error)*error=@"无效无符号整数";return NO;}NSScanner *sc=[NSScanner scannerWithString:s];unsigned long long v=0;if(![sc scanUnsignedLongLong:&v]||!sc.isAtEnd){if(error)*error=@"无效无符号整数";return NO;}if(type==ZNValueTypeU32&&v>UINT32_MAX){if(error)*error=@"超出 U32";return NO;}if(out)*out=v;return YES;}
    if(error)*error=@"Offset Hook Value Type 无效";return NO;
}

static BOOL ZNM591InstallOrUpdate(uintptr_t address,ZNValueType type,uint64_t raw,NSString **error) {
    os_unfair_lock_lock(&gZNM591HookLock);
    uint32_t count=gZNM591HookCount.load(std::memory_order_relaxed);
    for(uint32_t i=0;i<count;i++){
        if(gZNM591Hooks[i].address==address){gZNM591Hooks[i].type=(uint32_t)type;gZNM591Hooks[i].raw.store(raw,std::memory_order_release);os_unfair_lock_unlock(&gZNM591HookLock);return YES;}
    }
    if(count>=kZNM591MaxHooks){os_unfair_lock_unlock(&gZNM591HookLock);if(error)*error=@"Offset Hook 数量超过 512";return NO;}
    gZNM591Hooks[count].address=address;gZNM591Hooks[count].type=(uint32_t)type;gZNM591Hooks[count].raw.store(raw,std::memory_order_release);
    int rc=DobbyInstrument((void *)address,ZNM591InstrumentCallback);
    if(rc!=0){gZNM591Hooks[count].address=0;os_unfair_lock_unlock(&gZNM591HookLock);if(error)*error=[NSString stringWithFormat:@"DobbyInstrument 失败 rc=%d",rc];return NO;}
    gZNM591HookCount.store(count+1,std::memory_order_release);
    os_unfair_lock_unlock(&gZNM591HookLock);
    [[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[m5.9.1-offset-hook] installed address=%p type=%ld",(void *)address,(long)type]];
    return YES;
}

@interface ZNM56StaticValueCellBinder : NSObject
- (BOOL)applyText:(NSString *)text info:(NSDictionary *)info error:(NSString **)error;
@end
@interface ZNM56StaticValueCellBinder (ZNM591OffsetHook)
- (BOOL)znm591_applyText:(NSString *)text info:(NSDictionary *)info error:(NSString **)error;
@end
@implementation ZNM56StaticValueCellBinder (ZNM591OffsetHook)
- (BOOL)znm591_applyText:(NSString *)text info:(NSDictionary *)info error:(NSString **)error {
    ZNStaticDispatchRuntime *runtime=[ZNStaticDispatchRuntime sharedRuntime];[runtime refresh];
    NSMutableArray<ZNStaticPatchRecord *> *hooks=[NSMutableArray array];
    for(ZNStaticPatchRecord *r in runtime.records){if(ZNM591RecordMatches(r,info)&&r.entry&&(r.entry->flags&ZN44_STATIC_ENTRY_FLAG_OFFSET_HOOK_V1))[hooks addObject:r];}
    if(!hooks.count)return [self znm591_applyText:text info:info error:error];
    ZNValueType authored=(ZNValueType)[info[@"valueType"] integerValue];
    ZNFeatureControlType control=(ZNFeatureControlType)[info[@"controlType"] integerValue];
    if(authored==ZNValueTypeAuto)authored=(control==ZNFeatureControlTypeSlider)?ZNValueTypeF32:ZNValueTypeI32;
    uint64_t raw=0;NSString *local=nil;
    if(!ZNM591RawValue(text,authored,&raw,&local)){if(error)*error=local;return NO;}
    for(ZNStaticPatchRecord *r in hooks){
        uintptr_t address=r.imageBase+(uintptr_t)r.entry->siteRVA;
        if(!address){if(error)*error=@"Offset Hook 地址无效";return NO;}
        if(!ZNM591InstallOrUpdate(address,authored,raw,&local)){if(error)*error=local;return NO;}
    }
    [[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[m5.9.1-offset-hook] value=%@ records=%lu",text?:@"",(unsigned long)hooks.count]];
    return YES;
}
@end

extern "C" void ZNInstallM591OffsetHookControlsDeferred(void) {
    static dispatch_once_t once;dispatch_once(&once,^{
        Class builder=NSClassFromString(@"ZNStaticBinaryBuilder");Class meta=object_getClass(builder);
        Method b1=class_getClassMethod(builder,@selector(buildWorkspace:outputs:report:error:));
        Method b2=class_getClassMethod(builder,@selector(znm591_buildWorkspace:outputs:report:error:));
        if(meta&&b1&&b2)method_exchangeImplementations(b1,b2);

        Class controller=NSClassFromString(@"ZNRuntimeMenuControllerV040");
        Method r1=class_getInstanceMethod(controller,@selector(zn64fb_renderOther));
        Method r2=class_getInstanceMethod(controller,@selector(znm591_renderOther));
        if(r1&&r2)method_exchangeImplementations(r1,r2);

        Class binder=NSClassFromString(@"ZNM56StaticValueCellBinder");
        Method a1=class_getInstanceMethod(binder,@selector(applyText:info:error:));
        Method a2=class_getInstanceMethod(binder,@selector(znm591_applyText:info:error:));
        if(a1&&a2)method_exchangeImplementations(a1,a2);

        [[ZNRuntimeLogger sharedLogger]log:@"[m5.9.1] Offset Hook controls installed; no user Read/Validate requirement; no MOV/FMOV hard gate"];
    });
}
