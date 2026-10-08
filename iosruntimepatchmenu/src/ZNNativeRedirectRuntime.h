#import <Foundation/Foundation.h>
#import "ZNNativeRedirectAction.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZNNativeRedirectRuntime : NSObject
+ (instancetype)sharedRuntime;
@property(nonatomic,copy,readonly) NSString *lastStatus;

/// Strict Method A -> Method B support check.
/// V1 deliberately accepts only ABI-safe ARM64 GPR parameter/return shapes.
- (BOOL)supportsSourceCandidate:(NSDictionary<NSString *,id> *)source
                targetCandidate:(NSDictionary<NSString *,id> *)target
                         reason:(NSString * _Nullable * _Nullable)reason;

- (BOOL)installSourceCandidate:(NSDictionary<NSString *,id> *)source
                targetCandidate:(NSDictionary<NSString *,id> *)target
                           error:(NSString * _Nullable * _Nullable)error;

- (BOOL)installAction:(ZNNativeRedirectAction *)action
                error:(NSString * _Nullable * _Nullable)error;

- (BOOL)restoreSourceCandidate:(NSDictionary<NSString *,id> *)source
                         error:(NSString * _Nullable * _Nullable)error;

- (BOOL)restoreAction:(ZNNativeRedirectAction *)action
                error:(NSString * _Nullable * _Nullable)error;

- (nullable ZNNativeRedirectAction *)installedActionForSourceCandidate:(NSDictionary<NSString *,id> *)source;
- (nullable ZNNativeRedirectAction *)installedActionForSourceIdentity:(NSString *)sourceIdentity;
@end

NS_ASSUME_NONNULL_END
