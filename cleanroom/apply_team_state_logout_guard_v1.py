#!/usr/bin/env python3
"""Prevent ordinary team-state resync from touching M2 during world teardown."""

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
        '''local pendingRestore = false
local sceneSynchronized = false
''',
        '''local pendingRestore = false
local sceneSynchronized = false
local worldReadyForMarkers = false
local pendingSceneApply = false
''',
        "team sync world state",
    )

    source = replace_once(
        source,
        '''local function ApplyMarksToScene(marks)
    if not HasDLL() then return false end
    pcall(UnitXP, "MoonMarker.Clear")
''',
        '''local function ApplyMarksToScene(marks)
    if not worldReadyForMarkers or not HasDLL() then
        pendingSceneApply = true
        return false
    end
    pcall(UnitXP, "MoonMarker.Clear")
''',
        "scene apply lifecycle guard",
    )

    source = replace_once(
        source,
        '''    sceneSynchronized = true
    return true
end

local function ApplySnapshot(marks)
''',
        '''    sceneSynchronized = true
    pendingSceneApply = false
    return true
end

local function ApplySnapshot(marks)
''',
        "scene apply completion",
    )

    source = replace_once(
        source,
        '''eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
''',
        '''eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
''',
        "register world leaving event",
    )

    source = replace_once(
        source,
        '''    if event == "PLAYER_ENTERING_WORLD" then
        teamMarks = {}
        sceneSynchronized = false
        incomingSnapshot = nil
        heartbeatElapsed = 0
        if HasDLL() then pcall(UnitXP, "MoonMarker.Clear") end
        ScheduleTeamSync(1.2, true)
        return
    end

    if event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
''',
        '''    if event == "PLAYER_ENTERING_WORLD" then
        worldReadyForMarkers = false
        pendingSceneApply = true
        teamMarks = {}
        sceneSynchronized = false
        incomingSnapshot = nil
        heartbeatElapsed = 0
        ScheduleTeamSync(2.0, true)
        return
    end

    if event == "PLAYER_LEAVING_WORLD" then
        worldReadyForMarkers = false
        pendingSceneApply = false
        pendingSyncDelay = nil
        pendingRestore = false
        heartbeatElapsed = 0
        incomingSnapshot = nil
        SaveTeamState()
        return
    end

    if event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
''',
        "world lifecycle event branches",
    )

    source = replace_once(
        source,
        '''    if event == "PLAYER_LOGOUT" then
        SaveTeamState()
        return
    end
''',
        '''    if event == "PLAYER_LOGOUT" then
        worldReadyForMarkers = false
        pendingSceneApply = false
        pendingSyncDelay = nil
        pendingRestore = false
        heartbeatElapsed = 0
        incomingSnapshot = nil
        SaveTeamState()
        return
    end
''',
        "logout synchronization stop",
    )

    source = replace_once(
        source,
        '''        local prefix, message, channel, sender = arg1, arg2, arg3, arg4
        if prefix ~= PREFIX or not HasDLL() then return end
''',
        '''        local prefix, message, channel, sender = arg1, arg2, arg3, arg4
        if prefix ~= PREFIX or not HasDLL() or not worldReadyForMarkers then return end
''',
        "ignore addon messages outside world",
    )

    source = replace_once(
        source,
        '''eventFrame:SetScript("OnUpdate", function()
    local elapsed = arg1 or 0

    if pendingSyncDelay then
''',
        '''eventFrame:SetScript("OnUpdate", function()
    local elapsed = arg1 or 0

    if not worldReadyForMarkers and not pendingSyncDelay then return end

    if pendingSyncDelay then
''',
        "disable update during world teardown",
    )

    source = replace_once(
        source,
        '''            local restore = pendingRestore
            pendingSyncDelay = nil
            pendingRestore = false

            if not GroupChannel() then
''',
        '''            local restore = pendingRestore
            pendingSyncDelay = nil
            pendingRestore = false
            worldReadyForMarkers = true

            if not GroupChannel() then
''',
        "enable scene after entering delay",
    )

    source = replace_once(
        source,
        '''    if GroupChannel() and IsStateAuthority() then
''',
        '''    if worldReadyForMarkers and GroupChannel() and IsStateAuthority() then
''',
        "heartbeat world guard",
    )

    required = (
        'eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")',
        'if not worldReadyForMarkers or not HasDLL() then',
        'if prefix ~= PREFIX or not HasDLL() or not worldReadyForMarkers then return end',
        'if not worldReadyForMarkers and not pendingSyncDelay then return end',
        'worldReadyForMarkers = true',
        'if worldReadyForMarkers and GroupChannel() and IsStateAuthority() then',
    )
    for token in required:
        if token not in source:
            raise RuntimeError("missing logout sync guard token: " + token)

    path.write_text(source, encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--addon", required=True)
    args = parser.parse_args()
    install(Path(args.addon) / "MoonMarker")


if __name__ == "__main__":
    main()
