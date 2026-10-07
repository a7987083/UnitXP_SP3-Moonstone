#import "ZNNativeRedirectBuildPrepare.h"

#import "ZNNativeRedirectAction.h"
#import "ZNBuildManifest.h"
#import "ZNBuildCapabilityRegistry.h"
#import "ZNBuildItem.h"
#import "ZNPatchCore.h"

#import <mach-o/loader.h>
#import <mach/machine.h>
#import <sys/mman.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>

static BOOL ZNRDBuildEncodeBranch(uint64_t fromRVA,uint64_t toRVA,BOOL link,uint32_t *out) {
    int64_t delta=(int64_t)toRVA-(int64_t)fromRVA;
    if((delta&3LL)!=0||delta<=-(1LL<<27)||delta>=(1LL<<27))return NO;
    int64_t imm=delta>>2;
    if(out)*out=(link?0x94000000u:0x14000000u)|((uint32_t)imm&0x03FFFFFFu);
    return YES;
}

static BOOL ZNRDBuildFileOffsetForRVA(uint8_t *base,size_t size,uint64_t rva,uint64_t *out,NSString **error) {
    if(!base||size<sizeof(struct mach_header_64)){if(error)*error=@"Native Redirect Mach-O 太小";return NO;}
    struct mach_header_64 *mh=(struct mach_header_64 *)base;
    if(mh->magic!=MH_MAGIC_64||mh->cputype!=CPU_TYPE_ARM64){if(error)*error=@"Native Redirect 仅支持 thin arm64 Mach-O";return NO;}
    uint8_t *cursor=base+sizeof(*mh),*limit=cursor+mh->sizeofcmds;
    if(limit>base+size){if(error)*error=@"Native Redirect load commands 越界";return NO;}
    uint64_t imageBase=UINT64_MAX;
    for(uint32_t i=0;i<mh->ncmds;i++){
        if(cursor+sizeof(struct load_command)>limit)break;
        struct load_command *lc=(struct load_command *)cursor;
        if(lc->cmdsize<sizeof(*lc)||cursor+lc->cmdsize>limit)break;
        if(lc->cmd==LC_SEGMENT_64){
            struct segment_command_64 *seg=(struct segment_command_64 *)cursor;
            if(strncmp(seg->segname,SEG_TEXT,16)==0){imageBase=seg->vmaddr;break;}
        }
        cursor+=lc->cmdsize;
    }
    if(imageBase==UINT64_MAX){if(error)*error=@"Native Redirect 缺少 __TEXT";return NO;}

    uint64_t vm=imageBase+rva;
    cursor=base+sizeof(*mh);
    for(uint32_t i=0;i<mh->ncmds;i++){
        struct load_command *lc=(struct load_command *)cursor;
        if(lc->cmd==LC_SEGMENT_64){
            struct segment_command_64 *seg=(struct segment_command_64 *)cursor;
            if(vm>=seg->vmaddr&&vm<seg->vmaddr+seg->filesize){
                uint64_t off=seg->fileoff+(vm-seg->vmaddr);
                if(off+4>size){if(error)*error=@"Native Redirect RVA file range 越界";return NO;}
                if(out)*out=off;return YES;
            }
        }
        cursor+=lc->cmdsize;
    }
    if(error)*error=[NSString stringWithFormat:@"Native Redirect RVA 0x%llX 不在文件-backed segment",(unsigned long long)rva];
    return NO;
}

static BOOL ZNRDBuildPatchOutput(NSString *path,NSArray<ZNNativeRedirectAction *> *actions,NSString **error) {
    int fd=open(path.fileSystemRepresentation,O_RDWR);
    if(fd<0){if(error)*error=@"Native Redirect 无法打开生成输出";return NO;}
    struct stat st={}; if(fstat(fd,&st)!=0||st.st_size<=0){close(fd);if(error)*error=@"Native Redirect 输出大小无效";return NO;}
    size_t size=(size_t)st.st_size;
    uint8_t *base=(uint8_t *)mmap(NULL,size,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
    if(base==MAP_FAILED){close(fd);if(error)*error=@"Native Redirect mmap 输出失败";return NO;}
    BOOL ok=YES;NSString *local=nil;
    for(ZNNativeRedirectAction *a in actions){
        if(![a.sourceImage isEqualToString:a.targetImage]){
            local=@"Native Redirect Build V1 暂不支持跨 image redirect";ok=NO;break;
        }
        uint32_t instruction=0;
        BOOL link=a.kind==ZNNativeRedirectKindBranchLink;
        if(!ZNRDBuildEncodeBranch(a.sourceRVA,a.targetRVA,link,&instruction)){
            local=[NSString stringWithFormat:@"%@：生成期 B/BL 超出 ±128MB；Runtime Function Redirect 可用 Dobby，但 Build V1 暂不猜测 code cave",a.canonicalIdentity];
            ok=NO;break;
        }
        uint64_t off=0;
        if(!ZNRDBuildFileOffsetForRVA(base,size,a.sourceRVA,&off,&local)){ok=NO;break;}
        memcpy(base+off,&instruction,sizeof(instruction));
    }
    if(ok&&msync(base,size,MS_SYNC)!=0){local=@"Native Redirect msync 失败";ok=NO;}
    munmap(base,size);close(fd);
    if(!ok&&error)*error=local?:@"Native Redirect Build patch 失败";
    return ok;
}

static NSString *ZNRDOutputForImage(NSArray<NSString *> *outputs,NSString *image) {
    for(NSString *p in outputs){
        if([p.lastPathComponent isEqualToString:@"build_report.json"])continue;
        if([p.lastPathComponent isEqualToString:image])return p;
        if([image isEqualToString:@"UnityFramework"]&&[p.lastPathComponent isEqualToString:@"UnityFramework"])return p;
    }
    return nil;
}

void ZNInstallNativeRedirectBuildProvider(void) {
    static dispatch_once_t once;dispatch_once(&once,^{
        ZNRegisterBuildCapabilityProvider(@"native-redirect",^BOOL{
            return [ZNNativeRedirectStore sharedStore].actionsSnapshot.count>0;
        });

        ZNRegisterBuildItemProvider(@"native-redirect",
            ^NSArray<ZNBuildItem *> *(ZNBinaryPatchWorkspace *workspace){
                (void)workspace;
                NSMutableArray *items=[NSMutableArray array];
                NSArray *actions=[ZNNativeRedirectStore sharedStore].actionsSnapshot;
                [actions enumerateObjectsUsingBlock:^(ZNNativeRedirectAction *a,NSUInteger idx,BOOL *stop){
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
                (void)manifest;(void)workspace;
                for(ZNNativeRedirectAction *a in [ZNNativeRedirectStore sharedStore].actionsSnapshot){
                    if(!a.sourceRVA||!a.targetRVA||(a.sourceRVA&3ULL)||(a.targetRVA&3ULL)){
                        if(error)*error=[NSString stringWithFormat:@"%@：source/target RVA 无效",a.title?:@"Native Redirect"];return NO;
                    }
                    if(![a.sourceImage isEqualToString:a.targetImage]){
                        if(error)*error=@"Native Redirect Build V1 暂不支持跨 image redirect";return NO;
                    }
                    uint32_t branch=0;
                    if(!ZNRDBuildEncodeBranch(a.sourceRVA,a.targetRVA,a.kind==ZNNativeRedirectKindBranchLink,&branch)){
                        if(error)*error=[NSString stringWithFormat:@"%@：生成期 redirect 超出 ARM64 B/BL ±128MB",a.canonicalIdentity];return NO;
                    }
                }
                return YES;
            },
            ^BOOL(ZNBuildManifest *manifest,NSArray<NSString *> *outputs,BOOL runtimeOnlyBase,NSString **report,NSString **error){
                (void)manifest;(void)runtimeOnlyBase;
                NSArray<ZNNativeRedirectAction *> *actions=[ZNNativeRedirectStore sharedStore].actionsSnapshot;
                NSMutableDictionary<NSString *,NSMutableArray *> *byImage=[NSMutableDictionary dictionary];
                for(ZNNativeRedirectAction *a in actions){
                    NSMutableArray *bucket=byImage[a.sourceImage];
                    if(!bucket){bucket=[NSMutableArray array];byImage[a.sourceImage]=bucket;}
                    [bucket addObject:a];
                }
                for(NSString *image in byImage){
                    NSString *path=ZNRDOutputForImage(outputs,image);
                    if(!path){if(error)*error=[NSString stringWithFormat:@"Native Redirect 找不到生成输出：%@",image];return NO;}
                    if(!ZNRDBuildPatchOutput(path,byImage[image],error))return NO;
                }
                if(report)*report=[NSString stringWithFormat:@"Native Redirect：已预写 %lu 条 B/BL redirect",(unsigned long)actions.count];
                return YES;
            });
    });
}

__attribute__((constructor)) static void ZNRDInstallProviderCtor(void) {
    ZNInstallNativeRedirectBuildProvider();
}
