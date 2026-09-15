ARCHS = arm64
TARGET = iphone:clang:latest:12.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = JSONCapture

# Generic Full Sweep for the supplied UnityFramework:
# Unity 2019.4 / IL2CPP / ToLua / Lua 5.3.5.
# No game-specific fixed RVA hooks are compiled in.
JSONCapture_FILES = src/GenericFullSweep.m src/Lua53Analyzer.m
JSONCapture_CFLAGS = -Oz -fno-stack-protector -fno-builtin -fblocks -Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-nullability-completeness
JSONCapture_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
