#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/loader.h>
#include <math.h>
#include <string.h>

#import "ZNFeatureControlModel.h"
#import "ZNFeatureMetadataCodec.h"
#import "ZNStaticDispatchRuntime.h"
#import "ZNStaticPatchFormat.h"
#import "ZNValueTypeModel.h"
#import "ZNPatchCore.h"

@interface ZNStaticPatchRecord (ZNM56Private)
@property(nonatomic,assign) uintptr_t imageBase;
@property(nonatomic,assign) ZN44StaticEntry *entry;
@end

static UIViewController *ZNM56TopController(void){UIWindow *window=nil;for(UIScene *scene in UIApplication.sharedApplication.connectedScenes){if(![scene isKindOfClass:UIWindowScene.class]||scene.activationState!=UISceneActivationStateForegroundActive)continue;for(UIWindow *candidate in ((UIWindowScene *)scene).windows){if(candidate.isKeyWindow){window=candidate;break;}}if(window)break;}if(!window)window=UIApplication.sharedApplication.windows.firstObject;UIViewController *vc=window.rootViewController;while(vc.presentedViewController&&!vc.presentedViewController.isBeingDismissed)vc=vc.presentedViewController;return vc;}
static void ZNM56ShowFailure(NSString *message){dispatch_async(dispatch_get_main_queue(),^{UIViewController *top=ZNM56TopController();if(!top||[top isKindOfClass:UIAlertController.class])return;UIAlertController *a=[UIAlertController alertControllerWithTitle:@"执行失败" message:message.length?message:@"执行失败" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];[top presentViewController:a animated:YES completion:nil];});}

static BOOL ZNM56RecordMatches(ZNStaticPatchRecord *record,NSDictionary *info){uint64_t wantedID=[info[@"featureID"] unsignedLongLongValue];NSDictionary *meta=record.entry?ZNFeatureMetadataDecodeEntry(record.entry):nil;uint64_t recordID=[meta[@"featureID"] unsignedLongLongValue];if(wantedID&&recordID)return wantedID==recordID;NSString *wanted=[info[@"title"] isKindOfClass:NSString.class]?info[@"title"]:@"";NSString *recordName=[meta[@"title"] isKindOfClass:NSString.class]?meta[@"title"]:(record.group.length?record.group:record.title);return wanted.length&&[wanted caseInsensitiveCompare:recordName?:@""]==NSOrderedSame;}

static uintptr_t ZNM56ValueCellAddress(ZNStaticPatchRecord *record,ZNValueType *resolvedType,NSString **error){
    if(!record||!record.imageBase||!record.entry){if(error)*error=@"Static value-cell record metadata unavailable";return 0;}
    if(!(record.entry->flags&ZN44_STATIC_ENTRY_FLAG_VALUE_CELL_V1)){if(error)*error=@"当前生成物没有 RW Value Cell；请用 M5.6 重新生成 UnityFramework";return 0;}
    const struct mach_header_64 *mh=(const struct mach_header_64 *)record.imageBase;if(mh->magic!=MH_MAGIC_64){if(error)*error=@"value-cell runtime Mach-O 无效";return 0;}
    const uint8_t *cursor=(const uint8_t *)(mh+1),*limit=cursor+mh->sizeofcmds;uint64_t imageVMBase=UINT64_MAX;const struct segment_command_64 *znData=NULL;const struct section_64 *znDataSec=NULL;
    for(uint32_t i=0;i<mh->ncmds;i++){if(cursor+sizeof(struct load_command)>limit)break;const struct load_command *lc=(const struct load_command *)cursor;if(lc->cmdsize<sizeof(*lc)||cursor+lc->cmdsize>limit)break;if(lc->cmd==LC_SEGMENT_64&&lc->cmdsize>=sizeof(struct segment_command_64)){const struct segment_command_64 *seg=(const struct segment_command_64 *)cursor;if(strncmp(seg->segname,"__TEXT",16)==0)imageVMBase=seg->vmaddr;if(strncmp(seg->segname,"__ZNDATA",16)==0){znData=seg;uint64_t secBytes=(uint64_t)seg->nsects*sizeof(struct section_64);if(lc->cmdsize>=sizeof(*seg)+secBytes){const struct section_64 *secs=(const struct section_64 *)(seg+1);for(uint32_t j=0;j<seg->nsects;j++)if(strncmp(secs[j].sectname,"__zndata",16)==0){znDataSec=&secs[j];break;}}}}cursor+=lc->cmdsize;}
    if(imageVMBase==UINT64_MAX||!znData||!znDataSec){if(error)*error=@"value-cell runtime 缺少 __ZNDATA";return 0;}
    uintptr_t headerAddress=record.imageBase+(uintptr_t)(znDataSec->addr-imageVMBase);ZN44StaticHeader *header=(ZN44StaticHeader *)headerAddress;if(header->magic0!=ZN44_STATIC_MAGIC0||header->magic1!=ZN44_STATIC_MAGIC1||header->entrySize!=sizeof(ZN44StaticEntry)||!header->count||header->count>ZN44_STATIC_MAX_ENTRIES){if(error)*error=@"value-cell runtime Static Header 无效";return 0;}
    if(!(header->flags&ZN44_STATIC_HEADER_FLAG_VALUE_CELLS_V1)){if(error)*error=@"生成物未标记 Value Cells V1";return 0;}
    ZN44StaticEntry *entries=(ZN44StaticEntry *)(header+1);ptrdiff_t idx=record.entry-entries;if(idx<0||(uint32_t)idx>=header->count){if(error)*error=@"value-cell entry index 无效";return 0;}
    uint64_t cellBytes=(uint64_t)header->count*8u;uintptr_t segmentRuntime=record.imageBase+(uintptr_t)(znData->vmaddr-imageVMBase);uintptr_t cellBase=segmentRuntime+(uintptr_t)znData->filesize-(uintptr_t)cellBytes;
    uint32_t rawType=ZN44StaticValueCellTypeFromFlags(record.entry->flags);if(rawType>ZNValueTypeF64||rawType==ZNValueTypeAuto){if(error)*error=@"value-cell resolved type 无效";return 0;}if(resolvedType)*resolvedType=(ZNValueType)rawType;return cellBase+(uintptr_t)idx*8u;
}

static BOOL ZNM56ScanSigned(NSString *text,long long *out){NSScanner *s=[NSScanner scannerWithString:text?:@""];long long v=0;if(![s scanLongLong:&v]||!s.isAtEnd)return NO;if(out)*out=v;return YES;}
static BOOL ZNM56ScanUnsigned(NSString *text,unsigned long long *out){NSString *t=[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!t.length||[t hasPrefix:@"-"])return NO;NSScanner *s=[NSScanner scannerWithString:t];unsigned long long v=0;if(![s scanUnsignedLongLong:&v]||!s.isAtEnd)return NO;if(out)*out=v;return YES;}

static BOOL ZNM56WriteTextToCell(NSString *text,ZNValueType type,uintptr_t cell,NSString **error){
    if(type==ZNValueTypeI32){long long v=0;if(!ZNM56ScanSigned(text,&v)||v<INT32_MIN||v>INT32_MAX){if(error)*error=@"不是有效 I32";return NO;}uint32_t raw=(uint32_t)(int32_t)v;__atomic_store_n((uint32_t *)cell,raw,__ATOMIC_RELEASE);return YES;}
    if(type==ZNValueTypeU32){unsigned long long v=0;if(!ZNM56ScanUnsigned(text,&v)||v>UINT32_MAX){if(error)*error=@"不是有效 U32";return NO;}__atomic_store_n((uint32_t *)cell,(uint32_t)v,__ATOMIC_RELEASE);return YES;}
    if(type==ZNValueTypeI64){long long v=0;if(!ZNM56ScanSigned(text,&v)){if(error)*error=@"不是有效 I64";return NO;}__atomic_store_n((uint64_t *)cell,(uint64_t)v,__ATOMIC_RELEASE);return YES;}
    if(type==ZNValueTypeU64){unsigned long long v=0;if(!ZNM56ScanUnsigned(text,&v)){if(error)*error=@"不是有效 U64";return NO;}__atomic_store_n((uint64_t *)cell,(uint64_t)v,__ATOMIC_RELEASE);return YES;}
    if(type==ZNValueTypeF32){NSScanner *s=[NSScanner scannerWithString:text?:@""];double d=0;if(![s scanDouble:&d]||!s.isAtEnd||!isfinite(d)){if(error)*error=@"不是有效 F32";return NO;}float f=(float)d;uint32_t raw=0;memcpy(&raw,&f,4);__atomic_store_n((uint32_t *)cell,raw,__ATOMIC_RELEASE);return YES;}
    if(type==ZNValueTypeF64){NSScanner *s=[NSScanner scannerWithString:text?:@""];double d=0;if(![s scanDouble:&d]||!s.isAtEnd||!isfinite(d)){if(error)*error=@"不是有效 F64";return NO;}uint64_t raw=0;memcpy(&raw,&d,8);__atomic_store_n((uint64_t *)cell,raw,__ATOMIC_RELEASE);return YES;}
    if(error)*error=@"Value Cell 不支持 Auto/未知类型";return NO;
}

@interface ZNM56StaticValueCellBinder:NSObject
@property(nonatomic,strong)NSMutableDictionary<NSString *,NSNumber *> *sliderGenerations;
+ (instancetype)shared;-(void)numberChanged:(NSNotification *)note;-(void)sliderChanged:(NSNotification *)note;-(void)actionRequested:(NSNotification *)note;
@end
@implementation ZNM56StaticValueCellBinder
+ (instancetype)shared{static ZNM56StaticValueCellBinder *s;static dispatch_once_t once;dispatch_once(&once,^{s=[ZNM56StaticValueCellBinder new];s.sliderGenerations=[NSMutableDictionary dictionary];});return s;}
- (NSArray<ZNStaticPatchRecord *> *)recordsForInfo:(NSDictionary *)info{ZNStaticDispatchRuntime *runtime=[ZNStaticDispatchRuntime sharedRuntime];[runtime refresh];NSMutableArray *out=[NSMutableArray array];for(ZNStaticPatchRecord *r in runtime.records)if(ZNM56RecordMatches(r,info))[out addObject:r];return out;}
- (BOOL)applyText:(NSString *)text info:(NSDictionary *)info error:(NSString **)error{NSArray<ZNStaticPatchRecord *> *records=[self recordsForInfo:info];if(!records.count){if(error)*error=@"找不到 Static Feature 记录";return NO;}ZNStaticDispatchRuntime *runtime=[ZNStaticDispatchRuntime sharedRuntime];for(ZNStaticPatchRecord *r in records){ZNValueType resolved=ZNValueTypeAuto;NSString *local=nil;uintptr_t cell=ZNM56ValueCellAddress(r,&resolved,&local);if(!cell){if(error)*error=local;return NO;}if(!ZNM56WriteTextToCell(text,resolved,cell,&local)){if(error)*error=local;return NO;}if(!r.isEnabled&&![runtime setEnabled:YES forRecord:r error:&local]){if(error)*error=local?:@"启用 Static value-cell variant 失败";return NO;}}[[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[m5.6-value-cell] wrote value=%@ records=%lu RW-only",text?:@"",(unsigned long)records.count]];return YES;}
- (void)numberChanged:(NSNotification *)note{NSString *text=[note.userInfo[@"valueText"] isKindOfClass:NSString.class]?note.userInfo[@"valueText"]:[note.userInfo[@"value"] description];NSString *error=nil;if(![self applyText:text info:note.userInfo?:@{} error:&error])ZNM56ShowFailure(error);}
- (void)sliderChanged:(NSNotification *)note{NSString *text=[note.userInfo[@"valueText"] isKindOfClass:NSString.class]?note.userInfo[@"valueText"]:[note.userInfo[@"value"] description];NSString *key=[note.userInfo[@"key"] isKindOfClass:NSString.class]?note.userInfo[@"key"]:(note.userInfo[@"title"]?:@"feature");NSUInteger generation=[self.sliderGenerations[key] unsignedIntegerValue]+1;self.sliderGenerations[key]=@(generation);NSDictionary *info=[note.userInfo copy]?:@{};dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.10*NSEC_PER_SEC)),dispatch_get_main_queue(),^{if([self.sliderGenerations[key] unsignedIntegerValue]!=generation)return;NSString *error=nil;if(![self applyText:text info:info error:&error])ZNM56ShowFailure(error);});}
- (void)actionRequested:(NSNotification *)note{NSArray *records=[self recordsForInfo:note.userInfo?:@{}];if(!records.count){ZNM56ShowFailure(@"找不到 Static Feature 记录");return;}ZNStaticDispatchRuntime *runtime=[ZNStaticDispatchRuntime sharedRuntime];for(ZNStaticPatchRecord *r in records){NSString *error=nil;if(![runtime setEnabled:YES forRecord:r error:&error]){ZNM56ShowFailure(error);return;}}}
@end

extern "C" void ZNInstallM56StaticValueCellBindingDeferred(void){static dispatch_once_t once;dispatch_once(&once,^{
    Class oldClass=NSClassFromString(@"ZNM55StaticTypedBinder");if(oldClass&&[oldClass respondsToSelector:NSSelectorFromString(@"shared")]){id oldBinder=((id(*)(id,SEL))objc_msgSend)((id)oldClass,NSSelectorFromString(@"shared"));if(oldBinder)[NSNotificationCenter.defaultCenter removeObserver:oldBinder];}
    ZNM56StaticValueCellBinder *binder=[ZNM56StaticValueCellBinder shared];[NSNotificationCenter.defaultCenter addObserver:binder selector:@selector(numberChanged:) name:ZNFeatureNumberValueDidChangeNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:binder selector:@selector(sliderChanged:) name:ZNFeatureSliderValueDidChangeNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:binder selector:@selector(actionRequested:) name:ZNFeatureActionRequestedNotification object:nil];[[ZNRuntimeLogger sharedLogger]log:@"[m5.6-value-cell] Static Number/Slider RW-only binder installed"];
});}
