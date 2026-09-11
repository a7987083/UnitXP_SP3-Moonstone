ARCHS = arm64
TARGET = iphone:clang:latest:12.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HFAMapUniversal

# fenpingvip: standalone HFAMapUniversal floating UI + NVideo VIP diagnostic.
# Do not compile legacy Key Register / Auto Detect scanner UI here.
HFAMapUniversal_FILES = src/HFAMapEntry.mm
HFAMapUniversal_CFLAGS = -Oz -fno-stack-protector -fno-builtin -Wno-empty-body -Wno-unguarded-availability-new -fblocks
HFAMapUniversal_FRAMEWORKS = UIKit Foundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
