#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <math.h>
#include <stdint.h>
#include <string.h>

#import "ZNFeatureControlModel.h"
#import "ZNFeatureMetadataCodec.h"
#import "ZNRuntimePatchExecutor.h"
#import "ZNStaticDispatchRuntime.h"
#import "ZNStaticPatchFormat.h"
#import "ZNValueTypeModel.h"
#import "ZNPatchCore.h"

// M5.5 Static Typed Backend V2
// UI/state is independent from encoding. The adapter chooses a verified backend:
//   MOVZ(+MOVK) -> I32/U32/I64/U64
//   scalar FMOV S,#imm -> F32
//   scalar FMOV D,#imm -> F64
// Auto is inferred from the verified instruction family. Anything ambiguous or
// not exactly encodable fails closed.

@interface ZNStaticPatchRecord (ZNM55StaticPrivate)
@property(nonatomic,assign) uintptr_t imageBase;
@property(nonatomic,assign) ZN44StaticEntry *entry;
@property(nonatomic,assign) uint64_t onRVA;
@property(nonatomic,assign) BOOL payloadProtectionV2;
@end

static UIViewController *ZNM55TopController(void) {
    UIWindow *window=nil;
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes){if(![scene isKindOfClass:UIWindowScene.class]||scene.activationState!=UISceneActivationStateForegroundActive)continue;for(UIWindow *candidate in ((UIWindowScene *)scene).windows){if(candidate.isKeyWindow){window=candidate;break;}}if(window)break;}
    if(!window)window=UIApplication.sharedApplication.windows.firstObject;
    UIViewController *vc=window.rootViewController;while(vc.presentedViewController&&!vc.presentedViewController.isBeingDismissed)vc=vc.presentedViewController;return vc;
}
static void ZNM55ShowFailure(NSString *message){dispatch_async(dispatch_get_main_queue(),^{UIViewController *top=ZNM55TopController();if(!top||[top isKindOfClass:UIAlertController.class])return;UIAlertController *a=[UIAlertController alertControllerWithTitle:@"执行失败" message:message.length?message:@"执行失败" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];[top presentViewController:a animated:YES completion:nil];});}
static uint32_t ZNM55Read32(uintptr_t address){uint32_t v=0;memcpy(&v,(const void *)address,sizeof(v));return v;}
static BOOL ZNM55IsMOVZ(uint32_t i){return (i&0x7F800000u)==0x52800000u;}
static BOOL ZNM55IsMOVK(uint32_t i){return (i&0x7F800000u)==0x72800000u;}
static BOOL ZNM55IsScalarFMOVImm(uint32_t i){return (i&0xFF201FE0u)==0x1E201000u&&(((i>>22)&3u)==0u||((i>>22)&3u)==1u);}
static BOOL ZNM55DecodeBTarget(uint64_t branchRVA,uint32_t insn,uint64_t *targetRVA){if((insn&0x7C000000u)!=0x14000000u||(insn&0x80000000u))return NO;int64_t imm=(int64_t)(insn&0x03FFFFFFu);if(imm&0x02000000LL)imm|=~0x03FFFFFFLL;if(targetRVA)*targetRVA=(uint64_t)((int64_t)branchRVA+(imm<<2));return YES;}

static NSArray<NSNumber *> *ZNM55SourceAddresses(ZNStaticPatchRecord *record,NSString **error){
    if(!record||!record.entry||!record.imageBase||!record.onRVA){if(error)*error=@"Static typed record metadata unavailable";return nil;}
    if(!record.payloadProtectionV2){if(error)*error=@"Static Typed V2 当前仅支持 Protection V2 生成物";return nil;}
    uint32_t len=record.entry->enabledLength;if(!len||(len&3u)){if(error)*error=@"Enabled 长度必须为 4-byte 倍数";return nil;}NSUInteger count=len/4u;if(!count||count>32){if(error)*error=@"Enabled 指令数量超出 1-32";return nil;}
    NSMutableArray *out=[NSMutableArray arrayWithCapacity:count];uint64_t fragment=record.onRVA;
    for(NSUInteger i=0;i<count;i++){uint64_t source=fragment+(i==0?4u:0u);[out addObject:@(record.imageBase+(uintptr_t)source)];if(i+1>=count)break;uint64_t brRVA=source+4u;uint64_t next=0;if(!ZNM55DecodeBTarget(brRVA,ZNM55Read32(record.imageBase+(uintptr_t)brRVA),&next)){if(error)*error=[NSString stringWithFormat:@"Protection V2 fragment %lu branch 无法解析",(unsigned long)i];return nil;}fragment=next;}
    return out;
}

static uint32_t ZNM55ExpandF32(uint8_t imm){uint32_t sign=(imm>>7)&1u,b=(imm>>6)&1u,low=(imm>>4)&3u,frac=imm&15u;uint32_t exp=((b?0u:1u)<<7)|(b?0x7Cu:0u)|low;return(sign<<31)|(exp<<23)|(frac<<19);}
static uint64_t ZNM55ExpandF64(uint8_t imm){uint64_t sign=(imm>>7)&1u,b=(imm>>6)&1u,low=(imm>>4)&3u,frac=imm&15u;uint64_t exp=((b?0ULL:1ULL)<<10)|(b?0x3FCULL:0ULL)|low;return(sign<<63)|(exp<<52)|(frac<<48);}
static BOOL ZNM55FMOVImmForValue(double input,BOOL f64,uint8_t *outImm){
    if(!isfinite(input))return NO;
    if(f64){uint64_t target=0;memcpy(&target,&input,sizeof(target));for(unsigned imm=0;imm<256;imm++){if(ZNM55ExpandF64((uint8_t)imm)==target){if(outImm)*outImm=(uint8_t)imm;return YES;}}return NO;}
    float f=(float)input;uint32_t target=0;memcpy(&target,&f,sizeof(target));for(unsigned imm=0;imm<256;imm++){if(ZNM55ExpandF32((uint8_t)imm)==target){if(outImm)*outImm=(uint8_t)imm;return YES;}}return NO;
}

static BOOL ZNM55ScanSigned(NSString *text,long long *out){NSScanner *s=[NSScanner scannerWithString:text?:@""];long long v=0;if(![s scanLongLong:&v]||!s.isAtEnd)return NO;if(out)*out=v;return YES;}
static BOOL ZNM55ScanUnsigned(NSString *text,unsigned long long *out){NSString *t=[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!t.length||[t hasPrefix:@"-"])return NO;NSScanner *s=[NSScanner scannerWithString:t];unsigned long long v=0;if(![s scanUnsignedLongLong:&v]||!s.isAtEnd)return NO;if(out)*out=v;return YES;}
static ZNPatchActionDescriptor *ZNM55InstructionAction(ZNStaticPatchRecord *record,uintptr_t address,uint32_t oldInsn,uint32_t newInsn,NSString *kind,NSUInteger slot){if(oldInsn==newInsn)return nil;ZNPatchActionDescriptor *a=[[ZNPatchActionDescriptor alloc]initWithIdentifier:[NSString stringWithFormat:@"m55-static-%@-%u-%lu",kind,record.patchID,(unsigned long)slot] type:ZNPatchActionTypeBytes];a.resolvedAddress=address;a.zn_expectedBytes=[NSData dataWithBytes:&oldInsn length:4];a.zn_patchBytes=[NSData dataWithBytes:&newInsn length:4];a.zn_targetWritable=NO;return a;}

static NSArray<ZNPatchActionDescriptor *> *ZNM55MOVActions(ZNStaticPatchRecord *record,NSArray<NSNumber *> *addresses,ZNValueType type,NSString *text,NSString **error){
    uint32_t first=ZNM55Read32((uintptr_t)addresses.firstObject.unsignedLongLongValue);BOOL is64=(first&0x80000000u)!=0;
    if(!ZNM55IsMOVZ(first)){if(error)*error=[NSString stringWithFormat:@"整数后端要求 MOVZ，当前 0x%08X",first];return nil;}
    if((type==ZNValueTypeI32||type==ZNValueTypeU32)&&is64){if(error)*error=@"I32/U32 与 X 寄存器 MOV 不匹配";return nil;}
    if((type==ZNValueTypeI64||type==ZNValueTypeU64)&&!is64){if(error)*error=@"I64/U64 与 W 寄存器 MOV 不匹配";return nil;}
    uint64_t raw=0;ZNValueType resolved=type;
    if(resolved==ZNValueTypeAuto)resolved=is64?ZNValueTypeI64:ZNValueTypeI32;
    if(resolved==ZNValueTypeI32||resolved==ZNValueTypeI64){long long v=0;if(!ZNM55ScanSigned(text,&v)){if(error)*error=@"不是有效有符号整数";return nil;}if(resolved==ZNValueTypeI32&&(v<INT32_MIN||v>INT32_MAX)){if(error)*error=@"超出 I32 范围";return nil;}raw=resolved==ZNValueTypeI32?(uint64_t)(uint32_t)(int32_t)v:(uint64_t)v;}
    else if(resolved==ZNValueTypeU32||resolved==ZNValueTypeU64){unsigned long long v=0;if(!ZNM55ScanUnsigned(text,&v)){if(error)*error=@"不是有效无符号整数";return nil;}if(resolved==ZNValueTypeU32&&v>UINT32_MAX){if(error)*error=@"超出 U32 范围";return nil;}raw=(uint64_t)v;}
    else{if(error)*error=@"浮点 Value Type 不能使用 MOVZ/MOVK 后端";return nil;}
    uint32_t rd=first&31u,covered=0;NSMutableArray *moves=[NSMutableArray array];
    for(NSUInteger i=0;i<addresses.count;i++){uintptr_t address=(uintptr_t)addresses[i].unsignedLongLongValue;uint32_t insn=ZNM55Read32(address);BOOL compatible=i==0?ZNM55IsMOVZ(insn):ZNM55IsMOVK(insn);if(!compatible)break;if((((insn&0x80000000u)!=0)!=is64)||(insn&31u)!=rd)break;uint32_t hw=(insn>>21)&3u;if(!is64&&hw>1u)break;covered|=1u<<hw;[moves addObject:@{@"address":@(address),@"instruction":@(insn),@"hw":@(hw)}];}
    uint32_t chunks=is64?4u:2u;for(uint32_t hw=0;hw<chunks;hw++){uint16_t chunk=(uint16_t)((raw>>(hw*16u))&0xFFFFu);if(chunk&&!(covered&(1u<<hw))){if(error)*error=[NSString stringWithFormat:@"值 0x%llX 需要 MOVK LSL #%u，但 Enabled 没有该槽位",(unsigned long long)raw,hw*16u];return nil;}}
    NSMutableArray *actions=[NSMutableArray array];for(NSUInteger i=0;i<moves.count;i++){NSDictionary *m=moves[i];uintptr_t address=[m[@"address"] unsignedLongLongValue];uint32_t old=[m[@"instruction"] unsignedIntValue],hw=[m[@"hw"] unsignedIntValue];uint16_t chunk=(uint16_t)((raw>>(hw*16u))&0xFFFFu);uint32_t next=(old&~0x001FFFE0u)|((uint32_t)chunk<<5);ZNPatchActionDescriptor *a=ZNM55InstructionAction(record,address,old,next,@"mov",i);if(a)[actions addObject:a];}return actions;
}

static NSArray<ZNPatchActionDescriptor *> *ZNM55FMOVActions(ZNStaticPatchRecord *record,NSArray<NSNumber *> *addresses,ZNValueType type,NSString *text,NSString **error){
    uintptr_t address=(uintptr_t)addresses.firstObject.unsignedLongLongValue;uint32_t old=ZNM55Read32(address);if(!ZNM55IsScalarFMOVImm(old)){if(error)*error=[NSString stringWithFormat:@"浮点后端要求 scalar FMOV #imm，当前 0x%08X",old];return nil;}uint32_t ftype=(old>>22)&3u;BOOL f64=ftype==1u;
    if(type==ZNValueTypeF32&&f64){if(error)*error=@"F32 与 FMOV D 不匹配";return nil;}if(type==ZNValueTypeF64&&!f64){if(error)*error=@"F64 与 FMOV S 不匹配";return nil;}if(type!=ZNValueTypeAuto&&type!=ZNValueTypeF32&&type!=ZNValueTypeF64){if(error)*error=@"整数 Value Type 不能使用 FMOV 后端";return nil;}
    NSScanner *scanner=[NSScanner scannerWithString:text?:@""];double value=0;if(![scanner scanDouble:&value]||!scanner.isAtEnd||!isfinite(value)){if(error)*error=@"不是有效浮点数";return nil;}uint8_t imm=0;if(!ZNM55FMOVImmForValue(value,f64,&imm)){if(error)*error=[NSString stringWithFormat:@"%@ 无法由单条 FMOV %@,#imm 精确表示；已拒绝盲写",text?:@"值",f64?@"D":@"S"];return nil;}uint32_t next=(old&~(0xFFu<<13))|((uint32_t)imm<<13);ZNPatchActionDescriptor *a=ZNM55InstructionAction(record,address,old,next,f64?@"f64":@"f32",0);return a?@[a]:@[];
}

static BOOL ZNM55RecordMatches(ZNStaticPatchRecord *record,NSDictionary *info){uint64_t wantedID=[info[@"featureID"] unsignedLongLongValue];NSDictionary *meta=record.entry?ZNFeatureMetadataDecodeEntry(record.entry):nil;uint64_t recordID=[meta[@"featureID"] unsignedLongLongValue];if(wantedID&&recordID)return wantedID==recordID;NSString *wanted=[info[@"title"] isKindOfClass:NSString.class]?info[@"title"]:@"";NSString *recordName=[meta[@"title"] isKindOfClass:NSString.class]?meta[@"title"]:(record.group.length?record.group:record.title);return wanted.length&&[wanted caseInsensitiveCompare:recordName?:@""]==NSOrderedSame;}

@interface ZNM55StaticTypedBinder:NSObject
@property(nonatomic,strong)NSMutableDictionary<NSString *,NSNumber *> *sliderGenerations;
+ (instancetype)shared; - (void)numberChanged:(NSNotification *)note; - (void)sliderChanged:(NSNotification *)note; - (void)actionRequested:(NSNotification *)note;
@end
@implementation ZNM55StaticTypedBinder
+ (instancetype)shared{static ZNM55StaticTypedBinder *s;static dispatch_once_t once;dispatch_once(&once,^{s=[ZNM55StaticTypedBinder new];s.sliderGenerations=[NSMutableDictionary dictionary];});return s;}
- (NSArray<ZNStaticPatchRecord *> *)recordsForInfo:(NSDictionary *)info{ZNStaticDispatchRuntime *runtime=[ZNStaticDispatchRuntime sharedRuntime];[runtime refresh];NSMutableArray *out=[NSMutableArray array];for(ZNStaticPatchRecord *r in runtime.records)if(ZNM55RecordMatches(r,info))[out addObject:r];return out;}
- (BOOL)applyText:(NSString *)text info:(NSDictionary *)info error:(NSString **)error{
    NSArray *records=[self recordsForInfo:info];if(!records.count){if(error)*error=@"找不到 Static Feature 记录";return NO;}ZNValueType authored=(ZNValueType)[info[@"valueType"] integerValue];NSMutableArray *all=[NSMutableArray array];
    for(ZNStaticPatchRecord *r in records){NSString *local=nil;NSArray *addresses=ZNM55SourceAddresses(r,&local);if(!addresses.count){if(error)*error=local;return NO;}uint32_t first=ZNM55Read32((uintptr_t)[addresses.firstObject unsignedLongLongValue]);NSArray *actions=nil;if(ZNM55IsMOVZ(first))actions=ZNM55MOVActions(r,addresses,authored,text,&local);else if(ZNM55IsScalarFMOVImm(first))actions=ZNM55FMOVActions(r,addresses,authored,text,&local);else{local=[NSString stringWithFormat:@"Auto 无法识别 Enabled 首指令 0x%08X（仅 MOVZ/MOVK 或 scalar FMOV #imm）",first];}if(!actions){if(error)*error=local?:@"Static typed encode failed";return NO;}[all addObjectsFromArray:actions];}
    ZNStaticDispatchRuntime *runtime=[ZNStaticDispatchRuntime sharedRuntime];NSMutableArray *prior=[NSMutableArray array];for(ZNStaticPatchRecord *r in records){[prior addObject:@(r.isEnabled)];if(r.isEnabled)[runtime setEnabled:NO forRecord:r error:nil];}
    if(all.count){NSString *writeError=nil;if(![[ZNRuntimePatchExecutor sharedExecutor]setActions:all enabled:YES error:&writeError]){for(NSUInteger i=0;i<records.count;i++)if([prior[i] boolValue])[runtime setEnabled:YES forRecord:records[i] error:nil];if(error)*error=writeError?:@"Static typed write failed";return NO;}}
    for(NSUInteger i=0;i<records.count;i++){ZNStaticPatchRecord *r=records[i];if([prior[i] boolValue]||YES){NSString *enableError=nil;if(![runtime setEnabled:YES forRecord:r error:&enableError]){if(error)*error=enableError?:@"Static typed variant enable failed";return NO;}}}
    [[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[m5.5-static] %@ value=%@ type=%@ records=%lu SUCCESS",info[@"title"]?:@"feature",text?:@"",ZNValueTypeName(authored),(unsigned long)records.count]];return YES;
}
- (void)numberChanged:(NSNotification *)note{NSString *text=[note.userInfo[@"valueText"] isKindOfClass:NSString.class]?note.userInfo[@"valueText"]:[note.userInfo[@"value"] description];NSString *error=nil;if(![self applyText:text info:note.userInfo?:@{} error:&error])ZNM55ShowFailure(error);}
- (void)sliderChanged:(NSNotification *)note{NSString *text=[note.userInfo[@"valueText"] isKindOfClass:NSString.class]?note.userInfo[@"valueText"]:[note.userInfo[@"value"] description];NSString *key=[note.userInfo[@"key"] isKindOfClass:NSString.class]?note.userInfo[@"key"]:(note.userInfo[@"title"]?:@"feature");NSUInteger generation=[self.sliderGenerations[key] unsignedIntegerValue]+1;self.sliderGenerations[key]=@(generation);NSDictionary *info=[note.userInfo copy]?:@{};dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.12*NSEC_PER_SEC)),dispatch_get_main_queue(),^{if([self.sliderGenerations[key] unsignedIntegerValue]!=generation)return;NSString *error=nil;if(![self applyText:text info:info error:&error])ZNM55ShowFailure(error);});}
- (void)actionRequested:(NSNotification *)note{NSArray *records=[self recordsForInfo:note.userInfo?:@{}];if(!records.count){ZNM55ShowFailure(@"找不到 Static Feature 记录");return;}ZNStaticDispatchRuntime *runtime=[ZNStaticDispatchRuntime sharedRuntime];for(ZNStaticPatchRecord *r in records){NSString *error=nil;if(![runtime setEnabled:YES forRecord:r error:&error]){ZNM55ShowFailure(error);return;}}}
@end

extern "C" void ZNInstallM55StaticTypedBindingDeferred(void){static dispatch_once_t once;dispatch_once(&once,^{
    // M5.3 installed the legacy MOV-only observer. Remove only that observer and
    // replace it with this typed adapter; its Runtime auto-execute swizzles stay.
    Class oldClass=NSClassFromString(@"ZNM53StaticControlBinder");if(oldClass&&[oldClass respondsToSelector:NSSelectorFromString(@"shared")]){id oldBinder=((id(*)(id,SEL))objc_msgSend)((id)oldClass,NSSelectorFromString(@"shared"));if(oldBinder)[NSNotificationCenter.defaultCenter removeObserver:oldBinder];}
    ZNM55StaticTypedBinder *binder=[ZNM55StaticTypedBinder shared];[NSNotificationCenter.defaultCenter addObserver:binder selector:@selector(numberChanged:) name:ZNFeatureNumberValueDidChangeNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:binder selector:@selector(sliderChanged:) name:ZNFeatureSliderValueDidChangeNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:binder selector:@selector(actionRequested:) name:ZNFeatureActionRequestedNotification object:nil];[[ZNRuntimeLogger sharedLogger]log:@"[m5.5-static] Typed MOV/FMOV Static adapter installed"];
});}
