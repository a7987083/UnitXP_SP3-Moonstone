#import <Foundation/Foundation.h>

@class ZNNativeHookAction;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT const void * const ZNNativeHookCandidateAssociationKey;

@interface ZNNativeHookRuntime : NSObject
+ (instancetype)sharedRuntime;
@property(nonatomic,copy,readonly) NSArray<ZNNativeHookAction *> *generatedActions;
- (void)refreshGeneratedActions;

- (NSArray<NSNumber *> *)supportedInt32ArgumentIndicesForCandidate:(NSDictionary<NSString *, id> *)candidate
                                                            reason:(NSString * _Nullable * _Nullable)reason;
- (NSArray<NSNumber *> *)supportedManagedBoolCallbackArgumentIndicesForCandidate:(NSDictionary<NSString *, id> *)candidate
                                                                          reason:(NSString * _Nullable * _Nullable)reason;

- (BOOL)installTemporaryArgScaleInt32ForCandidate:(NSDictionary<NSString *, id> *)candidate
                                     argumentIndex:(NSUInteger)argumentIndex
                                        multiplier:(NSInteger)multiplier
                                             error:(NSString * _Nullable * _Nullable)error;

- (BOOL)installTemporaryManagedCallbackShortCircuitForCandidate:(NSDictionary<NSString *, id> *)candidate
                                                   argumentIndex:(NSUInteger)argumentIndex
                                                   callbackValue:(BOOL)callbackValue
                                                           error:(NSString * _Nullable * _Nullable)error;

- (BOOL)removeTemporaryHookForCandidate:(NSDictionary<NSString *, id> *)candidate
                                  error:(NSString * _Nullable * _Nullable)error;

- (NSString *)diagnosticsForCandidate:(NSDictionary<NSString *, id> *)candidate;
- (NSString *)liveTestStatus;
- (BOOL)hasLiveTestStatus;
- (void)clearLiveTestStatus;

- (BOOL)installAction:(ZNNativeHookAction *)action
                value:(NSInteger)value
                error:(NSString * _Nullable * _Nullable)error;

- (BOOL)setValue:(NSInteger)value
       forAction:(ZNNativeHookAction *)action
           error:(NSString * _Nullable * _Nullable)error;

- (BOOL)removeAction:(ZNNativeHookAction *)action
               error:(NSString * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
