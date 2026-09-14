ARCHS = arm64
TARGET = iphone:clang:latest:12.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = JSONCapture

JSONCapture_FILES = src/JSONCapture.m src/IL2CPPCapture.m src/LuaCapture.m src/Lua53Analyzer.m
JSONCapture_CFLAGS = -Oz -fno-stack-protector -fno-builtin -fblocks -Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-nullability-completeness
JSONCapture_FRAMEWORKS = UIKit Foundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
