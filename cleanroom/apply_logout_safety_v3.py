#!/usr/bin/env python3
"""Keep native M2 updates running while retaining internal logout guards."""

from __future__ import annotations

import argparse
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def install(upstream: Path) -> None:
    path = upstream / "sceneBegin_sceneEnd.cpp"
    source = path.read_text(encoding="utf-8")

    # V2 inserted an outer return before nativeM2Test::update(). That prevents
    # one-shot native models from being refreshed/re-attached during ordinary
    # gameplay on clients where scene_inWorld/WorldFrame is transient here.
    # The native renderer and projection renderer now both have their own
    # pointer/lifecycle validation, so remove only this over-broad outer guard.
    guarded = (
        "void __fastcall detoured_sceneEnd(uint32_t CGxDevice, void* ignored) {\n"
        "    // MoonMarker lifecycle guard: no M2 update or projection after the world starts tearing down.\n"
        "    const uint32_t moonMarkerWorldFrame = vanilla1121_worldFrame();\n"
        "    if (scene_inWorld != 1 || moonMarkerWorldFrame == 0\n"
        "        || (moonMarkerWorldFrame & 3u) != 0u) {\n"
        "        p_original_sceneEnd(CGxDevice);\n"
        "        return;\n"
        "    }\n\n"
    )
    unguarded = (
        "void __fastcall detoured_sceneEnd(uint32_t CGxDevice, void* ignored) {\n"
        "    // Native M2 keeps updating here; each MoonMarker renderer performs\n"
        "    // its own world-teardown validation before touching client memory.\n"
    )
    source = replace_once(
        source,
        guarded,
        unguarded,
        "remove over-broad SceneEnd return",
    )

    # Static invariants: persistent native update remains before the original
    # downstream scene_inWorld branch, while the dangerous outer return is gone.
    if "nativeM2Test::update();" not in source:
        raise RuntimeError("native M2 update missing after SceneEnd correction")
    if "MoonMarker lifecycle guard: no M2 update" in source:
        raise RuntimeError("over-broad SceneEnd guard still present")
    if "each MoonMarker renderer performs" not in source:
        raise RuntimeError("SceneEnd correction marker missing")

    path.write_text(source, encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--upstream", required=True)
    args = parser.parse_args()
    install(Path(args.upstream))


if __name__ == "__main__":
    main()
