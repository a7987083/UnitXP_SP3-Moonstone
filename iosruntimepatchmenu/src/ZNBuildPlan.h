#pragma once

#import <Foundation/Foundation.h>

@class ZNBinaryPatchWorkspace;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, ZNBuildMode) {
    ZNBuildModeEmpty = 0,
    ZNBuildModeRuntimeOnly,
    ZNBuildModeStaticOnly,
    ZNBuildModeMixed,
    ZNBuildModeInvalid,
};

typedef BOOL (^ZNBuildProviderProbe)(void);

@interface ZNBuildPlan : NSObject
@property(nonatomic,readonly) ZNBuildMode mode;
@property(nonatomic,readonly) BOOL canBuild;
@property(nonatomic,copy,readonly) NSString *blockedReason;
@property(nonatomic,copy,readonly) NSArray<NSString *> *activeProviders;
@property(nonatomic,readonly) NSUInteger completeStaticRows;
@property(nonatomic,readonly) NSUInteger partialStaticRows;
@property(nonatomic,readonly) NSUInteger runtimeProviderCount;

+ (instancetype)currentPlan;
+ (instancetype)executionPlan;
+ (instancetype)planForWorkspace:(ZNBinaryPatchWorkspace *)workspace includeTransientState:(BOOL)includeTransientState;
@end

/// Compatibility facade for existing UI call sites. Decision ownership lives in ZNBuildPlan.
@interface ZNBinaryBuildCoordinator : NSObject
+ (instancetype)sharedCoordinator;
@property(nonatomic,readonly) BOOL canBuild;
@property(nonatomic,copy,readonly) NSString *blockedReason;
@property(nonatomic,copy,readonly) NSArray<NSString *> *activeProviderIdentifiers;
@end

/// Runtime-owned build providers register here. Future Hook types only register a probe;
/// they do not modify UI or Pipeline mode-selection code.
FOUNDATION_EXPORT void ZNRegisterBuildCapabilityProvider(NSString *identifier,
                                                         ZNBuildProviderProbe probe);
FOUNDATION_EXPORT void ZNUnregisterBuildCapabilityProvider(NSString *identifier);

NS_ASSUME_NONNULL_END
