#import <Foundation/Foundation.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

// M6.14 generated-client execution context. Debug/authoring does not use it.
// While active, exact prepared method resolution is served from the startup
// binding cache and Resolver::refresh takes an O(1) fast path.
FOUNDATION_EXPORT void ZNIL2CPPPreparedExecutionPush(NSDictionary<NSString *,id> *context);
FOUNDATION_EXPORT void ZNIL2CPPPreparedExecutionPop(void);
FOUNDATION_EXPORT BOOL ZNIL2CPPPreparedExecutionActive(void);
FOUNDATION_EXPORT uintptr_t ZNIL2CPPPreparedExecutionReceiver(void);
FOUNDATION_EXPORT NSDictionary<NSString *,id> * _Nullable ZNIL2CPPPreparedExecutionCurrentContext(void);

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

// Baseline v0.5.7 resolver retained for compatibility. The authoring workspace
// now uses ZNIL2CPPHybridFinder for bounded low-memory search.
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
