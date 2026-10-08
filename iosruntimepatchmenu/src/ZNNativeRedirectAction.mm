#import "ZNNativeRedirectAction.h"
#import "ZNIL2CPPABIMetadata.h"

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
static NSString *ZNRDIdentity(NSString *assembly,NSString *ns,NSString *cls,NSString *method,NSUInteger argc) {
    NSString *owner=ns.length?[NSString stringWithFormat:@"%@.%@",ns,cls?:@""]:(cls?:@"");
    return [NSString stringWithFormat:@"%@!%@::%@/%lu",assembly?:@"",owner,method?:@"",(unsigned long)argc];
}
static NSArray<NSString *> *ZNRDParamTypes(NSDictionary *abi) {
    NSMutableArray *out=[NSMutableArray array];
    NSArray *params=[abi[@"parameters"] isKindOfClass:NSArray.class]?abi[@"parameters"]:@[];
    for(NSDictionary *p in params)[out addObject:[p[@"name"] isKindOfClass:NSString.class]?p[@"name"]:@"?"];
    return out;
}

@implementation ZNNativeRedirectAction
- (instancetype)init {
    self=[super init]; if(!self)return nil;
    _title=@"Method Redirect"; _featureDescription=@""; _controlType=@"switch";
    _sourceAssembly=@"Assembly-CSharp.dll";_sourceNamespace=@"";_sourceClass=@"";_sourceMethod=@"";
    _sourceParameterTypes=@[];_sourceReturnType=@"void";
    _targetAssembly=@"Assembly-CSharp.dll";_targetNamespace=@"";_targetClass=@"";_targetMethod=@"";
    _targetParameterTypes=@[];_targetReturnType=@"void";
    return self;
}
- (NSString *)sourceIdentity {
    return ZNRDIdentity(self.sourceAssembly,self.sourceNamespace,self.sourceClass,self.sourceMethod,self.sourceArgumentCount);
}
- (NSString *)targetIdentity {
    return ZNRDIdentity(self.targetAssembly,self.targetNamespace,self.targetClass,self.targetMethod,self.targetArgumentCount);
}
- (NSString *)canonicalIdentity {
    return [NSString stringWithFormat:@"%@ -> %@",self.sourceIdentity,self.targetIdentity];
}
- (id)copyWithZone:(NSZone *)zone {
    ZNNativeRedirectAction *a=[[[self class] allocWithZone:zone]init];
    a.actionID=self.actionID;a.title=self.title;a.featureDescription=self.featureDescription;a.controlType=self.controlType;
    a.sourceAssembly=self.sourceAssembly;a.sourceNamespace=self.sourceNamespace;a.sourceClass=self.sourceClass;a.sourceMethod=self.sourceMethod;
    a.sourceArgumentCount=self.sourceArgumentCount;a.sourceMethodRVA=self.sourceMethodRVA;a.sourceParameterTypes=self.sourceParameterTypes;
    a.sourceReturnType=self.sourceReturnType;a.sourceInstance=self.sourceInstance;
    a.targetAssembly=self.targetAssembly;a.targetNamespace=self.targetNamespace;a.targetClass=self.targetClass;a.targetMethod=self.targetMethod;
    a.targetArgumentCount=self.targetArgumentCount;a.targetMethodRVA=self.targetMethodRVA;a.targetParameterTypes=self.targetParameterTypes;
    a.targetReturnType=self.targetReturnType;a.targetInstance=self.targetInstance;
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
- (ZNNativeRedirectAction *)addSourceCandidate:(NSDictionary<NSString *,id> *)source
                                targetCandidate:(NSDictionary<NSString *,id> *)target
                                          title:(NSString *)title
                             featureDescription:(NSString *)featureDescription
                                    controlType:(NSString *)controlType
                                          error:(NSString **)error {
    if(![source isKindOfClass:NSDictionary.class]||![target isKindOfClass:NSDictionary.class]){
        if(error)*error=@"Method Redirect 需要 Source 和 Target 方法";return nil;
    }
    NSDictionary *sourceABI=ZNIL2CPPDescribeMethodABI(source);
    NSDictionary *targetABI=ZNIL2CPPDescribeMethodABI(target);
    if(![sourceABI[@"available"] boolValue]||![targetABI[@"available"] boolValue]){
        if(error)*error=@"Method Redirect ABI metadata 不完整";return nil;
    }
    uint64_t sourceRVA=[source[@"methodRVA"] unsignedLongLongValue];
    if(!sourceRVA)sourceRVA=[source[@"rva"] unsignedLongLongValue];
    uint64_t targetRVA=[target[@"methodRVA"] unsignedLongLongValue];
    if(!targetRVA)targetRVA=[target[@"rva"] unsignedLongLongValue];
    if(!sourceRVA||!targetRVA){
        if(error)*error=@"Method Redirect Source/Target 缺少 authored RVA";return nil;
    }

    ZNNativeRedirectAction *a=[ZNNativeRedirectAction new];
    a.sourceAssembly=[source[@"assembly"] isKindOfClass:NSString.class]?source[@"assembly"]:@"Assembly-CSharp.dll";
    a.sourceNamespace=[source[@"namespace"] isKindOfClass:NSString.class]?source[@"namespace"]:@"";
    a.sourceClass=[source[@"class"] isKindOfClass:NSString.class]?source[@"class"]:@"";
    a.sourceMethod=[source[@"method"] isKindOfClass:NSString.class]?source[@"method"]:@"";
    a.sourceArgumentCount=[source[@"argumentCount"] unsignedIntegerValue];
    a.sourceMethodRVA=sourceRVA;a.sourceParameterTypes=ZNRDParamTypes(sourceABI);
    a.sourceReturnType=[sourceABI[@"return"][@"name"] isKindOfClass:NSString.class]?sourceABI[@"return"][@"name"]:@"?";
    a.sourceInstance=[sourceABI[@"instance"] boolValue];

    a.targetAssembly=[target[@"assembly"] isKindOfClass:NSString.class]?target[@"assembly"]:@"Assembly-CSharp.dll";
    a.targetNamespace=[target[@"namespace"] isKindOfClass:NSString.class]?target[@"namespace"]:@"";
    a.targetClass=[target[@"class"] isKindOfClass:NSString.class]?target[@"class"]:@"";
    a.targetMethod=[target[@"method"] isKindOfClass:NSString.class]?target[@"method"]:@"";
    a.targetArgumentCount=[target[@"argumentCount"] unsignedIntegerValue];
    a.targetMethodRVA=targetRVA;a.targetParameterTypes=ZNRDParamTypes(targetABI);
    a.targetReturnType=[targetABI[@"return"][@"name"] isKindOfClass:NSString.class]?targetABI[@"return"][@"name"]:@"?";
    a.targetInstance=[targetABI[@"instance"] boolValue];

    if(!a.sourceClass.length||!a.sourceMethod.length||!a.targetClass.length||!a.targetMethod.length){
        if(error)*error=@"Method Redirect 方法身份不完整";return nil;
    }
    a.title=ZNRDTrim(title).length?ZNRDTrim(title):[NSString stringWithFormat:@"%@ → %@",a.sourceMethod,a.targetMethod];
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
