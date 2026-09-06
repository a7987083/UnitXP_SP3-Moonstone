#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZNIL2CPPResolver : NSObject
+ (instancetype)sharedResolver;

@property(nonatomic,assign,readonly,getter=isAvailable) BOOL available;
@property(nonatomic,copy,readonly) NSString *unityPath;
@property(nonatomic,copy,readonly) NSString *lastError;

- (void)refresh;
- (NSDictionary<NSString *, NSNumber *> *)capabilities;

- (nullable NSDictionary<NSString *, id> *)resolveMethodAssembly:(NSString *)assembly
                                                       namespace:(NSString *)namespaceName
                                                       className:(NSString *)className
                                                          method:(NSString *)methodName
                                                   argumentCount:(NSInteger)argumentCount;

- (nullable NSDictionary<NSString *, id> *)resolveFieldAssembly:(NSString *)assembly
                                                      namespace:(NSString *)namespaceName
                                                      className:(NSString *)className
                                                           field:(NSString *)fieldName;

- (NSString *)diagnosticReport;
@end

NS_ASSUME_NONNULL_END
