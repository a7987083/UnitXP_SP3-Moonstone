#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Registers Native Redirect as an independent BuildManifest provider.
/// Runtime Function Redirect may use Dobby for arbitrary distance; generated
/// binaries currently encode direct ARM64 B/BL and fail closed beyond ±128MB.
FOUNDATION_EXPORT void ZNInstallNativeRedirectBuildProvider(void);

NS_ASSUME_NONNULL_END
