ARCHS = arm64
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ZonoePatchV02

ZonoePatchV02_FILES = src/ZonoeRuntimeMenuV022.mm src/ZNTheme.mm
ZonoePatchV02_CFLAGS = -Oz -fobjc-arc -fblocks -Wno-deprecated-declarations -Wno-unguarded-availability-new
ZonoePatchV02_FRAMEWORKS = UIKit Foundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
