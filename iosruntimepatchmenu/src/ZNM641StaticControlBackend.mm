#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach/mach.h>
#include <math.h>
#include <string.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNFeatureControlModel.h"
#import "ZNStaticBinaryBuilder.h"
#import "ZNPatchCore.h"

// Backend only. No UIView/UIController ownership in this translation unit.
// Static Number/Slider reuse the established Value-Cell pipeline while the
// canonical M6.4.1 authoring/client renderers own every visible control.

static NSString * const kM641BackendPrefix = @"zonoe.m6.4.1.backend.v1";
static NSString * const kM641ControlPrefix = @"zonoe.m6.4.1.control.v1";
static NSString * const kM641SliderPrefix  = @"zonoe.m5.8.5.static-slider-max.v1";

static NSString *M641STrim(NSString *s){return [(s?:@"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];}
static NSString *M641SName(ZNBinaryPatchRow *r){NSString *g=M641STrim(r.group);if(g.length&&[g caseInsensitiveCompare:@"Imported"]!=NSOrderedSame)return g;NSString *t=M641STrim(r.title);return t.length?t:@"功能";}
static NSString *M641SKey(NSString *prefix,NSString *name){return [NSString stringWithFormat:@"%@.%@",prefix,M641STrim(name).lowercaseString];}
static BOOL M641SStatic(ZNBinaryPatchRow *r){NSString *v=[NSUserDefaults.standardUserDefaults stringForKey:M641SKey(kM641BackendPrefix,M641SName(r))];return [v isEqualToString:@"static"]||(!v.length&&r.enabledText.length);}
static NSString *M641SControl(ZNBinaryPatchRow *r){NSString *v=[NSUserDefaults.standardUserDefaults stringForKey:M641SKey(kM641ControlPrefix,M641SName(r))];return v?:@"";}
static uint32_t M641Read32(const uint8_t *p){uint32_t v=0;memcpy(&v,p,4);return v;}
static BOOL M641IsMOVZ(uint32_t i){return (i&0x7F800000u)==0x52800000u;}
static BOOL M641IsMOVK(uint32_t i){return (i&0x7F800000u)==0x72800000u;}
static BOOL M641IsFMOV(uint32_t i){return (i&0xFF201FE0u)==0x1E201000u&&((((i>>22)&3u)==0u)||(((i>>22)&3u)==1u));}
static NSString *M641Hex(NSData *data){const uint8_t *b=(const uint8_t *)data.bytes;NSMutableString *s=[NSMutableString stringWithCapacity:data.length*2];for(NSUInteger i=0;i<data.length;i++)[s appendFormat:@"%02X",b[i]];return s;}
static BOOL M641ParseRVA(NSString *text,uint64_t *out){NSString *s=M641STrim(text).lowercaseString;if(!s.length)return NO;const char *c=s.UTF8String;char *end=NULL;errno=0;unsigned long long v=strtoull(c,&end,0);if(errno||end==c||(end&&*end)){errno=0;end=NULL;v=strtoull(c,&end,16);}if(errno||end==c||(end&&*end))return NO;if(out)*out=(uint64_t)v;return YES;}
static NSData *M641ReadTemplate(NSString *target,uint64_t rva,NSString **error){uintptr_t addr=[[ZNModuleManager sharedManager]runtimeAddressForModule:target rva:rva];if(!addr){if(error)*error=@"Static Offset 无法解析到运行时地址";return nil;}uint8_t bytes[16]={0};vm_size_t copied=0;kern_return_t kr=vm_read_overwrite(mach_task_self(),(vm_address_t)addr,sizeof(bytes),(vm_address_t)bytes,&copied);if(kr!=KERN_SUCCESS||copied<4){if(error)*error=[NSString stringWithFormat:@"读取 Static Offset 原始指令失败 kr=%d",kr];return nil;}uint32_t first=M641Read32(bytes);NSUInteger len=0;if(M641IsMOVZ(first)){len=4;BOOL is64=(first&0x80000000u)!=0;uint32_t rd=first&31u;for(NSUInteger off=4;off+4<=MIN((NSUInteger)copied,sizeof(bytes));off+=4){uint32_t insn=M641Read32(bytes+off);if(!M641IsMOVK(insn)||(((insn&0x80000000u)!=0)!=is64)||(insn&31u)!=rd)break;len+=4;}}else if(M641IsFMOV(first)){len=4;}else{if(error)*error=[NSString stringWithFormat:@"Static Number/Slider 仅支持 MOVZ(+MOVK) / scalar FMOV immediate；当前 0x%08X。可切换 HEX 直接 Patch。",first];return nil;}return [NSData dataWithBytes:bytes length:len];}

@interface ZNBinaryPatchWorkspace (M641StaticBackend)
- (BOOL)m641s_validateAll:(NSString **)error;
@end
@implementation ZNBinaryPatchWorkspace (M641StaticBackend)
- (BOOL)m641s_validateAll:(NSString **)error{
    for(ZNBinaryPatchRow *r in self.rows){if(!r.offsetText.length||!M641SStatic(r))continue;NSString *ctl=M641SControl(r);BOOL numeric=[ctl isEqualToString:@"number"]||[ctl isEqualToString:@"slider"];if(!numeric)continue;if(r.enabledText.length)continue;uint64_t rva=0;if(!M641ParseRVA(r.offsetText,&rva))continue;NSString *target=(r.explicitTarget&&r.target.length)?r.target:self.defaultTarget;NSString *local=nil;NSData *templ=M641ReadTemplate(target,rva,&local);if(!templ.length){r.statusText=[NSString stringWithFormat:@"❌ %@",local?:@"Static Value 模板失败"];if(error)*error=local?:@"Static Value 模板失败";return NO;}r.enabledText=M641Hex(templ);r.statusText=@"Static Number/Slider 已建立 Value Cell 模板";[[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[m6.4.1-static] template %@+%@ bytes=%lu",target,r.offsetText,(unsigned long)templ.length]];}
    return [self m641s_validateAll:error];
}
@end

@interface ZNStaticBinaryBuilder (M641StaticBackend)
+ (BOOL)m641s_buildWorkspace:(ZNBinaryPatchWorkspace *)workspace outputs:(NSArray<NSString *> **)outputs report:(NSString **)report error:(NSString **)error;
@end
@implementation ZNStaticBinaryBuilder (M641StaticBackend)
+ (BOOL)m641s_buildWorkspace:(ZNBinaryPatchWorkspace *)workspace outputs:(NSArray<NSString *> **)outputs report:(NSString **)report error:(NSString **)error{
    for(ZNBinaryPatchRow *r in workspace.rows){if(!r.offsetText.length||!M641SStatic(r))continue;NSString *ctl=M641SControl(r);if(![ctl isEqualToString:@"slider"])continue;NSString *name=M641SName(r);id v=[NSUserDefaults.standardUserDefaults objectForKey:M641SKey(kM641SliderPrefix,name)];double max=[v isKindOfClass:NSNumber.class]?[v doubleValue]:0;if(!isfinite(max)||max<=0){if(error)*error=[NSString stringWithFormat:@"%@：Static Slider Max 必须大于 0",name];return NO;}if(max>16383){if(error)*error=[NSString stringWithFormat:@"%@：Static Slider 当前 Max 上限 16383",name];return NO;}}
    return [self m641s_buildWorkspace:workspace outputs:outputs report:report error:error];
}
@end

extern "C" void ZNInstallM641StaticControlBackendDeferred(void){static dispatch_once_t once;dispatch_once(&once,^{Class w=NSClassFromString(@"ZNBinaryPatchWorkspace");Method a=class_getInstanceMethod(w,@selector(validateAll:)),b=class_getInstanceMethod(w,@selector(m641s_validateAll:));if(a&&b)method_exchangeImplementations(a,b);Class builder=NSClassFromString(@"ZNStaticBinaryBuilder");Method c=class_getClassMethod(builder,@selector(buildWorkspace:outputs:report:error:)),d=class_getClassMethod(builder,@selector(m641s_buildWorkspace:outputs:report:error:));if(c&&d)method_exchangeImplementations(c,d);[[ZNRuntimeLogger sharedLogger]log:@"[m6.4.1-static] backend-only Number/Slider Value Cell semantics installed"];} );}
