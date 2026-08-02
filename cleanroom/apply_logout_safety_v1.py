#!/usr/bin/env python3
"""Apply the validated MoonMarker logout-safety guards."""

from __future__ import annotations

import argparse
from pathlib import Path

from apply_logout_safety_native_v1 import install as install_native_safety
from apply_logout_safety_v2 import install as install_legacy_overlay_safety
from apply_logout_safety_v3 import install as install_sceneend_correction


def install(upstream: Path) -> None:
    # Keep the already field-tested Persistent-LogoutSafe V3 lifecycle code.
    # The later scene-mutation experiment is intentionally not installed:
    # it changed native create/release behavior and regressed logout stability.
    install_native_safety(upstream)
    install_legacy_overlay_safety(upstream)
    install_sceneend_correction(upstream)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--upstream", required=True)
    args = parser.parse_args()
    install(Path(args.upstream))


if __name__ == "__main__":
    main()
