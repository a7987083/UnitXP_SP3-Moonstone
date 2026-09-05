ARCHS = arm64
TARGET = iphone:clang:latest:12.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = RuntimeConfig

RuntimeConfig_FILES = src/RuntimeConfig.m ../logintcppayload/vendor/fishhook.c
RuntimeConfig_CFLAGS = -Oz -fno-stack-protector -fno-builtin -fblocks -Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-unused-function
RuntimeConfig_FRAMEWORKS = UIKit Foundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
