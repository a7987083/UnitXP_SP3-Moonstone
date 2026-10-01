#import <Foundation/Foundation.h>
#import "ZNTypedValueStaticFormat.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZNTypedValueRuntimeRecord : NSObject
@property(nonatomic,copy,readonly) NSString *target;
@property(nonatomic,copy,readonly) NSString *title;
@property(nonatomic,copy,readonly) NSString *valueType;
@property(nonatomic,assign,readonly) uint64_t rva;
@property(nonatomic,assign,readonly) ZNTVStaticControl control;
@property(nonatomic,assign,readonly) double minValue;
@property(nonatomic,assign,readonly) double maxValue;
@property(nonatomic,assign,readonly) double stepValue;
@property(nonatomic,assign,readonly) double defaultValue;
@property(nonatomic,copy,readonly) NSString *currentValueText;
@end

@interface ZNTypedValueDispatchRuntime : NSObject
+ (instancetype)sharedRuntime;
@property(nonatomic,copy,readonly) NSArray<ZNTypedValueRuntimeRecord *> *records;
- (void)refresh;
- (BOOL)refreshValueForRecord:(ZNTypedValueRuntimeRecord *)record error:(NSString * _Nullable * _Nullable)error;
- (BOOL)setValueText:(NSString *)value forRecord:(ZNTypedValueRuntimeRecord *)record error:(NSString * _Nullable * _Nullable)error;
- (NSArray<NSString *> *)diagnosticLines;
@end

NS_ASSUME_NONNULL_END
