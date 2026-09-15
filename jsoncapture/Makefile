ARCHS = arm64
TARGET = iphone:clang:latest:12.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = JSONCapture

# Generic build for the newly supplied UnityFramework:
# Unity 2019.4 / IL2CPP / ToLua / Lua 5.3.5.
# Intentionally excludes JSONCapture.m and the old game-specific LuaSweep.m so
# no fixed UnityFramework RVA hooks from the previous game are compiled in.
JSONCapture_FILES = src/GenericSweep.m src/Lua53Analyzer.m
JSONCapture_CFLAGS = -Oz -fno-stack-protector -fno-builtin -fblocks -Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-nullability-completeness
JSONCapture_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
