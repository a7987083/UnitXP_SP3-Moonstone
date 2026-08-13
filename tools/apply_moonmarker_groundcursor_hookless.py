#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "upstream")
cpp = root / "moonMarker.cpp"
header = root / "moonMarker.h"
dllmain = root / "dllmain.cpp"

for p in (cpp, header, dllmain):
    if not p.exists():
        raise SystemExit(f"missing required source: {p}")

def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, got {count}")
    return text.replace(old, new, 1)

s = cpp.read_text(encoding="utf-8")
s = replace_once(s, '#include "MinHook.h"\n', '', "remove MoonMarker MinHook include")

old_cursor_block = '''using GroundCursorProc = int(__fastcall*)(C3Vector*, void*);\nusing CursorModeProc = void(__fastcall*)(int, void*);\nusing CursorObjectActionProc = void(__thiscall*)(std::uint32_t, int);\nusing CursorObjectTargetProc = void(__thiscall*)(std::uint32_t, int, int, void*, int);\n\nGroundCursorProc gOriginalGroundCursor = nullptr;\nbool gGroundCursorHookCreated = false;\nbool gCaptureActive = false;\nbool gCaptureReceived = false;\nC3Vector gCapturedPosition = {};\n\nint __fastcall detouredGroundCursor(C3Vector* position, void*) {\n    if (!gCaptureActive) {\n        return gOriginalGroundCursor != nullptr\n            ? gOriginalGroundCursor(position, nullptr) : 0;\n    }\n\n    if (position != nullptr) {\n        gCapturedPosition = *position;\n        gCaptureReceived = std::isfinite(position->x)\n            && std::isfinite(position->y)\n            && std::isfinite(position->z);\n    }\n\n    *reinterpret_cast<std::uint32_t*>(0x00CECAC0) = 0;\n    reinterpret_cast<CursorModeProc>(0x00523D20)(1, nullptr);\n    reinterpret_cast<CursorModeProc>(0x00523C20)(1, nullptr);\n    gCaptureActive = false;\n    return 0;\n}\n\nbool cursorWorldIntersection(C3Vector& intersection) {\n    if (!moonMarkerRuntimeGuard::enabled()) return false;\n    if (!gGroundCursorHookCreated || gOriginalGroundCursor == nullptr) return false;\n\n    gCapturedPosition = {};\n    gCaptureReceived = false;\n    gCaptureActive = true;\n\n    *reinterpret_cast<std::uint32_t*>(0x00CECAC0) = 0x40;\n    reinterpret_cast<CursorModeProc>(0x00523D20)(2, nullptr);\n    reinterpret_cast<CursorModeProc>(0x00523C20)(2, nullptr);\n\n    const std::uint32_t cursorObject = *reinterpret_cast<std::uint32_t*>(0x00BE1148);\n    if (cursorObject == 0 || (cursorObject & 1) != 0) {\n        gCaptureActive = false;\n        *reinterpret_cast<std::uint32_t*>(0x00CECAC0) = 0;\n        reinterpret_cast<CursorModeProc>(0x00523D20)(1, nullptr);\n        reinterpret_cast<CursorModeProc>(0x00523C20)(1, nullptr);\n        return false;\n    }\n\n    reinterpret_cast<CursorObjectActionProc>(0x00514810)(cursorObject, 1);\n    auto target = reinterpret_cast<CursorObjectTargetProc>(0x00515090);\n    target(cursorObject, 2, 1, reinterpret_cast<void*>(0x00CF0BC8), 0);\n    target(cursorObject, 2, 0, reinterpret_cast<void*>(0x00CF0BC8), 0);\n\n    if (!gCaptureReceived) {\n        gCaptureActive = false;\n        return false;\n    }\n\n    intersection = gCapturedPosition;\n    return true;\n}\n'''

new_cursor_block = '''constexpr float kMaxPlacementDistance = 120.0f;\n\nstruct ScreenPoint {\n    float x = -1.0f;\n    float y = -1.0f;\n};\n\nC3Vector add(const C3Vector& a, const C3Vector& b) {\n    C3Vector result = {};\n    result.x = a.x + b.x;\n    result.y = a.y + b.y;\n    result.z = a.z + b.z;\n    return result;\n}\n\nC3Vector scale(const C3Vector& value, const float factor) {\n    C3Vector result = {};\n    result.x = value.x * factor;\n    result.y = value.y * factor;\n    result.z = value.z * factor;\n    return result;\n}\n\nScreenPoint project(const C3Vector& value) {\n    C3Vector mutableValue = value;\n    const C3Vector projected = vanilla1121_worldToScreen(mutableValue);\n    ScreenPoint point = {};\n    point.x = projected.x;\n    point.y = projected.y;\n    return point;\n}\n\nbool validScreenPoint(const ScreenPoint& point) {\n    return std::isfinite(point.x) && std::isfinite(point.y)\n        && point.x >= 0.0f && point.y >= 0.0f;\n}\n\nbool cursorRay(C3Vector& origin, C3Vector& direction) {\n    const HWND window = vanilla1121_gameWindow();\n    if (window == NULL) return false;\n\n    POINT cursor = {};\n    if (!GetCursorPos(&cursor) || !ScreenToClient(window, &cursor)) return false;\n\n    const RECT client = vanilla1121_gameClientRect();\n    const float width = static_cast<float>(client.right - client.left);\n    const float height = static_cast<float>(client.bottom - client.top);\n    if (width <= 1.0f || height <= 1.0f) return false;\n\n    const std::uint32_t camera = vanilla1121_getCamera();\n    if (camera == 0 || (camera & 1u) != 0u) return false;\n\n    origin = vanilla1121_getCameraPosition(camera);\n    C3Vector forward = vanilla1121_getCameraForwardVector(camera);\n    C3Vector right = vanilla1121_getCameraRightVector(camera);\n    C3Vector up = vanilla1121_getCameraUpVector(camera);\n    vectorNormalize(forward);\n    vectorNormalize(right);\n    vectorNormalize(up);\n    if (vectorAlmostZero(forward) || vectorAlmostZero(right) || vectorAlmostZero(up))\n        return false;\n\n    float horizontalFov = vanilla1121_getCameraFoV(camera);\n    float aspect = vanilla1121_getCameraAspectRatio(camera);\n    if (!std::isfinite(horizontalFov) || horizontalFov < 0.1f || horizontalFov > 3.0f)\n        horizontalFov = 1.0f;\n    if (!std::isfinite(aspect) || aspect < 0.5f || aspect > 4.0f)\n        aspect = width / height;\n\n    const float verticalFov =\n        2.0f * std::atan(std::tan(horizontalFov * 0.5f) / aspect);\n    float normalizedX =\n        (2.0f * (static_cast<float>(cursor.x) + 0.5f) / width) - 1.0f;\n    float normalizedY =\n        1.0f - (2.0f * (static_cast<float>(cursor.y) + 0.5f) / height);\n\n    const C3Vector probeCenter = add(origin, scale(forward, 20.0f));\n    const ScreenPoint centerScreen = project(probeCenter);\n    const ScreenPoint rightScreen = project(add(probeCenter, scale(right, 4.0f)));\n    const ScreenPoint upScreen = project(add(probeCenter, scale(up, 4.0f)));\n    if (validScreenPoint(centerScreen) && validScreenPoint(rightScreen)\n        && rightScreen.x < centerScreen.x) {\n        normalizedX = -normalizedX;\n    }\n    if (validScreenPoint(centerScreen) && validScreenPoint(upScreen)\n        && upScreen.y > centerScreen.y) {\n        normalizedY = -normalizedY;\n    }\n\n    direction = forward;\n    direction = add(direction,\n        scale(right, normalizedX * std::tan(horizontalFov * 0.5f)));\n    direction = add(direction,\n        scale(up, normalizedY * std::tan(verticalFov * 0.5f)));\n    vectorNormalize(direction);\n    return !vectorAlmostZero(direction);\n}\n\nbool cursorWorldIntersection(C3Vector& intersection) {\n    if (!moonMarkerRuntimeGuard::enabled()) return false;\n\n    C3Vector origin = {};\n    C3Vector direction = {};\n    if (!cursorRay(origin, direction)) return false;\n\n    const C3Vector end = add(origin, scale(direction, kMaxPlacementDistance));\n    float distance = 1.0f;\n    C3Vector hit = {};\n    if (!CWorld_Intersect(&origin, &end, &hit, &distance, 0x100111)) return false;\n    if (!std::isfinite(distance) || distance < 0.0f || distance > 1.0f)\n        return false;\n    if (!std::isfinite(hit.x) || !std::isfinite(hit.y) || !std::isfinite(hit.z))\n        return false;\n\n    intersection = hit;\n    return true;\n}\n'''

s = replace_once(s, old_cursor_block, new_cursor_block,
                 "replace permanent ground-cursor hook with on-demand ray")

old_functions = '''bool initializeGroundCursorHook() {\n    if (!moonMarkerRuntimeGuard::enabled()) return false;\n    if (gGroundCursorHookCreated) return true;\n    const MH_STATUS status = MH_CreateHook(\n        reinterpret_cast<LPVOID>(0x006E60F0),\n        reinterpret_cast<LPVOID>(&detouredGroundCursor),\n        reinterpret_cast<LPVOID*>(&gOriginalGroundCursor));\n    if (status != MH_OK) {\n        gOriginalGroundCursor = nullptr;\n        return false;\n    }\n    gGroundCursorHookCreated = true;\n    return true;\n}\n\nbool shutdownGroundCursorHook() {\n    if (!gGroundCursorHookCreated) return true;\n    const MH_STATUS status = MH_RemoveHook(reinterpret_cast<LPVOID>(0x006E60F0));\n    gGroundCursorHookCreated = false;\n    gOriginalGroundCursor = nullptr;\n    gCaptureActive = false;\n    gCaptureReceived = false;\n    return status == MH_OK;\n}\n\n'''
s = replace_once(s, old_functions, '', "remove ground-cursor hook lifecycle")
cpp.write_text(s, encoding="utf-8")

h = header.read_text(encoding="utf-8")
h = replace_once(h,
'''// Creates/removes the one-shot game ground-cursor hook.\nbool initializeGroundCursorHook();\nbool shutdownGroundCursorHook();\n\n''',
'''// Ground position is resolved on demand from the current OS cursor and\n// the game's camera/world-intersection helpers. No input/cursor hook is installed.\n''',
"remove hook declarations")
header.write_text(h, encoding="utf-8")

d = dllmain.read_text(encoding="utf-8")
d = replace_once(d,
'''        // MoonMarker has its own hardcoded client ABI. Validate it before\n        // creating any MoonMarker hook; upstream UnitXP hooks still load when\n        // the client is unsupported.\n        if (moonMarkerRuntimeGuard::initialize()) {\n            if (!moonMarker::initializeGroundCursorHook()) {\n                moonMarkerRuntimeGuard::markHookInstallFailed(\n                    "GROUND_CURSOR_HOOK_INSTALL_FAILED");\n            }\n        }\n''',
'''        // Validate MoonMarker's remaining native ABI. Ground position is now\n        // resolved on demand, so no MoonMarker input/cursor hook is installed.\n        (void)moonMarkerRuntimeGuard::initialize();\n''',
"remove startup ground-cursor hook")
d = replace_once(d,
'''            if (moonMarker::shutdownGroundCursorHook() == false) {\n                MessageBoxW(NULL, utf8_to_utf16(u8"Failed to remove MoonMarker ground cursor hook. Game might crash later.").data(), utf8_to_utf16(u8"UnitXP Service Pack 3").data(), MB_OK | MB_ICONINFORMATION | MB_SYSTEMMODAL);\n                return FALSE;\n            }\n''',
'',
"remove shutdown ground-cursor hook")
dllmain.write_text(d, encoding="utf-8")

print("Applied MoonMarker hookless ground cursor conversion")
