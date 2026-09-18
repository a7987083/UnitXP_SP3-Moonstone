ARCHS = arm64
TARGET = iphone:clang:latest:12.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = JSONCapture

# Stable v0.7.1 core + clean v0.8 Mode1/Mode2 rebuild.
# - v0.5.x capture/network/recovery behavior remains unchanged.
# - v0.6.0 page context + NetWorkManager protobuf capture remains unchanged.
# - v0.7.0/v0.7.1 runtime_page_snapshot remains the only business-data reducer.
# - v0.8.0-alpha1 adds Mode1 as an exact byte mirror of canonical snapshot writes.
# - No second JSON/protobuf reducer is introduced for Mode1.
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
	@python3 scripts/apply_v060_page_protobuf.py
	@python3 scripts/apply_v060_hardening.py
	@python3 scripts/apply_v070_page_snapshot.py
	@python3 scripts/apply_v071_snapshot_completeness.py
	@python3 scripts/apply_v080_mode1_exact_mirror.py

include $(THEOS_MAKE_PATH)/tweak.mk
