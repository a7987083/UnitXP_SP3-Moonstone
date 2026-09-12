ARCHS = arm64
TARGET = iphone:clang:latest:12.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HFAMapUniversal

# fenpingvip v7 authorized offset-patch test build:
# - v1 HF floating shell behavior
# - RVA/VA diagnostics for NVideo main image
# - validates write site 0x4AB18 == 02 0C 00 F9
# - patches that write site to ARM64 NOP for deterministic state testing
# - level 0/1/2/3 writes the verified DIYVIP::_status +0x18 slot
# - one-tap restore returns 0x4AB18 to the original instruction
HFAMapUniversal_FILES = src/HFAMapOffsetPatch.mm
HFAMapUniversal_CFLAGS = -Oz -fno-stack-protector -fno-builtin -Wno-empty-body -Wno-unguarded-availability-new -fblocks
HFAMapUniversal_FRAMEWORKS = UIKit Foundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
