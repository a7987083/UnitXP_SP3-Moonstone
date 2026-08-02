#!/usr/bin/env python3
"""Split MoonMarker event handling to stay below WoW 1.12's 32-upvalue limit."""

from __future__ import annotations

import argparse
from pathlib import Path


EVENT_START = 'eventFrame:SetScript("OnEvent", function()\n'
EVENT_END = '\n\neventFrame:SetScript("OnUpdate", function()'


SPLIT_EVENT_HANDLER = r'''local function MoonMarkerHandleVariablesLoaded()
    if MoonMarkerDB.point then
        frame:ClearAllPoints()
        frame:SetPoint(MoonMarkerDB.point, UIParent,
            MoonMarkerDB.relativePoint or MoonMarkerDB.point,
            MoonMarkerDB.x or 0, MoonMarkerDB.y or 0)
    end
    selectedColor = MoonMarkerDB.selectedColor or selectedColor
    selectedMarker = MoonMarkerDB.selectedMarker or selectedMarker
    if not colorByKey[selectedColor] then selectedColor = "white" end
    if not markerByKey[selectedMarker] then selectedMarker = "skull" end
    SaveSelection()
    RefreshSelection()
    if MoonMarkerDB.hidden then frame:Hide() end
    Print("已加载。可在按键设置的“" .. ADDON_TITLE .. "”分类中自定义按键")
end

local function MoonMarkerHandleWorldEvent(currentEvent)
    if currentEvent == "PLAYER_ENTERING_WORLD" then
        worldReadyForMarkers = false
        pendingSceneApply = true
        teamMarks = {}
        sceneSynchronized = false
        incomingSnapshot = nil
        heartbeatElapsed = 0
        ScheduleTeamSync(2.0, true)
        return true
    end

    if currentEvent == "PLAYER_LEAVING_WORLD" then
        worldReadyForMarkers = false
        pendingSceneApply = false
        pendingSyncDelay = nil
        pendingRestore = false
        heartbeatElapsed = 0
        incomingSnapshot = nil
        SaveTeamState()
        return true
    end

    if currentEvent == "RAID_ROSTER_UPDATE" or currentEvent == "PARTY_MEMBERS_CHANGED" then
        ScheduleTeamSync(0.8, false)
        heartbeatElapsed = TEAM_SYNC_INTERVAL
        return true
    end

    if currentEvent == "PLAYER_LOGOUT" then
        worldReadyForMarkers = false
        pendingSceneApply = false
        pendingSyncDelay = nil
        pendingRestore = false
        heartbeatElapsed = 0
        incomingSnapshot = nil
        SaveTeamState()
        return true
    end

    return false
end

local function MoonMarkerHandleAddonMessage(prefix, message, channel, sender)
    if prefix ~= PREFIX or not HasDLL() or not worldReadyForMarkers then return end
    local playerName = UnitName("player")
    if sender and playerName and SameName(sender, playerName) then return end

    if message == "SYNCREQ" then
        if SenderInGroup(sender) and IsStateAuthority() then BroadcastSnapshot() end
        return
    end

    local _, _, beginEpoch, beginCount = string.find(message or "",
        "^SYNCBEGIN%s+(%d+)%s+(%d+)$")
    if beginEpoch and beginCount then
        if not SenderIsStateAuthority(sender) then return end
        local count = tonumber(beginCount) or -1
        if count < 0 or count > table.getn(colors) then return end
        incomingSnapshot = { epoch = beginEpoch, expected = count, marks = {} }
        return
    end

    local _, _, stateEpoch, stateColor, stateMarker, sx, sy, sz = string.find(message or "",
        "^SYNC%s+(%d+)%s+(%S+)%s+(%S+)%s+([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)$")
    if stateEpoch and incomingSnapshot and incomingSnapshot.epoch == stateEpoch then
        if not SenderIsStateAuthority(sender) then return end
        if colorByKey[stateColor] and markerByKey[stateMarker]
            and CountMarks(incomingSnapshot.marks) < table.getn(colors)
            and IsFiniteCoordinate(sx) and IsFiniteCoordinate(sy)
            and IsFiniteCoordinate(sz) then
            incomingSnapshot.marks[stateColor] = {
                marker = stateMarker,
                x = tonumber(sx), y = tonumber(sy), z = tonumber(sz),
            }
        end
        return
    end

    local _, _, endEpoch = string.find(message or "", "^SYNCEND%s+(%d+)$")
    if endEpoch and incomingSnapshot and incomingSnapshot.epoch == endEpoch then
        if not SenderIsStateAuthority(sender) then return end
        local snapshot = incomingSnapshot
        incomingSnapshot = nil
        if CountMarks(snapshot.marks) == snapshot.expected then
            ApplySnapshot(snapshot.marks)
        end
        return
    end

    if not SenderCanControl(sender) then
        if message == "CLEAR" or string.find(message or "", "^PLACE%s+") then
            Print("已忽略无权限成员 " .. tostring(sender) .. " 的团队光柱操作")
        end
        return
    end

    if message == "CLEAR" then
        pcall(UnitXP, "MoonMarker.Clear")
        ClearTeamState()
        return
    end

    local _, _, color, marker, x, y, z = string.find(message or "",
        "^PLACE%s+(%S+)%s+(%S+)%s+([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)$")
    if color and marker and x and y and z then
        local nx, ny, nz = tonumber(x), tonumber(y), tonumber(z)
        pcall(UnitXP, "MoonMarker.Remote", color, nx, ny, nz, marker)
        SetTeamMark(color, marker, nx, ny, nz)
        return
    end

    -- Backward compatibility with Native White Team Sync v1 messages.
    local _, _, oldColor, oldX, oldY, oldZ = string.find(message or "",
        "^PLACE%s+(%S+)%s+([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)$")
    if oldColor and oldX and oldY and oldZ then
        pcall(UnitXP, "MoonMarker.Remote", oldColor,
            tonumber(oldX), tonumber(oldY), tonumber(oldZ))
    end
end

eventFrame:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        MoonMarkerHandleVariablesLoaded()
        return
    end
    if MoonMarkerHandleWorldEvent(event) then return end
    if event == "CHAT_MSG_ADDON" then
        MoonMarkerHandleAddonMessage(arg1, arg2, arg3, arg4)
    end
end)'''


def install(addon_root: Path) -> None:
    path = addon_root / "MoonMarker.lua"
    source = path.read_text(encoding="utf-8")

    if "local function MoonMarkerHandleAddonMessage" in source:
        raise RuntimeError("MoonMarker event handlers are already split")

    start = source.find(EVENT_START)
    if start < 0:
        raise RuntimeError("MoonMarker OnEvent start not found")
    end = source.find(EVENT_END, start)
    if end < 0:
        raise RuntimeError("MoonMarker OnEvent end not found")

    old = source[start:end]
    required_old = (
        'if event == "VARIABLES_LOADED" then',
        'if event == "PLAYER_LEAVING_WORLD" then',
        'if event == "CHAT_MSG_ADDON" then',
        'ClearTeamState()',
        'ApplySnapshot(snapshot.marks)',
    )
    for token in required_old:
        if token not in old:
            raise RuntimeError("unexpected OnEvent layout; missing: " + token)

    source = source[:start] + SPLIT_EVENT_HANDLER + source[end:]

    required_new = (
        "local function MoonMarkerHandleVariablesLoaded()",
        "local function MoonMarkerHandleWorldEvent(currentEvent)",
        "local function MoonMarkerHandleAddonMessage(prefix, message, channel, sender)",
        "MoonMarkerHandleWorldEvent(event)",
        "MoonMarkerHandleAddonMessage(arg1, arg2, arg3, arg4)",
    )
    for token in required_new:
        if token not in source:
            raise RuntimeError("missing upvalue-fix token: " + token)

    path.write_text(source, encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--addon", required=True)
    args = parser.parse_args()
    install(Path(args.addon) / "MoonMarker")


if __name__ == "__main__":
    main()
