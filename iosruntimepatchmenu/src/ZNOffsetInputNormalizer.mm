#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach-o/loader.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#import "ZNBinaryPatchWorkspace.h"
#import "ZNPatchCore.h"

static NSString *ZNINTrim(NSString *value){return [value?:@"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];}
static BOOL ZNINParse(NSString *input,uint64_t *out){NSString *s=[ZNINTrim(input) lowercaseString];if(!s.length)return NO;const char *c=s.UTF8String;char *end=NULL;errno=0;unsigned long long v=strtoull(c,&end,0);if(errno||end==c||(end&&*end!='\0')){errno=0;end=NULL;v=strtoull(c,&end,16);}if(errno||end==c||(end&&*end!='\0'))return NO;if(out)*out=v;return YES;}
static uint64_t ZNINVMBase(uintptr_t base){if(!base)return UINT64_MAX;const struct mach_header_64 *mh=(const struct mach_header_64 *)base;if(mh->magic!=MH_MAGIC_64)return UINT64_MAX;const uint8_t *p=(const uint8_t *)(mh+1),*end=p+mh->sizeofcmds;for(uint32_t i=0;i<mh->ncmds;i++){if(p+sizeof(struct load_command)>end)break;const struct load_command *lc=(const struct load_command *)p;if(lc->cmdsize<sizeof(*lc)||p+lc->cmdsize>end)break;if(lc->cmd==LC_SEGMENT_64&&lc->cmdsize>=sizeof(struct segment_command_64)){const struct segment_command_64 *seg=(const struct segment_command_64 *)p;if(strncmp(seg->segname,SEG_TEXT,16)==0)return seg->vmaddr;}p+=lc->cmdsize;}return UINT64_MAX;}
static BOOL ZNINRVAHit(uintptr_t base,uint64_t rva){if(!base)return NO;const struct mach_header_64 *mh=(const struct mach_header_64 *)base;if(mh->magic!=MH_MAGIC_64)return NO;uint64_t vmBase=ZNINVMBase(base);if(vmBase==UINT64_MAX)return NO;uint64_t va=vmBase+rva;const uint8_t *p=(const uint8_t *)(mh+1),*end=p+mh->sizeofcmds;for(uint32_t i=0;i<mh->ncmds;i++){if(p+sizeof(struct load_command)>end)break;const struct load_command *lc=(const struct load_command *)p;if(lc->cmdsize<sizeof(*lc)||p+lc->cmdsize>end)break;if(lc->cmd==LC_SEGMENT_64&&lc->cmdsize>=sizeof(struct segment_command_64)){const struct segment_command_64 *seg=(const struct segment_command_64 *)p;if(va>=seg->vmaddr&&va+4<=seg->vmaddr+seg->vmsize)return YES;}p+=lc->cmdsize;}return NO;}
static NSString *ZNINNormalize(NSString *target,NSString *input){uint64_t raw=0;if(!ZNINParse(input,&raw))return input;NSDictionary *module=[[ZNModuleManager sharedManager]moduleNamed:target];uintptr_t base=(uintptr_t)[module[@"base"]unsignedLongLongValue];if(!base)return input;if(ZNINRVAHit(base,raw))return [NSString stringWithFormat:@"0x%llX",raw];uint64_t vmBase=ZNINVMBase(base);if(vmBase!=UINT64_MAX&&raw>=vmBase){uint64_t rva=raw-vmBase;if(ZNINRVAHit(base,rva)){[[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[offset-input] VA %@ -> RVA 0x%llX target=%@",input?:@"",rva,target?:@""]];return [NSString stringWithFormat:@"0x%llX",rva];}}return input;}

@interface ZNBinaryPatchWorkspace (ZNOffsetInputNormalizer)
- (void)znin_updateOffset:(NSString *)text row:(NSUInteger)index;
- (BOOL)znin_importJSONAtPath:(NSString *)path error:(NSString **)error;
@end
@implementation ZNBinaryPatchWorkspace (ZNOffsetInputNormalizer)
- (void)znin_updateOffset:(NSString *)text row:(NSUInteger)index{if(index>=self.rows.count){[self znin_updateOffset:text row:index];return;}ZNBinaryPatchRow *row=self.rows[index];NSString *target=(row.explicitTarget&&row.target.length)?row.target:self.defaultTarget;[self znin_updateOffset:ZNINNormalize(target,text) row:index];}
- (BOOL)znin_importJSONAtPath:(NSString *)path error:(NSString **)error{BOOL ok=[self znin_importJSONAtPath:path error:error];if(!ok)return NO;for(NSUInteger i=0;i<self.rows.count;i++){ZNBinaryPatchRow *row=self.rows[i];if(!row.offsetText.length)continue;NSString *target=(row.explicitTarget&&row.target.length)?row.target:self.defaultTarget;row.offsetText=ZNINNormalize(target,row.offsetText);}return YES;}
@end
static void ZNINSwap(Class cls,SEL a,SEL b){Method x=class_getInstanceMethod(cls,a),y=class_getInstanceMethod(cls,b);if(x&&y)method_exchangeImplementations(x,y);}
extern "C" void ZNInstallOffsetInputNormalizerDeferred(void){static dispatch_once_t once;dispatch_once(&once,^{Class cls=ZNBinaryPatchWorkspace.class;ZNINSwap(cls,@selector(updateOffset:row:),@selector(znin_updateOffset:row:));ZNINSwap(cls,@selector(importJSONAtPath:error:),@selector(znin_importJSONAtPath:error:));[[ZNRuntimeLogger sharedLogger]log:@"[m5.12-offset-input] RVA + Mach-O VA input normalization installed"];});}
