#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ZNNativeRedirectKind) {
    ZNNativeRedirectKindFunction = 0,
    ZNNativeRedirectKindBranch = 1,
    ZNNativeRedirectKindBranchLink = 2,
};

FOUNDATION_EXPORT NSString *ZNNativeRedirectKindKey(ZNNativeRedirectKind kind);
FOUNDATION_EXPORT ZNNativeRedirectKind ZNNativeRedirectKindFromKey(NSString *key);

@interface ZNNativeRedirectAction : NSObject <NSCopying>
@property(nonatomic,assign) uint32_t actionID;
@property(nonatomic,copy) NSString *title;
@property(nonatomic,copy) NSString *featureDescription;
@property(nonatomic,copy) NSString *sourceImage;
@property(nonatomic,assign) uint64_t sourceRVA;
@property(nonatomic,copy) NSString *targetImage;
@property(nonatomic,assign) uint64_t targetRVA;
@property(nonatomic,assign) ZNNativeRedirectKind kind;
@property(nonatomic,copy) NSString *controlType; // button / switch
@property(nonatomic,copy,readonly) NSString *canonicalIdentity;
@end

@interface ZNNativeRedirectStore : NSObject
+ (instancetype)sharedStore;
- (NSArray<ZNNativeRedirectAction *> *)actionsSnapshot;
- (nullable ZNNativeRedirectAction *)addSourceImage:(NSString *)sourceImage
                                          sourceRVA:(uint64_t)sourceRVA
                                        targetImage:(NSString *)targetImage
                                          targetRVA:(uint64_t)targetRVA
                                               kind:(ZNNativeRedirectKind)kind
                                              title:(nullable NSString *)title
                                 featureDescription:(nullable NSString *)featureDescription
                                        controlType:(nullable NSString *)controlType
                                              error:(NSString * _Nullable * _Nullable)error;
- (BOOL)removeActionAtIndex:(NSUInteger)index;
- (void)clear;
@end

NS_ASSUME_NONNULL_END
