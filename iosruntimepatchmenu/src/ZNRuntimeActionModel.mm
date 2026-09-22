#import "ZNRuntimeActionModel.h"
#import "ZNIL2CPPMethodSignature.h"
#import "ZNPatchCore.h"

static NSString *ZNRMATrim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static uint32_t ZNRMAFNV1a32(NSString *text) {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    uint32_t h = UINT32_C(2166136261);
    for (NSUInteger i = 0; i < data.length; i++) {
        h ^= bytes[i];
        h *= UINT32_C(16777619);
    }
    return h ? h : 1u;
}

@implementation ZNRuntimeMethodAction

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _title = @"";
    _group = @"Runtime Methods";
    _assembly = @"Assembly-CSharp.dll";
    _namespaceName = @"";
    _className = @"";
    _methodName = @"";
    _argumentValues = @[];
    _parameterTypeNames = @[];
    _signatureAvailable = NO;
    return self;
}

- (NSString *)legacyCanonicalIdentity {
    NSString *owner = self.namespaceName.length
        ? [NSString stringWithFormat:@"%@.%@", self.namespaceName, self.className]
        : self.className;
    return [NSString stringWithFormat:@"%@!%@::%@/%lu",
            self.assembly ?: @"",
            owner ?: @"",
            self.methodName ?: @"",
            (unsigned long)self.argumentCount];
}

- (NSString *)canonicalIdentity {
    if (self.signatureAvailable && self.parameterTypeNames.count == self.argumentCount) {
        return ZNIL2CPPFullMethodIdentity(self.assembly ?: @"",
                                          self.namespaceName ?: @"",
                                          self.className ?: @"",
                                          self.methodName ?: @"",
                                          self.parameterTypeNames ?: @[]);
    }
    return self.legacyCanonicalIdentity;
}

- (id)copyWithZone:(NSZone *)zone {
    ZNRuntimeMethodAction *copy = [[[self class] allocWithZone:zone] init];
    copy.actionID = self.actionID;
    copy.title = self.title;
    copy.group = self.group;
    copy.assembly = self.assembly;
    copy.namespaceName = self.namespaceName;
    copy.className = self.className;
    copy.methodName = self.methodName;
    copy.argumentCount = self.argumentCount;
    copy.argumentValues = self.argumentValues ?: @[];
    copy.parameterTypeNames = self.parameterTypeNames ?: @[];
    copy.signatureAvailable = self.signatureAvailable;
    return copy;
}

@end

@interface ZNRuntimeActionStore ()
@property(nonatomic,strong) NSMutableArray<ZNRuntimeMethodAction *> *mutableActions;
@end

@implementation ZNRuntimeActionStore

+ (instancetype)sharedStore {
    static ZNRuntimeActionStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ store = [ZNRuntimeActionStore new]; });
    return store;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _mutableActions = [NSMutableArray array];
    return self;
}

- (NSArray<ZNRuntimeMethodAction *> *)actions {
    return [self actionsSnapshot];
}

- (ZNRuntimeMethodAction *)addMethodCandidate:(NSDictionary<NSString *,id> *)candidate
                                         title:(NSString *)title
                                         error:(NSString **)error {
    return [self addMethodCandidate:candidate title:title argumentValues:@[] error:error];
}

- (ZNRuntimeMethodAction *)addMethodCandidate:(NSDictionary<NSString *,id> *)candidate
                                         title:(NSString *)title
                                argumentValues:(NSArray<NSString *> *)argumentValues
                                         error:(NSString **)error {
    NSString *assembly = ZNRMATrim([candidate[@"assembly"] isKindOfClass:NSString.class] ? candidate[@"assembly"] : @"");
    NSString *namespaceName = ZNRMATrim([candidate[@"namespace"] isKindOfClass:NSString.class] ? candidate[@"namespace"] : @"");
    NSString *className = ZNRMATrim([candidate[@"class"] isKindOfClass:NSString.class] ? candidate[@"class"] : @"");
    NSString *methodName = ZNRMATrim([candidate[@"method"] isKindOfClass:NSString.class] ? candidate[@"method"] : @"");
    NSInteger argc = [candidate[@"argumentCount"] respondsToSelector:@selector(integerValue)] ? [candidate[@"argumentCount"] integerValue] : -1;

    if (!assembly.length) assembly = @"Assembly-CSharp.dll";
    if (!className.length || !methodName.length || argc < 0) {
        if (error) *error = @"方法身份不完整，无法创建 Runtime Method Call";
        return nil;
    }
    if (argc > 1) {
        if (error) *error = [NSString stringWithFormat:@"M4.2 首版支持 /0 与 /1；当前 argumentCount=%ld", (long)argc];
        return nil;
    }
    NSArray<NSString *> *values = argumentValues ?: @[];
    if (argc == 0) values = @[];
    if (argc == 1 && values.count != 1) {
        if (error) *error = @"/1 方法必须提供 1 个参数值";
        return nil;
    }

    NSArray<NSString *> *parameterTypes = nil;
    BOOL signatureAvailable = NO;
    id candidateTypes = candidate[@"parameterTypeNames"];
    if ([candidateTypes isKindOfClass:NSArray.class] && [(NSArray *)candidateTypes count] == (NSUInteger)argc) {
        parameterTypes = [candidateTypes copy];
        signatureAvailable = ![candidate[@"signatureAvailable"] respondsToSelector:@selector(boolValue)] || [candidate[@"signatureAvailable"] boolValue];
    }
    if (!signatureAvailable) {
        NSString *signatureError = nil;
        NSArray<NSString *> *derived = ZNIL2CPPParameterTypeNamesForCandidate(candidate, &signatureError);
        if (derived && derived.count == (NSUInteger)argc) {
            parameterTypes = derived;
            signatureAvailable = YES;
        } else {
            [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m4.6-signature] authoring legacy fallback %@::%@/%ld reason=%@",
                                                 className, methodName, (long)argc, signatureError ?: @"signature unavailable"]];
        }
    }

    ZNRuntimeMethodAction *action = [ZNRuntimeMethodAction new];
    action.assembly = assembly;
    action.namespaceName = namespaceName;
    action.className = className;
    action.methodName = methodName;
    action.argumentCount = (NSUInteger)argc;
    action.argumentValues = [values copy];
    action.parameterTypeNames = parameterTypes ?: @[];
    action.signatureAvailable = signatureAvailable;
    action.title = ZNRMATrim(title).length ? ZNRMATrim(title) : methodName;
    action.group = @"Runtime Methods";
    action.actionID = ZNRMAFNV1a32(action.canonicalIdentity);

    @synchronized (self) {
        for (ZNRuntimeMethodAction *existing in self.mutableActions) {
            if ([existing.canonicalIdentity isEqualToString:action.canonicalIdentity]) {
                if (error) *error = @"该方法按钮已存在；可在 Builder 中修改名称/参数";
                return [existing copy];
            }
        }
        [self.mutableActions addObject:action];
    }

    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[runtime-method-call] authoring add id=%u %@ args=%@ signature=%@",
                                         action.actionID,
                                         action.canonicalIdentity,
                                         action.argumentValues,
                                         action.signatureAvailable ? @"full" : @"legacy"]];
    return [action copy];
}

- (BOOL)updateTitle:(NSString *)title atIndex:(NSUInteger)index error:(NSString **)error {
    NSString *trimmed = ZNRMATrim(title);
    @synchronized (self) {
        if (index >= self.mutableActions.count) {
            if (error) *error = @"Runtime Method Call 索引已失效";
            return NO;
        }
        ZNRuntimeMethodAction *action = self.mutableActions[index];
        action.title = trimmed.length ? trimmed : action.methodName;
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[runtime-method-call] authoring rename id=%u title=%@",
                                             action.actionID,
                                             action.title]];
        return YES;
    }
}

- (BOOL)updateArgumentValues:(NSArray<NSString *> *)argumentValues atIndex:(NSUInteger)index error:(NSString **)error {
    @synchronized (self) {
        if (index >= self.mutableActions.count) {
            if (error) *error = @"Runtime Method Call 索引已失效";
            return NO;
        }
        ZNRuntimeMethodAction *action = self.mutableActions[index];
        NSArray<NSString *> *values = argumentValues ?: @[];
        if (action.argumentCount == 0) values = @[];
        if (action.argumentCount == 1 && values.count != 1) {
            if (error) *error = @"/1 方法必须保存 1 个参数值";
            return NO;
        }
        if (action.argumentCount > 1) {
            if (error) *error = @"M4.2 首版仅允许编辑 /0 与 /1 参数";
            return NO;
        }
        action.argumentValues = [values copy];
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[runtime-method-call] authoring args id=%u values=%@",
                                             action.actionID,
                                             action.argumentValues]];
        return YES;
    }
}

- (BOOL)removeActionAtIndex:(NSUInteger)index {
    @synchronized (self) {
        if (index >= self.mutableActions.count) return NO;
        ZNRuntimeMethodAction *action = self.mutableActions[index];
        [self.mutableActions removeObjectAtIndex:index];
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[runtime-method-call] authoring remove id=%u %@",
                                             action.actionID,
                                             action.canonicalIdentity]];
        return YES;
    }
}

- (void)clear {
    @synchronized (self) {
        [self.mutableActions removeAllObjects];
    }
    [[ZNRuntimeLogger sharedLogger] log:@"[runtime-method-call] authoring actions cleared"];
}

- (NSArray<ZNRuntimeMethodAction *> *)actionsSnapshot {
    @synchronized (self) {
        NSMutableArray *copy = [NSMutableArray arrayWithCapacity:self.mutableActions.count];
        for (ZNRuntimeMethodAction *action in self.mutableActions) [copy addObject:[action copy]];
        return [copy copy];
    }
}

@end
