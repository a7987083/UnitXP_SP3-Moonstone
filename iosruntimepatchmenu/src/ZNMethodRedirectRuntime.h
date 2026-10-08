#import <Foundation/Foundation.h>

@class ZNRuntimeMethodActionRecord;

NS_ASSUME_NONNULL_BEGIN

// Runtime owner for generated Method Redirect actions.
// Hooks are installed once during capability prepare. Customer UI toggles only
// the atomic enabled state; it never calls DobbyHook/DobbyDestroy.
@interface ZNMethodRedirectRuntime : NSObject
+ (instancetype)sharedRuntime;

@property(nonatomic,copy,readonly) NSString *lastStatus;

- (BOOL)reconcileRecords:(NSArray<ZNRuntimeMethodActionRecord *> *)records
                   error:(NSString * _Nullable * _Nullable)error;

- (BOOL)setEnabled:(BOOL)enabled
         forRecord:(ZNRuntimeMethodActionRecord *)record
             error:(NSString * _Nullable * _Nullable)error;

- (BOOL)isEnabledForRecord:(ZNRuntimeMethodActionRecord *)record;
- (NSString *)statusForRecord:(ZNRuntimeMethodActionRecord *)record;
@end

NS_ASSUME_NONNULL_END
