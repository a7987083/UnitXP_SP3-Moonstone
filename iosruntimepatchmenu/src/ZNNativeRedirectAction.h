#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZNNativeRedirectAction : NSObject <NSCopying>
@property(nonatomic,assign) uint32_t actionID;
@property(nonatomic,copy) NSString *title;
@property(nonatomic,copy) NSString *featureDescription;
@property(nonatomic,copy) NSString *controlType; // switch / button

@property(nonatomic,copy) NSString *sourceAssembly;
@property(nonatomic,copy) NSString *sourceNamespace;
@property(nonatomic,copy) NSString *sourceClass;
@property(nonatomic,copy) NSString *sourceMethod;
@property(nonatomic,assign) NSUInteger sourceArgumentCount;
@property(nonatomic,assign) uint64_t sourceMethodRVA;
@property(nonatomic,copy) NSArray<NSString *> *sourceParameterTypes;
@property(nonatomic,copy) NSString *sourceReturnType;
@property(nonatomic,assign) BOOL sourceInstance;

@property(nonatomic,copy) NSString *targetAssembly;
@property(nonatomic,copy) NSString *targetNamespace;
@property(nonatomic,copy) NSString *targetClass;
@property(nonatomic,copy) NSString *targetMethod;
@property(nonatomic,assign) NSUInteger targetArgumentCount;
@property(nonatomic,assign) uint64_t targetMethodRVA;
@property(nonatomic,copy) NSArray<NSString *> *targetParameterTypes;
@property(nonatomic,copy) NSString *targetReturnType;
@property(nonatomic,assign) BOOL targetInstance;

@property(nonatomic,copy,readonly) NSString *sourceIdentity;
@property(nonatomic,copy,readonly) NSString *targetIdentity;
@property(nonatomic,copy,readonly) NSString *canonicalIdentity;
@end

@interface ZNNativeRedirectStore : NSObject
+ (instancetype)sharedStore;
- (NSArray<ZNNativeRedirectAction *> *)actionsSnapshot;
- (nullable ZNNativeRedirectAction *)addSourceCandidate:(NSDictionary<NSString *,id> *)source
                                         targetCandidate:(NSDictionary<NSString *,id> *)target
                                                   title:(nullable NSString *)title
                                      featureDescription:(nullable NSString *)featureDescription
                                             controlType:(nullable NSString *)controlType
                                                   error:(NSString * _Nullable * _Nullable)error;
- (BOOL)removeActionAtIndex:(NSUInteger)index;
- (void)clear;
@end

NS_ASSUME_NONNULL_END
