#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ZNPatchState) {
    ZNPatchStateUninitialized = 0,
    ZNPatchStateReady,
    ZNPatchStateEnabled,
    ZNPatchStateDisabled,
    ZNPatchStateUnsupported,
    ZNPatchStateFailed,
};

@interface ZNPatchDescriptor : NSObject
@property(nonatomic,copy,readonly) NSString *identifier;
@property(nonatomic,copy,readonly) NSString *name;
@property(nonatomic,copy,readonly) NSString *category;
@property(nonatomic,copy,readonly) NSString *backend;
@property(nonatomic,assign) ZNPatchState state;
@property(nonatomic,assign) BOOL enabled;
@property(nonatomic,assign) double value;
- (instancetype)initWithIdentifier:(NSString *)identifier
                              name:(NSString *)name
                          category:(NSString *)category
                           backend:(NSString *)backend
                             value:(double)value;
@end

@interface ZNRuntimeLogger : NSObject
+ (instancetype)sharedLogger;
- (void)log:(NSString *)message;
- (NSArray<NSString *> *)recentLines:(NSUInteger)limit;
- (void)clear;
@end

@interface ZNModuleManager : NSObject
+ (instancetype)sharedManager;
- (NSArray<NSDictionary<NSString *, id> *> *)loadedImages;
- (nullable NSDictionary<NSString *, id> *)mainExecutable;
- (nullable NSDictionary<NSString *, id> *)unityFramework;
- (NSString *)diagnosticReport;
@end

@interface ZNPatchManager : NSObject
+ (instancetype)sharedManager;
- (BOOL)enabledForFeature:(NSString *)identifier;
- (void)setFeature:(NSString *)identifier enabled:(BOOL)enabled;
- (double)valueForFeature:(NSString *)identifier fallback:(double)fallback;
- (void)setFeature:(NSString *)identifier value:(double)value;
- (nullable ZNPatchDescriptor *)descriptorForIdentifier:(NSString *)identifier;
- (NSArray<ZNPatchDescriptor *> *)allDescriptors;
- (NSDictionary<NSString *, NSNumber *> *)stateCounts;
- (BOOL)runSelfTest;
- (NSString *)diagnosticReport;
@end

FOUNDATION_EXPORT NSString *ZNStringForPatchState(ZNPatchState state);

NS_ASSUME_NONNULL_END
