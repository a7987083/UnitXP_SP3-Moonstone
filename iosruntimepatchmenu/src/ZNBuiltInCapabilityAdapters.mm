#import "ZNBuiltInCapabilityAdapters.h"
#import "ZNCapabilityRegistry.h"
#import "ZNStaticDispatchRuntime.h"
#import "ZNRuntimeActionRuntime.h"
#import "ZNNativeHookRuntime.h"
#import "ZNNativeHookScheduler.h"
#import "ZNNativeHookAction.h"

NSString * const ZNCapabilityStaticPatchIdentifier=@"static-patch";
NSString * const ZNCapabilityRuntimeMethodIdentifier=@"runtime-method";
NSString * const ZNCapabilityNativeHookIdentifier=@"native-hook";

@interface ZNStaticPatchCapabilityAdapter:NSObject<ZNRuntimeCapabilityAdapter>@end
@implementation ZNStaticPatchCapabilityAdapter
- (NSString *)capabilityIdentifier{return ZNCapabilityStaticPatchIdentifier;}
- (BOOL)prepareForImageCount:(uint32_t)c error:(NSString **)e{(void)c;(void)e;[[ZNStaticDispatchRuntime sharedRuntime] refresh];return YES;}
- (NSArray *)snapshotItems{return [ZNStaticDispatchRuntime sharedRuntime].records?:@[];}
- (BOOL)activateItem:(id)item value:(id)value error:(NSString **)error{
    if(![item isKindOfClass:ZNStaticPatchRecord.class]){if(error)*error=@"Static Patch item 类型错误";return NO;}
    return [[ZNStaticDispatchRuntime sharedRuntime] setEnabled:[value boolValue] forRecord:item error:error];
}
- (BOOL)deactivateItem:(id)item error:(NSString **)error{return [self activateItem:item value:@NO error:error];}
@end

@interface ZNRuntimeMethodCapabilityAdapter:NSObject<ZNRuntimeCapabilityAdapter>@end
@implementation ZNRuntimeMethodCapabilityAdapter
- (NSString *)capabilityIdentifier{return ZNCapabilityRuntimeMethodIdentifier;}
- (BOOL)prepareForImageCount:(uint32_t)c error:(NSString **)e{(void)c;(void)e;[[ZNRuntimeActionRuntime sharedRuntime] refresh];return YES;}
- (NSArray *)snapshotItems{return [ZNRuntimeActionRuntime sharedRuntime].records?:@[];}
- (BOOL)activateItem:(id)item value:(id)value error:(NSString **)error{
    (void)value;
    if(![item isKindOfClass:ZNRuntimeMethodActionRecord.class]){if(error)*error=@"Runtime Method item 类型错误";return NO;}
    return [[ZNRuntimeActionRuntime sharedRuntime] executeRecord:item error:error];
}
@end

@interface ZNNativeHookCapabilityAdapter:NSObject<ZNRuntimeCapabilityAdapter>@end
@implementation ZNNativeHookCapabilityAdapter
- (NSString *)capabilityIdentifier{return ZNCapabilityNativeHookIdentifier;}
- (BOOL)prepareForImageCount:(uint32_t)c error:(NSString **)e{
    (void)c;(void)e;
    ZNNativeHookRuntime *runtime=[ZNNativeHookRuntime sharedRuntime];
    [runtime refreshGeneratedActions];
    [[ZNNativeHookScheduler sharedScheduler] reconcileActions:runtime.generatedActions?:@[]];
    return YES;
}
- (NSArray *)snapshotItems{return [ZNNativeHookRuntime sharedRuntime].generatedActions?:@[];}
- (BOOL)activateItem:(id)item value:(id)value error:(NSString **)error{
    if(![item isKindOfClass:ZNNativeHookAction.class]){if(error)*error=@"Native Hook item 类型错误";return NO;}
    NSInteger desired=[value respondsToSelector:@selector(integerValue)]?[value integerValue]:0;
    [[ZNNativeHookScheduler sharedScheduler] setDesiredValue:desired forAction:item];
    return YES;
}
@end

void ZNRegisterBuiltInCapabilityAdapters(void){
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken,^{
        ZNCapabilityRegistry *r=[ZNCapabilityRegistry sharedRegistry];
        [r registerAdapter:[ZNStaticPatchCapabilityAdapter new]];
        [r registerAdapter:[ZNRuntimeMethodCapabilityAdapter new]];
        [r registerAdapter:[ZNNativeHookCapabilityAdapter new]];
    });
}
