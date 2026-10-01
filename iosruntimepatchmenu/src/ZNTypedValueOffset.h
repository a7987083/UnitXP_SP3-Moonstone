#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ZNTypedValueControlKind) {
    ZNTypedValueControlKindSlider = 0,
    ZNTypedValueControlKindNumber = 1,
};

@interface ZNTypedValueOffset : NSObject
@property(nonatomic,copy) NSString *title;
@property(nonatomic,copy) NSString *target;
@property(nonatomic,copy) NSString *offsetText;
@property(nonatomic,copy) NSString *valueType;
@property(nonatomic,assign) ZNTypedValueControlKind controlKind;
@property(nonatomic,copy) NSString *valueText;
@property(nonatomic,assign) double minValue;
@property(nonatomic,assign) double maxValue;
@property(nonatomic,assign) double stepValue;
@property(nonatomic,copy,readonly) NSString *originalValueText;
@property(nonatomic,assign,readonly) uint64_t rva;
@property(nonatomic,assign,readonly) uint64_t resolvedAddress;
@property(nonatomic,assign,readonly,getter=isValidated) BOOL validated;
@property(nonatomic,assign,readonly,getter=isApplied) BOOL applied;
@property(nonatomic,copy,readonly) NSString *lastError;

- (BOOL)validate:(NSString * _Nullable * _Nullable)error;
- (BOOL)applyValue:(NSString *)value error:(NSString * _Nullable * _Nullable)error;
- (BOOL)restore:(NSString * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
