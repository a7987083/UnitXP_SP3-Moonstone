#import <Foundation/Foundation.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

typedef BOOL (*ZNComplexStructTransformFn)(uintptr_t base,
                                           uintptr_t decoder,
                                           uintptr_t encoder,
                                           int32_t multiplier,
                                           int64_t * _Nullable before,
                                           int64_t * _Nullable after);

FOUNDATION_EXPORT NSString * const ZNComplexStructCodecSecureLongWholeAccessor;

@interface ZNComplexStructCodecRegistry : NSObject
+ (instancetype)sharedRegistry;
- (void)registerCodecKey:(NSString *)key transform:(ZNComplexStructTransformFn)transform;
- (nullable NSValue *)transformValueForCodecKey:(NSString *)key;
- (BOOL)supportsCodecKey:(NSString *)key;
@end

FOUNDATION_EXPORT void ZNRegisterBuiltInComplexStructCodecs(void);

NS_ASSUME_NONNULL_END
