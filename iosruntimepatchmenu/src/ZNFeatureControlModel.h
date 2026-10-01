#import <Foundation/Foundation.h>
#import "ZNBinaryPatchWorkspace.h"
#import "ZNPatchCore.h"

NS_ASSUME_NONNULL_BEGIN

// M5.10+ Static Offset authoring is Switch/byte-patch only.
// Runtime Method / IL2CPP owns Slider/Number/Button argument controls in the
// RuntimeAction model; this header intentionally exposes no Static Offset
// typed-control/value-type editing API.

FOUNDATION_EXPORT NSString *ZNFeatureControlTypeName(ZNFeatureControlType type);

@interface ZNBinaryPatchWorkspace (ZNFeatureEditingSupport)
- (BOOL)removeFeatureNamed:(NSString *)featureName
                     error:(NSString * _Nullable * _Nullable)error;
- (BOOL)removePatchAtGlobalIndex:(NSUInteger)index
                           error:(NSString * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
