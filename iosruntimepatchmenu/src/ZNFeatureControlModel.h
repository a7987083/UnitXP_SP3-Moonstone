#import <Foundation/Foundation.h>
#import "ZNBinaryPatchWorkspace.h"
#import "ZNPatchCore.h"
#import "ZNValueTypeModel.h"

NS_ASSUME_NONNULL_BEGIN

// Ordinary Offset control metadata ABI. Keep the established 128-byte Static Entry.
// bits 8..10: control type; bits 11..13: numeric value type.
#define ZN_FEATURE_CONTROL_FLAG_SHIFT 8u
#define ZN_FEATURE_CONTROL_FLAG_MASK  UINT32_C(0x00000700)
#define ZN_FEATURE_VALUE_FLAG_SHIFT   11u
#define ZN_FEATURE_VALUE_FLAG_MASK    UINT32_C(0x00003800)

static inline uint32_t ZNFeatureControlFlags(ZNFeatureControlType type) {
    return (((uint32_t)type << ZN_FEATURE_CONTROL_FLAG_SHIFT) & ZN_FEATURE_CONTROL_FLAG_MASK);
}
static inline ZNFeatureControlType ZNFeatureControlTypeFromFlags(uint32_t flags) {
    uint32_t raw = (flags & ZN_FEATURE_CONTROL_FLAG_MASK) >> ZN_FEATURE_CONTROL_FLAG_SHIFT;
    switch (raw) {
        case ZNFeatureControlTypeSwitch:
        case ZNFeatureControlTypeSlider:
        case ZNFeatureControlTypeButton:
        case ZNFeatureControlTypeNumber:
            return (ZNFeatureControlType)raw;
        default: return ZNFeatureControlTypeSwitch;
    }
}
static inline uint32_t ZNFeatureValueTypeFlags(ZNValueType type) {
    return (((uint32_t)type << ZN_FEATURE_VALUE_FLAG_SHIFT) & ZN_FEATURE_VALUE_FLAG_MASK);
}
static inline ZNValueType ZNFeatureValueTypeFromFlags(uint32_t flags) {
    uint32_t raw = (flags & ZN_FEATURE_VALUE_FLAG_MASK) >> ZN_FEATURE_VALUE_FLAG_SHIFT;
    return raw <= ZNValueTypeF64 ? (ZNValueType)raw : ZNValueTypeAuto;
}

FOUNDATION_EXPORT NSString *ZNFeatureControlTypeName(ZNFeatureControlType type);
FOUNDATION_EXPORT ZNFeatureControlType ZNFeatureControlTypeForFeatureName(NSString *featureName);
FOUNDATION_EXPORT ZNValueType ZNFeatureValueTypeForFeatureName(NSString *featureName);
FOUNDATION_EXPORT NSNotificationName const ZNFeatureNumberValueDidChangeNotification;
FOUNDATION_EXPORT NSNotificationName const ZNFeatureSliderValueDidChangeNotification;
FOUNDATION_EXPORT NSNotificationName const ZNFeatureActionRequestedNotification;

@interface ZNBinaryPatchRow (ZNFeatureControlModel)
@property(nonatomic,assign) ZNFeatureControlType featureControlType;
@property(nonatomic,assign) ZNValueType featureValueType;
@end

@interface ZNBinaryPatchWorkspace (ZNFeatureControlEditingV2)
- (ZNFeatureControlType)controlTypeForFeature:(NSString *)featureName;
- (BOOL)setControlType:(ZNFeatureControlType)type forFeature:(NSString *)featureName error:(NSString * _Nullable * _Nullable)error;
- (ZNValueType)valueTypeForFeature:(NSString *)featureName;
- (BOOL)setValueType:(ZNValueType)type forFeature:(NSString *)featureName error:(NSString * _Nullable * _Nullable)error;
- (BOOL)removeFeatureNamed:(NSString *)featureName error:(NSString * _Nullable * _Nullable)error;
- (BOOL)removePatchAtGlobalIndex:(NSUInteger)index error:(NSString * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
