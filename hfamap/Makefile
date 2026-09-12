ARCHS = arm64
TARGET = iphone:clang:latest:12.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HFAMapUniversal

# fenpingvip v6 unified build:
# - v1 HF floating shell behavior (position/drag/window reattach/front ordering)
# - v2 NVideo VIP Diagnostic clicked panel/content
# - real level 0/1/2/3 buttons using DIYVIP updateStatus:type: with no auto-restore
# Legacy Key Register / Auto Detect / Full Scan sources are intentionally excluded.
HFAMapUniversal_FILES = src/HFAMapEntry.mm
HFAMapUniversal_CFLAGS = -Oz -fno-stack-protector -fno-builtin -Wno-empty-body -Wno-unguarded-availability-new -fblocks
HFAMapUniversal_FRAMEWORKS = UIKit Foundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
