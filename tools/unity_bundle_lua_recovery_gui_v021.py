#!/usr/bin/env python3
"""Windows GUI entry point for Unity Bundle Lua Recovery v0.2.1."""
from __future__ import annotations

import sys

import unity_bundle_lua_recovery_v021 as compat
import unity_bundle_lua_recovery_gui as gui

# Ensure the old GUI module uses the fixed v0.2.1 scanner and version string.
gui.scan_game_root = compat.scan_game_root
gui.self_test = compat.self_test
gui.APP_VERSION = compat.APP_VERSION


def main():
    if "--self-test" in sys.argv:
        compat.self_test()
        return
    gui.main()


if __name__ == "__main__":
    main()
