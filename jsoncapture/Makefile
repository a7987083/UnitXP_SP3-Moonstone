ARCHS = arm64
TARGET = iphone:clang:latest:12.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = JSONCapture

# v0.5 Manual Task Engine
# - Runtime Lua loader capture hooks are lightweight and user-toggleable.
# - No loaded-bundle watcher, no disk watcher, no persistent log poll.
# - Local scan only runs when the user presses Start and only scans Documents/Bundle.
# - Decrypt and JSON recovery are manual, mutually exclusive tasks.
# - Only genuinely NEW runtime Lua captures preempt manual work.
# - v0.5.1 restores scroll + draggable compact menu.
# - v0.5.2 adds cross-launch MD5/SHA256 runtime Lua cache and duplicate skip UI.
# - v0.5.4 adds an exact-target, read-only response observer on the SAME serialized hook-install path.
JSONCapture_FILES = src/ManualTaskEngineV05.m src/JCG5ScrollFix.m src/OnDeviceLuaRecovery.m
JSONCapture_CFLAGS = -Oz -fno-stack-protector -fno-builtin -fblocks -Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-nullability-completeness -Wno-unused-function
src/ManualTaskEngineV05.m_CFLAGS = -include src/JCG5CompileCompat.h
JSONCapture_FRAMEWORKS = Foundation UIKit QuartzCore

before-all::
	@python3 scripts/apply_v052_runtime_cache.py
	@python3 scripts/apply_v054_response_observer.py

include $(THEOS_MAKE_PATH)/tweak.mk
