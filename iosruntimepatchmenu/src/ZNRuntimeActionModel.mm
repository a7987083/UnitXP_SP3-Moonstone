#import "ZNRuntimeActionModel.h"
#import "ZNRuntimeActionFormat.h"
#import "ZNIL2CPPMethodSignature.h"
#import "ZNIL2CPPABIMetadata.h"
#import "ZNValueTypeModel.h"
#import "ZNPatchCore.h"

static NSString *ZNRMATrim(NSString *value) { return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; }
static uint32_t ZNRMAFNV1a32(NSString *text) {
    NSData *data=[text dataUsingEncoding:NSUTF8StringEncoding]?:[NSData data]; const uint8_t *bytes=(const uint8_t *)data.bytes; uint32_t h=UINT32_C(2166136261);
    for(NSUInteger i=0;i<data.length;i++){h^=bytes[i];h*=UINT32_C(16777619);} return h?:1u;
}

NSString *ZNRuntimeArgumentControlTypeName(ZNRuntimeArgumentControlType type) {
    switch(type){case ZNRuntimeArgumentControlTypeSwitch:return @"开关";case ZNRuntimeArgumentControlTypeButton:return @"按钮";case ZNRuntimeArgumentControlTypeNumber:return @"数值";case ZNRuntimeArgumentControlTypeSlider:return @"滑块";default:return @"固定";}
}
NSString *ZNRuntimeArgumentControlTypeKey(ZNRuntimeArgumentControlType type) {
    switch(type){case ZNRuntimeArgumentControlTypeSwitch:return @"switch";case ZNRuntimeArgumentControlTypeButton:return @"button";case ZNRuntimeArgumentControlTypeNumber:return @"number";case ZNRuntimeArgumentControlTypeSlider:return @"slider";default:return @"fixed";}
}
ZNRuntimeArgumentControlType ZNRuntimeArgumentControlTypeFromKey(NSString *key) {
    NSString *k=(key?:@"").lowercaseString; if([k isEqualToString:@"switch"])return ZNRuntimeArgumentControlTypeSwitch;if([k isEqualToString:@"button"])return ZNRuntimeArgumentControlTypeButton;if([k isEqualToString:@"number"])return ZNRuntimeArgumentControlTypeNumber;if([k isEqualToString:@"slider"])return ZNRuntimeArgumentControlTypeSlider;return ZNRuntimeArgumentControlTypeFixed;
}

static NSDictionary *ZNRMAConfig(BOOL enabled, ZNRuntimeArgumentControlType controlType, ZNValueType valueType, NSString *managedType) {
    ZNValueType resolved=valueType==ZNValueTypeAuto?ZNValueTypeForManagedTypeName(managedType):valueType;
    NSDictionary *range=ZNDefaultRangeForValueType(resolved, controlType==ZNRuntimeArgumentControlTypeSlider);
    return @{@"enabled":@(enabled),@"type":ZNRuntimeArgumentControlTypeKey(enabled?controlType:ZNRuntimeArgumentControlTypeFixed),@"valueType":ZNValueTypeKey(valueType),@"default":range[@"default"]?:@1,@"min":range[@"min"]?:@0,@"max":range[@"max"]?:@(INT32_MAX),@"step":range[@"step"]?:@1};
}

static BOOL ZNRMARedirectGPRKind(ZNIL2CPPABIValueKind kind) {
    return kind==ZNIL2CPPABIValueKindBool ||
           kind==ZNIL2CPPABIValueKindSigned32 ||
           kind==ZNIL2CPPABIValueKindUnsigned32 ||
           kind==ZNIL2CPPABIValueKindSigned64 ||
           kind==ZNIL2CPPABIValueKindUnsigned64 ||
           kind==ZNIL2CPPABIValueKindPointer ||
           kind==ZNIL2CPPABIValueKindObjectReference;
}

static NSString *ZNRMARedirectTypeName(NSDictionary *info) {
    return [info[@"name"] isKindOfClass:NSString.class] ? info[@"name"] : @"?";
}

static BOOL ZNRMARedirectCompatibleType(NSDictionary *source, NSDictionary *target) {
    BOOL sourceByRef=[source[@"byRef"] boolValue], targetByRef=[target[@"byRef"] boolValue];
    if(sourceByRef!=targetByRef)return NO;
    if(sourceByRef){
        return [ZNRMARedirectTypeName(source) caseInsensitiveCompare:ZNRMARedirectTypeName(target)]==NSOrderedSame;
    }
    ZNIL2CPPABIValueKind sk=(ZNIL2CPPABIValueKind)[source[@"kind"] integerValue];
    ZNIL2CPPABIValueKind tk=(ZNIL2CPPABIValueKind)[target[@"kind"] integerValue];
    if(sk!=tk || !ZNRMARedirectGPRKind(sk))return NO;
    if(sk==ZNIL2CPPABIValueKindPointer || sk==ZNIL2CPPABIValueKindObjectReference)
        return [ZNRMARedirectTypeName(source) caseInsensitiveCompare:ZNRMARedirectTypeName(target)]==NSOrderedSame;
    return YES;
}

static BOOL ZNRMAValidateMethodRedirectABI(NSDictionary *source, NSDictionary *target, NSDictionary **outMetadata, NSString **error) {
    NSDictionary *sa=ZNIL2CPPDescribeMethodABI(source);
    NSDictionary *ta=ZNIL2CPPDescribeMethodABI(target);
    if(![sa[@"available"] boolValue] || ![ta[@"available"] boolValue]){
        if(error)*error=@"Method Redirect Source/Target ABI metadata 不完整";
        return NO;
    }
    if([sa[@"generic"] boolValue]||[sa[@"inflated"] boolValue]||[ta[@"generic"] boolValue]||[ta[@"inflated"] boolValue]){
        if(error)*error=@"Method Redirect V1 不支持 generic/inflated 方法";
        return NO;
    }
    if(![sa[@"instanceKnown"] boolValue] || ![ta[@"instanceKnown"] boolValue]){
        if(error)*error=@"Method Redirect 无法确认 Source/Target static/instance";
        return NO;
    }
    NSArray *sp=[sa[@"parameters"] isKindOfClass:NSArray.class]?sa[@"parameters"]:@[];
    NSArray *tp=[ta[@"parameters"] isKindOfClass:NSArray.class]?ta[@"parameters"]:@[];
    if(sp.count!=tp.count){
        if(error)*error=@"Method Redirect V1 要求 Source/Target 参数数量一致";
        return NO;
    }
    for(NSUInteger i=0;i<sp.count;i++){
        if(!ZNRMARedirectCompatibleType(sp[i],tp[i])){
            if(error)*error=[NSString stringWithFormat:@"Method Redirect 参数%lu ABI 不兼容：%@ → %@",
                             (unsigned long)i+1,ZNRMARedirectTypeName(sp[i]),ZNRMARedirectTypeName(tp[i])];
            return NO;
        }
    }
    NSDictionary *sr=[sa[@"return"] isKindOfClass:NSDictionary.class]?sa[@"return"]:@{};
    NSDictionary *tr=[ta[@"return"] isKindOfClass:NSDictionary.class]?ta[@"return"]:@{};
    ZNIL2CPPABIValueKind srk=(ZNIL2CPPABIValueKind)[sr[@"kind"] integerValue];
    ZNIL2CPPABIValueKind trk=(ZNIL2CPPABIValueKind)[tr[@"kind"] integerValue];
    BOOL returnOK=(srk==ZNIL2CPPABIValueKindVoid && trk==ZNIL2CPPABIValueKindVoid) ||
                  (srk==trk && ZNRMARedirectGPRKind(srk) && ZNRMARedirectCompatibleType(sr,tr));
    if(!returnOK){
        if(error)*error=[NSString stringWithFormat:@"Method Redirect 返回 ABI 不兼容：%@ → %@",
                         ZNRMARedirectTypeName(sr),ZNRMARedirectTypeName(tr)];
        return NO;
    }
    NSUInteger sourceNative=sp.count+([sa[@"instance"] boolValue]?1u:0u)+1u;
    NSUInteger targetNative=tp.count+([ta[@"instance"] boolValue]?1u:0u)+1u;
    if(sourceNative>8 || targetNative>8){
        if(error)*error=@"Method Redirect V1 超过 ARM64 x0~x7 GPR 参数预算";
        return NO;
    }
    if(outMetadata){
        *outMetadata=@{
            @"sourceInstance":@([sa[@"instance"] boolValue]),
            @"targetInstance":@([ta[@"instance"] boolValue]),
            @"sourceReturnType":ZNRMARedirectTypeName(sr),
            @"targetReturnType":ZNRMARedirectTypeName(tr),
            @"abiValidated":@YES
        };
    }
    return YES;
}

static NSArray<NSDictionary<NSString *,id> *> *ZNRMADefaultConfigs(NSUInteger count, NSArray<NSString *> *parameterTypes) {
    NSMutableArray *items=[NSMutableArray arrayWithCapacity:count];
    for(NSUInteger i=0;i<count;i++){NSString *managed=i<parameterTypes.count?parameterTypes[i]:@"";[items addObject:ZNRMAConfig(NO,ZNRuntimeArgumentControlTypeFixed,ZNValueTypeAuto,managed)];}
    return [items copy];
}

@implementation ZNRuntimeMethodAction
- (instancetype)init { self=[super init];if(!self)return nil;_executionKind=ZNRuntimeExecutionKindMethodCall;_title=@"";_group=@"Runtime Methods";_featureDescription=@"";_assembly=@"Assembly-CSharp.dll";_namespaceName=@"";_className=@"";_methodName=@"";_argumentValues=@[];_parameterTypeNames=@[];_signatureAvailable=NO;_argumentControlConfigs=@[];_immediateChain=@{};_methodRedirectTarget=@{};return self; }
- (NSString *)legacyCanonicalIdentity {NSString *owner=self.namespaceName.length?[NSString stringWithFormat:@"%@.%@",self.namespaceName,self.className]:self.className;return [NSString stringWithFormat:@"%@!%@::%@/%lu",self.assembly?:@"",owner?:@"",self.methodName?:@"",(unsigned long)self.argumentCount];}
- (NSString *)canonicalIdentity {if(self.signatureAvailable&&self.parameterTypeNames.count==self.argumentCount)return ZNIL2CPPFullMethodIdentity(self.assembly?:@"",self.namespaceName?:@"",self.className?:@"",self.methodName?:@"",self.parameterTypeNames?:@[]);return self.legacyCanonicalIdentity;}
- (id)copyWithZone:(NSZone *)zone {ZNRuntimeMethodAction *copy=[[[self class] allocWithZone:zone]init];copy.actionID=self.actionID;copy.executionKind=self.executionKind;copy.title=self.title;copy.group=self.group;copy.featureDescription=self.featureDescription?:@"";copy.assembly=self.assembly;copy.namespaceName=self.namespaceName;copy.className=self.className;copy.methodName=self.methodName;copy.methodRVA=self.methodRVA;copy.argumentCount=self.argumentCount;copy.argumentValues=self.argumentValues?:@[];copy.parameterTypeNames=self.parameterTypeNames?:@[];copy.signatureAvailable=self.signatureAvailable;copy.argumentControlConfigs=self.argumentControlConfigs?:@[];copy.immediateChain=self.immediateChain?:@{};copy.methodRedirectTarget=self.methodRedirectTarget?:@{};return copy;}
@end

@interface ZNRuntimeActionStore ()
@property(nonatomic,strong) NSMutableArray<ZNRuntimeMethodAction *> *mutableActions;
@end
@implementation ZNRuntimeActionStore
+ (instancetype)sharedStore {static ZNRuntimeActionStore *store;static dispatch_once_t once;dispatch_once(&once,^{store=[ZNRuntimeActionStore new];});return store;}
- (instancetype)init {self=[super init];if(!self)return nil;_mutableActions=[NSMutableArray array];return self;}
- (NSArray<ZNRuntimeMethodAction *> *)actions{return [self actionsSnapshot];}
- (ZNRuntimeMethodAction *)addMethodCandidate:(NSDictionary<NSString *,id> *)candidate title:(NSString *)title error:(NSString **)error{return [self addMethodCandidate:candidate title:title argumentValues:@[] error:error];}
- (ZNRuntimeMethodAction *)addMethodCandidate:(NSDictionary<NSString *,id> *)candidate title:(NSString *)title argumentValues:(NSArray<NSString *> *)argumentValues error:(NSString **)error {
    NSString *assembly=ZNRMATrim([candidate[@"assembly"] isKindOfClass:NSString.class]?candidate[@"assembly"]:@"");NSString *namespaceName=ZNRMATrim([candidate[@"namespace"] isKindOfClass:NSString.class]?candidate[@"namespace"]:@"");NSString *className=ZNRMATrim([candidate[@"class"] isKindOfClass:NSString.class]?candidate[@"class"]:@"");NSString *methodName=ZNRMATrim([candidate[@"method"] isKindOfClass:NSString.class]?candidate[@"method"]:@"");NSInteger argc=[candidate[@"argumentCount"] respondsToSelector:@selector(integerValue)]?[candidate[@"argumentCount"] integerValue]:-1;
    if(!assembly.length)assembly=@"Assembly-CSharp.dll";if(!className.length||!methodName.length||argc<0){if(error)*error=@"方法身份不完整，无法创建 Runtime Method Call";return nil;}if((NSUInteger)argc>ZN_RUNTIME_ACTION_MAX_ARGUMENTS){if(error)*error=[NSString stringWithFormat:@"参数数量超过上限 %u",ZN_RUNTIME_ACTION_MAX_ARGUMENTS];return nil;}
    NSArray<NSString *> *values=argumentValues?:@[];if(argc==0)values=@[];if(argc>0&&values.count!=(NSUInteger)argc){if(error)*error=[NSString stringWithFormat:@"/%ld 方法必须提供 %ld 个参数值",(long)argc,(long)argc];return nil;}
    NSArray<NSString *> *parameterTypes=nil;BOOL signatureAvailable=NO;id candidateTypes=candidate[@"parameterTypeNames"];
    if([candidateTypes isKindOfClass:NSArray.class]&&[(NSArray *)candidateTypes count]==(NSUInteger)argc){parameterTypes=[candidateTypes copy];signatureAvailable=![candidate[@"signatureAvailable"] respondsToSelector:@selector(boolValue)]||[candidate[@"signatureAvailable"] boolValue];}
    if(!signatureAvailable){NSString *signatureError=nil;NSArray<NSString *> *derived=ZNIL2CPPParameterTypeNamesForCandidate(candidate,&signatureError);if(derived&&derived.count==(NSUInteger)argc){parameterTypes=derived;signatureAvailable=YES;}else [[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[m4.6-signature] authoring legacy fallback %@::%@/%ld reason=%@",className,methodName,(long)argc,signatureError?:@"signature unavailable"]];}
    ZNRuntimeMethodAction *action=[ZNRuntimeMethodAction new];
    NSInteger requestedKind=[candidate[@"znExecutionKind"] integerValue];
    action.executionKind=(requestedKind==ZNRuntimeExecutionKindDirectNativeCall)?ZNRuntimeExecutionKindDirectNativeCall:ZNRuntimeExecutionKindMethodCall;
    uint64_t methodRVA=[candidate[@"methodRVA"] respondsToSelector:@selector(unsignedLongLongValue)]?[candidate[@"methodRVA"] unsignedLongLongValue]:0;
    if(!methodRVA&&[candidate[@"rva"] respondsToSelector:@selector(unsignedLongLongValue)])methodRVA=[candidate[@"rva"] unsignedLongLongValue];
    if(action.executionKind==ZNRuntimeExecutionKindDirectNativeCall&&!methodRVA){if(error)*error=@"Direct Native Call 必须来自已解析 RVA 的候选";return nil;}
    action.assembly=assembly;action.namespaceName=namespaceName;action.className=className;action.methodName=methodName;action.methodRVA=methodRVA;action.argumentCount=(NSUInteger)argc;action.argumentValues=[values copy];action.parameterTypeNames=parameterTypes?:@[];action.signatureAvailable=signatureAvailable;action.title=ZNRMATrim(title).length?ZNRMATrim(title):methodName;action.group=(action.executionKind==ZNRuntimeExecutionKindDirectNativeCall)?@"Direct Native Calls":@"Runtime Methods";action.argumentControlConfigs=ZNRMADefaultConfigs(action.argumentCount,action.parameterTypeNames);
    @synchronized(self){uint32_t serial=0;BOOL collision=NO;do{NSString *seed=[NSString stringWithFormat:@"%ld|%@|0x%llX|%@|%@|%lu|%u",(long)action.executionKind,action.canonicalIdentity?:@"",(unsigned long long)action.methodRVA,action.title?:@"",action.argumentValues?:@[],(unsigned long)self.mutableActions.count,serial++];action.actionID=ZNRMAFNV1a32(seed);collision=NO;for(ZNRuntimeMethodAction *existing in self.mutableActions)if(existing.actionID==action.actionID){collision=YES;break;}}while(collision);[self.mutableActions addObject:action];}
    [[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[m5.5-typed] add id=%u %@ rva=0x%llX types=%@",action.actionID,action.canonicalIdentity,(unsigned long long)action.methodRVA,action.parameterTypeNames]];return [action copy];
}
- (ZNRuntimeMethodAction *)addDirectNativeCallCandidate:(NSDictionary<NSString *,id> *)candidate
                                                  title:(NSString *)title
                                         argumentValues:(NSArray<NSString *> *)argumentValues
                                                  error:(NSString **)error {
    NSMutableDictionary *tagged=[candidate mutableCopy]?:[NSMutableDictionary dictionary];
    tagged[@"znExecutionKind"]=@(ZNRuntimeExecutionKindDirectNativeCall);
    return [self addMethodCandidate:tagged title:title argumentValues:argumentValues error:error];
}

- (ZNRuntimeMethodAction *)addMethodRedirectSourceCandidate:(NSDictionary<NSString *,id> *)source
                                            targetCandidate:(NSDictionary<NSString *,id> *)target
                                                      title:(NSString *)title
                                                      error:(NSString **)error {
    if(![source isKindOfClass:NSDictionary.class]||![target isKindOfClass:NSDictionary.class]){
        if(error)*error=@"Method Redirect 需要 Source 和 Target 方法";
        return nil;
    }
    NSString *sourceAssembly=ZNRMATrim([source[@"assembly"] isKindOfClass:NSString.class]?source[@"assembly"]:@"");
    NSString *sourceNS=ZNRMATrim([source[@"namespace"] isKindOfClass:NSString.class]?source[@"namespace"]:@"");
    NSString *sourceClass=ZNRMATrim([source[@"class"] isKindOfClass:NSString.class]?source[@"class"]:@"");
    NSString *sourceMethod=ZNRMATrim([source[@"method"] isKindOfClass:NSString.class]?source[@"method"]:@"");
    NSInteger sourceArgc=[source[@"argumentCount"] respondsToSelector:@selector(integerValue)]?[source[@"argumentCount"] integerValue]:-1;
    NSString *targetAssembly=ZNRMATrim([target[@"assembly"] isKindOfClass:NSString.class]?target[@"assembly"]:@"");
    NSString *targetNS=ZNRMATrim([target[@"namespace"] isKindOfClass:NSString.class]?target[@"namespace"]:@"");
    NSString *targetClass=ZNRMATrim([target[@"class"] isKindOfClass:NSString.class]?target[@"class"]:@"");
    NSString *targetMethod=ZNRMATrim([target[@"method"] isKindOfClass:NSString.class]?target[@"method"]:@"");
    NSInteger targetArgc=[target[@"argumentCount"] respondsToSelector:@selector(integerValue)]?[target[@"argumentCount"] integerValue]:-1;
    if(!sourceAssembly.length)sourceAssembly=@"Assembly-CSharp.dll";
    if(!targetAssembly.length)targetAssembly=@"Assembly-CSharp.dll";
    if(!sourceClass.length||!sourceMethod.length||sourceArgc<0||sourceArgc>(NSInteger)ZN_RUNTIME_ACTION_MAX_ARGUMENTS||
       !targetClass.length||!targetMethod.length||targetArgc<0||targetArgc>(NSInteger)ZN_RUNTIME_ACTION_MAX_ARGUMENTS){
        if(error)*error=@"Method Redirect Source/Target 方法身份不完整";
        return nil;
    }
    uint64_t sourceRVA=[source[@"methodRVA"] respondsToSelector:@selector(unsignedLongLongValue)]?[source[@"methodRVA"] unsignedLongLongValue]:0;
    if(!sourceRVA&&[source[@"rva"] respondsToSelector:@selector(unsignedLongLongValue)])sourceRVA=[source[@"rva"] unsignedLongLongValue];
    uint64_t targetRVA=[target[@"methodRVA"] respondsToSelector:@selector(unsignedLongLongValue)]?[target[@"methodRVA"] unsignedLongLongValue]:0;
    if(!targetRVA&&[target[@"rva"] respondsToSelector:@selector(unsignedLongLongValue)])targetRVA=[target[@"rva"] unsignedLongLongValue];
    if(!sourceRVA||!targetRVA){
        if(error)*error=@"Method Redirect Source/Target 必须来自已解析 RVA 的 Method Finder 候选";
        return nil;
    }
    NSDictionary *redirectABIMetadata=nil;
    if(!ZNRMAValidateMethodRedirectABI(source,target,&redirectABIMetadata,error))return nil;

    NSArray<NSString *> *sourceTypes=nil;BOOL sourceSig=NO;
    id sourceCandidateTypes=source[@"parameterTypeNames"];
    if([sourceCandidateTypes isKindOfClass:NSArray.class]&&[(NSArray *)sourceCandidateTypes count]==(NSUInteger)sourceArgc){
        sourceTypes=[sourceCandidateTypes copy];
        sourceSig=![source[@"signatureAvailable"] respondsToSelector:@selector(boolValue)]||[source[@"signatureAvailable"] boolValue];
    }
    if(!sourceSig){
        NSString *sigError=nil;
        NSArray<NSString *> *derived=ZNIL2CPPParameterTypeNamesForCandidate(source,&sigError);
        if(derived&&derived.count==(NSUInteger)sourceArgc){sourceTypes=derived;sourceSig=YES;}
    }

    NSArray<NSString *> *targetTypes=nil;BOOL targetSig=NO;
    id targetCandidateTypes=target[@"parameterTypeNames"];
    if([targetCandidateTypes isKindOfClass:NSArray.class]&&[(NSArray *)targetCandidateTypes count]==(NSUInteger)targetArgc){
        targetTypes=[targetCandidateTypes copy];
        targetSig=![target[@"signatureAvailable"] respondsToSelector:@selector(boolValue)]||[target[@"signatureAvailable"] boolValue];
    }
    if(!targetSig){
        NSString *sigError=nil;
        NSArray<NSString *> *derived=ZNIL2CPPParameterTypeNamesForCandidate(target,&sigError);
        if(derived&&derived.count==(NSUInteger)targetArgc){targetTypes=derived;targetSig=YES;}
    }

    ZNRuntimeMethodAction *action=[ZNRuntimeMethodAction new];
    action.executionKind=ZNRuntimeExecutionKindMethodRedirect;
    action.assembly=sourceAssembly;action.namespaceName=sourceNS;action.className=sourceClass;action.methodName=sourceMethod;
    action.methodRVA=sourceRVA;action.argumentCount=(NSUInteger)sourceArgc;action.argumentValues=@[];
    action.parameterTypeNames=sourceTypes?:@[];action.signatureAvailable=sourceSig;
    action.argumentControlConfigs=@[];action.immediateChain=@{};
    action.methodRedirectTarget=@{
        @"assembly":targetAssembly,
        @"namespace":targetNS,
        @"class":targetClass,
        @"method":targetMethod,
        @"argumentCount":@(targetArgc),
        @"methodRVA":@(targetRVA),
        @"parameterTypeNames":targetTypes?:@[],
        @"signatureAvailable":@(targetSig),
        @"sourceInstance":redirectABIMetadata[@"sourceInstance"]?:@NO,
        @"targetInstance":redirectABIMetadata[@"targetInstance"]?:@NO,
        @"sourceReturnType":redirectABIMetadata[@"sourceReturnType"]?:@"?",
        @"targetReturnType":redirectABIMetadata[@"targetReturnType"]?:@"?",
        @"abiValidated":@YES,
    };
    action.title=ZNRMATrim(title).length?ZNRMATrim(title):[NSString stringWithFormat:@"%@ → %@",sourceMethod,targetMethod];
    action.group=@"Method Redirects";

    @synchronized(self){
        uint32_t serial=0;BOOL collision=NO;
        do{
            NSString *seed=[NSString stringWithFormat:@"redirect|%@|%@|0x%llX|0x%llX|%@|%lu|%u",
                            action.canonicalIdentity,targetClass,(unsigned long long)sourceRVA,(unsigned long long)targetRVA,
                            action.title?:@"",(unsigned long)self.mutableActions.count,serial++];
            action.actionID=ZNRMAFNV1a32(seed);
            collision=NO;
            for(ZNRuntimeMethodAction *existing in self.mutableActions)if(existing.actionID==action.actionID){collision=YES;break;}
        }while(collision);
        [self.mutableActions addObject:action];
    }
    [[ZNRuntimeLogger sharedLogger]log:[NSString stringWithFormat:@"[method-redirect] add id=%u %@ -> %@::%@/%ld",
        action.actionID,action.canonicalIdentity,targetClass,targetMethod,(long)targetArgc]];
    return [action copy];
}

- (BOOL)updateTitle:(NSString *)title atIndex:(NSUInteger)index error:(NSString **)error {NSString *trimmed=ZNRMATrim(title);@synchronized(self){if(index>=self.mutableActions.count){if(error)*error=@"Runtime Method Call 索引已失效";return NO;}ZNRuntimeMethodAction *action=self.mutableActions[index];action.title=trimmed.length?trimmed:action.methodName;return YES;}}
- (BOOL)updateFeatureDescription:(NSString *)featureDescription atIndex:(NSUInteger)index error:(NSString **)error {NSString *trimmed=ZNRMATrim(featureDescription);@synchronized(self){if(index>=self.mutableActions.count){if(error)*error=@"Runtime Method Call 索引已失效";return NO;}self.mutableActions[index].featureDescription=trimmed?:@"";return YES;}}
- (BOOL)updateArgumentValues:(NSArray<NSString *> *)argumentValues atIndex:(NSUInteger)index error:(NSString **)error {@synchronized(self){if(index>=self.mutableActions.count){if(error)*error=@"Runtime Method Call 索引已失效";return NO;}ZNRuntimeMethodAction *action=self.mutableActions[index];NSArray<NSString *> *values=argumentValues?:@[];if(action.argumentCount==0)values=@[];if(action.argumentCount>0&&values.count!=action.argumentCount){if(error)*error=@"参数数量不匹配";return NO;}action.argumentValues=[values copy];return YES;}}
- (BOOL)updateArgumentControlConfigs:(NSArray<NSDictionary<NSString *,id> *> *)configs atIndex:(NSUInteger)index error:(NSString **)error {
    @synchronized(self){if(index>=self.mutableActions.count){if(error)*error=@"Runtime Method Call 索引已失效";return NO;}ZNRuntimeMethodAction *action=self.mutableActions[index];if(configs.count!=action.argumentCount){if(error)*error=@"参数控件配置数量必须等于 argc";return NO;}NSMutableArray *clean=[NSMutableArray arrayWithCapacity:configs.count];
        for(NSUInteger i=0;i<configs.count;i++){NSDictionary *raw=configs[i];BOOL enabled=[raw[@"enabled"]boolValue];ZNRuntimeArgumentControlType control=enabled?ZNRuntimeArgumentControlTypeFromKey(raw[@"type"]):ZNRuntimeArgumentControlTypeFixed;ZNValueType vt=ZNValueTypeFromKey([raw[@"valueType"] isKindOfClass:NSString.class]?raw[@"valueType"]:@"auto");NSString *managed=i<action.parameterTypeNames.count?action.parameterTypeNames[i]:@"";ZNValueType resolved=vt==ZNValueTypeAuto?ZNValueTypeForManagedTypeName(managed):vt;NSDictionary *defaults=ZNDefaultRangeForValueType(resolved,control==ZNRuntimeArgumentControlTypeSlider);[clean addObject:@{@"enabled":@(enabled),@"type":ZNRuntimeArgumentControlTypeKey(control),@"valueType":ZNValueTypeKey(vt),@"default":raw[@"default"]?:defaults[@"default"]?:@1,@"min":raw[@"min"]?:defaults[@"min"]?:@0,@"max":raw[@"max"]?:defaults[@"max"]?:@(INT32_MAX),@"step":raw[@"step"]?:defaults[@"step"]?:@1}];}
        action.argumentControlConfigs=[clean copy];return YES;}
}
- (BOOL)updateImmediateChain:(NSDictionary<NSString *,id> *)chain atIndex:(NSUInteger)index error:(NSString **)error {@synchronized(self){if(index>=self.mutableActions.count){if(error)*error=@"Runtime Method Call 索引已失效";return NO;}ZNRuntimeMethodAction *action=self.mutableActions[index];if(!chain.count){action.immediateChain=@{};return YES;}NSString *className=[chain[@"class"] isKindOfClass:NSString.class]?chain[@"class"]:@"";NSString *method=[chain[@"method"] isKindOfClass:NSString.class]?chain[@"method"]:@"";NSInteger argc=[chain[@"argumentCount"]integerValue];if(!className.length||!method.length||argc<0||argc>(NSInteger)ZN_RUNTIME_ACTION_MAX_ARGUMENTS){if(error)*error=@"链式目标 Class/Method/argc 无效";return NO;}action.immediateChain=[chain copy];return YES;}}
- (BOOL)removeActionAtIndex:(NSUInteger)index {@synchronized(self){if(index>=self.mutableActions.count)return NO;[self.mutableActions removeObjectAtIndex:index];return YES;}}
- (void)clear {@synchronized(self){[self.mutableActions removeAllObjects];}}
- (NSArray<ZNRuntimeMethodAction *> *)actionsSnapshot {@synchronized(self){NSMutableArray *copy=[NSMutableArray arrayWithCapacity:self.mutableActions.count];for(ZNRuntimeMethodAction *action in self.mutableActions)[copy addObject:[action copy]];return [copy copy];}}

- (NSArray<NSDictionary<NSString *,id> *> *)exportDictionaries {
    @synchronized(self){
        NSMutableArray *out=[NSMutableArray arrayWithCapacity:self.mutableActions.count];
        for(ZNRuntimeMethodAction *a in self.mutableActions){
            [out addObject:@{
                @"actionID":@(a.actionID), @"executionKind":@(a.executionKind),
                @"title":a.title?:@"", @"group":a.group?:@"", @"description":a.featureDescription?:@"",
                @"assembly":a.assembly?:@"Assembly-CSharp.dll", @"namespace":a.namespaceName?:@"",
                @"class":a.className?:@"", @"method":a.methodName?:@"", @"methodRVA":@(a.methodRVA),
                @"argumentCount":@(a.argumentCount), @"argumentValues":a.argumentValues?:@[],
                @"parameterTypeNames":a.parameterTypeNames?:@[], @"signatureAvailable":@(a.signatureAvailable),
                @"argumentControls":a.argumentControlConfigs?:@[], @"immediateChain":a.immediateChain?:@{},
                @"methodRedirectTarget":a.methodRedirectTarget?:@{}
            }];
        }
        return [out copy];
    }
}

- (BOOL)replaceWithImportedDictionaries:(NSArray<NSDictionary<NSString *,id> *> *)items error:(NSString **)error {
    if(![items isKindOfClass:NSArray.class]){if(error)*error=@"Runtime Actions JSON 不是数组";return NO;}
    NSMutableArray<ZNRuntimeMethodAction *> *parsed=[NSMutableArray arrayWithCapacity:items.count];
    NSMutableSet<NSNumber *> *ids=[NSMutableSet set];
    for(NSUInteger i=0;i<items.count;i++){
        NSDictionary *d=[items[i] isKindOfClass:NSDictionary.class]?items[i]:nil;
        if(!d){if(error)*error=[NSString stringWithFormat:@"Runtime Action #%lu 格式无效",(unsigned long)i+1];return NO;}
        ZNRuntimeMethodAction *a=[ZNRuntimeMethodAction new];
        NSInteger kind=[d[@"executionKind"] integerValue];
        if(kind!=ZNRuntimeExecutionKindMethodCall&&kind!=ZNRuntimeExecutionKindDirectNativeCall&&kind!=ZNRuntimeExecutionKindMethodRedirect){if(error)*error=[NSString stringWithFormat:@"Runtime Action #%lu executionKind 无效",(unsigned long)i+1];return NO;}
        a.executionKind=(ZNRuntimeExecutionKind)kind;
        a.title=ZNRMATrim([d[@"title"] isKindOfClass:NSString.class]?d[@"title"]:@"");
        a.group=ZNRMATrim([d[@"group"] isKindOfClass:NSString.class]?d[@"group"]:@"");
        a.featureDescription=ZNRMATrim([d[@"description"] isKindOfClass:NSString.class]?d[@"description"]:@"");
        a.assembly=ZNRMATrim([d[@"assembly"] isKindOfClass:NSString.class]?d[@"assembly"]:@""); if(!a.assembly.length)a.assembly=@"Assembly-CSharp.dll";
        a.namespaceName=ZNRMATrim([d[@"namespace"] isKindOfClass:NSString.class]?d[@"namespace"]:@"");
        a.className=ZNRMATrim([d[@"class"] isKindOfClass:NSString.class]?d[@"class"]:@"");
        a.methodName=ZNRMATrim([d[@"method"] isKindOfClass:NSString.class]?d[@"method"]:@"");
        a.methodRVA=[d[@"methodRVA"] unsignedLongLongValue];
        a.argumentCount=[d[@"argumentCount"] unsignedIntegerValue];
        if(!a.className.length||!a.methodName.length||a.argumentCount>ZN_RUNTIME_ACTION_MAX_ARGUMENTS){if(error)*error=[NSString stringWithFormat:@"Runtime Action #%lu 方法身份/参数数量无效",(unsigned long)i+1];return NO;}
        if((a.executionKind==ZNRuntimeExecutionKindDirectNativeCall||a.executionKind==ZNRuntimeExecutionKindMethodRedirect)&&!a.methodRVA){if(error)*error=[NSString stringWithFormat:@"Runtime Action #%lu 缺少 methodRVA",(unsigned long)i+1];return NO;}
        NSArray *values=[d[@"argumentValues"] isKindOfClass:NSArray.class]?d[@"argumentValues"]:@[];
        if(a.executionKind==ZNRuntimeExecutionKindMethodRedirect){
            if(values.count){if(error)*error=[NSString stringWithFormat:@"Method Redirect #%lu 不应持久化参数值",(unsigned long)i+1];return NO;}
            a.argumentValues=@[];
        }else{
            if(values.count!=a.argumentCount){if(error)*error=[NSString stringWithFormat:@"Runtime Action #%lu 参数值数量不匹配",(unsigned long)i+1];return NO;}
            a.argumentValues=[values copy];
        }
        NSArray *types=[d[@"parameterTypeNames"] isKindOfClass:NSArray.class]?d[@"parameterTypeNames"]:@[];
        a.signatureAvailable=[d[@"signatureAvailable"] boolValue]&&types.count==a.argumentCount;
        a.parameterTypeNames=a.signatureAvailable?[types copy]:@[];
        NSArray *controls=[d[@"argumentControls"] isKindOfClass:NSArray.class]?d[@"argumentControls"]:@[];
        a.argumentControlConfigs=(a.executionKind==ZNRuntimeExecutionKindMethodRedirect)?@[]:(controls.count==a.argumentCount?[controls copy]:ZNRMADefaultConfigs(a.argumentCount,a.parameterTypeNames));
        a.immediateChain=[d[@"immediateChain"] isKindOfClass:NSDictionary.class]?[d[@"immediateChain"] copy]:@{};
        a.methodRedirectTarget=[d[@"methodRedirectTarget"] isKindOfClass:NSDictionary.class]?[d[@"methodRedirectTarget"] copy]:@{};
        if(a.executionKind==ZNRuntimeExecutionKindMethodRedirect){
            NSDictionary *t=a.methodRedirectTarget;
            NSString *tc=ZNRMATrim([t[@"class"] isKindOfClass:NSString.class]?t[@"class"]:@"");
            NSString *tm=ZNRMATrim([t[@"method"] isKindOfClass:NSString.class]?t[@"method"]:@"");
            NSInteger ta=[t[@"argumentCount"] integerValue];
            uint64_t tr=[t[@"methodRVA"] unsignedLongLongValue];
            if(!tc.length||!tm.length||ta<0||ta>(NSInteger)ZN_RUNTIME_ACTION_MAX_ARGUMENTS||!tr){
                if(error)*error=[NSString stringWithFormat:@"Method Redirect #%lu Target descriptor 无效",(unsigned long)i+1];
                return NO;
            }
        }
        uint32_t actionID=[d[@"actionID"] unsignedIntValue];
        if(!actionID){NSString *seed=[NSString stringWithFormat:@"import|%ld|%@|0x%llX|%lu",(long)a.executionKind,a.canonicalIdentity,(unsigned long long)a.methodRVA,(unsigned long)i];actionID=ZNRMAFNV1a32(seed);}
        if([ids containsObject:@(actionID)]){if(error)*error=[NSString stringWithFormat:@"Runtime Action #%lu actionID 重复",(unsigned long)i+1];return NO;}
        [ids addObject:@(actionID)];a.actionID=actionID;
        if(!a.title.length)a.title=a.methodName;
        if(!a.group.length)a.group=(a.executionKind==ZNRuntimeExecutionKindDirectNativeCall)?@"Direct Native Calls":(a.executionKind==ZNRuntimeExecutionKindMethodRedirect?@"Method Redirects":@"Runtime Methods");
        [parsed addObject:a];
    }
    @synchronized(self){self.mutableActions=parsed;}
    return YES;
}
@end
