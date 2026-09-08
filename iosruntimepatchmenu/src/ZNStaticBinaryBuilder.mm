#import "ZNStaticBinaryBuilder.h"
#import "ZNBinaryPatchWorkspace.h"
#import "ZNPatchRuntimeValidator.h"
#import "ZNPatchCore.h"
#import "ZNStaticPatchFormat.h"
#import <mach-o/loader.h>
#import <mach/machine.h>
#import <sys/mman.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>
#import <vector>
#import <algorithm>

struct ZNBSection { uint64_t fileStart,fileEnd,addr,size; uint32_t flags; };
struct ZNBSegment { uint64_t vmaddr,vmsize,fileoff,filesize; vm_prot_t initprot,maxprot; char name[17]; std::vector<ZNBSection> sections; };
struct ZNBGap { uint64_t fileoff,size,rva; size_t segIndex; };
struct ZNBSite { __unsafe_unretained ZNBinaryPatchRow *row; uint64_t rva,fileoff,window; size_t segIndex; NSData *original; NSData *enabled; };

static uint64_t ZNBAlign(uint64_t v,uint64_t a){return (v+a-1)&~(a-1);} 
static int64_t ZNBSX(uint64_t v,int bits){uint64_t m=1ULL<<(bits-1);return (int64_t)((v^m)-m);} 
static uint32_t ZNBRead32(const uint8_t *p){uint32_t v;memcpy(&v,p,4);return v;} static void ZNBWrite32(uint8_t *p,uint32_t v){memcpy(p,&v,4);} 
static BOOL ZNBZero(const uint8_t *base,uint64_t off,uint64_t len){for(uint64_t i=0;i<len;i++)if(base[off+i])return NO;return YES;}

static BOOL ZNBParse(uint8_t *base,size_t size,std::vector<ZNBSegment> &segs,uint64_t &imageVMBase,NSString **error){
    if(size<sizeof(mach_header_64)){if(error)*error=@"Mach-O 太小";return NO;} mach_header_64 *mh=(mach_header_64 *)base;
    if(mh->magic!=MH_MAGIC_64){if(error)*error=@"Binary Builder V1 仅支持 thin 64-bit Mach-O";return NO;}
    if(mh->cputype!=CPU_TYPE_ARM64){if(error)*error=@"目标不是 arm64/arm64e Mach-O";return NO;}
    if(sizeof(*mh)+(uint64_t)mh->sizeofcmds>size){if(error)*error=@"Mach-O load commands 越界";return NO;}
    imageVMBase=UINT64_MAX; uint8_t *p=base+sizeof(*mh), *end=p+mh->sizeofcmds;
    for(uint32_t i=0;i<mh->ncmds;i++){
        if(p+sizeof(load_command)>end){if(error)*error=@"load command 损坏";return NO;} load_command *lc=(load_command *)p;
        if(lc->cmdsize<sizeof(load_command)||p+lc->cmdsize>end){if(error)*error=@"load command size 损坏";return NO;}
        if(lc->cmd==LC_SEGMENT_64&&lc->cmdsize>=sizeof(segment_command_64)){
            segment_command_64 *sg=(segment_command_64 *)p; if(sg->fileoff+sg->filesize>size){if(error)*error=@"segment file range 越界";return NO;}
            ZNBSegment s={};s.vmaddr=sg->vmaddr;s.vmsize=sg->vmsize;s.fileoff=sg->fileoff;s.filesize=sg->filesize;s.initprot=sg->initprot;s.maxprot=sg->maxprot;memcpy(s.name,sg->segname,16);s.name[16]=0;
            if(strncmp(sg->segname,SEG_TEXT,16)==0) imageVMBase=sg->vmaddr;
            if(lc->cmdsize>=sizeof(segment_command_64)+(uint64_t)sg->nsects*sizeof(section_64)){
                section_64 *sec=(section_64 *)(sg+1); for(uint32_t j=0;j<sg->nsects;j++){
                    uint32_t type=sec[j].flags&SECTION_TYPE; if(type==S_ZEROFILL||type==S_GB_ZEROFILL||type==S_THREAD_LOCAL_ZEROFILL)continue;
                    if(!sec[j].size||!sec[j].offset)continue; uint64_t fs=sec[j].offset,fe=fs+sec[j].size; if(fe>size)continue;
                    s.sections.push_back({fs,fe,sec[j].addr,sec[j].size,sec[j].flags});
                }
            }
            segs.push_back(s);
        } p+=lc->cmdsize;
    }
    if(imageVMBase==UINT64_MAX){if(error)*error=@"未找到 __TEXT segment";return NO;} return YES;
}

static BOOL ZNBRVAToFile(const std::vector<ZNBSegment>&segs,uint64_t baseVM,uint64_t rva,uint64_t len,uint64_t &file,size_t &idx){
    uint64_t va=baseVM+rva; for(size_t i=0;i<segs.size();i++){const ZNBSegment&s=segs[i];if(va>=s.vmaddr&&va+len<=s.vmaddr+s.filesize){file=s.fileoff+(va-s.vmaddr);idx=i;return YES;}}return NO;
}
static uint64_t ZNBFileToRVA(const ZNBSegment&s,uint64_t baseVM,uint64_t off){return s.vmaddr+(off-s.fileoff)-baseVM;}

static std::vector<ZNBGap> ZNBGaps(const uint8_t *base,const std::vector<ZNBSegment>&segs,uint64_t baseVM,BOOL executable,uint64_t need,const std::vector<uint64_t>&sites){
    std::vector<ZNBGap> out; for(size_t si=0;si<segs.size();si++){const ZNBSegment&s=segs[si];
        if(executable){if(!(s.initprot&VM_PROT_EXECUTE))continue;}else{if(!(s.initprot&VM_PROT_WRITE))continue;}
        if(!s.filesize||s.sections.empty())continue; std::vector<std::pair<uint64_t,uint64_t>> rs; for(auto&q:s.sections)if(q.fileStart>=s.fileoff&&q.fileEnd<=s.fileoff+s.filesize)rs.push_back({q.fileStart,q.fileEnd});
        if(rs.empty())continue;std::sort(rs.begin(),rs.end());uint64_t cursor=rs[0].second;
        for(size_t i=1;i<=rs.size();i++){uint64_t next=(i<rs.size()?rs[i].first:s.fileoff+s.filesize);if(next>cursor){uint64_t a=ZNBAlign(cursor,executable?16:8);if(next>a&&next-a>=need&&ZNBZero(base,a,need)){
                    uint64_t rva=ZNBFileToRVA(s,baseVM,a);BOOL reach=YES;if(executable)for(uint64_t site:sites){int64_t d0=(int64_t)rva-(int64_t)site,d1=(int64_t)(rva+need)-(int64_t)site;if(d0<=-(1LL<<27)||d0>=(1LL<<27)||d1<=-(1LL<<27)||d1>=(1LL<<27)){reach=NO;break;}}
                    if(reach)out.push_back({a,next-a,rva,si});}
            }if(i<rs.size())cursor=std::max(cursor,rs[i].second);}
    }std::sort(out.begin(),out.end(),[](const ZNBGap&a,const ZNBGap&b){return a.size>b.size;});return out;
}

static BOOL ZNBEncodeB(uint64_t from,uint64_t to,BOOL link,uint32_t *out){int64_t d=(int64_t)to-(int64_t)from;if((d&3)||d<-(1LL<<27)||d>=(1LL<<27))return NO;uint32_t imm=(uint32_t)((d>>2)&0x03FFFFFF);*out=(link?0x94000000u:0x14000000u)|imm;return YES;}
static BOOL ZNBEncodeADRP(uint64_t from,uint64_t to,uint32_t *out){int64_t pages=((int64_t)(to&~0xFFFULL)-(int64_t)(from&~0xFFFULL))>>12;if(pages<-(1LL<<20)||pages>=(1LL<<20))return NO;uint64_t u=(uint64_t)pages&0x1FFFFF;*out=0x90000000u|((uint32_t)(u&3)<<29)|((uint32_t)((u>>2)&0x7FFFF)<<5)|17u;return YES;}
static uint32_t ZNBLdrX17(uint64_t target){uint32_t imm=(uint32_t)((target&0xFFFULL)>>3);return 0xF9400000u|(imm<<10)|(17u<<5)|17u;}
static BOOL ZNBIsRet(uint32_t x){return (x&0xFFFFFC1Fu)==0xD65F0000u;} static BOOL ZNBIsBR(uint32_t x){return (x&0xFFFFFC1Fu)==0xD61F0000u;}

static BOOL ZNBRelocate(uint32_t ins,uint64_t src,uint64_t dst,uint64_t winStart,uint64_t winEnd,uint32_t *out,BOOL *terminal,NSString **error){
    *terminal=NO;
    if((ins&0x7C000000u)==0x14000000u){BOOL link=(ins&0x80000000u)!=0;int64_t d=ZNBSX(ins&0x03FFFFFFu,26)<<2;uint64_t target=(uint64_t)((int64_t)src+d);if(target>=winStart&&target<winEnd){if(error)*error=@"PC-relative B/BL 指向被覆盖窗口内部，V1 拒绝生成";return NO;}if(!ZNBEncodeB(dst,target,link,out)){if(error)*error=@"重定位 B/BL 超出 ±128MB";return NO;}*terminal=!link;return YES;}
    if((ins&0xFF000010u)==0x54000000u || (ins&0x7E000000u)==0x34000000u || (ins&0x3B000000u)==0x18000000u){int64_t d=ZNBSX((ins>>5)&0x7FFFFu,19)<<2;uint64_t target=(uint64_t)((int64_t)src+d);if(target>=winStart&&target<winEnd){if(error)*error=@"PC-relative imm19 指向被覆盖窗口内部";return NO;}int64_t nd=(int64_t)target-(int64_t)dst;if((nd&3)||nd<-(1LL<<20)||nd>=(1LL<<20)){if(error)*error=@"重定位 imm19 超出 ±1MB";return NO;}*out=(ins&~0x00FFFFE0u)|(((uint32_t)(nd>>2)&0x7FFFFu)<<5);return YES;}
    if((ins&0x7E000000u)==0x36000000u){int64_t d=ZNBSX((ins>>5)&0x3FFFu,14)<<2;uint64_t target=(uint64_t)((int64_t)src+d);if(target>=winStart&&target<winEnd){if(error)*error=@"TBZ/TBNZ 指向被覆盖窗口内部";return NO;}int64_t nd=(int64_t)target-(int64_t)dst;if((nd&3)||nd<-(1LL<<15)||nd>=(1LL<<15)){if(error)*error=@"重定位 TBZ/TBNZ 超出 ±32KB";return NO;}*out=(ins&~0x0007FFE0u)|(((uint32_t)(nd>>2)&0x3FFFu)<<5);return YES;}
    uint32_t adrMask=ins&0x9F000000u;if(adrMask==0x10000000u||adrMask==0x90000000u){uint64_t imm=((uint64_t)((ins>>5)&0x7FFFF)<<2)|((ins>>29)&3);int64_t simm=ZNBSX(imm,21);uint64_t target;if(adrMask==0x90000000u)target=(uint64_t)((int64_t)(src&~0xFFFULL)+(simm<<12));else target=(uint64_t)((int64_t)src+simm);if(target>=winStart&&target<winEnd){if(error)*error=@"ADR/ADRP 指向被覆盖窗口内部";return NO;}int64_t nimm=adrMask==0x90000000u?(((int64_t)(target&~0xFFFULL)-(int64_t)(dst&~0xFFFULL))>>12):((int64_t)target-(int64_t)dst);if(nimm<-(1LL<<20)||nimm>=(1LL<<20)){if(error)*error=@"重定位 ADR/ADRP 超范围";return NO;}uint64_t u=(uint64_t)nimm&0x1FFFFF;*out=(ins&~((3u<<29)|(0x7FFFFu<<5)))|((uint32_t)(u&3)<<29)|((uint32_t)((u>>2)&0x7FFFF)<<5);return YES;}
    *out=ins;if(ZNBIsRet(ins)||ZNBIsBR(ins))*terminal=YES;return YES;
}

static BOOL ZNBInboundInterior(const uint8_t *base,const std::vector<ZNBSegment>&segs,uint64_t baseVM,uint64_t site,uint64_t len){uint64_t end=site+len;
    for(const ZNBSegment&s:segs){if(!(s.initprot&VM_PROT_EXECUTE))continue;for(const ZNBSection&q:s.sections){if(q.fileEnd<=q.fileStart)continue;for(uint64_t off=q.fileStart;off+4<=q.fileEnd;off+=4){uint32_t ins=ZNBRead32(base+off);uint64_t src=q.addr+(off-q.fileStart)-baseVM,target=0;BOOL has=NO;
                if((ins&0x7C000000u)==0x14000000u){target=(uint64_t)((int64_t)src+(ZNBSX(ins&0x03FFFFFFu,26)<<2));has=YES;}
                else if((ins&0xFF000010u)==0x54000000u||(ins&0x7E000000u)==0x34000000u){target=(uint64_t)((int64_t)src+(ZNBSX((ins>>5)&0x7FFFFu,19)<<2));has=YES;}
                else if((ins&0x7E000000u)==0x36000000u){target=(uint64_t)((int64_t)src+(ZNBSX((ins>>5)&0x3FFFu,14)<<2));has=YES;}
                if(has&&target>site&&target<end)return YES;}}}return NO;}

static BOOL ZNBVariant(uint8_t *base,uint64_t fileoff,uint64_t rva,uint64_t reserved,NSData *source,uint64_t sourceRVA,uint64_t winStart,uint64_t winEnd,uint64_t resume,NSString **error){
    const uint32_t NOP=0xD503201Fu;for(uint64_t p=0;p<reserved;p+=4)ZNBWrite32(base+fileoff+p,NOP);ZNBWrite32(base+fileoff,0xA8C147F0u);
    BOOL terminalSeen=NO;const uint8_t *src=(const uint8_t *)source.bytes;for(NSUInteger i=0;i<source.length;i+=4){uint32_t ins=ZNBRead32(src+i),rel=0;BOOL term=NO;if(!ZNBRelocate(ins,sourceRVA+i,rva+4+i,winStart,winEnd,&rel,&term,error))return NO;ZNBWrite32(base+fileoff+4+i,rel);if(term)terminalSeen=YES;}
    if(!terminalSeen){uint32_t b=0;if(!ZNBEncodeB(rva+4+source.length,resume,NO,&b)){if(error)*error=@"Variant 返回原代码超出 ±128MB";return NO;}ZNBWrite32(base+fileoff+4+source.length,b);}return YES;
}

static void ZNBCopyFixed(char *dst,size_t cap,NSString *s){memset(dst,0,cap);NSData *d=[s dataUsingEncoding:NSUTF8StringEncoding];if(!d.length)return;memcpy(dst,d.bytes,std::min(cap-1,(size_t)d.length));}

static BOOL ZNBBuildTarget(NSString *target,NSArray<ZNBinaryPatchRow *> *rows,NSString *folder,NSString **outPath,NSDictionary **meta,NSString **error){
    NSDictionary *module=[[ZNModuleManager sharedManager] moduleNamed:target];if(!module){if(error)*error=[NSString stringWithFormat:@"目标模块未加载：%@",target];return NO;}NSString *input=module[@"path"];if(!input.length){if(error)*error=@"无法取得目标 Mach-O 路径";return NO;}
    NSString *name=input.lastPathComponent.length?input.lastPathComponent:target;NSString *output=[folder stringByAppendingPathComponent:[name stringByAppendingString:@".znpatched"]];NSFileManager *fm=NSFileManager.defaultManager;[fm removeItemAtPath:output error:nil];NSError *copyErr=nil;if(![fm copyItemAtPath:input toPath:output error:&copyErr]){if(error)*error=[NSString stringWithFormat:@"复制目标失败：%@",copyErr.localizedDescription];return NO;}
    int fd=open(output.fileSystemRepresentation,O_RDWR);if(fd<0){if(error)*error=@"打开输出文件失败";[fm removeItemAtPath:output error:nil];return NO;}struct stat st={};if(fstat(fd,&st)!=0||st.st_size<=0){close(fd);[fm removeItemAtPath:output error:nil];if(error)*error=@"读取输出文件大小失败";return NO;}
    size_t size=(size_t)st.st_size;uint8_t *base=(uint8_t *)mmap(NULL,size,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);if(base==MAP_FAILED){close(fd);[fm removeItemAtPath:output error:nil];if(error)*error=@"mmap 输出文件失败";return NO;}
    BOOL success=NO;NSString *local=nil;std::vector<ZNBSegment>segs;uint64_t baseVM=0;do{
        if(!ZNBParse(base,size,segs,baseVM,&local))break;std::vector<ZNBSite>sites;std::vector<uint64_t>siteRVAs;
        for(ZNBinaryPatchRow *r in rows){NSData *enabled=r.validator.patchBytes,*live=r.validator.capturedOriginalBytes;if(!enabled.length||!live.length||enabled.length!=live.length||(enabled.length&3)){local=@"Patch 必须已验证且长度为 4-byte 倍数";break;}uint64_t rv=r.validator.rva,fo=0;size_t si=0;if(!ZNBRVAToFile(segs,baseVM,rv,enabled.length,fo,si)){local=[NSString stringWithFormat:@"%@+0x%llX 无法映射到 file offset",target,rv];break;}if(!(segs[si].initprot&VM_PROT_EXECUTE)){local=[NSString stringWithFormat:@"%@+0x%llX 不在 executable segment",target,rv];break;}NSData *disk=[NSData dataWithBytes:base+fo length:enabled.length];if(![disk isEqualToData:live]){local=[NSString stringWithFormat:@"%@+0x%llX 磁盘原字节与 Live Original 不一致",target,rv];break;}if(ZNBInboundInterior(base,segs,baseVM,rv,enabled.length)){local=[NSString stringWithFormat:@"%@+0x%llX 覆盖窗口内部存在直接分支目标，V1 拒绝",target,rv];break;}sites.push_back({r,rv,fo,(uint64_t)enabled.length,si,disk,enabled});siteRVAs.push_back(rv);}
        if(local)break;for(size_t a=0;a<sites.size();a++)for(size_t b=a+1;b<sites.size();b++){uint64_t a0=sites[a].rva,a1=a0+sites[a].window,b0=sites[b].rva,b1=b0+sites[b].window;if(a0<b1&&b0<a1){local=@"Patch 覆盖窗口互相重叠";break;}}if(local)break;
        uint64_t codeNeed=0;for(auto&s:sites){uint64_t vs=ZNBAlign(4+s.window+4,16);codeNeed=ZNBAlign(codeNeed,16)+16+vs+vs;}codeNeed+=32;uint64_t dataNeed=ZNBAlign(sizeof(ZN44StaticHeader)+sites.size()*sizeof(ZN44StaticEntry),8);
        auto cg=ZNBGaps(base,segs,baseVM,YES,codeNeed,siteRVAs),dg=ZNBGaps(base,segs,baseVM,NO,dataNeed,{});if(cg.empty()){local=@"无安全 executable gap：V1 不会把任意 0 区当 code cave";break;}if(dg.empty()){local=@"无安全 writable gap：V1 拒绝生成";break;}ZNBGap code=cg[0],data=dg[0];
        ZN44StaticHeader *hdr=(ZN44StaticHeader *)(base+data.fileoff);memset(hdr,0,dataNeed);hdr->magic0=ZN44_STATIC_MAGIC0;hdr->magic1=ZN44_STATIC_MAGIC1;hdr->version=ZN44_STATIC_VERSION;hdr->count=(uint32_t)sites.size();hdr->entrySize=sizeof(ZN44StaticEntry);ZN44StaticEntry *entries=(ZN44StaticEntry *)(hdr+1);
        uint64_t cursor=code.fileoff;const uint32_t NOP=0xD503201Fu;
        for(size_t i=0;i<sites.size();i++){ZNBSite&s=sites[i];cursor=ZNBAlign(cursor,16);uint64_t thunkFO=cursor,thunkRVA=ZNBFileToRVA(segs[code.segIndex],baseVM,thunkFO);cursor+=16;uint64_t vs=ZNBAlign(4+s.window+4,16);uint64_t offFO=ZNBAlign(cursor,16),offRVA=ZNBFileToRVA(segs[code.segIndex],baseVM,offFO);cursor=offFO+vs;uint64_t onFO=ZNBAlign(cursor,16),onRVA=ZNBFileToRVA(segs[code.segIndex],baseVM,onFO);cursor=onFO+vs;
            uint64_t entryRVA=data.rva+sizeof(ZN44StaticHeader)+i*sizeof(ZN44StaticEntry);uint32_t adrp=0;if(!ZNBEncodeADRP(thunkRVA+4,entryRVA,&adrp)){local=@"Thunk → selectedTarget ADRP 超出 ±4GB";break;}uint64_t pageoff=entryRVA&0xFFFULL;if(pageoff&7){local=@"selectedTarget 未 8-byte 对齐";break;}ZNBWrite32(base+thunkFO,0xA9BF47F0u);ZNBWrite32(base+thunkFO+4,adrp);ZNBWrite32(base+thunkFO+8,ZNBLdrX17(entryRVA));ZNBWrite32(base+thunkFO+12,0xD61F0220u);
            if(!ZNBVariant(base,offFO,offRVA,vs,s.original,s.rva,s.rva,s.rva+s.window,s.rva+s.window,&local))break;if(!ZNBVariant(base,onFO,onRVA,vs,s.enabled,s.rva,s.rva,s.rva+s.window,s.rva+s.window,&local))break;
            uint32_t siteB=0;if(!ZNBEncodeB(s.rva,thunkRVA,NO,&siteB)){local=@"Site → thunk 超出 ±128MB";break;}ZNBWrite32(base+s.fileoff,siteB);for(uint64_t p=4;p<s.window;p+=4)ZNBWrite32(base+s.fileoff+p,NOP);
            ZN44StaticEntry &e=entries[i];memset(&e,0,sizeof(e));e.offRVA=offRVA;e.onRVA=onRVA;e.siteRVA=s.rva;e.windowLength=(uint32_t)s.window;e.patchID=(uint32_t)i+1;e.enabledLength=(uint32_t)s.enabled.length;ZNBCopyFixed(e.title,sizeof(e.title),s.row.title.length?s.row.title:[NSString stringWithFormat:@"Patch #%u",e.patchID]);ZNBCopyFixed(e.group,sizeof(e.group),s.row.group.length?s.row.group:@"Imported");
        }if(local)break;msync(base,size,MS_SYNC);success=YES;if(meta)*meta=@{@"target":target,@"input":input,@"output":output,@"patchCount":@(sites.size()),@"codeGapRVA":[NSString stringWithFormat:@"0x%llX",code.rva],@"dataGapRVA":[NSString stringWithFormat:@"0x%llX",data.rva],@"needsResign":@YES};if(outPath)*outPath=output;
    }while(0);munmap(base,size);close(fd);if(!success){[fm removeItemAtPath:output error:nil];if(error)*error=local?:@"生成失败";}return success;
}

@implementation ZNStaticBinaryBuilder
+ (BOOL)buildWorkspace:(ZNBinaryPatchWorkspace *)workspace outputs:(NSArray<NSString *> **)outputs report:(NSString **)report error:(NSString **)error {
    if(!workspace||workspace.hasAnyApplied){if(error)*error=@"生成前必须恢复所有临时 Runtime Patch";return NO;}if(!workspace.filledCount){if(error)*error=@"没有 Patch";return NO;}
    NSMutableDictionary<NSString *,NSMutableArray<ZNBinaryPatchRow *> *> *groups=[NSMutableDictionary dictionary];
    for(ZNBinaryPatchRow *r in workspace.rows){if(!r.offsetText.length&&!r.enabledText.length)continue;if(!r.validated||!r.validator){if(error)*error=@"所有已填写 Patch 必须先“读取验证”通过";return NO;}NSString *t=(r.explicitTarget&&r.target.length)?r.target:workspace.defaultTarget;if(!groups[t])groups[t]=[NSMutableArray array];[groups[t] addObject:r];}
    NSString *root=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/ZonoePatchOutput"];NSDateFormatter *fmt=[NSDateFormatter new];fmt.dateFormat=@"yyyyMMdd-HHmmss";NSString *folder=[root stringByAppendingPathComponent:[fmt stringFromDate:NSDate.date]];NSError *dirErr=nil;if(![NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&dirErr]){if(error)*error=dirErr.localizedDescription;return NO;}
    NSMutableArray *paths=[NSMutableArray array],*metas=[NSMutableArray array];__block NSString *fail=nil;for(NSString *target in groups){NSString *p=nil;NSDictionary *m=nil;NSString *e=nil;if(!ZNBBuildTarget(target,groups[target],folder,&p,&m,&e)){fail=[NSString stringWithFormat:@"%@：%@",target,e?:@"生成失败"];break;}[paths addObject:p];if(m)[metas addObject:m];}
    if(fail){[NSFileManager.defaultManager removeItemAtPath:folder error:nil];if(error)*error=fail;return NO;}
    NSDictionary *rep=@{@"format":@"com.zonoe.static-dispatch/v1",@"generatedAt":@([[NSDate date] description]),@"targets":metas,@"notes":@[@"JSON original is ignored",@"OFF bytes are captured/verified from the installed original binary",@"Runtime toggles only RW selectedTarget pointers",@"Output Mach-O must be re-signed before installation",@"V1 uses only unclaimed zero-filled file-backed segment gaps and rejects unsafe layouts"]};NSData *json=[NSJSONSerialization dataWithJSONObject:rep options:NSJSONWritingPrettyPrinted error:nil];NSString *rp=[folder stringByAppendingPathComponent:@"build_report.json"];[json writeToFile:rp atomically:YES];[paths addObject:rp];if(outputs)*outputs=paths;if(report)*report=[NSString stringWithFormat:@"生成成功：%lu 个目标 · %lu 个 Patch\n输出：%@\n必须重新签名后安装",(unsigned long)groups.count,(unsigned long)workspace.filledCount,folder];return YES;
}
@end
