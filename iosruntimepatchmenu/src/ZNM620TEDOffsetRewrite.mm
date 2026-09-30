#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach/mach.h>
#include <math.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNFeatureControlModel.h"
#import "ZNStaticBinaryBuilder.h"
#import "ZNPatchRuntimeValidator.h"
#import "ZNPatchCore.h"

// M6.2 TED-style Offset rewrite.
//
// This intentionally replaces the M5.9.x/M6.1 Offset promotion/hook path.
// Number / Slider:
//   Offset only (Slider also needs Max). No authored Patch HEX.
//   We read the live ARM64 instruction, require a supported immediate form,
//   synthesize the builder compatibility bytes internally, and let the proven
//   Static Value Cell post-process own runtime value mutation.
// Switch / Button:
//   Offset + authored Patch HEX remain mandatory.
//
// No IL2CPP exact-method promotion, no Offset Hook backend, no second UI.

static NSString * const kZNM620SliderMaxPrefix = @"zonoe.m5.8.5.static-slider-max.v1";

static NSString *ZNM620Trim(NSString *s) {
    return [s ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *ZNM620FeatureName(ZNBinaryPatchRow *row) {
    NSString *g=ZNM620Trim(row.group);
    if(g.length && [g caseInsensitiveCompare:@"Imported"]!=NSOrderedSame) return g;
    NSString *t=ZNM620Trim(row.title);
    return t.length?t:@"功能";
}

static BOOL ZNM620ParseRVA(NSString *text,uint64_t *out) {
    NSString *s=ZNM620Trim(text).lowercaseString;
    if(!s.length)return NO;
    const char *c=s.UTF8String; char *end=NULL; errno=0;
    unsigned long long v=strtoull(c,&end,0);
    if(errno||end==c||(end&&*end)){errno=0;end=NULL;v=strtoull(c,&end,16);}
    if(errno||end==c||(end&&*end))return NO;
    if(out)*out=(uint64_t)v;
    return YES;
}

static BOOL ZNM620IsMOVZ(uint32_t i){ return (i & 0x7F800000u)==0x52800000u; }
static BOOL ZNM620IsScalarFMOVImm(uint32_t i){
    return (i & 0xFF201FE0u)==0x1E201000u && ((((i>>22)&3u)==0u)||(((i>>22)&3u)==1u));
}

static NSString *ZNM620Hex4(uint32_t insn) {
    uint8_t b[4]; memcpy(b,&insn,4);
    return [NSString stringWithFormat:@"%02X%02X%02X%02X",b[0],b[1],b[2],b[3]];
}

static NSString *ZNM620InstructionName(uint32_t insn) {
    if(ZNM620IsMOVZ(insn)) return (insn&0x80000000u)?@"MOVZ Xn,#imm":@"MOVZ Wn,#imm";
    if(ZNM620IsScalarFMOVImm(insn)) return (((insn>>22)&3u)==1u)?@"FMOV Dn,#imm":@"FMOV Sn,#imm";
    return [NSString stringWithFormat:@"unsupported 0x%08X",insn];
}

static BOOL ZNM620IsAutoValueRow(ZNBinaryPatchRow *row) {
    if(!ZNM620Trim(row.offsetText).length)return NO;
    return row.featureControlType==ZNFeatureControlTypeNumber || row.featureControlType==ZNFeatureControlTypeSlider;
}

@interface ZNM620PreparedValidator : ZNPatchRuntimeValidator
@property(nonatomic,copy) NSString *mTarget;
@property(nonatomic,assign) uint64_t mRVA;
@property(nonatomic,copy) NSData *mBytes;
@property(nonatomic,assign) uintptr_t mAddress;
@end
@implementation ZNM620PreparedValidator
- (NSString *)target{return self.mTarget?:@"";}
- (uint64_t)rva{return self.mRVA;}
- (NSData *)patchBytes{return self.mBytes;}
- (NSData *)capturedOriginalBytes{return self.mBytes;}
- (NSData *)currentBytes{return self.mBytes;}
- (uintptr_t)runtimeAddress{return self.mAddress;}
- (BOOL)isConfigured{return YES;}
- (BOOL)isValidated{return YES;}
- (BOOL)isApplied{return NO;}
- (NSString *)lastResult{return @"M6.2 TED Auto Value prepared";}
@end

static BOOL ZNM620PrepareAutoRows(ZNBinaryPatchWorkspace *workspace,NSString **error) {
    for(ZNBinaryPatchRow *row in workspace.rows) {
        if(!ZNM620IsAutoValueRow(row))continue;
        NSString *feature=ZNM620FeatureName(row);
        if(row.featureControlType==ZNFeatureControlTypeSlider) {
            NSString *key=[NSString stringWithFormat:@"%@.%@",kZNM620SliderMaxPrefix,feature.lowercaseString];
            id stored=[NSUserDefaults.standardUserDefaults objectForKey:key];
            double max=[stored isKindOfClass:NSNumber.class]?[stored doubleValue]:0.0;
            if(!isfinite(max)||max<=0.0) {
                row.statusText=@"❌ Slider Max 必须大于 0";
                if(error)*error=[NSString stringWithFormat:@"%@：Slider Max 必须大于 0",feature];
                return NO;
            }
        }

        uint64_t rva=0;
        if(!ZNM620ParseRVA(row.offsetText,&rva)) {
            row.statusText=@"❌ Offset 格式无效";
            if(error)*error=[NSString stringWithFormat:@"%@：Offset 格式无效",feature];
            return NO;
        }
        NSString *target=(row.explicitTarget&&ZNM620Trim(row.target).length)?ZNM620Trim(row.target):ZNM620Trim(workspace.defaultTarget);
        uintptr_t address=[[ZNModuleManager sharedManager]runtimeAddressForModule:target rva:rva];
        if(!address) {
            row.statusText=@"❌ Offset 无法解析到运行时地址";
            if(error)*error=[NSString stringWithFormat:@"%@：%@+0x%llX 无法解析",feature,target,rva];
            return NO;
        }

        uint32_t insn=0; vm_size_t copied=0;
        kern_return_t kr=vm_read_overwrite(mach_task_self(),(vm_address_t)address,4,(vm_address_t)&insn,&copied);
        if(kr!=KERN_SUCCESS||copied!=4) {
            row.statusText=@"❌ 无法读取 Offset 指令";
            if(error)*error=[NSString stringWithFormat:@"%@：无法读取 %@+0x%llX 指令 kr=%d",feature,target,rva,kr];
            return NO;
        }
        if(!ZNM620IsMOVZ(insn)&&!ZNM620IsScalarFMOVImm(insn)) {
            NSString *kind=ZNM620InstructionName(insn);
            row.statusText=[NSString stringWithFormat:@"❌ 自动数值不支持：%@",kind];
            if(error)*error=[NSString stringWithFormat:@"%@：Offset 0x%llX 为 %@，Number/Slider 仅支持 MOVZ(+MOVK) 或 scalar FMOV immediate",feature,rva,kind];
            return NO;
        }

        NSData *bytes=[NSData dataWithBytes:&insn length:4];
        ZNM620PreparedValidator *v=[ZNM620PreparedValidator new];
        v.mTarget=target; v.mRVA=rva; v.mBytes=bytes; v.mAddress=address;
        row.validator=v;
        row.validated=YES;
        row.originalHex=ZNM620Hex4(insn);
        // Internal builder compatibility only. This is not an authored Patch.
        row.enabledText=row.originalHex;
        row.offsetText=[NSString stringWithFormat:@"0x%llX",rva];
        row.statusText=[NSString stringWithFormat:@"✅ 自动数值 · %@ · 无需 Patch",ZNM620InstructionName(insn)];
        [[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[m6.2-ted] %@ %@+0x%llX %@",feature,target,rva,ZNM620InstructionName(insn)]];
    }
    return YES;
}

@interface ZNBinaryPatchWorkspace (ZNM620TEDValidation)
- (BOOL)znm620_validateAll:(NSString **)error;
@end
@implementation ZNBinaryPatchWorkspace (ZNM620TEDValidation)
- (BOOL)znm620_validateAll:(NSString **)error {
    if(self.hasAnyApplied){if(error)*error=@"请先恢复当前临时 Patch";return NO;}
    NSString *autoError=nil;
    if(!ZNM620PrepareAutoRows(self,&autoError)) {
        self.lastStatus=[NSString stringWithFormat:@"自动数值准备失败：%@",autoError?:@"未知错误"];
        if(error)*error=autoError?:@"自动数值准备失败";
        return NO;
    }

    NSMutableArray<ZNBinaryPatchRow *> *manual=[NSMutableArray array];
    for(ZNBinaryPatchRow *row in self.rows) {
        if(!row.offsetText.length&&!row.enabledText.length)continue;
        if(!ZNM620IsAutoValueRow(row))[manual addObject:row];
    }
    if(manual.count) {
        NSMutableArray<ZNBinaryPatchRow *> *storage=self.rows;
        NSArray *snapshot=[storage copy];
        [storage removeAllObjects]; [storage addObjectsFromArray:manual];
        NSString *manualError=nil; BOOL ok=[self znm620_validateAll:&manualError];
        [storage removeAllObjects]; [storage addObjectsFromArray:snapshot];
        if(!ok) {
            self.lastStatus=[NSString stringWithFormat:@"手写 Patch 验证失败：%@",manualError?:@"未知错误"];
            if(error)*error=manualError?:@"手写 Patch 验证失败";
            return NO;
        }
    }
    NSUInteger autoCount=0; for(ZNBinaryPatchRow *r in self.rows)if(ZNM620IsAutoValueRow(r))autoCount++;
    self.lastStatus=[NSString stringWithFormat:@"验证完成：自动数值 %lu · 手写 Patch %lu",(unsigned long)autoCount,(unsigned long)manual.count];
    return YES;
}
@end

@interface ZNStaticBinaryBuilder (ZNM620TEDBuild)
+ (BOOL)znm620_buildWorkspace:(ZNBinaryPatchWorkspace *)workspace outputs:(NSArray<NSString *> **)outputs report:(NSString **)report error:(NSString **)error;
@end
@implementation ZNStaticBinaryBuilder (ZNM620TEDBuild)
+ (BOOL)znm620_buildWorkspace:(ZNBinaryPatchWorkspace *)workspace outputs:(NSArray<NSString *> **)outputs report:(NSString **)report error:(NSString **)error {
    NSString *prepareError=nil;
    if(!ZNM620PrepareAutoRows(workspace,&prepareError)) { if(error)*error=prepareError?:@"自动数值准备失败"; return NO; }
    BOOL ok=[self znm620_buildWorkspace:workspace outputs:outputs report:report error:error];
    if(ok&&report) {
        NSString *base=*report?:@"";
        NSString *line=@"M6.2 TED Offset：Number/Slider 自动识别指令；Switch/Button 使用手写 Patch";
        *report=base.length?[base stringByAppendingFormat:@"\n%@",line]:line;
    }
    return ok;
}
@end

extern "C" void ZNInstallM620TEDOffsetRewriteDeferred(void) {
    static dispatch_once_t once; dispatch_once(&once,^{
        Class ws=NSClassFromString(@"ZNBinaryPatchWorkspace");
        Method va=class_getInstanceMethod(ws,@selector(validateAll:));
        Method vb=class_getInstanceMethod(ws,@selector(znm620_validateAll:));
        if(va&&vb)method_exchangeImplementations(va,vb);

        Class b=NSClassFromString(@"ZNStaticBinaryBuilder");
        Method ba=class_getClassMethod(b,@selector(buildWorkspace:outputs:report:error:));
        Method bb=class_getClassMethod(b,@selector(znm620_buildWorkspace:outputs:report:error:));
        if(ba&&bb)method_exchangeImplementations(ba,bb);
        [[ZNRuntimeLogger sharedLogger]log:@"[m6.2-ted] Offset rewrite installed: Number/Slider auto; Switch/Button manual Patch; no old Offset Hook / IL2CPP promotion"];
    });
}
