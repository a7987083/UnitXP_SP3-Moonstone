#!/usr/bin/env python3
"""Reject native M2 mutations when the WoW world is entering teardown."""

from __future__ import annotations

import argparse
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def install(upstream: Path) -> None:
    cpp_path = upstream / "nativeM2Test.cpp"
    header_path = upstream / "nativeM2Test.h"
    source = cpp_path.read_text(encoding="utf-8")
    header = header_path.read_text(encoding="utf-8")

    old_world_frame = '''bool currentWorldFrame(std::uint32_t& frame) {
    frame = *reinterpret_cast<const std::uint32_t*>(kWorldFramePointerAddress);
    if ((frame & 3u) != 0u) return false;
    return readableCommittedRange(frame, 0x3B0u);
}
'''
    new_world_frame = '''bool currentWorldFrame(std::uint32_t& frame) {
    frame = *reinterpret_cast<const std::uint32_t*>(kWorldFramePointerAddress);
    if (frame < 0x10000u || (frame & 3u) != 0u) return false;

    // The client projection routine reads WorldFrame + 0x65B8. During logout
    // WorldFrame can remain non-zero while this camera field is already gone.
    if (!readableCommittedRange(frame + 0x3A0u, 8u)
        || !readableCommittedRange(frame + 0x65B8u, 4u)) {
        return false;
    }
    const std::uint32_t cameraBlock =
        *reinterpret_cast<const std::uint32_t*>(frame + 0x65B8u);
    return cameraBlock >= 0x10000u
        && readableCommittedRange(cameraBlock, 0x40u);
}

bool sceneMutationReadyInternal(void*& context) {
    context = currentContext();
    if (context == nullptr
        || !readableCommittedRange(
            reinterpret_cast<std::uintptr_t>(context), 0x40u)) {
        return false;
    }
    std::uint32_t frame = 0;
    return currentWorldFrame(frame);
}
'''
    source = replace_once(
        source, old_world_frame, new_world_frame,
        "exact WorldFrame mutation validation")

    old_release = '''    void* liveContext = currentContext();
    void* modelContext = readField<void*>(slot.model, 0x2C);
    if (liveContext != nullptr && liveContext == slot.context && modelContext == slot.context) {
        reinterpret_cast<SetBooleanProc>(kAttachToRenderListAddress)(slot.model, 0);
        reinterpret_cast<ReleaseModelProc>(kReleaseModelAddress)(slot.model);
'''
    new_release = '''    void* liveContext = nullptr;
    if (!sceneMutationReadyInternal(liveContext)
        || liveContext != slot.context
        || !readableCommittedRange(
            reinterpret_cast<std::uintptr_t>(slot.model), 0x54u)) {
        ++gDroppedStalePointers;
        if (updateStage) gLastErrorStage = "cleared_world_not_ready";
        resetSlot(slot);
        return;
    }

    void* modelContext = readField<void*>(slot.model, 0x2C);
    if (modelContext == slot.context) {
        reinterpret_cast<SetBooleanProc>(kAttachToRenderListAddress)(slot.model, 0);
        reinterpret_cast<ReleaseModelProc>(kReleaseModelAddress)(slot.model);
'''
    source = replace_once(
        source, old_release, new_release,
        "safe native slot release")

    old_slot_start = '''    Slot& slot = gSlots[static_cast<std::size_t>(selectedColor)];
    releaseSlot(slot, false);
    slot.playerObject = playerObject;
'''
    new_slot_start = '''    void* mutationContext = nullptr;
    if (!sceneMutationReadyInternal(mutationContext)) {
        gLastErrorStage = "world_not_ready_create_rejected";
        return false;
    }

    Slot& slot = gSlots[static_cast<std::size_t>(selectedColor)];
    releaseSlot(slot, false);
    slot.playerObject = playerObject;
'''
    source = replace_once(
        source, old_slot_start, new_slot_start,
        "reject create during world teardown")

    old_context_assign = '''    gLastErrorStage = "find_world_context";
    slot.context = currentContext();
    if (slot.context == nullptr) {
        resetSlot(slot);
        return false;
    }
'''
    new_context_assign = '''    gLastErrorStage = "find_world_context";
    slot.context = mutationContext;
    void* contextCheck = nullptr;
    if (!sceneMutationReadyInternal(contextCheck)
        || contextCheck != slot.context) {
        resetSlot(slot);
        gLastErrorStage = "world_changed_before_create";
        return false;
    }
'''
    source = replace_once(
        source, old_context_assign, new_context_assign,
        "stable create context")

    old_after_create = '''    ++gCreateSuccesses;

    if (readField<void*>(slot.model, 0x2C) != slot.context) {
'''
    new_after_create = '''    ++gCreateSuccesses;

    void* contextAfterCreate = nullptr;
    if (!sceneMutationReadyInternal(contextAfterCreate)
        || contextAfterCreate != slot.context
        || !readableCommittedRange(
            reinterpret_cast<std::uintptr_t>(slot.model), 0x54u)) {
        // Do not call the client release routine while the world is tearing
        // down. The client owns destruction of this just-created object.
        resetSlot(slot);
        gLastErrorStage = "world_changed_after_create";
        return false;
    }

    if (readField<void*>(slot.model, 0x2C) != slot.context) {
'''
    source = replace_once(
        source, old_after_create, new_after_create,
        "post-create world validation")

    old_update_check = '''        if (liveContext == nullptr || liveContext != slot.context) {
            ++gDroppedStalePointers;
            resetSlot(slot);
            gLastErrorStage = "world_context_changed";
            continue;
        }
'''
    new_update_check = '''        if (liveContext == nullptr || liveContext != slot.context
            || !readableCommittedRange(
                reinterpret_cast<std::uintptr_t>(slot.model), 0x54u)) {
            ++gDroppedStalePointers;
            resetSlot(slot);
            gLastErrorStage = "world_context_changed";
            continue;
        }
'''
    source = replace_once(
        source, old_update_check, new_update_check,
        "safe per-frame model pointer")

    old_status_guard = '''        if (result.contextMatches) {
            result.modelContextPointer = static_cast<std::uint32_t>(
'''
    new_status_guard = '''        if (result.contextMatches
            && readableCommittedRange(
                reinterpret_cast<std::uintptr_t>(slot.model), 0x54u)) {
            result.modelContextPointer = static_cast<std::uint32_t>(
'''
    source = replace_once(
        source, old_status_guard, new_status_guard,
        "safe status model reads")

    public_anchor = '''void clear() {
'''
    public_function = '''bool worldReadyForMutation() {
    void* context = nullptr;
    return sceneMutationReadyInternal(context);
}

'''
    source = replace_once(
        source, public_anchor, public_function + public_anchor,
        "public scene mutation readiness")

    if "bool worldReadyForMutation();" not in header:
        header = replace_once(
            header,
            "// Removes every native model.\nvoid clear();\n",
            "// Returns true only while client scene mutation is safe.\n"
            "bool worldReadyForMutation();\n\n"
            "// Removes every native model.\nvoid clear();\n",
            "scene readiness declaration",
        )

    cpp_path.write_text(source, encoding="utf-8", newline="\n")
    header_path.write_text(header, encoding="utf-8", newline="\n")

    required = (
        "sceneMutationReadyInternal",
        "world_not_ready_create_rejected",
        "cleared_world_not_ready",
        "world_changed_after_create",
        "bool worldReadyForMutation()",
        "frame + 0x65B8u",
    )
    for token in required:
        if token not in source:
            raise RuntimeError("missing scene mutation guard token: " + token)
    if "bool worldReadyForMutation();" not in header:
        raise RuntimeError("nativeM2Test.h missing scene readiness declaration")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--upstream", required=True)
    args = parser.parse_args()
    install(Path(args.upstream))


if __name__ == "__main__":
    main()
