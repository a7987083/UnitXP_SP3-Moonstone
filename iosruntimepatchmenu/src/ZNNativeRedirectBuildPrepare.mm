#import "ZNNativeRedirectBuildPrepare.h"

#import "ZNNativeRedirectAction.h"
#import "ZNBinaryPatchWorkspace.h"
#import "ZNFeatureControlModel.h"
#import "ZNBuildManifest.h"
#import "ZNBuildCapabilityRegistry.h"
#import "ZNBuildItem.h"
#import "ZNPatchCore.h"

static NSString * const kZNRDWorkspaceMarker=@"native-redirect://";

static BOOL ZNRDBuildEncodeBranch(uint64_t fromRVA,uint64_t toRVA,BOOL link,uint32_t *out) {
    int64_t delta=(int64_t)toRVA-(int64_t)fromRVA;
    if((delta&3LL)!=0||delta<=-(1LL<<27)||delta>=(1LL<<27))return NO;
    int64_t imm=delta>>2;
    if(out)*out=(link?0x94000000u:0x14000000u)|((uint32_t)imm&0x03FFFFFFu);
    return YES;
}

static NSString *ZNRDInstructionHex(uint32_t instruction) {
    const uint8_t *p=(const uint8_t *)&instruction;
    return [NSString stringWithFormat:@"%02X %02X %02X %02X",p[0],p[1],p[2],p[3]];
}

static void ZNRDSyncWorkspaceRows(ZNBinaryPatchWorkspace *workspace) {
    if(!workspace)return;
    NSIndexSet *old=[workspace.rows indexesOfObjectsPassingTest:^BOOL(ZNBinaryPatchRow *row,NSUInteger idx,BOOL *stop){
        (void)idx;(void)stop;
        return [row.sourcePath hasPrefix:kZNRDWorkspaceMarker];
    }];
    if(old.count)[workspace.rows removeObjectsAtIndexes:old];

    for(ZNNativeRedirectAction *a in [ZNNativeRedirectStore sharedStore].actionsSnapshot){
        if(!a.sourceRVA||!a.targetRVA||![a.sourceImage isEqualToString:a.targetImage])continue;
        uint32_t instruction=0;
        BOOL link=a.kind==ZNNativeRedirectKindBranchLink;
        // Function Redirect uses Dobby only for temporary runtime testing.
        // Generated-client semantics are a prepared static B redirect so that
        // Switch OFF can restore the Builder-captured original instruction.
        if(!ZNRDBuildEncodeBranch(a.sourceRVA,a.targetRVA,link,&instruction))continue;

        ZNBinaryPatchRow *row=[ZNBinaryPatchRow new];
        row.target=a.sourceImage.length?a.sourceImage:@"UnityFramework";
        row.explicitTarget=YES;
        row.offsetText=[NSString stringWithFormat:@"0x%llX",(unsigned long long)a.sourceRVA];
        row.enabledText=ZNRDInstructionHex(instruction);
        row.originalHex=@"";
        row.title=a.title.length?a.title:@"Native Redirect";
        row.group=row.title;
        row.featureDescription=a.featureDescription?:@"";
        row.sourcePath=[NSString stringWithFormat:@"%@%u",kZNRDWorkspaceMarker,a.actionID];
        row.statusText=@"Native Redirect · Builder V3 待验证";
        row.validated=NO;
        row.featureControlType=[a.controlType isEqualToString:@"button"]
            ? ZNFeatureControlTypeButton : ZNFeatureControlTypeSwitch;
        [workspace.rows addObject:row];
    }
}

void ZNInstallNativeRedirectBuildProvider(void) {
    static dispatch_once_t once;dispatch_once(&once,^{
        ZNRegisterBuildCapabilityProvider(@"native-redirect",^BOOL{
            return [ZNNativeRedirectStore sharedStore].actionsSnapshot.count>0;
        });

        ZNRegisterBuildItemProvider(@"native-redirect",
            ^NSArray<ZNBuildItem *> *(ZNBinaryPatchWorkspace *workspace){
                // The independent Native Redirect model owns authoring. At
                // manifest collection time it materializes deterministic Static
                // Patch rows; the existing Static Builder V3 then owns original
                // capture, relocation, prepared dispatch and client controls.
                ZNRDSyncWorkspaceRows(workspace);
                NSMutableArray *items=[NSMutableArray array];
                [[ZNNativeRedirectStore sharedStore].actionsSnapshot enumerateObjectsUsingBlock:
                    ^(ZNNativeRedirectAction *a,NSUInteger idx,BOOL *stop){
                        (void)stop;
                        [items addObject:[ZNBuildItem itemWithProvider:@"native-redirect"
                                                                  kind:@"native-redirect"
                                                            identifier:a.canonicalIdentity
                                                                domain:ZNBuildItemDomainRuntime
                                                              metadata:@{@"index":@(idx),@"title":a.title?:@""}]];
                    }];
                return items;
            },
            ^BOOL(ZNBuildManifest *manifest,ZNBinaryPatchWorkspace *workspace,NSString **error){
                (void)manifest;
                NSArray<ZNNativeRedirectAction *> *actions=[ZNNativeRedirectStore sharedStore].actionsSnapshot;
                for(ZNNativeRedirectAction *a in actions){
                    if(!a.sourceRVA||!a.targetRVA||(a.sourceRVA&3ULL)||(a.targetRVA&3ULL)){
                        if(error)*error=[NSString stringWithFormat:@"%@：source/target RVA 无效",a.title?:@"Native Redirect"];
                        return NO;
                    }
                    if(![a.sourceImage isEqualToString:a.targetImage]){
                        if(error)*error=@"Native Redirect Build V1 暂不支持跨 image redirect";
                        return NO;
                    }
                    uint32_t branch=0;
                    if(!ZNRDBuildEncodeBranch(a.sourceRVA,a.targetRVA,a.kind==ZNNativeRedirectKindBranchLink,&branch)){
                        if(error)*error=[NSString stringWithFormat:
                            @"%@：Source → Target 超出 ARM64 B/BL ±128MB；Runtime Function Redirect 可测试，但当前 Build V1 不猜测覆盖窗口",
                            a.canonicalIdentity];
                        return NO;
                    }
                }
                ZNRDSyncWorkspaceRows(workspace);
                return YES;
            },
            ^BOOL(ZNBuildManifest *manifest,NSArray<NSString *> *outputs,BOOL runtimeOnlyBase,NSString **report,NSString **error){
                (void)manifest;(void)outputs;(void)runtimeOnlyBase;(void)error;
                NSUInteger count=[ZNNativeRedirectStore sharedStore].actionsSnapshot.count;
                if(report)*report=[NSString stringWithFormat:
                    @"Native Redirect：%lu actions 已由 Static Builder V3 prepared dispatch 承载",
                    (unsigned long)count];
                return YES;
            });
    });
}

__attribute__((constructor)) static void ZNRDInstallProviderCtor(void) {
    ZNInstallNativeRedirectBuildProvider();
}
