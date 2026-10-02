#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nullable
ZNDirectNativeAnalyzeCandidate(NSDictionary<NSString *, id> *candidate,
                               NSString * _Nullable * _Nullable error);

FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nullable
ZNDirectNativeTestCandidate(NSDictionary<NSString *, id> *candidate,
                            NSString * _Nullable * _Nullable error);

FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nullable
ZNDirectNativeValidatedConfigForCandidate(NSDictionary<NSString *, id> *candidate);

FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nullable
ZNDirectNativeExecuteConfig(NSDictionary<NSString *, id> *config,
                            NSString * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
