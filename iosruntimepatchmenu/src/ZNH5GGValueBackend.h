#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZNH5GGValueBackend : NSObject
+ (instancetype)sharedBackend;
@property(nonatomic,assign,readonly,getter=isAvailable) BOOL available;
@property(nonatomic,copy,readonly) NSString *availabilityText;
- (nullable NSString *)readAddress:(uint64_t)address type:(NSString *)type error:(NSString * _Nullable * _Nullable)error;
- (BOOL)writeAddress:(uint64_t)address value:(NSString *)value type:(NSString *)type error:(NSString * _Nullable * _Nullable)error;
// Raw code-patch bridge for M5.11 authoring. Patch bytes must be a 4-byte
// multiple (same ARM64 contract as Static Offset). Internally this uses the
// H5GG U32 API chunk-by-chunk and verifies every write with a read-back.
- (BOOL)writeRawARM64BytesAtAddress:(uint64_t)address
                              bytes:(NSData *)bytes
                           rollback:(NSData *)rollback
                              error:(NSString * _Nullable * _Nullable)error;
+ (BOOL)isSupportedType:(NSString *)type;
+ (NSUInteger)sizeForType:(NSString *)type;
@end

NS_ASSUME_NONNULL_END
