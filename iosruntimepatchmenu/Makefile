ARCHS = arm64
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ZonoePatchV03

ZonoePatchV03_FILES = src/ZonoeRuntimeMenu.mm src/ZNDeferredBootstrap.mm src/ZNTheme.mm src/ZNPatchCore.mm src/ZNPatchCoreV041.mm src/ZNRuntimePatchExecutor.mm src/ZNExecutablePageProbe.mm src/ZNRuntimeDiagnosticsV042.mm src/ZNPatchRuntimeValidator.mm src/ZNDeveloperGate.mm src/ZNIL2CPPResolver.mm src/ZNIL2CPPHybridFinder.mm src/ZNIL2CPPNamedOffsetWorkspace.mm src/ZNPatchJSONImporter.mm src/ZNBinaryPatchWorkspace.mm src/ZNStaticBinaryPipeline.mm src/ZNStaticBinaryBuilderV3.mm src/ZNFeatureMetadataCodec.mm src/ZNStaticMetadataPrivacy.mm src/ZNStaticRVAProtection.mm src/ZNAdhocMachOSigner.mm src/ZNGeneratedBinaryPostprocess.mm src/ZNStaticDispatchRuntime.mm src/ZNSharedSiteProbeV2.mm src/ZNSharedSiteExecutionProbeV3.mm src/ZNSharedSiteExecutionProbeV3Bootstrap.mm src/ZNFeatureGroupUI.mm src/ZNPublicCompactUI.mm src/ZNFeatureBuilderUI.mm src/ZNIL2CPPMethodFinderUI.mm
ZonoePatchV03_CFLAGS = -Oz -fobjc-arc -fblocks -fvisibility=hidden -include src/ZNVMRegionCompat.h -Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-objc-method-access -Wno-unused-const-variable -Wno-unused-function
ZonoePatchV03_FRAMEWORKS = UIKit Foundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk