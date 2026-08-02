#!/usr/bin/env python3
"""Avoid replaying locally applied markers through the deferred team-state queue."""

from __future__ import annotations

import argparse
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str, count: int = 1) -> str:
    actual = text.count(old)
    if actual != count:
        raise RuntimeError(f"{label}: expected {count} matches, found {actual}")
    return text.replace(old, new, count)


def install(addon_root: Path) -> None:
    path = addon_root / "MoonMarker.lua"
    source = path.read_text(encoding="utf-8")

    source = replace_once(
        source,
        '''local pendingSceneApply = false
local sceneApplyElapsed = 0
''',
        '''local pendingSceneApply = false
local sceneApplyElapsed = 0
local pendingSceneFull = false
local pendingSceneClear = false
local pendingSceneColors = {}
''',
        "pending scene state",
    )

    source = replace_once(
        source,
        '''local function SetTeamMark(color, marker, x, y, z)
    if not colorByKey[color] or not markerByKey[marker]
        or not IsFiniteCoordinate(x) or not IsFiniteCoordinate(y)
        or not IsFiniteCoordinate(z) then return end
    teamMarks[color] = {
        marker = marker, x = tonumber(x), y = tonumber(y), z = tonumber(z),
    }
    sceneSynchronized = false
    pendingSceneApply = true
    SaveTeamState()
end

local function ClearTeamState()
    teamMarks = {}
    incomingSnapshot = nil
    sceneSynchronized = false
    pendingSceneApply = true
    SaveTeamState()
end
''',
        '''local function SetTeamMark(color, marker, x, y, z, sceneAlreadyApplied)
    if not colorByKey[color] or not markerByKey[marker]
        or not IsFiniteCoordinate(x) or not IsFiniteCoordinate(y)
        or not IsFiniteCoordinate(z) then return end
    teamMarks[color] = {
        marker = marker, x = tonumber(x), y = tonumber(y), z = tonumber(z),
    }

    if sceneAlreadyApplied then
        pendingSceneColors[color] = nil
        if not pendingSceneFull and not pendingSceneClear
            and next(pendingSceneColors) == nil then
            pendingSceneApply = false
            sceneSynchronized = true
        end
    else
        pendingSceneColors[color] = true
        pendingSceneApply = true
        sceneSynchronized = false
    end
    SaveTeamState()
end

local function ClearTeamState(sceneAlreadyApplied)
    teamMarks = {}
    incomingSnapshot = nil
    pendingSceneColors = {}
    pendingSceneFull = false

    if sceneAlreadyApplied then
        pendingSceneClear = false
        pendingSceneApply = false
        sceneSynchronized = true
    else
        pendingSceneClear = true
        pendingSceneApply = true
        sceneSynchronized = false
    end
    SaveTeamState()
end
''',
        "local and remote cache semantics",
    )

    source = replace_once(
        source,
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
        '''local function ApplySnapshot(marks)
    local normalized = CopyMarks(marks)
    local changed = not MarksEqual(teamMarks, normalized)
    teamMarks = normalized
    if changed or not sceneSynchronized then
        pendingSceneColors = {}
        pendingSceneClear = false
        pendingSceneFull = true
        sceneSynchronized = false
        pendingSceneApply = true
    end
    SaveTeamState()
end

local function ApplyPendingSceneChanges()
    if pendingSceneClear then
        local called, cleared = pcall(UnitXP, "MoonMarker.Clear")
        if not called or cleared == false then return false end
        pendingSceneClear = false
        pendingSceneFull = false
        pendingSceneColors = {}
        pendingSceneApply = false
        sceneSynchronized = true
        sceneApplyElapsed = 0
        return true
    end

    if pendingSceneFull then
        local ok = ApplyMarksToScene(teamMarks)
        if ok then
            pendingSceneFull = false
            pendingSceneColors = {}
        end
        return ok
    end

    for color in pairs(pendingSceneColors) do
        local mark = teamMarks[color]
        if mark then
            local called, placed = pcall(UnitXP, "MoonMarker.Remote", color,
                mark.x, mark.y, mark.z, mark.marker)
            if not called or placed == false then return false end
        end
        pendingSceneColors[color] = nil
    end

    pendingSceneApply = false
    sceneSynchronized = true
    sceneApplyElapsed = 0
    return true
end
''',
        "incremental deferred application",
    )

    source = replace_once(
        source,
        '''    SetTeamMark(color, marker, x, y, z)
    Broadcast(string.format("PLACE %s %s %.5f %.5f %.5f",
''',
        '''    SetTeamMark(color, marker, x, y, z, true)
    Broadcast(string.format("PLACE %s %s %.5f %.5f %.5f",
''',
        "local placement is already applied",
    )

    source = replace_once(
        source,
        '''    if HasDLL() then pcall(UnitXP, "MoonMarker.Clear") end
    ClearTeamState()
''',
        '''    if HasDLL() then pcall(UnitXP, "MoonMarker.Clear") end
    ClearTeamState(true)
''',
        "local clear is already applied",
    )

    source = replace_once(
        source,
        '''        pendingSceneApply = false
        pendingSyncDelay = nil
''',
        '''        pendingSceneApply = false
        pendingSceneFull = false
        pendingSceneClear = false
        pendingSceneColors = {}
        pendingSyncDelay = nil
''',
        "clear pending work on world exit",
        count=2,
    )

    source = replace_once(
        source,
        '''            ApplyMarksToScene(teamMarks)
        end
''',
        '''            ApplyPendingSceneChanges()
        end
''',
        "run incremental deferred work",
    )

    required = (
        "SetTeamMark(color, marker, x, y, z, true)",
        "ClearTeamState(true)",
        "local function ApplyPendingSceneChanges()",
        "local pendingSceneColors = {}",
        "ApplyPendingSceneChanges()",
    )
    for token in required:
        if token not in source:
            raise RuntimeError("missing local scene fix token: " + token)

    path.write_text(source, encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--addon", required=True)
    args = parser.parse_args()
    install(Path(args.addon) / "MoonMarker")


if __name__ == "__main__":
    main()
