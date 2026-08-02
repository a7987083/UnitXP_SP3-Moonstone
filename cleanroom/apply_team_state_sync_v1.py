#!/usr/bin/env python3
"""Add authoritative ordinary-marker snapshots and relog recovery to MoonMarker.lua."""

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
        '''local function Broadcast(payload)
    local channel = GroupChannel()
    if channel and CanBroadcast() then SendAddonMessage(PREFIX, payload, channel) end
end

local function SaveSelection()
''',
        r'''local function SenderInGroup(sender)
    if not sender then return false end
    if SameName(sender, UnitName("player")) then return true end
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local name = GetRaidRosterInfo(i)
            if SameName(sender, name) then return true end
        end
        return false
    end
    if GetNumPartyMembers and GetNumPartyMembers() > 0 then
        for i = 1, GetNumPartyMembers() do
            if SameName(sender, UnitName("party" .. i)) then return true end
        end
    end
    return false
end

local function CurrentStateAuthorityName()
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        local assistants = {}
        for i = 1, GetNumRaidMembers() do
            local name, rank, _, _, _, _, _, online = GetRaidRosterInfo(i)
            if name and online then
                if (rank or 0) >= 2 then return name end
                if (rank or 0) == 1 then table.insert(assistants, name) end
            end
        end
        table.sort(assistants)
        return assistants[1]
    end

    if GetNumPartyMembers and GetNumPartyMembers() > 0 then
        local leaderIndex = GetPartyLeaderIndex and GetPartyLeaderIndex() or -1
        if leaderIndex == 0 then return UnitName("player") end
        if leaderIndex and leaderIndex > 0 then return UnitName("party" .. leaderIndex) end
        if IsPartyLeader("player") == 1 then return UnitName("player") end
        for i = 1, GetNumPartyMembers() do
            local unit = "party" .. i
            if IsPartyLeader(unit) == 1 then return UnitName(unit) end
        end
    end
    return nil
end

local function IsStateAuthority()
    local authority = CurrentStateAuthorityName()
    return authority and SameName(authority, UnitName("player"))
end

local function SenderIsStateAuthority(sender)
    local authority = CurrentStateAuthorityName()
    return authority and SameName(authority, sender)
end

local function SendGroupMessage(payload, requireControl)
    local channel = GroupChannel()
    if not channel then return false end
    if requireControl and not CanBroadcast() then return false end
    SendAddonMessage(PREFIX, payload, channel)
    return true
end

local function Broadcast(payload)
    return SendGroupMessage(payload, true)
end

local TEAM_SYNC_INTERVAL = 5.0
local TEAM_STATE_MAX_AGE = 600
local teamMarks = {}
local incomingSnapshot = nil
local syncEpoch = 0
local heartbeatElapsed = 0
local pendingSyncDelay = nil
local pendingRestore = false
local sceneSynchronized = false

local function IsFiniteCoordinate(value)
    value = tonumber(value)
    return value and value == value and math.abs(value) <= 1000000
end

local function CopyMarks(source)
    local result = {}
    for color, mark in pairs(source or {}) do
        if colorByKey[color] and type(mark) == "table" and markerByKey[mark.marker]
            and IsFiniteCoordinate(mark.x) and IsFiniteCoordinate(mark.y)
            and IsFiniteCoordinate(mark.z) then
            result[color] = {
                marker = mark.marker,
                x = tonumber(mark.x), y = tonumber(mark.y), z = tonumber(mark.z),
            }
        end
    end
    return result
end

local function CountMarks(source)
    local count = 0
    for _ in pairs(source or {}) do count = count + 1 end
    return count
end

local function MarksEqual(left, right)
    if CountMarks(left) ~= CountMarks(right) then return false end
    for color, a in pairs(left or {}) do
        local b = right and right[color]
        if not b or a.marker ~= b.marker
            or math.abs((a.x or 0) - (b.x or 0)) > 0.0001
            or math.abs((a.y or 0) - (b.y or 0)) > 0.0001
            or math.abs((a.z or 0) - (b.z or 0)) > 0.0001 then
            return false
        end
    end
    return true
end

local function GroupSignature()
    local names = {}
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local name = GetRaidRosterInfo(i)
            name = NormalizeName(name)
            if name ~= "" then table.insert(names, name) end
        end
    elseif GetNumPartyMembers and GetNumPartyMembers() > 0 then
        local player = NormalizeName(UnitName("player"))
        if player ~= "" then table.insert(names, player) end
        for i = 1, GetNumPartyMembers() do
            local name = NormalizeName(UnitName("party" .. i))
            if name ~= "" then table.insert(names, name) end
        end
    end
    table.sort(names)
    return table.concat(names, ",")
end

local function CurrentZoneKey()
    local zone = GetRealZoneText and GetRealZoneText() or ""
    return string.lower(tostring(zone or ""))
end

local function SaveTeamState()
    local signature = GroupSignature()
    if signature == "" then return end
    MoonMarkerDB.teamState = {
        signature = signature,
        zone = CurrentZoneKey(),
        savedAt = time and time() or 0,
        marks = CopyMarks(teamMarks),
    }
end

local function RestoreSavedTeamState()
    local saved = MoonMarkerDB.teamState
    if type(saved) ~= "table" or type(saved.marks) ~= "table" then return false end
    local signature = GroupSignature()
    if signature == "" or saved.signature ~= signature then return false end
    if tostring(saved.zone or "") ~= CurrentZoneKey() then return false end
    local now = time and time() or 0
    local savedAt = tonumber(saved.savedAt) or 0
    if now > 0 and savedAt > 0 and now - savedAt > TEAM_STATE_MAX_AGE then return false end
    teamMarks = CopyMarks(saved.marks)
    return true
end

local function SetTeamMark(color, marker, x, y, z)
    if not colorByKey[color] or not markerByKey[marker]
        or not IsFiniteCoordinate(x) or not IsFiniteCoordinate(y)
        or not IsFiniteCoordinate(z) then return end
    teamMarks[color] = {
        marker = marker, x = tonumber(x), y = tonumber(y), z = tonumber(z),
    }
    sceneSynchronized = true
    SaveTeamState()
end

local function ClearTeamState()
    teamMarks = {}
    incomingSnapshot = nil
    sceneSynchronized = true
    SaveTeamState()
end

local function ApplyMarksToScene(marks)
    if not HasDLL() then return false end
    pcall(UnitXP, "MoonMarker.Clear")
    for _, info in ipairs(colors) do
        local mark = marks[info.key]
        if mark then
            pcall(UnitXP, "MoonMarker.Remote", info.key,
                mark.x, mark.y, mark.z, mark.marker)
        end
    end
    sceneSynchronized = true
    return true
end

local function ApplySnapshot(marks)
    local normalized = CopyMarks(marks)
    local changed = not MarksEqual(teamMarks, normalized)
    teamMarks = normalized
    if changed or not sceneSynchronized then ApplyMarksToScene(teamMarks) end
    SaveTeamState()
end

local function BroadcastSnapshot()
    if not IsStateAuthority() then return false end
    syncEpoch = syncEpoch + 1
    if syncEpoch > 999999999 then syncEpoch = 1 end
    local epoch = tostring(syncEpoch)
    Broadcast(string.format("SYNCBEGIN %s %d", epoch, CountMarks(teamMarks)))
    for _, info in ipairs(colors) do
        local mark = teamMarks[info.key]
        if mark then
            Broadcast(string.format("SYNC %s %s %s %.5f %.5f %.5f",
                epoch, info.key, mark.marker, mark.x, mark.y, mark.z))
        end
    end
    Broadcast("SYNCEND " .. epoch)
    return true
end

local function RequestSnapshot()
    if not GroupChannel() then return false end
    return SendGroupMessage("SYNCREQ", false)
end

local function ScheduleTeamSync(delay, restore)
    pendingSyncDelay = tonumber(delay) or 0.8
    pendingRestore = pendingRestore or (restore and true or false)
end

local function SaveSelection()
''',
        "team state helpers",
    )

    source = replace_once(
        source,
        '''    SelectColor(color, false)
    SelectMarker(marker, false)
    Broadcast(string.format("PLACE %s %s %.5f %.5f %.5f",
        color, marker, x, y, z))
''',
        '''    SelectColor(color, false)
    SelectMarker(marker, false)
    SetTeamMark(color, marker, x, y, z)
    Broadcast(string.format("PLACE %s %s %.5f %.5f %.5f",
        color, marker, x, y, z))
''',
        "cache local placement",
    )

    source = replace_once(
        source,
        '''    if HasDLL() then pcall(UnitXP, "MoonMarker.Clear") end
    if send then Broadcast("CLEAR") end
''',
        '''    if HasDLL() then pcall(UnitXP, "MoonMarker.Clear") end
    ClearTeamState()
    if send then Broadcast("CLEAR") end
''',
        "cache local clear",
    )

    source = replace_once(
        source,
        '''eventFrame:RegisterEvent("VARIABLES_LOADED")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:SetScript("OnEvent", function()
''',
        '''eventFrame:RegisterEvent("VARIABLES_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:SetScript("OnEvent", function()
''',
        "register state sync events",
    )

    source = replace_once(
        source,
        '''        Print("已加载。可在按键设置的“" .. ADDON_TITLE .. "”分类中自定义按键")
        return
    end

    if event == "CHAT_MSG_ADDON" then
''',
        '''        Print("已加载。可在按键设置的“" .. ADDON_TITLE .. "”分类中自定义按键")
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        teamMarks = {}
        sceneSynchronized = false
        incomingSnapshot = nil
        heartbeatElapsed = 0
        if HasDLL() then pcall(UnitXP, "MoonMarker.Clear") end
        ScheduleTeamSync(1.2, true)
        return
    end

    if event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
        ScheduleTeamSync(0.8, false)
        heartbeatElapsed = TEAM_SYNC_INTERVAL
        return
    end

    if event == "PLAYER_LOGOUT" then
        SaveTeamState()
        return
    end

    if event == "CHAT_MSG_ADDON" then
''',
        "state sync event branches",
    )

    source = replace_once(
        source,
        '''        local playerName = UnitName("player")
        if sender and playerName and SameName(sender, playerName) then return end

        if not SenderCanControl(sender) then
''',
        r'''        local playerName = UnitName("player")
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
''',
        "handle state sync messages",
    )

    source = replace_once(
        source,
        '''        if message == "CLEAR" then
            pcall(UnitXP, "MoonMarker.Clear")
            return
        end
''',
        '''        if message == "CLEAR" then
            pcall(UnitXP, "MoonMarker.Clear")
            ClearTeamState()
            return
        end
''',
        "cache remote clear",
    )

    source = replace_once(
        source,
        '''        if color and marker and x and y and z then
            pcall(UnitXP, "MoonMarker.Remote", color, tonumber(x), tonumber(y), tonumber(z), marker)
            return
        end
''',
        '''        if color and marker and x and y and z then
            local nx, ny, nz = tonumber(x), tonumber(y), tonumber(z)
            pcall(UnitXP, "MoonMarker.Remote", color, nx, ny, nz, marker)
            SetTeamMark(color, marker, nx, ny, nz)
            return
        end
''',
        "cache remote placement",
    )

    source = replace_once(
        source,
        '''    end
end)

SLASH_MOONMARKER1 = "/moonmarker"
''',
        r'''    end
end)

eventFrame:SetScript("OnUpdate", function()
    local elapsed = arg1 or 0

    if pendingSyncDelay then
        pendingSyncDelay = pendingSyncDelay - elapsed
        if pendingSyncDelay <= 0 then
            local restore = pendingRestore
            pendingSyncDelay = nil
            pendingRestore = false

            if not GroupChannel() then
                teamMarks = {}
                incomingSnapshot = nil
                sceneSynchronized = true
            else
                if restore then
                    if RestoreSavedTeamState() then
                        ApplyMarksToScene(teamMarks)
                    else
                        teamMarks = {}
                        sceneSynchronized = false
                    end
                end
                if IsStateAuthority() then BroadcastSnapshot() else RequestSnapshot() end
            end
        end
    end

    if GroupChannel() and IsStateAuthority() then
        heartbeatElapsed = heartbeatElapsed + elapsed
        if heartbeatElapsed >= TEAM_SYNC_INTERVAL then
            heartbeatElapsed = 0
            BroadcastSnapshot()
        end
    else
        heartbeatElapsed = 0
    end
end)

SLASH_MOONMARKER1 = "/moonmarker"
''',
        "state sync OnUpdate",
    )

    source = replace_once(
        source,
        '''SLASH_MOONMARKERSTATUS1 = "/mmstatus"
''',
        '''SLASH_MOONMARKERSYNC1 = "/mmsync"
SlashCmdList["MOONMARKERSYNC"] = function()
    if not GroupChannel() then
        Print("当前不在小队或团队中")
    elseif IsStateAuthority() then
        BroadcastSnapshot()
        Print("已广播当前团队光柱状态")
    else
        RequestSnapshot()
        Print("已请求当前团队光柱状态")
    end
end

SLASH_MOONMARKERSTATUS1 = "/mmstatus"
''',
        "manual sync command",
    )

    for token in (
        'TEAM_SYNC_INTERVAL = 5.0',
        'eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")',
        'message == "SYNCREQ"',
        '^SYNCBEGIN%s+',
        'BroadcastSnapshot()',
        'RestoreSavedTeamState()',
        'SetTeamMark(color, marker, x, y, z)',
        'SLASH_MOONMARKERSYNC1 = "/mmsync"',
    ):
        if token not in source:
            raise RuntimeError("missing team sync token: " + token)

    path.write_text(source, encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--addon-root", required=True)
    args = parser.parse_args()
    install(Path(args.addon_root))


if __name__ == "__main__":
    main()
