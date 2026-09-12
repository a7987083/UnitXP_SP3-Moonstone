ARCHS = arm64
TARGET = iphone:clang:latest:12.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HFAMapUniversal

# fenpingvip v4:
# Keep the original HFAMapUniversal shell from HFAMapLegacy.m unchanged.
# Replace only the panel contents with NVideo VIP diagnostics and add a
# real 0/1/2/3 state controller that calls DIYVIP's own updateStatus:type:
# transition path. The selected in-process status is not auto-restored.
HFAMapUniversal_FILES = src/HFAMapLegacy.m src/HFAMapPatchExecutionTrace.m src/HFAMapSecretCallGraphProbe.m src/HFANVideoVIPShellAdapter.m src/HFANVideoVIPStateVerifier.m
HFAMapUniversal_CFLAGS = -Oz -fno-stack-protector -fno-builtin -Wno-empty-body -Wno-unguarded-availability-new -fblocks
HFAMapUniversal_FRAMEWORKS = UIKit Foundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
