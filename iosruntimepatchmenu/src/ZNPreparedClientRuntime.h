#import <Foundation/Foundation.h>

@class ZNRuntimeMethodActionRecord;

NS_ASSUME_NONNULL_BEGIN

// M6.14 generated-client runtime.
// Formal generated client actions are bound automatically from Prepared
// Descriptors during process startup. Menu execution is cache-only and never
// performs Finder/Resolver/Hook installation work.
@interface ZNPreparedClientRuntime : NSObject
+ (instancetype)sharedRuntime;
- (void)start;
- (void)requestReconcile;
- (BOOL)executeRuntimeRecord:(ZNRuntimeMethodActionRecord *)record
                      values:(NSArray<NSString *> *)values
                       error:(NSString * _Nullable * _Nullable)error;
- (BOOL)executeDirectRecord:(ZNRuntimeMethodActionRecord *)record
                     values:(NSArray<NSString *> *)values
                      error:(NSString * _Nullable * _Nullable)error;
- (BOOL)isPreparedActionID:(uint32_t)actionID;
@end

NS_ASSUME_NONNULL_END
