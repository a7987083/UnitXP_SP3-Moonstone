#!/usr/bin/env python3
"""Guard MoonMarker SceneEnd projection during world teardown."""

from __future__ import annotations

import argparse
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def install(upstream: Path) -> None:
    # The first bad build inserted nativeM2Test::update() and
    # moonMarker::updateProjectedMarks() before scene_inWorld was checked.
    # Put an unconditional teardown guard at the first instruction of SceneEnd.
    scene_path = upstream / "sceneBegin_sceneEnd.cpp"
    scene = scene_path.read_text(encoding="utf-8")
    scene_signature = (
        "void __fastcall detoured_sceneEnd(uint32_t CGxDevice, void* ignored) {\n"
    )
    scene_guard = (
        scene_signature
        + "    // MoonMarker lifecycle guard: no M2 update or projection after the world starts tearing down.\n"
        + "    const uint32_t moonMarkerWorldFrame = vanilla1121_worldFrame();\n"
        + "    if (scene_inWorld != 1 || moonMarkerWorldFrame == 0\n"
        + "        || (moonMarkerWorldFrame & 3u) != 0u) {\n"
        + "        p_original_sceneEnd(CGxDevice);\n"
        + "        return;\n"
        + "    }\n\n"
    )
    scene = replace_once(
        scene,
        scene_signature,
        scene_guard,
        "SceneEnd pre-update world guard",
    )
    scene_path.write_text(scene, encoding="utf-8", newline="\n")

    path = upstream / "moonMarker.cpp"
    source = path.read_text(encoding="utf-8")

    # cursorRay() appears before the Present-rendering section where the helper
    # implementations are installed. Declare them at the start of the anonymous
    # namespace so every replaced projection/camera call has a visible prototype.
    namespace_anchor = "namespace moonMarker {\nnamespace {\n"
    forward_declarations = r'''

bool moonMarkerReadableCommittedRange(std::uintptr_t address, std::size_t bytes);
bool moonMarkerCurrentWorldFrame(std::uint32_t& frame);
bool moonMarkerWorldReady();
bool moonMarkerSafeWorldToScreen(const C3Vector& input, C3Vector& output);
C3Vector moonMarkerSafeWorldToScreenValue(const C3Vector& input);
'''
    source = replace_once(
        source,
        namespace_anchor,
        namespace_anchor + forward_declarations,
        "projection safety forward declarations",
    )

    anchor = "constexpr DWORD kMarkerFVF = D3DFVF_XYZRHW | D3DFVF_DIFFUSE | D3DFVF_TEX1;\n"
    helpers = r'''

constexpr std::uintptr_t kMoonMarkerWorldContextPointerAddress = 0x00C7B298;
constexpr std::uintptr_t kMoonMarkerWorldFramePointerAddress = 0x00B4B2BC;
constexpr std::uintptr_t kMoonMarkerWorldToScreenAddress = 0x00483EE0;
constexpr std::uintptr_t kMoonMarkerDdcToNdcAddress = 0x0041ADE0;

using MoonMarkerWorldToScreenProc = bool (__thiscall*)(
    std::uint32_t, float*, float*);
using MoonMarkerDdcToNdcProc = void (__fastcall*)(
    float*, float*, float, float);

bool moonMarkerReadableCommittedRange(std::uintptr_t address, std::size_t bytes) {
    if (address < 0x10000u || bytes == 0) return false;

    MEMORY_BASIC_INFORMATION info = {};
    if (VirtualQuery(reinterpret_cast<const void*>(address), &info, sizeof(info))
            != sizeof(info)) {
        return false;
    }
    if (info.State != MEM_COMMIT
        || (info.Protect & PAGE_GUARD) != 0
        || (info.Protect & PAGE_NOACCESS) != 0) {
        return false;
    }

    const std::uintptr_t start =
        reinterpret_cast<std::uintptr_t>(info.BaseAddress);
    const std::uintptr_t end = start + info.RegionSize;
    if (address < start || address >= end) return false;
    return bytes <= end - address;
}

bool moonMarkerCurrentWorldFrame(std::uint32_t& frame) {
    frame = *reinterpret_cast<const std::uint32_t*>(
        kMoonMarkerWorldFramePointerAddress);
    if (frame < 0x10000u || (frame & 3u) != 0u) return false;

    // 0x00483EFA reads [WorldFrame + 0x65B8]. Validate the exact fields used by
    // the client projection routine before calling it.
    if (!moonMarkerReadableCommittedRange(frame + 0x3A0u, 8u)
        || !moonMarkerReadableCommittedRange(frame + 0x65B8u, 4u)) {
        return false;
    }

    const std::uint32_t cameraBlock =
        *reinterpret_cast<const std::uint32_t*>(frame + 0x65B8u);
    if (cameraBlock < 0x10000u
        || !moonMarkerReadableCommittedRange(cameraBlock, 0x40u)) {
        return false;
    }
    return true;
}

bool moonMarkerWorldReady() {
    const std::uintptr_t context = *reinterpret_cast<const std::uintptr_t*>(
        kMoonMarkerWorldContextPointerAddress);
    if (context < 0x10000u || (context & 1u) != 0u
        || !moonMarkerReadableCommittedRange(context, sizeof(void*))) {
        return false;
    }

    std::uint32_t frame = 0;
    return moonMarkerCurrentWorldFrame(frame);
}

bool moonMarkerSafeWorldToScreen(
        const C3Vector& input, C3Vector& output) {
    output.x = -100000.0f;
    output.y = -100000.0f;
    output.z = 0.0f;

    std::uint32_t frame = 0;
    if (!moonMarkerCurrentWorldFrame(frame)) return false;

    C3Vector world = input;
    C3Vector ddc = {};
    if (!reinterpret_cast<MoonMarkerWorldToScreenProc>(
            kMoonMarkerWorldToScreenAddress)(frame, &world.x, &ddc.x)) {
        return false;
    }

    std::uint32_t frameAfter = 0;
    if (!moonMarkerCurrentWorldFrame(frameAfter) || frameAfter != frame) {
        return false;
    }

    float x = -1.0f;
    float y = -1.0f;
    reinterpret_cast<MoonMarkerDdcToNdcProc>(kMoonMarkerDdcToNdcAddress)(
        &x, &y, ddc.x, ddc.y);

    const RECT client = vanilla1121_gameClientRect();
    const float width = static_cast<float>(client.right - client.left);
    const float height = static_cast<float>(client.bottom - client.top);
    if (width <= 1.0f || height <= 1.0f) return false;

    const float bottom = *reinterpret_cast<const float*>(frame + 0x3A0u);
    const float left = *reinterpret_cast<const float*>(frame + 0x3A4u);
    if (!std::isfinite(bottom) || !std::isfinite(left)) return false;

    output.x = (left * width) + (x * width);
    output.y = height - (y * height) - (bottom * height);
    output.z = ddc.z;
    return std::isfinite(output.x) && std::isfinite(output.y);
}

C3Vector moonMarkerSafeWorldToScreenValue(const C3Vector& input) {
    C3Vector output = {};
    moonMarkerSafeWorldToScreen(input, output);
    return output;
}
'''
    source = replace_once(
        source,
        anchor,
        anchor + helpers,
        "marker projection safety helpers",
    )

    source = replace_once(
        source,
        "void updateProjectedMarks() {\n",
        "void updateProjectedMarks() {\n"
        "    if (!moonMarkerWorldReady()) {\n"
        "        resetProjected();\n"
        "        return;\n"
        "    }\n",
        "projected marker world guard",
    )

    call_count = source.count("vanilla1121_worldToScreen(")
    if call_count < 1:
        raise RuntimeError("MoonMarker has no worldToScreen call to replace")
    source = source.replace(
        "vanilla1121_worldToScreen(",
        "moonMarkerSafeWorldToScreenValue(",
    )

    # Validate every camera pointer used by placement/projection helpers.
    camera_guard = "if (camera == 0 || (camera & 1) != 0) {"
    camera_guard_safe = (
        "if (camera == 0 || (camera & 1) != 0\n"
        "        || !moonMarkerReadableCommittedRange(camera, 0x100u)) {"
    )
    source = source.replace(camera_guard, camera_guard_safe)

    if "vanilla1121_worldToScreen(" in source:
        raise RuntimeError("unsafe MoonMarker worldToScreen call remains")

    for token in (
        "moonMarkerSafeWorldToScreen",
        "moonMarkerWorldReady",
        "frame + 0x65B8u",
        "void updateProjectedMarks()",
        "projection safety forward declarations",
    ):
        if token not in source and token != "projection safety forward declarations":
            raise RuntimeError("missing projection safety token: " + token)

    path.write_text(source, encoding="utf-8", newline="\n")

    checks = {
        scene_path: (
            "MoonMarker lifecycle guard",
            "scene_inWorld != 1 || moonMarkerWorldFrame == 0",
        ),
        path: (
            "moonMarkerCurrentWorldFrame",
            "moonMarkerSafeWorldToScreenValue",
            "frame + 0x65B8u",
            "C3Vector moonMarkerSafeWorldToScreenValue(const C3Vector& input);",
        ),
    }
    for check_path, tokens in checks.items():
        text = check_path.read_text(encoding="utf-8")
        for token in tokens:
            if token not in text:
                raise RuntimeError(f"{check_path.name} missing token: {token}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--upstream", required=True)
    args = parser.parse_args()
    install(Path(args.upstream))


if __name__ == "__main__":
    main()
