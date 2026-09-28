#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach/mach.h>
#import <mach/mach_vm.h>
#include <math.h>
#include <string.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNFeatureControlModel.h"
#import "ZNStaticBinaryBuilder.h"
#import "ZNPatchCore.h"

// M5.8.5 — Unified Control Semantics
// Runtime and Static share the same public authoring contract:
//   Slider: authored value is required and means max (min=0, step=1).
//   Number: no authored value required.
// Static Number/Slider may omit Enabled. During validation we safely read the
// original MOVZ(+MOVK) / scalar FMOV immediate instruction sequence at Offset
// and use that as the Value-Cell source template.

static const NSInteger kZNM585TypeTagBase = 466000;
static const NSInteger kZNM585SliderMaxTagBase = 931000;
static const uint32_t kZNM585SliderMaxMask = UINT32_C(0xFFFC0000);
static const uint32_t kZNM585SliderMaxShift = 18u;
static NSString * const kZNM585StaticSliderMaxDefaults = @"zonoe.m5.8.5.static-slider-max.v1";

static NSString *ZNM585Trim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL ZNM585FeatureMatches(ZNBinaryPatchRow *row, NSString *featureName) {
    NSString *wanted = ZNM585Trim(featureName);
    if (!wanted.length) return NO;
    NSString *group = ZNM585Trim(row.group);
    if (!group.length || [group caseInsensitiveCompare:@"Imported"] == NSOrderedSame) group = ZNM585Trim(row.title);
    return [group caseInsensitiveCompare:wanted] == NSOrderedSame;
}

static NSString *ZNM585FeatureNameForRow(ZNBinaryPatchRow *row) {
    NSString *group = ZNM585Trim(row.group);
    if (group.length && [group caseInsensitiveCompare:@"Imported"] != NSOrderedSame) return group;
    NSString *title = ZNM585Trim(row.title);
    return title.length ? title : @"功能";
}

static NSString *ZNM585SliderDefaultsKey(NSString *featureName) {
    return [NSString stringWithFormat:@"%@.%@", kZNM585StaticSliderMaxDefaults, ZNM585Trim(featureName).lowercaseString];
}

static double ZNM585StoredSliderMax(NSString *featureName) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:ZNM585SliderDefaultsKey(featureName)];
    return [value isKindOfClass:NSNumber.class] ? [value doubleValue] : 0.0;
}

static void ZNM585StoreSliderMax(NSString *featureName, double value) {
    NSString *key = ZNM585SliderDefaultsKey(featureName);
    if (isfinite(value) && value > 0.0) [NSUserDefaults.standardUserDefaults setDouble:value forKey:key];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
}

extern "C" double ZNM585SliderMaximumForFeatureName(NSString *featureName) {
    return ZNM585StoredSliderMax(featureName ?: @"");
}

extern "C" uint32_t ZNM585SliderMaximumFlagsForFeatureName(NSString *featureName) {
    double value = ZNM585SliderMaximumForFeatureName(featureName);
    if (!isfinite(value) || value <= 0.0) return 0;
    uint32_t encoded = (uint32_t)llround(value);
    if (encoded < 1u) encoded = 1u;
    if (encoded > 0x3FFFu) encoded = 0x3FFFu;
    return (encoded << kZNM585SliderMaxShift) & kZNM585SliderMaxMask;
}

static uint32_t ZNM585Read32(const uint8_t *p) { uint32_t v=0; memcpy(&v,p,4); return v; }
static BOOL ZNM585IsMOVZ(uint32_t i) { return (i & 0x7F800000u) == 0x52800000u; }
static BOOL ZNM585IsMOVK(uint32_t i) { return (i & 0x7F800000u) == 0x72800000u; }
static BOOL ZNM585IsScalarFMOVImm(uint32_t i) { return (i & 0xFF201FE0u) == 0x1E201000u && ((((i>>22)&3u)==0u) || (((i>>22)&3u)==1u)); }

static NSString *ZNM585Hex(NSData *data) {
    const uint8_t *bytes=(const uint8_t *)data.bytes;
    NSMutableString *s=[NSMutableString stringWithCapacity:data.length*2];
    for (NSUInteger i=0;i<data.length;i++) [s appendFormat:@"%02X",bytes[i]];
    return s;
}

static BOOL ZNM585ParseRVA(NSString *text, uint64_t *out) {
    NSString *s=ZNM585Trim(text).lowercaseString;
    if (!s.length) return NO;
    const char *c=s.UTF8String; char *end=NULL; errno=0;
    unsigned long long v=strtoull(c,&end,0);
    if (errno || end==c || (end&&*end)) { errno=0; end=NULL; v=strtoull(c,&end,16); }
    if (errno || end==c || (end&&*end)) return NO;
    if (out) *out=v;
    return YES;
}

static NSData *ZNM585ReadValueTemplate(NSString *target, uint64_t rva, NSString **error) {
    uintptr_t address=[[ZNModuleManager sharedManager] runtimeAddressForModule:target rva:rva];
    if (!address) { if(error)*error=@"Offset 无法解析到运行时地址"; return nil; }
    uint8_t bytes[16]={0}; mach_vm_size_t copied=0;
    kern_return_t kr=mach_vm_read_overwrite(mach_task_self(), (mach_vm_address_t)address, sizeof(bytes), (mach_vm_address_t)bytes, &copied);
    if (kr!=KERN_SUCCESS || copied<4) { if(error)*error=[NSString stringWithFormat:@"读取 Offset 原始指令失败 kr=%d",kr]; return nil; }
    uint32_t first=ZNM585Read32(bytes);
    NSUInteger length=0;
    if (ZNM585IsMOVZ(first)) {
        length=4;
        BOOL is64=(first&0x80000000u)!=0; uint32_t rd=first&31u;
        for (NSUInteger off=4; off+4<=MIN((NSUInteger)copied,sizeof(bytes)); off+=4) {
            uint32_t insn=ZNM585Read32(bytes+off);
            if (!ZNM585IsMOVK(insn) || (((insn&0x80000000u)!=0)!=is64) || (insn&31u)!=rd) break;
            length+=4;
        }
    } else if (ZNM585IsScalarFMOVImm(first)) {
        length=4;
    } else {
        if (error) *error=[NSString stringWithFormat:@"Offset 原始指令 0x%08X 不是 MOVZ(+MOVK) / scalar FMOV #imm，无法自动建立 Number/Slider Value Cell",first];
        return nil;
    }
    return [NSData dataWithBytes:bytes length:length];
}

@interface ZNBinaryPatchWorkspace (ZNM585UnifiedControlSemantics)
- (BOOL)znm585_validateAll:(NSString **)error;
@end

@implementation ZNBinaryPatchWorkspace (ZNM585UnifiedControlSemantics)
- (BOOL)znm585_validateAll:(NSString **)error {
    for (ZNBinaryPatchRow *row in self.rows) {
        if (!row.offsetText.length || row.enabledText.length) continue;
        ZNFeatureControlType type=row.featureControlType;
        if (type!=ZNFeatureControlTypeNumber && type!=ZNFeatureControlTypeSlider) continue;
        uint64_t rva=0;
        if (!ZNM585ParseRVA(row.offsetText,&rva)) continue;
        NSString *target=(row.explicitTarget&&row.target.length)?row.target:self.defaultTarget;
        NSString *local=nil;
        NSData *templ=ZNM585ReadValueTemplate(target,rva,&local);
        if (!templ.length) {
            row.statusText=[NSString stringWithFormat:@"❌ %@",local?:@"自动读取 Value 模板失败"];
            if (error) *error=local?:@"自动读取 Value 模板失败";
            return NO;
        }
        row.enabledText=ZNM585Hex(templ);
        row.statusText=@"已从 Offset 原始指令自动建立 Value 模板";
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m5.8.5-static] auto-template %@+%@ bytes=%lu",target,row.offsetText,(unsigned long)templ.length]];
    }
    return [self znm585_validateAll:error];
}
@end

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
- (void)zn64fb_renderOther;
@end

static NSArray<NSDictionary *> *ZNM585FeatureGroups(ZNBinaryPatchWorkspace *workspace) {
    NSMutableArray *order=[NSMutableArray array];
    NSMutableDictionary *names=[NSMutableDictionary dictionary];
    NSMutableDictionary *rows=[NSMutableDictionary dictionary];
    for (ZNBinaryPatchRow *row in workspace.rows) {
        if (!row.offsetText.length && !row.enabledText.length && !ZNM585Trim(row.group).length && !ZNM585Trim(row.title).length) continue;
        NSString *name=ZNM585FeatureNameForRow(row); NSString *key=name.lowercaseString;
        if (!rows[key]) { rows[key]=[NSMutableArray array]; names[key]=name; [order addObject:key]; }
        [rows[key] addObject:row];
    }
    NSMutableArray *out=[NSMutableArray array];
    for (NSString *key in order) [out addObject:@{@"name":names[key]?:@"功能",@"rows":[rows[key] copy]?:@[]}];
    return out;
}

@interface ZNRuntimeMenuControllerV040 (ZNM585BuilderUI)
- (void)znm585_renderOther;
- (void)znm585_sliderMaxChanged:(UITextField *)field;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNM585BuilderUI)
- (void)znm585_renderOther {
    [self znm585_renderOther];
    ZNBinaryPatchWorkspace *workspace=[ZNBinaryPatchWorkspace sharedWorkspace];
    NSArray *features=ZNM585FeatureGroups(workspace);
    BOOL locked=workspace.hasAnyApplied||workspace.isBuilding;
    for (NSUInteger i=0;i<features.count;i++) {
        NSDictionary *feature=features[i]; NSString *name=feature[@"name"]?:@"功能";
        if ([workspace controlTypeForFeature:name]!=ZNFeatureControlTypeSlider) continue;
        UIButton *type=(UIButton *)[self.contentView viewWithTag:kZNM585TypeTagBase+(NSInteger)i];
        UIView *card=type.superview; if(!type||!card)continue;
        CGRect tf=type.frame; CGFloat fieldW=MIN(82.0,MAX(62.0,CGRectGetWidth(tf)*0.44));
        type.frame=CGRectMake(tf.origin.x,tf.origin.y,MAX(44.0,tf.size.width-fieldW-4.0),tf.size.height);
        UITextField *field=[[UITextField alloc]initWithFrame:CGRectMake(CGRectGetMaxX(type.frame)+4.0,tf.origin.y,fieldW,tf.size.height)];
        field.tag=kZNM585SliderMaxTagBase+(NSInteger)i;
        double max=ZNM585StoredSliderMax(name);
        field.text=max>0?[NSString stringWithFormat:@"%.0f",max]:@"";
        field.placeholder=@"Max";
        field.enabled=!locked;
        field.keyboardType=UIKeyboardTypeNumberPad;
        field.textAlignment=NSTextAlignmentCenter;
        field.font=[UIFont systemFontOfSize:9.0 weight:UIFontWeightSemibold];
        field.textColor=UIColor.labelColor;
        field.backgroundColor=[UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:.8];
        field.layer.cornerRadius=7.0; field.layer.borderWidth=1.0; field.layer.borderColor=[UIColor.separatorColor colorWithAlphaComponent:.7].CGColor;
        [field addTarget:self action:@selector(znm585_sliderMaxChanged:) forControlEvents:UIControlEventEditingChanged|UIControlEventEditingDidEnd];
        field.accessibilityLabel=[NSString stringWithFormat:@"%@ 滑块最大值",name];
        [card addSubview:field];
    }
}
- (void)znm585_sliderMaxChanged:(UITextField *)field {
    NSInteger index=field.tag-kZNM585SliderMaxTagBase; if(index<0)return;
    NSArray *features=ZNM585FeatureGroups([ZNBinaryPatchWorkspace sharedWorkspace]);
    if((NSUInteger)index>=features.count)return;
    NSString *name=features[(NSUInteger)index][@"name"]?:@"";
    NSDecimalNumber *n=[NSDecimalNumber decimalNumberWithString:ZNM585Trim(field.text) locale:@{NSLocaleDecimalSeparator:@"."}];
    double value=(![n isEqualToNumber:NSDecimalNumber.notANumber])?n.doubleValue:0.0;
    ZNM585StoreSliderMax(name,value);
}
@end

@interface ZNStaticBinaryBuilder (ZNM585UnifiedBuild)
+ (BOOL)znm585_buildWorkspace:(ZNBinaryPatchWorkspace *)workspace outputs:(NSArray<NSString *> **)outputs report:(NSString **)report error:(NSString **)error;
@end

@implementation ZNStaticBinaryBuilder (ZNM585UnifiedBuild)
+ (BOOL)znm585_buildWorkspace:(ZNBinaryPatchWorkspace *)workspace outputs:(NSArray<NSString *> **)outputs report:(NSString **)report error:(NSString **)error {
    NSMutableSet *checked=[NSMutableSet set];
    for (ZNBinaryPatchRow *row in workspace.rows) {
        if (!row.offsetText.length) continue;
        NSString *name=ZNM585FeatureNameForRow(row); if([checked containsObject:name.lowercaseString])continue; [checked addObject:name.lowercaseString];
        if ([workspace controlTypeForFeature:name]!=ZNFeatureControlTypeSlider) continue;
        double max=ZNM585StoredSliderMax(name);
        if (!isfinite(max)||max<=0.0) { if(error)*error=[NSString stringWithFormat:@"%@：滑块必须在生成时填写大于 0 的最大值（例如 31）",name]; return NO; }
        if (max>16383.0) { if(error)*error=[NSString stringWithFormat:@"%@：Static Slider 当前最大值上限为 16383",name]; return NO; }
    }
    return [self znm585_buildWorkspace:workspace outputs:outputs report:report error:error];
}
@end

extern "C" void ZNInstallM585UnifiedControlSemanticsDeferred(void) {
    static dispatch_once_t onceToken; dispatch_once(&onceToken, ^{
        Class workspace=NSClassFromString(@"ZNBinaryPatchWorkspace");
        Method v1=class_getInstanceMethod(workspace,@selector(validateAll:));
        Method v2=class_getInstanceMethod(workspace,@selector(znm585_validateAll:));
        if(v1&&v2)method_exchangeImplementations(v1,v2);

        Class controller=NSClassFromString(@"ZNRuntimeMenuControllerV040");
        Method r1=class_getInstanceMethod(controller,@selector(zn64fb_renderOther));
        Method r2=class_getInstanceMethod(controller,@selector(znm585_renderOther));
        if(r1&&r2)method_exchangeImplementations(r1,r2);

        Class builder=NSClassFromString(@"ZNStaticBinaryBuilder"); Class meta=object_getClass(builder);
        Method b1=class_getClassMethod(builder,@selector(buildWorkspace:outputs:report:error:));
        Method b2=class_getClassMethod(builder,@selector(znm585_buildWorkspace:outputs:report:error:));
        if(meta&&b1&&b2)method_exchangeImplementations(b1,b2);

        [[ZNRuntimeLogger sharedLogger] log:@"[m5.8.5] unified controls installed: Static Slider max + Offset-only Number/Slider auto-template"];
    });
}
