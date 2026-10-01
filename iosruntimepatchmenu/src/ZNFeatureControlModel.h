#import <Foundation/Foundation.h>
#import "ZNBinaryPatchWorkspace.h"
#import "ZNPatchCore.h"
#import "ZNValueTypeModel.h"

NS_ASSUME_NONNULL_BEGIN

// Ordinary Offset authoring UI model.
// Control type and numeric value type are intentionally independent:
// Button/Switch choose interaction semantics; Number/Slider additionally use Value Type.

FOUNDATION_EXPORT NSString *ZNFeatureControlTypeName(ZNFeatureControlType type);
FOUNDATION_EXPORT ZNFeatureControlType ZNFeatureControlTypeForFeatureName(NSString *featureName);
FOUNDATION_EXPORT ZNValueType ZNFeatureValueTypeForFeatureName(NSString *featureName);

@interface ZNBinaryPatchRow (ZNFeatureControlModel)
@property(nonatomic,assign) ZNFeatureControlType featureControlType;
@property(nonatomic,assign) ZNValueType featureValueType;
@end

@interface ZNBinaryPatchWorkspace (ZNFeatureControlEditingV2)
- (ZNFeatureControlType)controlTypeForFeature:(NSString *)featureName;
- (BOOL)setControlType:(ZNFeatureControlType)type
            forFeature:(NSString *)featureName
                 error:(NSString * _Nullable * _Nullable)error;
- (ZNValueType)valueTypeForFeature:(NSString *)featureName;
- (BOOL)setValueType:(ZNValueType)type
          forFeature:(NSString *)featureName
               error:(NSString * _Nullable * _Nullable)error;
- (BOOL)removeFeatureNamed:(NSString *)featureName
                     error:(NSString * _Nullable * _Nullable)error;
- (BOOL)removePatchAtGlobalIndex:(NSUInteger)index
                           error:(NSString * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
