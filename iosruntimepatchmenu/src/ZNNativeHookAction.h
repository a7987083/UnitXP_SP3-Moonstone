#import <Foundation/Foundation.h>
#import "ZNNativeHookTemplate.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZNNativeHookAction : NSObject <NSCopying>
@property(nonatomic,assign) uint32_t actionID;
@property(nonatomic,copy) NSString *title;
@property(nonatomic,copy) NSString *group;
@property(nonatomic,copy) NSString *featureDescription;
@property(nonatomic,copy) NSString *assembly;
@property(nonatomic,copy) NSString *namespaceName;
@property(nonatomic,copy) NSString *className;
@property(nonatomic,copy) NSString *methodName;
@property(nonatomic,assign) NSUInteger argumentCount;
@property(nonatomic,copy) NSArray<NSString *> *parameterTypeNames;
@property(nonatomic,assign) BOOL signatureAvailable;
@property(nonatomic,assign) ZNNativeHookTemplateKind templateKind;
@property(nonatomic,assign) NSUInteger argumentIndex;
@property(nonatomic,assign) NSInteger minValue;
@property(nonatomic,assign) NSInteger maxValue;
@property(nonatomic,assign) NSInteger defaultValue;
@property(nonatomic,assign) NSUInteger callbackArgumentIndex;
@property(nonatomic,assign) BOOL callbackValue;
@property(nonatomic,assign) BOOL skipOriginal;
@property(nonatomic,assign) uint64_t fallbackRVA;
@property(nonatomic,copy) NSString *fallbackUUID;
@property(nonatomic,copy,readonly) NSString *canonicalIdentity;
@end

@interface ZNNativeHookStore : NSObject
+ (instancetype)sharedStore;
- (nullable ZNNativeHookAction *)addArgScaleInt32Candidate:(NSDictionary<NSString *, id> *)candidate
                                                     title:(nullable NSString *)title
                                             argumentIndex:(NSUInteger)argumentIndex
                                                       min:(NSInteger)minValue
                                                       max:(NSInteger)maxValue
                                              defaultValue:(NSInteger)defaultValue
                                                     error:(NSString * _Nullable * _Nullable)error;
- (nullable ZNNativeHookAction *)addManagedCallbackShortCircuitCandidate:(NSDictionary<NSString *, id> *)candidate
                                                                   title:(nullable NSString *)title
                                                   callbackArgumentIndex:(NSUInteger)argumentIndex
                                                           callbackValue:(BOOL)callbackValue
                                                            skipOriginal:(BOOL)skipOriginal
                                                                   error:(NSString * _Nullable * _Nullable)error;
- (NSArray<ZNNativeHookAction *> *)actionsSnapshot;
- (BOOL)updateTitle:(nullable NSString *)title atIndex:(NSUInteger)index;
- (BOOL)updateDescription:(nullable NSString *)featureDescription atIndex:(NSUInteger)index;
- (BOOL)removeActionAtIndex:(NSUInteger)index;
- (void)clear;
@end

NS_ASSUME_NONNULL_END
