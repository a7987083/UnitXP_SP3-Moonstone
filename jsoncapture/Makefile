ARCHS = arm64
TARGET = iphone:clang:latest:12.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = JSONCapture

# JSONCapture patch chain
# - v0.7.0: descriptor-driven protobuf + request-correlated page snapshots.
# - v0.7.1: deeper protobuf snapshot + stable-parent child-UI merge.
# - v0.8.0/0.8.1: Mode lifecycle and runtime-latest observation.
# - v0.8.2: full SHA-256 content identity + semantic/file snapshot hashes.
# - v0.8.3: Documents/Bundles path, recovery-memory bounding, Mode1/Mode2
#   canonical runtime_page_snapshot control plane, and read-only UI-router discovery.
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
	@python3 scripts/apply_v080_page_dependency.py
	@python3 scripts/apply_v080_runtime_auto_fix.py
	@python3 scripts/apply_v081_runtime_latest_sync.py
	@python3 scripts/apply_v082_sha256_identity.py
	@python3 scripts/apply_v083_foundation_fixes.py
	@python3 scripts/apply_v083_recovery_memory.py
	@python3 scripts/apply_v083_recovery_summary_restore.py
	@python3 scripts/apply_v083_snapshot_mode_unify.py
	@python3 scripts/apply_v083_compile_cleanup.py
	@python3 scripts/apply_v083_router_discovery.py

include $(THEOS_MAKE_PATH)/tweak.mk
