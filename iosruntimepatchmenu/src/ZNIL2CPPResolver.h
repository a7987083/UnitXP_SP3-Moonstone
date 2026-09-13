#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZNIL2CPPResolver : NSObject
+ (instancetype)sharedResolver;

@property(nonatomic,assign,readonly,getter=isAvailable) BOOL available;
@property(nonatomic,copy,readonly) NSString *unityPath;
@property(nonatomic,copy,readonly) NSString *lastError;
@property(nonatomic,copy,readonly) NSString *lastNamedResolution;

- (void)refresh;
- (NSDictionary<NSString *, NSNumber *> *)capabilities;

// Authoring-time parser used by the Named Offset Resolver. Supported forms:
//   GetMoney
//   GetMoney/0
//   PlayerData::GetMoney/0
//   Game.PlayerData::GetMoney/0
//   Assembly-CSharp.dll!Game.PlayerData::GetMoney/0+0x10
// The returned dictionary contains method plus optional assembly/class/
// namespace/argumentCount and a signed delta.
+ (nullable NSDictionary<NSString *, id> *)parseNamedOffsetExpression:(NSString *)expression
                                                                error:(NSString * _Nullable * _Nullable)error;

// Resolves a named IL2CPP method to a UnityFramework RVA. Simple method names
// are accepted only when the runtime enumeration APIs are available and the
// match is unique. Ambiguous names are rejected instead of choosing a random
// first match. The result contains target, rva/rvaText, canonical method name,
// methodPointer, pointerSource, delta, and searchMode.
- (nullable NSDictionary<NSString *, id> *)resolveNamedOffsetExpression:(NSString *)expression
                                                                   error:(NSString * _Nullable * _Nullable)error;

- (nullable NSDictionary<NSString *, id> *)resolveMethodAssembly:(NSString *)assembly
                                                       namespace:(NSString *)namespaceName
                                                       className:(NSString *)className
                                                          method:(NSString *)methodName
                                                   argumentCount:(NSInteger)argumentCount;

- (nullable NSDictionary<NSString *, id> *)resolveFieldAssembly:(NSString *)assembly
                                                      namespace:(NSString *)namespaceName
                                                      className:(NSString *)className
                                                           field:(NSString *)fieldName;

- (NSString *)diagnosticReport;
@end

NS_ASSUME_NONNULL_END
