#import <Foundation/Foundation.h>
#import "ZNPatchCore.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZNPatchActionDescriptor (ZNRuntimePatchExecution)
@property(nonatomic,copy,nullable) NSData *zn_expectedBytes;
@property(nonatomic,copy,nullable) NSData *zn_patchBytes;
@property(nonatomic,copy,nullable) NSData *zn_originalBytes;
@property(nonatomic,assign) BOOL zn_wroteRuntimeMemory;
@end

@interface ZNRuntimePatchExecutor : NSObject
+ (instancetype)sharedExecutor;
- (BOOL)setActions:(NSArray<ZNPatchActionDescriptor *> *)actions
           enabled:(BOOL)enabled
             error:(NSString * _Nullable * _Nullable)error;
- (BOOL)runSelfTest;
- (NSString *)diagnosticReport;
@end

NS_ASSUME_NONNULL_END
