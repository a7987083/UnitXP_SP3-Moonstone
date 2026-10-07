#import "ZNNativeRedirectAction.h"

static NSString *ZNRDTrim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}
static uint32_t ZNRDFNV1a32(NSString *text) {
    uint32_t h=2166136261u;
    NSData *data=[text dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    const uint8_t *p=(const uint8_t *)data.bytes;
    for(NSUInteger i=0;i<data.length;i++){h^=p[i];h*=16777619u;}
    return h?:1u;
}

NSString *ZNNativeRedirectKindKey(ZNNativeRedirectKind kind) {
    switch(kind){
        case ZNNativeRedirectKindBranch:return @"b";
        case ZNNativeRedirectKindBranchLink:return @"bl";
        default:return @"function";
    }
}
ZNNativeRedirectKind ZNNativeRedirectKindFromKey(NSString *key) {
    NSString *k=ZNRDTrim(key).lowercaseString;
    if([k isEqualToString:@"b"])return ZNNativeRedirectKindBranch;
    if([k isEqualToString:@"bl"])return ZNNativeRedirectKindBranchLink;
    return ZNNativeRedirectKindFunction;
}

@implementation ZNNativeRedirectAction
- (instancetype)init {
    self=[super init]; if(!self)return nil;
    _title=@"Native Redirect"; _featureDescription=@"";
    _sourceImage=@"UnityFramework"; _targetImage=@"UnityFramework";
    _controlType=@"switch"; _kind=ZNNativeRedirectKindFunction;
    return self;
}
- (NSString *)canonicalIdentity {
    return [NSString stringWithFormat:@"%@+0x%llX -> %@+0x%llX [%@]",
            self.sourceImage?:@"",(unsigned long long)self.sourceRVA,
            self.targetImage?:@"",(unsigned long long)self.targetRVA,
            ZNNativeRedirectKindKey(self.kind)];
}
- (id)copyWithZone:(NSZone *)zone {
    ZNNativeRedirectAction *a=[[[self class] allocWithZone:zone]init];
    a.actionID=self.actionID;a.title=self.title;a.featureDescription=self.featureDescription;
    a.sourceImage=self.sourceImage;a.sourceRVA=self.sourceRVA;a.targetImage=self.targetImage;
    a.targetRVA=self.targetRVA;a.kind=self.kind;a.controlType=self.controlType;
    return a;
}
@end

@interface ZNNativeRedirectStore ()
@property(nonatomic,strong) NSMutableArray<ZNNativeRedirectAction *> *mutableActions;
@end
@implementation ZNNativeRedirectStore
+ (instancetype)sharedStore {
    static ZNNativeRedirectStore *s; static dispatch_once_t once;
    dispatch_once(&once,^{s=[ZNNativeRedirectStore new];});
    return s;
}
- (instancetype)init {self=[super init];if(!self)return nil;_mutableActions=[NSMutableArray array];return self;}
- (NSArray<ZNNativeRedirectAction *> *)actionsSnapshot {
    @synchronized(self){NSMutableArray *out=[NSMutableArray arrayWithCapacity:self.mutableActions.count];
        for(ZNNativeRedirectAction *a in self.mutableActions)[out addObject:[a copy]];
        return [out copy];}
}
- (ZNNativeRedirectAction *)addSourceImage:(NSString *)sourceImage
                                 sourceRVA:(uint64_t)sourceRVA
                               targetImage:(NSString *)targetImage
                                 targetRVA:(uint64_t)targetRVA
                                      kind:(ZNNativeRedirectKind)kind
                                     title:(NSString *)title
                        featureDescription:(NSString *)featureDescription
                               controlType:(NSString *)controlType
                                     error:(NSString **)error {
    NSString *src=ZNRDTrim(sourceImage),*dst=ZNRDTrim(targetImage);
    if(!src.length)src=@"UnityFramework"; if(!dst.length)dst=src;
    if(!sourceRVA||!targetRVA||(sourceRVA&3ULL)||(targetRVA&3ULL)){
        if(error)*error=@"Native Redirect source/target RVA 必须是非零 4-byte 对齐地址";return nil;
    }
    if(kind<ZNNativeRedirectKindFunction||kind>ZNNativeRedirectKindBranchLink){
        if(error)*error=@"Native Redirect kind 无效";return nil;
    }
    ZNNativeRedirectAction *a=[ZNNativeRedirectAction new];
    a.sourceImage=src;a.sourceRVA=sourceRVA;a.targetImage=dst;a.targetRVA=targetRVA;a.kind=kind;
    a.title=ZNRDTrim(title).length?ZNRDTrim(title):@"Native Redirect";
    a.featureDescription=ZNRDTrim(featureDescription);
    NSString *control=ZNRDTrim(controlType).lowercaseString;
    a.controlType=[control isEqualToString:@"button"]?@"button":@"switch";
    @synchronized(self){
        NSString *seed=[NSString stringWithFormat:@"%@|%@|%lu",a.canonicalIdentity,a.title,(unsigned long)self.mutableActions.count];
        a.actionID=ZNRDFNV1a32(seed);
        [self.mutableActions addObject:a];
    }
    return [a copy];
}
- (BOOL)removeActionAtIndex:(NSUInteger)index {@synchronized(self){if(index>=self.mutableActions.count)return NO;[self.mutableActions removeObjectAtIndex:index];return YES;}}
- (void)clear {@synchronized(self){[self.mutableActions removeAllObjects];}}
@end
