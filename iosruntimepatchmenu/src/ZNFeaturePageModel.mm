#import "ZNFeaturePageModel.h"

@interface ZNFeaturePageModel ()
@property(nonatomic,copy,readwrite) NSArray<ZNFeaturePageItem *> *items;
@property(nonatomic,assign,readwrite) NSUInteger generation;
@property(nonatomic,copy) NSArray<ZNFeaturePageItem *> *staticItems;
@property(nonatomic,copy) NSArray<ZNFeaturePageItem *> *runtimeItems;
@end

@implementation ZNFeaturePageItem
- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _identifier = @"";
    _title = @"";
    _source = ZNFeaturePageSourceStaticOffset;
    _controlType = ZNFeatureControlTypeSwitch;
    _valueType = ZNValueTypeAuto;
    _minimumValue = 0.0;
    _maximumValue = 0.0;
    _step = 1.0;
    _currentValueText = @"";
    return self;
}
@end

@implementation ZNFeaturePageModel
+ (instancetype)sharedModel {
    static ZNFeaturePageModel *model;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        model = [ZNFeaturePageModel new];
        model.staticItems = @[];
        model.runtimeItems = @[];
        model.items = @[];
    });
    return model;
}

- (void)zn_rebuildMergedSnapshot {
    NSMutableArray<ZNFeaturePageItem *> *merged = [NSMutableArray arrayWithCapacity:self.staticItems.count + self.runtimeItems.count];
    [merged addObjectsFromArray:self.staticItems ?: @[]];
    [merged addObjectsFromArray:self.runtimeItems ?: @[]];
    self.items = [merged copy];
    self.generation += 1;
}

- (void)publishStaticItems:(NSArray<ZNFeaturePageItem *> *)items {
    self.staticItems = [items copy] ?: @[];
    [self zn_rebuildMergedSnapshot];
}

- (void)publishRuntimeItems:(NSArray<ZNFeaturePageItem *> *)items {
    self.runtimeItems = [items copy] ?: @[];
    [self zn_rebuildMergedSnapshot];
}
@end
