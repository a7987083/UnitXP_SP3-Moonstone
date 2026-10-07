#import <Foundation/Foundation.h>
#import "ZNNativeRedirectAction.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZNNativeRedirectRuntime : NSObject
+ (instancetype)sharedRuntime;
@property(nonatomic,copy,readonly) NSString *lastStatus;
- (BOOL)installAction:(ZNNativeRedirectAction *)action error:(NSString * _Nullable * _Nullable)error;
- (BOOL)restoreAction:(ZNNativeRedirectAction *)action error:(NSString * _Nullable * _Nullable)error;
- (nullable ZNNativeRedirectAction *)installedActionForSourceImage:(NSString *)sourceImage
                                                         sourceRVA:(uint64_t)sourceRVA;
- (BOOL)restoreInstalledForSourceImage:(NSString *)sourceImage
                              sourceRVA:(uint64_t)sourceRVA
                                 error:(NSString * _Nullable * _Nullable)error;
- (nullable NSData *)currentBytesForAction:(ZNNativeRedirectAction *)action
                                    count:(NSUInteger)count
                                    error:(NSString * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
