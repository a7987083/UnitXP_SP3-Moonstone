#pragma once
#import <Foundation/Foundation.h>

@class ZNBinaryPatchWorkspace;

FOUNDATION_EXPORT BOOL ZNBuildExecutorBuildWorkspace(ZNBinaryPatchWorkspace *workspace,
                                                     NSArray<NSString *> * _Nullable * _Nullable outputs,
                                                     NSString * _Nullable * _Nullable report,
                                                     NSString * _Nullable * _Nullable error);
