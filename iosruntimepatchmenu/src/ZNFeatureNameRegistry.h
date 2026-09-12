#import <Foundation/Foundation.h>
#import <stdint.h>

NS_ASSUME_NONNULL_BEGIN

// UI-only display metadata. Generated target Mach-O files deliberately do not
// carry these strings; the registry lives in the host app's own data container.
FOUNDATION_EXPORT void ZNFeatureNameRegistryStore(NSString *target,
                                                  uint64_t siteRVA,
                                                  uint32_t patchID,
                                                  NSString * _Nullable title,
                                                  NSString * _Nullable group);

FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> * _Nullable
ZNFeatureNameRegistryLookup(NSString *target, uint64_t siteRVA, uint32_t patchID);

NS_ASSUME_NONNULL_END
