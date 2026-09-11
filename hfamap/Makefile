ARCHS = arm64
TARGET = iphone:clang:latest:12.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HFAMapUniversal

# fenpingvip v3:
# Keep the original HFAMapUniversal shell from HFAMapLegacy.m unchanged.
# Only replace the original panel contents with the NVideo VIP diagnostic UI.
HFAMapUniversal_FILES = src/HFAMapLegacy.m src/HFAMapPatchExecutionTrace.m src/HFAMapSecretCallGraphProbe.m src/HFANVideoVIPShellAdapter.m
HFAMapUniversal_CFLAGS = -Oz -fno-stack-protector -fno-builtin -Wno-empty-body -Wno-unguarded-availability-new -fblocks
HFAMapUniversal_FRAMEWORKS = UIKit Foundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
