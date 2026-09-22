#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZNRuntimeMethodAction : NSObject <NSCopying>
@property(nonatomic,assign) uint32_t actionID;
@property(nonatomic,copy) NSString *title;
@property(nonatomic,copy) NSString *group;
@property(nonatomic,copy) NSString *assembly;
@property(nonatomic,copy) NSString *namespaceName;
@property(nonatomic,copy) NSString *className;
@property(nonatomic,copy) NSString *methodName;
@property(nonatomic,assign) NSUInteger argumentCount;
@property(nonatomic,copy,readonly) NSString *canonicalIdentity;
@end

@interface ZNRuntimeActionStore : NSObject
+ (instancetype)sharedStore;
@property(nonatomic,copy,readonly) NSArray<ZNRuntimeMethodAction *> *actions;

- (nullable ZNRuntimeMethodAction *)addMethodCandidate:(NSDictionary<NSString *, id> *)candidate
                                                 title:(nullable NSString *)title
                                                 error:(NSString * _Nullable * _Nullable)error;
- (BOOL)updateTitle:(nullable NSString *)title
            atIndex:(NSUInteger)index
              error:(NSString * _Nullable * _Nullable)error;
- (BOOL)removeActionAtIndex:(NSUInteger)index;
- (void)clear;
- (NSArray<ZNRuntimeMethodAction *> *)actionsSnapshot;
@end

NS_ASSUME_NONNULL_END
