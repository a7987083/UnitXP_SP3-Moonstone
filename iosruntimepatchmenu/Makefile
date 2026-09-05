ARCHS = arm64
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ZonoeRuntimeMenuV01

ZonoeRuntimeMenuV01_FILES = src/ZonoeRuntimeMenu.mm
ZonoeRuntimeMenuV01_CFLAGS = -Oz -fobjc-arc -fblocks -Wno-deprecated-declarations -Wno-unguarded-availability-new
ZonoeRuntimeMenuV01_FRAMEWORKS = UIKit Foundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
