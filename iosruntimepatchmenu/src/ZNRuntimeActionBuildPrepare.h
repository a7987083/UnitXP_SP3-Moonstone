#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// M6.14 build-time preparation for Runtime Method / Direct Native Call.
// Resolves every authored action while the authoring host has IL2CPP ready and
// persists an RVA/UUID/static descriptor into the action model.
FOUNDATION_EXPORT BOOL ZNBuildPrepareRuntimeActionDescriptorsV1(
    NSString * _Nullable * _Nullable report,
    NSString * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
