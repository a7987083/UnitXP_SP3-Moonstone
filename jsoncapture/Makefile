ARCHS = arm64
TARGET = iphone:clang:latest:12.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = JSONCapture

# v0.5 Manual Task Engine
# - Runtime Lua loader capture hooks are always lightweight and user-toggleable.
# - No loaded-bundle watcher, no disk watcher, no persistent log poll.
# - Local scan only runs when the user presses Start and only scans Documents/Bundle.
# - Decrypt and JSON recovery are manual, mutually exclusive tasks.
# - Any runtime capture immediately requests the active manual task to stop.
JSONCapture_FILES = src/ManualTaskEngineV05.m src/OnDeviceLuaRecovery.m
JSONCapture_CFLAGS = -Oz -fno-stack-protector -fno-builtin -fblocks -Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-nullability-completeness -Wno-unused-function
JSONCapture_FRAMEWORKS = Foundation UIKit QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
