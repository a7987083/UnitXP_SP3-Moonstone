ARCHS = arm64
TARGET = iphone:clang:latest:12.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LoginIPRedirectV10

LoginIPRedirectV10_FILES = src/LoginIPRedirectV10.m ../logintcppayload/vendor/fishhook.c
LoginIPRedirectV10_CFLAGS = -Oz -fno-stack-protector -fno-builtin -fblocks -Wno-deprecated-declarations -Wno-unguarded-availability-new
LoginIPRedirectV10_FRAMEWORKS = UIKit Foundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
