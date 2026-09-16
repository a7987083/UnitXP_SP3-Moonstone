ARCHS = arm64
TARGET = iphone:clang:latest:12.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = JSONCapture

# g4-r2 = device-validated g3 persistent full sweep + Chinese overlay UI +
# queued on-device static Lua 5.3 -> JSON recovery.
# GenericG4ChineseUIR2.m includes GenericPersistentSweep.m, which includes the g2 core.
# r2 fixes overlay touch passthrough and false capture-busy detection.
# No game-specific fixed RVA hooks are compiled in.
JSONCapture_FILES = src/GenericG4ChineseUIR2.m src/Lua53Analyzer.m src/OnDeviceLuaRecovery.m
JSONCapture_CFLAGS = -Oz -fno-stack-protector -fno-builtin -fblocks -Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-nullability-completeness -Wno-unused-function
JSONCapture_FRAMEWORKS = Foundation UIKit QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
