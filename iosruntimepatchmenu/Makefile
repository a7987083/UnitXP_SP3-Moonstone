ARCHS = arm64
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ZonoePatchV03

ZonoePatchV03_FILES = src/ZonoeRuntimeMenu.mm src/ZNDeferredBootstrap.mm src/ZNTheme.mm src/ZNPatchCore.mm src/ZNPatchCoreV041.mm src/ZNRuntimePatchExecutor.mm src/ZNExecutablePageProbe.mm src/ZNRuntimeDiagnosticsV042.mm src/ZNPatchRuntimeValidator.mm src/ZNOffsetResolverV2.mm src/ZNBinaryPatchWorkspaceAddressV2.mm src/ZNRuntimeMenuModalShell.mm src/ZNDeveloperGate.mm src/ZNIL2CPPResolver.mm src/ZNIL2CPPHybridFinder.mm src/ZNIL2CPPNamedOffsetWorkspace.mm src/ZNPatchJSONImporter.mm src/ZNBinaryPatchWorkspace.mm src/ZNFeatureControlModel.mm src/ZNStaticBinaryPipeline.mm src/ZNStaticBinaryBuilderV3.mm src/ZNFeatureMetadataCodec.mm src/ZNStaticMetadataPrivacy.mm src/ZNStaticRVAProtection.mm src/ZNAdhocMachOSigner.mm src/ZNGeneratedBinaryPostprocess.mm src/ZNStaticDispatchRuntime.mm src/ZNSharedSiteProbeV2.mm src/ZNSharedSiteExecutionProbeV3.mm src/ZNSharedSiteExecutionProbeV3Bootstrap.mm src/ZNFeatureGroupUI.mm src/ZNFeatureRuntimeControlsV2.mm src/ZNPublicCompactUI.mm src/ZNFeatureBuilderUI.mm src/ZNFeatureBuilderControlsV2.mm src/ZNIL2CPPMethodFinderUI.mm src/ZNIL2CPPMethodFinderMenuBinding.mm src/ZNIL2CPPMethodFinderSearchV2.mm src/ZNIL2CPPMethodFinderZeroVMAddrFix.mm src/ZNIL2CPPMethodFinderUXV2.mm src/ZNIL2CPPMethodFinderSearchV3.mm src/ZNIL2CPPMethodFinderUIV3.mm src/ZNIL2CPPMethodFinderPatchBridgeV3.mm src/ZNIL2CPPMethodFinderM2.mm src/ZNIL2CPPMethodFinderM21CancelUX.mm src/ZNIL2CPPMethodFinderM22StableCancelUX.mm src/ZNIL2CPPABIMetadata.mm src/ZNIL2CPPABIDetailUI.mm src/ZNRuntimeActionModel.mm src/ZNIL2CPPInvokeEngine.mm src/ZNRuntimeActionBuilder.mm src/ZNRuntimeActionRuntime.mm src/ZNRuntimeMethodCallFinderUI.mm src/ZNRuntimeMethodCallBuilderUI.mm src/ZNRuntimeMethodCallFeatureUI.mm src/ZNRuntimeMethodCallBootstrap.mm src/ZNUXFixesV2.mm src/ZNMethodFinderM42UI.mm
ZonoePatchV03_CFLAGS = -Oz -fobjc-arc -fblocks -fvisibility=hidden -include src/ZNVMRegionCompat.h -Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-objc-method-access -Wno-unused-const-variable -Wno-unused-function -Wno-incomplete-implementation
ZonoePatchV03_FRAMEWORKS = UIKit Foundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
