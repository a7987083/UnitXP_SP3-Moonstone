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
# - v0.5.5 persists only fully validated JSON bodies from the proven response observer path.
# - v0.5.6 correlates saved JSON with URL/method/status and classifies hot-update/notice responses.
# - v0.5.7 adds UnityWebRequestDelegate/NSURLSession backend JSON capture across DownloadHandler types.
# - v0.5.8 wraps g_requestHttpServer on the Lua VM thread to capture SocketTCP/protobuf bodies after optional AES decrypt.
# - v0.5.9 adds session-scoped request/response coverage statistics without expanding the hook surface.
JSONCapture_FILES = src/ManualTaskEngineV05.m src/JCG5ScrollFix.m src/OnDeviceLuaRecovery.m
JSONCapture_CFLAGS = -Oz -fno-stack-protector -fno-builtin -fblocks -Wno-deprecated-declarations -Wno-unguarded-availability-new -Wno-nullability-completeness -Wno-unused-function
src/ManualTaskEngineV05.m_CFLAGS = -include src/JCG5CompileCompat.h
JSONCapture_FRAMEWORKS = Foundation UIKit QuartzCore

before-all::
	@python3 scripts/apply_v052_runtime_cache.py
	@python3 scripts/apply_v054_response_observer.py
	@python3 scripts/apply_v055_response_capture.py
	@python3 scripts/apply_v056_response_metadata.py
	@python3 scripts/apply_v056_response_metadata_hardening.py
	@python3 scripts/apply_v057_unity_all_json.py
	@python3 scripts/apply_v057_compile_compat.py
	@python3 scripts/apply_v058_socket_http_json.py
	@python3 scripts/apply_v059_network_coverage.py
	@python3 scripts/apply_v059_compile_fix.py

include $(THEOS_MAKE_PATH)/tweak.mk
