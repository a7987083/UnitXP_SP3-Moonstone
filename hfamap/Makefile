ARCHS = arm64
TARGET = iphone:clang:latest:12.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HFAMapUniversal

HFAMapUniversal_FILES = \
    src/HFAMapEntry.mm \
    src/HFAMapCore.mm \
    src/HFAMapModules.mm \
    src/HFAMapResolver.mm \
    src/HFAMapImageProbe.mm \
    src/HFAMapHook.mm

HFAMapUniversal_CFLAGS = -fobjc-arc
HFAMapUniversal_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
