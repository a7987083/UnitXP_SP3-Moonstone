#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Authoring-time Feature description store. The key is the normalized Feature
// display name. ZNFeatureMetadataCodec snapshots this text into generated Mach-O
// metadata, so customer runtime does not depend on NSUserDefaults.
FOUNDATION_EXPORT NSString *ZNFeatureDescriptionForName(NSString *featureName);
FOUNDATION_EXPORT void ZNSetFeatureDescriptionForName(NSString *featureName, NSString *descriptionText);
FOUNDATION_EXPORT void ZNMoveFeatureDescription(NSString *oldFeatureName, NSString *newFeatureName);
FOUNDATION_EXPORT NSString *ZNFeatureDescriptionNormalizedKey(NSString *featureName);

NS_ASSUME_NONNULL_END
