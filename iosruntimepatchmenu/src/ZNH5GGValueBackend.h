#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZNH5GGValueBackend : NSObject
+ (instancetype)sharedBackend;
@property(nonatomic,assign,readonly,getter=isAvailable) BOOL available;
@property(nonatomic,copy,readonly) NSString *availabilityText;
- (nullable NSString *)readAddress:(uint64_t)address type:(NSString *)type error:(NSString * _Nullable * _Nullable)error;
- (BOOL)writeAddress:(uint64_t)address value:(NSString *)value type:(NSString *)type error:(NSString * _Nullable * _Nullable)error;
+ (BOOL)isSupportedType:(NSString *)type;
+ (NSUInteger)sizeForType:(NSString *)type;
@end

NS_ASSUME_NONNULL_END
