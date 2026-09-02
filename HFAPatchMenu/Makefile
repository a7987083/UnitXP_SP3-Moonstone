ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HFAPatchMenu

HFAPatchMenu_FILES = \
	src/HFAPatchEntry.mm \
	src/HFAPatchLogger.m \
	src/HFAPatchConfig.m \
	src/HFAPatchEngine.mm \
	src/HFAPatchMenuUI.m

HFAPatchMenu_CFLAGS = -fobjc-arc -Oz -Wall -Wextra -Wno-unused-parameter
HFAPatchMenu_CCFLAGS = -std=c++17
HFAPatchMenu_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
