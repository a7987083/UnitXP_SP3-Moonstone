#import <Foundation/Foundation.h>
#import "ZNFeatureControlModel.h"
#import "ZNValueTypeModel.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, ZNFeaturePageSource) {
    ZNFeaturePageSourceStaticOffset = 1,
    ZNFeaturePageSourceRuntimeIL2CPP = 2,
};

@interface ZNFeaturePageItem : NSObject
@property(nonatomic,copy) NSString *identifier;
@property(nonatomic,copy) NSString *title;
@property(nonatomic,assign) ZNFeaturePageSource source;
@property(nonatomic,assign) ZNFeatureControlType controlType;
@property(nonatomic,assign) ZNValueType valueType;
@property(nonatomic,assign) double minimumValue;
@property(nonatomic,assign) double maximumValue;
@property(nonatomic,assign) double step;
@property(nonatomic,copy) NSString *currentValueText;
@property(nonatomic,strong,nullable) id backingRecord;
@end

// UI reads snapshots from here. Renderers must never trigger discovery scans.
@interface ZNFeaturePageModel : NSObject
+ (instancetype)sharedModel;
@property(nonatomic,copy,readonly) NSArray<ZNFeaturePageItem *> *items;
@property(nonatomic,assign,readonly) NSUInteger generation;
- (void)publishStaticItems:(NSArray<ZNFeaturePageItem *> *)items;
- (void)publishRuntimeItems:(NSArray<ZNFeaturePageItem *> *)items;
@end

NS_ASSUME_NONNULL_END
