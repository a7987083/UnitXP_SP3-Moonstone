#import <Foundation/Foundation.h>

@class ZNNativeHookAction;

NS_ASSUME_NONNULL_BEGIN

@interface ZNNativeHookRuntime : NSObject
+ (instancetype)sharedRuntime;

- (NSArray<NSNumber *> *)supportedInt32ArgumentIndicesForCandidate:(NSDictionary<NSString *, id> *)candidate
                                                            reason:(NSString * _Nullable * _Nullable)reason;

- (BOOL)installTemporaryArgScaleInt32ForCandidate:(NSDictionary<NSString *, id> *)candidate
                                     argumentIndex:(NSUInteger)argumentIndex
                                        multiplier:(NSInteger)multiplier
                                             error:(NSString * _Nullable * _Nullable)error;

- (BOOL)removeTemporaryHookForCandidate:(NSDictionary<NSString *, id> *)candidate
                                  error:(NSString * _Nullable * _Nullable)error;

- (NSString *)diagnosticsForCandidate:(NSDictionary<NSString *, id> *)candidate;

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
