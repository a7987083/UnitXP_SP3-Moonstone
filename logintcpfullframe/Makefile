ARCHS = arm64
TARGET = iphone:clang:latest:12.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LoginTCPFullFrame

LoginTCPFullFrame_FILES = src/LoginTCPFullFrame.m vendor/fishhook.c
LoginTCPFullFrame_CFLAGS = -Oz -fno-stack-protector -fno-builtin -fblocks -Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-unused-function
LoginTCPFullFrame_FRAMEWORKS = UIKit Foundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
