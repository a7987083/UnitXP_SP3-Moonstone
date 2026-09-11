ARCHS = arm64
TARGET = iphone:clang:latest:12.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HFAMapUniversal

HFAMapUniversal_FILES = src/HFAMapLegacy.m src/HFAMapPatchExecutionTrace.m src/HFAMapSecretCallGraphProbe.m src/HFANVideoVIPDiagnostic.m
HFAMapUniversal_CFLAGS = -Oz -fno-stack-protector -fno-builtin -Wno-empty-body -fblocks -include QuartzCore/QuartzCore.h
HFAMapUniversal_FRAMEWORKS = UIKit Foundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
