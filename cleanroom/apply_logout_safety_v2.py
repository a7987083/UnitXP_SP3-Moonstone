#!/usr/bin/env python3
"""Guard the legacy MoonMarker Present overlay during world teardown."""

from __future__ import annotations

import argparse
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def install(upstream: Path) -> None:
    path = upstream / "moonMarker.cpp"
    source = path.read_text(encoding="utf-8")

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
    if ((frame & 3u) != 0u) return false;
    return moonMarkerReadableCommittedRange(frame, 0x3B0u);
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
        "legacy overlay world helpers",
    )

    source = replace_once(
        source,
        "void renderPresent(IDirect3DDevice9* device) {\n"
        "    if (device == nullptr || count() == 0) {\n",
        "void renderPresent(IDirect3DDevice9* device) {\n"
        "    if (!moonMarkerWorldReady()) {\n"
        "        gProjectedMarks = 0;\n"
        "        return;\n"
        "    }\n"
        "    if (device == nullptr || count() == 0) {\n",
        "legacy overlay early world guard",
    )

    source = replace_once(
        source,
        "    const uint32_t camera = vanilla1121_getCamera();\n"
        "    if (camera == 0 || (camera & 1) != 0) {\n",
        "    const uint32_t camera = vanilla1121_getCamera();\n"
        "    if (camera == 0 || (camera & 1) != 0\n"
        "        || !moonMarkerReadableCommittedRange(camera, 0x400u)) {\n",
        "legacy overlay camera guard",
    )

    call_count = source.count("vanilla1121_worldToScreen(")
    if call_count < 1:
        raise RuntimeError("legacy overlay has no worldToScreen call to replace")
    source = source.replace(
        "vanilla1121_worldToScreen(",
        "moonMarkerSafeWorldToScreenValue(",
    )

    if "vanilla1121_worldToScreen(" in source:
        raise RuntimeError("unsafe legacy worldToScreen call remains")

    for token in (
        "moonMarkerSafeWorldToScreen",
        "moonMarkerWorldReady",
        "moonMarkerReadableCommittedRange(camera, 0x400u)",
    ):
        if token not in source:
            raise RuntimeError("missing legacy logout guard token: " + token)

    path.write_text(source, encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--upstream", required=True)
    args = parser.parse_args()
    install(Path(args.upstream))


if __name__ == "__main__":
    main()
