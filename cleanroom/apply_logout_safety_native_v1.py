#!/usr/bin/env python3
"""Prevent native M2 WorldToScreen/model access after world teardown."""

from pathlib import Path
import argparse


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def install(upstream: Path):
    path = upstream / "nativeM2Test.cpp"
    source = path.read_text(encoding="utf-8")

    source = replace_once(source,
'''constexpr std::uintptr_t kWorldM2ContextPointerAddress = 0x00C7B298;
constexpr std::uintptr_t kCreateModelAddress = 0x00707350;
''',
'''constexpr std::uintptr_t kWorldM2ContextPointerAddress = 0x00C7B298;
constexpr std::uintptr_t kWorldFramePointerAddress = 0x00B4B2BC;
constexpr std::uintptr_t kWorldToScreenAddress = 0x00483EE0;
constexpr std::uintptr_t kDdcToNdcAddress = 0x0041ADE0;
constexpr std::uintptr_t kCreateModelAddress = 0x00707350;
''', "world frame constants")

    source = replace_once(source,
'''using CreateModelProc = void* (__thiscall*)(void*, const char*, std::uint32_t);
using ReleaseModelProc = void (__thiscall*)(void*);
''',
'''using CreateModelProc = void* (__thiscall*)(void*, const char*, std::uint32_t);
using WorldToScreenProc = bool (__thiscall*)(std::uint32_t, float*, float*);
using DdcToNdcProc = void (__fastcall*)(float*, float*, float, float);
using ReleaseModelProc = void (__thiscall*)(void*);
''', "projection proc types")

    source = replace_once(source,
'''void* currentContext() {
    void* context = *reinterpret_cast<void**>(kWorldM2ContextPointerAddress);
    if (context == nullptr || (reinterpret_cast<std::uintptr_t>(context) & 1u) != 0u) {
        return nullptr;
    }
    return context;
}

void buildWorldMatrix''',
'''void* currentContext() {
    void* context = *reinterpret_cast<void**>(kWorldM2ContextPointerAddress);
    if (context == nullptr || (reinterpret_cast<std::uintptr_t>(context) & 1u) != 0u) {
        return nullptr;
    }
    return context;
}

bool readableCommittedRange(std::uintptr_t address, std::size_t bytes) {
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
    const std::uintptr_t regionStart =
        reinterpret_cast<std::uintptr_t>(info.BaseAddress);
    const std::uintptr_t regionEnd = regionStart + info.RegionSize;
    if (address < regionStart || address > regionEnd) return false;
    return bytes <= regionEnd - address;
}

bool currentWorldFrame(std::uint32_t& frame) {
    frame = *reinterpret_cast<const std::uint32_t*>(kWorldFramePointerAddress);
    if ((frame & 3u) != 0u) return false;
    return readableCommittedRange(frame, 0x3B0u);
}

bool safeWorldToScreen(const C3Vector& input, C3Vector& output) {
    output = {};
    std::uint32_t frame = 0;
    if (!currentWorldFrame(frame)) return false;

    C3Vector world = input;
    C3Vector ddc = {};
    if (!reinterpret_cast<WorldToScreenProc>(kWorldToScreenAddress)(
            frame, &world.x, &ddc.x)) {
        return false;
    }

    std::uint32_t frameAfter = 0;
    if (!currentWorldFrame(frameAfter) || frameAfter != frame) return false;

    float x = -1.0f;
    float y = -1.0f;
    reinterpret_cast<DdcToNdcProc>(kDdcToNdcAddress)(
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

void buildWorldMatrix''', "safe world frame helpers")

    source = replace_once(source,
'''    C3Vector world = slot.position;
    world.z += kIconWorldHeight;
    C3Vector screen = vanilla1121_worldToScreen(world);
    const RECT client = vanilla1121_gameClientRect();
''',
'''    C3Vector world = slot.position;
    world.z += kIconWorldHeight;
    C3Vector screen = {};
    if (!safeWorldToScreen(world, screen)) return;
    const RECT client = vanilla1121_gameClientRect();
''', "safe icon projection")

    source = replace_once(source,
'''void update() {
    resetProjected();
    void* liveContext = currentContext();
    moonMarkerAdvancedState::observeWorldContext(
        reinterpret_cast<std::uintptr_t>(liveContext));
    for (std::size_t i = 0; i < gSlots.size(); ++i) {
''',
'''void update() {
    resetProjected();
    void* liveContext = currentContext();
    std::uint32_t worldFrame = 0;
    const bool worldReady = liveContext != nullptr
        && currentWorldFrame(worldFrame);
    moonMarkerAdvancedState::observeWorldContext(worldReady
        ? reinterpret_cast<std::uintptr_t>(liveContext) : 0u);
    if (!worldReady) {
        for (Slot& slot : gSlots) {
            if (slot.active || slot.model != nullptr) ++gDroppedStalePointers;
            resetSlot(slot);
        }
        if (gPlacementPreview.active || gPlacementPreview.model != nullptr) {
            ++gDroppedStalePointers;
        }
        if (gAdvancedPreview.active || gAdvancedPreview.model != nullptr) {
            ++gDroppedStalePointers;
        }
        resetPlacementPreview();
        resetAdvancedPreview();
        moonMarkerAdvancedState::clearAll("WORLD_NOT_READY");
        gLastErrorStage = "world_not_ready_drop_without_release";
        return;
    }
    for (std::size_t i = 0; i < gSlots.size(); ++i) {
''', "world exit early drop")

    source = replace_once(source,
'''void clear() {
    moonMarkerAdvancedState::clearAll("NATIVE_CLEAR_ALL");
    for (Slot& slot : gSlots) releaseSlot(slot, false);
    releasePlacementPreview(false);
    releaseAdvancedPreview(false);
    resetProjected();
    gLastErrorStage = "cleared_all";
}
''',
'''void clear() {
    moonMarkerAdvancedState::clearAll("NATIVE_CLEAR_ALL");
    std::uint32_t worldFrame = 0;
    if (currentContext() == nullptr || !currentWorldFrame(worldFrame)) {
        for (Slot& slot : gSlots) resetSlot(slot);
        resetPlacementPreview();
        resetAdvancedPreview();
        resetProjected();
        gLastErrorStage = "cleared_all_world_not_ready";
        return;
    }
    for (Slot& slot : gSlots) releaseSlot(slot, false);
    releasePlacementPreview(false);
    releaseAdvancedPreview(false);
    resetProjected();
    gLastErrorStage = "cleared_all";
}
''', "safe clear during logout")

    path.write_text(source, encoding="utf-8", newline="\n")
    for token in (
        "safeWorldToScreen",
        "world_not_ready_drop_without_release",
        "cleared_all_world_not_ready",
        "VirtualQuery",
    ):
        if token not in source:
            raise RuntimeError("missing logout-safety token: " + token)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--upstream", required=True)
    args = parser.parse_args()
    install(Path(args.upstream))


if __name__ == "__main__":
    main()
