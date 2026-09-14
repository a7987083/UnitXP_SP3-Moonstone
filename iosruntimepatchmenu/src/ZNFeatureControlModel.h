#import <Foundation/Foundation.h>
#import "ZNBinaryPatchWorkspace.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(uint32_t, ZNFeatureControlType) {
    ZNFeatureControlTypeToggle = 0,
    ZNFeatureControlTypeNumber = 1,
    ZNFeatureControlTypeAction = 2,
    ZNFeatureControlTypeSlider = 3,
};

// Keep the existing 128-byte Static Entry ABI. Bits 8..10 of entry.flags are
// reserved for the public Feature control model. Legacy outputs leave them 0
// and therefore decode as Toggle.
#define ZN_FEATURE_CONTROL_FLAG_SHIFT 8u
#define ZN_FEATURE_CONTROL_FLAG_MASK  UINT32_C(0x00000700)

static inline uint32_t ZNFeatureControlFlags(ZNFeatureControlType type) {
    return (((uint32_t)type << ZN_FEATURE_CONTROL_FLAG_SHIFT) & ZN_FEATURE_CONTROL_FLAG_MASK);
}

static inline ZNFeatureControlType ZNFeatureControlTypeFromFlags(uint32_t flags) {
    uint32_t raw = (flags & ZN_FEATURE_CONTROL_FLAG_MASK) >> ZN_FEATURE_CONTROL_FLAG_SHIFT;
    return raw <= ZNFeatureControlTypeSlider ? (ZNFeatureControlType)raw : ZNFeatureControlTypeToggle;
}

FOUNDATION_EXPORT NSString *ZNFeatureControlTypeName(ZNFeatureControlType type);
FOUNDATION_EXPORT ZNFeatureControlType ZNFeatureControlTypeForFeatureName(NSString *featureName);

FOUNDATION_EXPORT NSNotificationName const ZNFeatureNumberValueDidChangeNotification;
FOUNDATION_EXPORT NSNotificationName const ZNFeatureSliderValueDidChangeNotification;
FOUNDATION_EXPORT NSNotificationName const ZNFeatureActionRequestedNotification;

@interface ZNBinaryPatchRow (ZNFeatureControlModel)
@property(nonatomic,assign) ZNFeatureControlType featureControlType;
@end

@interface ZNBinaryPatchWorkspace (ZNFeatureControlEditingV2)
- (ZNFeatureControlType)controlTypeForFeature:(NSString *)featureName;
- (BOOL)setControlType:(ZNFeatureControlType)type
            forFeature:(NSString *)featureName
                 error:(NSString * _Nullable * _Nullable)error;
- (BOOL)removeFeatureNamed:(NSString *)featureName
                     error:(NSString * _Nullable * _Nullable)error;
- (BOOL)removePatchAtGlobalIndex:(NSUInteger)index
                           error:(NSString * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
