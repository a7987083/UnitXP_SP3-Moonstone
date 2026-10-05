#import "ZNComplexStructCodec.h"
#import "ZNNativeHookTemplate.h"

NSString * const ZNComplexStructCodecSecureLongWholeAccessor=@"secure-long-whole-accessor";

typedef int64_t (*ZNCSSecureLongGetterFn)(uintptr_t);
typedef void (*ZNCSSecureLongSetterFn)(uintptr_t,int64_t);

static BOOL ZNCSecureLongWholeTransform(uintptr_t base,
                                        uintptr_t decoder,
                                        uintptr_t encoder,
                                        int32_t multiplier,
                                        int64_t *before,
                                        int64_t *after) {
    if(base<0x1000||!decoder||!encoder)return NO;
    ZNCSSecureLongGetterFn getter=(ZNCSSecureLongGetterFn)decoder;
    ZNCSSecureLongSetterFn setter=(ZNCSSecureLongSetterFn)encoder;
    int64_t input=getter(base);
    int64_t output=ZNNativeHookScaleInt64(input,multiplier);
    setter(base,output);
    if(before)*before=input;
    if(after)*after=output;
    return YES;
}

@interface ZNComplexStructCodecRegistry ()
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSValue *> *transforms;
@end

@implementation ZNComplexStructCodecRegistry
+ (instancetype)sharedRegistry {
    static ZNComplexStructCodecRegistry *registry;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken,^{registry=[ZNComplexStructCodecRegistry new];registry.transforms=[NSMutableDictionary dictionary];});
    return registry;
}
- (void)registerCodecKey:(NSString *)key transform:(ZNComplexStructTransformFn)transform {
    if(!key.length||!transform)return;
    @synchronized(self){self.transforms[key]=[NSValue valueWithPointer:(const void *)transform];}
}
- (NSValue *)transformValueForCodecKey:(NSString *)key {
    if(!key.length)return nil;
    @synchronized(self){return self.transforms[key];}
}
- (BOOL)supportsCodecKey:(NSString *)key {
    return [self transformValueForCodecKey:key]!=nil;
}
@end

void ZNRegisterBuiltInComplexStructCodecs(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken,^{
        [[ZNComplexStructCodecRegistry sharedRegistry] registerCodecKey:ZNComplexStructCodecSecureLongWholeAccessor
                                                              transform:ZNCSecureLongWholeTransform];
    });
}
