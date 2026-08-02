#!/usr/bin/env python3
"""Queue ordinary team-state scene mutations instead of running them in addon events."""

from __future__ import annotations

import argparse
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def install(addon_root: Path) -> None:
    path = addon_root / "MoonMarker.lua"
    source = path.read_text(encoding="utf-8")

    source = replace_once(
        source,
        '''local pendingSceneApply = false
''',
        '''local pendingSceneApply = false
local sceneApplyElapsed = 0
''',
        "scene apply retry timer",
    )

    source = replace_once(
        source,
        '''    sceneSynchronized = true
    SaveTeamState()
end

local function ClearTeamState()
''',
        '''    sceneSynchronized = false
    pendingSceneApply = true
    SaveTeamState()
end

local function ClearTeamState()
''',
        "queue received placement",
    )

    source = replace_once(
        source,
        '''local function ClearTeamState()
    teamMarks = {}
    incomingSnapshot = nil
    sceneSynchronized = true
    SaveTeamState()
end
''',
        '''local function ClearTeamState()
    teamMarks = {}
    incomingSnapshot = nil
    sceneSynchronized = false
    pendingSceneApply = true
    SaveTeamState()
end
''',
        "queue received clear",
    )

    source = replace_once(
        source,
        '''local function ApplyMarksToScene(marks)
    if not worldReadyForMarkers or not HasDLL() then
        pendingSceneApply = true
        return false
    end
    pcall(UnitXP, "MoonMarker.Clear")
    for _, info in ipairs(colors) do
        local mark = marks[info.key]
        if mark then
            pcall(UnitXP, "MoonMarker.Remote", info.key,
                mark.x, mark.y, mark.z, mark.marker)
        end
    end
    sceneSynchronized = true
    pendingSceneApply = false
    return true
end
''',
        '''local function ApplyMarksToScene(marks)
    if not worldReadyForMarkers or not HasDLL() then
        pendingSceneApply = true
        return false
    end

    local called, cleared = pcall(UnitXP, "MoonMarker.Clear")
    if not called or cleared == false then
        pendingSceneApply = true
        sceneSynchronized = false
        return false
    end

    for _, info in ipairs(colors) do
        local mark = marks[info.key]
        if mark then
            local remoteCalled, remoteOk = pcall(UnitXP, "MoonMarker.Remote", info.key,
                mark.x, mark.y, mark.z, mark.marker)
            if not remoteCalled or remoteOk == false then
                pendingSceneApply = true
                sceneSynchronized = false
                return false
            end
        end
    end

    sceneSynchronized = true
    pendingSceneApply = false
    sceneApplyElapsed = 0
    return true
end
''',
        "checked deferred scene apply",
    )

    source = replace_once(
        source,
        '''local function ApplySnapshot(marks)
    local normalized = CopyMarks(marks)
    local changed = not MarksEqual(teamMarks, normalized)
    teamMarks = normalized
    if changed or not sceneSynchronized then ApplyMarksToScene(teamMarks) end
    SaveTeamState()
end
''',
        '''local function ApplySnapshot(marks)
    local normalized = CopyMarks(marks)
    local changed = not MarksEqual(teamMarks, normalized)
    teamMarks = normalized
    if changed or not sceneSynchronized then
        sceneSynchronized = false
        pendingSceneApply = true
    end
    SaveTeamState()
end
''',
        "defer received snapshot",
    )

    source = replace_once(
        source,
        '''    if message == "CLEAR" then
        pcall(UnitXP, "MoonMarker.Clear")
        ClearTeamState()
        return
    end
''',
        '''    if message == "CLEAR" then
        ClearTeamState()
        return
    end
''',
        "do not clear from addon event",
    )

    source = replace_once(
        source,
        '''    if color and marker and x and y and z then
        local nx, ny, nz = tonumber(x), tonumber(y), tonumber(z)
        pcall(UnitXP, "MoonMarker.Remote", color, nx, ny, nz, marker)
        SetTeamMark(color, marker, nx, ny, nz)
        return
    end
''',
        '''    if color and marker and x and y and z then
        local nx, ny, nz = tonumber(x), tonumber(y), tonumber(z)
        SetTeamMark(color, marker, nx, ny, nz)
        return
    end
''',
        "do not place from addon event",
    )

    source = replace_once(
        source,
        '''    if oldColor and oldX and oldY and oldZ then
        pcall(UnitXP, "MoonMarker.Remote", oldColor,
            tonumber(oldX), tonumber(oldY), tonumber(oldZ))
    end
''',
        '''    if oldColor and oldX and oldY and oldZ then
        SetTeamMark(oldColor, "star",
            tonumber(oldX), tonumber(oldY), tonumber(oldZ))
    end
''',
        "defer legacy placement",
    )

    source = replace_once(
        source,
        '''    if worldReadyForMarkers and GroupChannel() and IsStateAuthority() then
''',
        '''    if worldReadyForMarkers and pendingSceneApply then
        sceneApplyElapsed = sceneApplyElapsed + elapsed
        if sceneApplyElapsed >= 0.20 then
            sceneApplyElapsed = 0
            ApplyMarksToScene(teamMarks)
        end
    else
        sceneApplyElapsed = 0
    end

    if worldReadyForMarkers and GroupChannel() and IsStateAuthority() then
''',
        "scene apply retry loop",
    )

    required = (
        "local sceneApplyElapsed = 0",
        "cleared == false",
        "remoteOk == false",
        "if worldReadyForMarkers and pendingSceneApply then",
        "SetTeamMark(oldColor, \"star\"",
    )
    for token in required:
        if token not in source:
            raise RuntimeError("missing deferred scene token: " + token)

    if 'pcall(UnitXP, "MoonMarker.Remote", color, nx, ny, nz, marker)' in source:
        raise RuntimeError("direct addon-event Remote call remains")

    path.write_text(source, encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--addon", required=True)
    args = parser.parse_args()
    install(Path(args.addon) / "MoonMarker")


if __name__ == "__main__":
    main()
