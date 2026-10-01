#import <Foundation/Foundation.h>
#import "ZNTypedValueOffset.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZNTypedValueRow : NSObject
@property(nonatomic,strong) ZNTypedValueOffset *entry;
@property(nonatomic,copy) NSString *statusText;
@end

@interface ZNTypedValueWorkspace : NSObject
+ (instancetype)sharedWorkspace;
@property(nonatomic,strong,readonly) NSMutableArray<ZNTypedValueRow *> *rows;
@property(nonatomic,copy) NSString *lastStatus;
@property(nonatomic,assign,readonly) BOOL hasAnyApplied;
- (ZNTypedValueRow *)addRow;
- (BOOL)removeRowAtIndex:(NSUInteger)index error:(NSString * _Nullable * _Nullable)error;
- (BOOL)validateRowAtIndex:(NSUInteger)index error:(NSString * _Nullable * _Nullable)error;
- (BOOL)applyRowAtIndex:(NSUInteger)index value:(NSString *)value error:(NSString * _Nullable * _Nullable)error;
- (BOOL)restoreRowAtIndex:(NSUInteger)index error:(NSString * _Nullable * _Nullable)error;
- (BOOL)restoreAll:(NSString * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
