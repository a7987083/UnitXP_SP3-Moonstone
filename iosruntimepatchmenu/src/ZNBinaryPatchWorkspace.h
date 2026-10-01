#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@class ZNPatchRuntimeValidator;
@class ZNTypedValueOffset;

typedef NS_ENUM(NSInteger, ZNOffsetControlKind) {
    ZNOffsetControlKindSwitch = 0,
    ZNOffsetControlKindSlider = 1,
    ZNOffsetControlKindNumber = 2,
};

@interface ZNBinaryPatchRow : NSObject
@property(nonatomic,copy) NSString *target;
@property(nonatomic,assign) BOOL explicitTarget;
@property(nonatomic,copy) NSString *offsetText;
@property(nonatomic,copy) NSString *enabledText;
@property(nonatomic,copy) NSString *originalHex;
@property(nonatomic,copy) NSString *title;
@property(nonatomic,copy) NSString *group;
@property(nonatomic,copy) NSString *sourcePath;
@property(nonatomic,copy) NSString *statusText;
@property(nonatomic,assign) BOOL validated;
@property(nonatomic,assign) BOOL lowConfidence;
@property(nonatomic,assign) BOOL conflict;
@property(nonatomic,strong,nullable) ZNPatchRuntimeValidator *validator;

// M5.11 unified Offset authoring. One row is either a raw byte Switch patch
// or a typed Slider/Number value at Target+RVA.
@property(nonatomic,assign) ZNOffsetControlKind controlKind;
@property(nonatomic,copy) NSString *valueType;
@property(nonatomic,assign) double minValue;
@property(nonatomic,assign) double maxValue;
@property(nonatomic,assign) double stepValue;
@property(nonatomic,strong,nullable) ZNTypedValueOffset *typedEntry;
@end

@interface ZNBinaryPatchWorkspace : NSObject
+ (instancetype)sharedWorkspace;
@property(nonatomic,copy) NSString *defaultTarget;
@property(nonatomic,strong,readonly) NSMutableArray<ZNBinaryPatchRow *> *rows;
@property(nonatomic,copy,readonly) NSArray<NSString *> *jsonFiles;
@property(nonatomic,assign) BOOL showJSONFiles;
@property(nonatomic,copy) NSString *lastStatus;
@property(nonatomic,copy,readonly) NSArray<NSString *> *lastOutputPaths;
@property(nonatomic,assign,getter=isBuilding) BOOL building;

- (void)ensureDefaultRows;
- (void)addEmptyRow;
- (void)updateOffset:(NSString *)text row:(NSUInteger)index;
- (void)updateEnabled:(NSString *)text row:(NSUInteger)index;
- (void)updateDefaultTarget:(NSString *)text;

- (void)refreshJSONFiles;
- (BOOL)importJSONAtPath:(NSString *)path error:(NSString * _Nullable * _Nullable)error;

- (NSUInteger)filledCount;
- (NSUInteger)validatedCount;
- (BOOL)hasAnyApplied;
- (BOOL)validateAll:(NSString * _Nullable * _Nullable)error;
- (BOOL)applyAll:(NSString * _Nullable * _Nullable)error;
- (BOOL)restoreAll:(NSString * _Nullable * _Nullable)error;
- (void)setBuildOutputs:(NSArray<NSString *> *)paths status:(NSString *)status;
@end

@interface ZNBinaryPatchWorkspace (ZNFeatureEditing)
- (NSString *)addFeature;
- (void)addPatchToFeature:(NSString *)featureName;
- (BOOL)renameFeature:(NSString *)oldName to:(NSString *)newName error:(NSString * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
