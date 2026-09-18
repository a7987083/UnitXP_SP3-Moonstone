ARCHS = arm64
TARGET = iphone:clang:latest:12.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = JSONCapture

# Stable v0.7.1 core + clean v0.8 Mode1/Mode2 rebuild.
# - v0.7.0/v0.7.1 runtime_page_snapshot remains the only business-data reducer.
# - alpha1..alpha4: Mode1 exact follower, Mode2 active state machine, ResourcesUI/Bundles fixes.
# - alpha5: crash-resumable SHA256 journal + expanded Router discovery.
# - alpha6: nonblocking parseMsg-only Mode2 pump + actual recovered_json SHA256 validation.
# - alpha7: semantic-first/adaptive Router selection; runtime capture no longer cancels static recovery;
#   manual file tasks run at Utility QoS and SHA verification yields cooperatively.
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
	@python3 scripts/apply_v080_mode2_auto.py
	@python3 scripts/apply_v080_alpha3_runtime_sync.py
	@python3 scripts/apply_v080_alpha3_compile_fix.py
	@python3 scripts/apply_v080_alpha4_preflight.py
	@python3 scripts/apply_v080_alpha4_mode1_mode2_fix.py
	@python3 scripts/apply_v080_recovery_memsafe.py
	@python3 scripts/apply_v080_alpha4_stability.py
	@python3 scripts/apply_v080_alpha4_compile_fix.py
	@python3 scripts/apply_v080_alpha5_router_discovery.py
	@python3 scripts/apply_v080_alpha5_recovery_sha256_resume.py
	@python3 scripts/apply_v080_alpha5_identity.py
	@python3 scripts/apply_v080_alpha5_compile_fix.py
	@python3 scripts/apply_v080_alpha6_nonblocking_runtime.py
	@python3 scripts/apply_v080_alpha6_recovered_json_hashcheck.py
	@python3 scripts/apply_v080_alpha6_compile_fix.py
	@python3 scripts/apply_v080_alpha7_skill_router_recovery.py

include $(THEOS_MAKE_PATH)/tweak.mk
