#!/usr/bin/env python3
"""Compatibility/robustness launcher for Unity Bundle Lua Recovery v0.2.1.

Fixes two failures observed on real exported iOS Unity data:
1) SerializedFile without an embedded Unity version -> configure UnityPy fallback to 2019.4.33f1.
2) bundle_errors.jsonl path not writable / colliding with a directory -> error logging must not abort recovery.

The recovery core remains read-only toward the user's game data and never executes Lua.
"""
from __future__ import annotations

import json
import tempfile
from pathlib import Path

import UnityPy
import UnityPy.config

import unity_bundle_lua_recovery as core

TARGET_UNITY_VERSION = "2019.4.33f1"
APP_VERSION = "0.2.1"

# The supplied UnityFramework was positively identified as Unity 2019.4.33f1.
# UnityPy explicitly requires FALLBACK_UNITY_VERSION when a SerializedFile does
# not carry a parseable version string.
UnityPy.config.FALLBACK_UNITY_VERSION = TARGET_UNITY_VERSION
core.APP_VERSION = APP_VERSION

_original_append_jsonl = core.append_jsonl


def _fallback_log_path(path: Path) -> Path:
    root = Path(tempfile.gettempdir()) / "UnityBundleLuaRecovery" / "logs"
    root.mkdir(parents=True, exist_ok=True)
    tag = core.safe_name(str(path.parent), 80)
    return root / f"{tag}_{path.name}.jsonl"


def safe_append_jsonl(path: Path, obj: dict):
    """Best-effort JSONL logging. Logging failure must never kill a scan."""
    path = Path(path)
    try:
        # A previous run/user folder can accidentally occupy the intended file path.
        if path.exists() and path.is_dir():
            path = path.with_name(path.name + ".log")
        _original_append_jsonl(path, obj)
        return
    except (PermissionError, IsADirectoryError, OSError):
        pass

    try:
        fallback = _fallback_log_path(path)
        with fallback.open("a", encoding="utf-8") as f:
            f.write(json.dumps(obj, ensure_ascii=False) + "\n")
    except Exception:
        # Error reporting is non-critical. Never mask the actual Bundle result.
        return


core.append_jsonl = safe_append_jsonl


def scan_game_root(*args, **kwargs):
    # Re-assert in case a packaged dependency resets config during startup.
    UnityPy.config.FALLBACK_UNITY_VERSION = TARGET_UNITY_VERSION
    return core.scan_game_root(*args, **kwargs)


def self_test():
    core.self_test()
    assert UnityPy.config.FALLBACK_UNITY_VERSION == TARGET_UNITY_VERSION
    # Verify collision-safe logger with a directory occupying the nominal file path.
    tmp = Path(tempfile.mkdtemp(prefix="ublr-v021-"))
    collision = tmp / "bundle_errors.jsonl"
    collision.mkdir()
    safe_append_jsonl(collision, {"self_test": True})
    assert (tmp / "bundle_errors.jsonl.log").is_file()
    print("v0.2.1 compatibility self-test passed")


if __name__ == "__main__":
    self_test()
