ARCHS = arm64
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ZonoePatchV03

ZonoePatchV03_FILES = src/ZonoeRuntimeMenuV044.mm src/ZNTheme.mm src/ZNPatchCore.mm src/ZNPatchCoreV041.mm src/ZNRuntimePatchExecutor.mm src/ZNExecutablePageProbe.mm src/ZNRuntimeDiagnosticsV042.mm src/ZNPatchRuntimeValidator.mm src/ZNDeveloperGate.mm src/ZNIL2CPPResolver.mm src/ZNPatchJSONImporter.mm src/ZNBinaryPatchWorkspace.mm src/ZNStaticBinaryBuilder.mm src/ZNStaticDispatchRuntime.mm
ZonoePatchV03_CFLAGS = -Oz -fobjc-arc -fblocks -Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-objc-method-access
ZonoePatchV03_FRAMEWORKS = UIKit Foundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
