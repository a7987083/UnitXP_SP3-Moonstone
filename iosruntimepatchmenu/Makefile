ARCHS = arm64
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ZonoePatchV03

ZonoePatchV03_FILES = src/ZonoeRuntimeMenuV030.mm src/ZNTheme.mm src/ZNPatchCore.mm src/ZNDeveloperGate.mm
ZonoePatchV03_CFLAGS = -Oz -fobjc-arc -fblocks -Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-objc-method-access
ZonoePatchV03_FRAMEWORKS = UIKit Foundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
