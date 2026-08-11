#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else 'upstream')

h = r'''#pragma once

namespace addonProfiler {
    int handleLua(void* L);
    void onFrameBoundary();
}
'''

cpp = r'''#include "addonProfiler.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <deque>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#include <Windows.h>

#include "LuaDebug.h"
#include "Vanilla1121_functions.h"

namespace addonProfiler {
namespace {

constexpr const char* kVersion = "AddonProfiler B1";
constexpr std::size_t kMaxLongFrames = 64;
constexpr std::size_t kMaxFunctions = 4096;
constexpr double kDefaultLongFrameMs = 50.0;

enum class ContextKind : std::uint8_t {
    Other = 0,
    OnUpdate = 1,
    OnEvent = 2,
};

struct Aggregate {
    std::uint64_t totalTicks = 0;
    std::uint64_t totalCalls = 0;
    std::uint64_t windowTicks = 0;
    std::uint64_t windowCalls = 0;
    std::uint64_t lastTicks = 0;
    std::uint64_t lastCalls = 0;

    std::uint64_t currentFrameTicks = 0;
    std::uint64_t windowPeakFrameTicks = 0;
    std::uint64_t lastPeakFrameTicks = 0;
    std::vector<std::uint64_t> windowActiveFrameSamples{};
    std::vector<std::uint64_t> lastActiveFrameSamples{};

    std::uint64_t eventWindowTicks = 0;
    std::uint64_t updateWindowTicks = 0;
    std::uint64_t otherWindowTicks = 0;
    std::uint64_t eventLastTicks = 0;
    std::uint64_t updateLastTicks = 0;
    std::uint64_t otherLastTicks = 0;

    std::uint64_t eventWindowCalls = 0;
    std::uint64_t updateWindowCalls = 0;
    std::uint64_t otherWindowCalls = 0;
    std::uint64_t eventLastCalls = 0;
    std::uint64_t updateLastCalls = 0;
    std::uint64_t otherLastCalls = 0;
};

struct CallFrame {
    LARGE_INTEGER started{};
    std::uint64_t hookTicksAtStart = 0;
    std::uint64_t childAdjustedTicks = 0;
    std::string addon{};
    std::string file{};
    std::string function{};
    std::string what{};
    int lineDefined = -1;
    ContextKind context = ContextKind::Other;
    bool attributed = false;
    bool profilerApi = false;
};

struct LongFrame {
    std::string time{};
    double frameMs = 0.0;
    double luaMs = 0.0;
    std::string addon{};
    std::string file{};
};

struct SourceIdentity {
    std::string addon{};
    std::string file{};
    bool attributed = false;
    bool system = false;
};

static bool gRunning = false;
static bool gDeep = false;
static bool gSuppressHook = false;
static void* gLuaState = nullptr;
static LARGE_INTEGER gFrequency{};
static LARGE_INTEGER gLastFrameBoundary{};
static LARGE_INTEGER gWindowStarted{};
static LARGE_INTEGER gMemorySampleTime{};
static LARGE_INTEGER gLastGcTime{};
static double gLastLuaMemoryKb = -1.0;
static double gLuaMemoryKb = -1.0;
static double gAllocRateKbSec = 0.0;
static std::uint64_t gGcDetectedCount = 0;
static double gLongFrameMs = kDefaultLongFrameMs;

static std::uint64_t gHookOverheadTicks = 0;
static std::uint64_t gExplicitProfilerWorkTicks = 0;
static std::uint64_t gWindowHookOverheadBase = 0;
static std::uint64_t gWindowExplicitOverheadBase = 0;
static std::uint64_t gLastHookOverheadTicks = 0;
static std::uint64_t gLastExplicitOverheadTicks = 0;

static std::uint64_t gFrameCount = 0;
static std::uint64_t gWindowFrameCount = 0;
static std::uint64_t gLastWindowFrameCount = 0;
static std::uint64_t gWindowFrameIntervalTicks = 0;
static std::uint64_t gLastWindowFrameIntervalTicks = 0;
static std::uint64_t gWindowPeakFrameIntervalTicks = 0;
static std::uint64_t gLastWindowPeakFrameIntervalTicks = 0;
static double gLastWindowSeconds = 0.0;

static std::uint64_t gWindowLuaTicks = 0;
static std::uint64_t gLastLuaTicks = 0;
static std::uint64_t gWindowAttributedTicks = 0;
static std::uint64_t gLastAttributedTicks = 0;
static std::uint64_t gWindowSystemTicks = 0;
static std::uint64_t gLastSystemTicks = 0;
static std::uint64_t gWindowUnattributedTicks = 0;
static std::uint64_t gLastUnattributedTicks = 0;

static std::unordered_map<std::string, Aggregate> gAddons{};
static std::unordered_map<std::string, Aggregate> gFiles{};
static std::unordered_map<std::string, Aggregate> gFunctions{};
static std::vector<CallFrame> gStack{};
static std::deque<LongFrame> gLongFrames{};
static bool gFunctionOverflow = false;

static std::uint64_t qpcNow() {
    LARGE_INTEGER now{};
    QueryPerformanceCounter(&now);
    return static_cast<std::uint64_t>(now.QuadPart);
}

static double ticksToMs(std::uint64_t ticks) {
    if (gFrequency.QuadPart <= 0) {
        return 0.0;
    }
    return static_cast<double>(ticks) * 1000.0 / static_cast<double>(gFrequency.QuadPart);
}

static double ticksToSeconds(std::uint64_t ticks) {
    if (gFrequency.QuadPart <= 0) {
        return 0.0;
    }
    return static_cast<double>(ticks) / static_cast<double>(gFrequency.QuadPart);
}

static std::string normalizeSlashes(std::string s) {
    for (char& c : s) {
        if (c == '\\') {
            c = '/';
        }
    }
    return s;
}

static std::string lowerAscii(std::string s) {
    for (char& c : s) {
        if (c >= 'A' && c <= 'Z') {
            c = static_cast<char>(c - 'A' + 'a');
        }
    }
    return s;
}

static SourceIdentity parseSource(const char* rawSource, const CallFrame* parent) {
    SourceIdentity out{};
    std::string src = rawSource ? rawSource : "";
    if (!src.empty() && src[0] == '@') {
        src.erase(src.begin());
    }
    src = normalizeSlashes(src);
    const std::string low = lowerAscii(src);
    const std::string needle = "interface/addons/";
    const auto pos = low.find(needle);
    if (pos != std::string::npos) {
        const std::size_t addonStart = pos + needle.size();
        const std::size_t slash = src.find('/', addonStart);
        if (slash != std::string::npos && slash > addonStart) {
            out.addon = src.substr(addonStart, slash - addonStart);
            out.file = src.substr(slash + 1);
        }
        else if (addonStart < src.size()) {
            out.addon = src.substr(addonStart);
            out.file = out.addon;
        }
        if (!out.addon.empty()) {
            out.attributed = true;
            return out;
        }
    }

    if (low.find("interface/framexml/") != std::string::npos ||
        low.find("interface/sharedxml/") != std::string::npos ||
        low.find("blizzard_") != std::string::npos) {
        out.addon = "Blizzard";
        out.file = src.empty() ? "Blizzard" : src;
        out.attributed = true;
        out.system = true;
        return out;
    }

    if (parent && parent->attributed) {
        out.addon = parent->addon;
        out.file = parent->file;
        out.attributed = true;
        out.system = (parent->addon == "Blizzard");
        return out;
    }

    if (!src.empty() && src != "=[C]" && src != "[C]") {
        out.addon = "Blizzard";
        out.file = src;
        out.attributed = true;
        out.system = true;
    }
    return out;
}

static ContextKind classifyRootContext(void* L) {
    const int top = lua_gettop(L);
    ContextKind result = ContextKind::Other;

    lua_getglobal(L, "event");
    if (lua_type(L, -1) == LUA_TSTRING) {
        const std::string e = lua_tostring(L, -1);
        if (!e.empty()) {
            result = ContextKind::OnEvent;
        }
    }
    lua_settop(L, top);

    if (result == ContextKind::Other) {
        lua_getglobal(L, "arg1");
        if (lua_isnumber(L, -1)) {
            result = ContextKind::OnUpdate;
        }
        lua_settop(L, top);
    }
    return result;
}

static void addContext(Aggregate& s, ContextKind context, std::uint64_t ticks) {
    if (context == ContextKind::OnEvent) {
        s.eventWindowTicks += ticks;
        s.eventWindowCalls++;
    }
    else if (context == ContextKind::OnUpdate) {
        s.updateWindowTicks += ticks;
        s.updateWindowCalls++;
    }
    else {
        s.otherWindowTicks += ticks;
        s.otherWindowCalls++;
    }
}

static void addAggregate(Aggregate& s, std::uint64_t ticks, ContextKind context) {
    s.totalTicks += ticks;
    s.totalCalls++;
    s.windowTicks += ticks;
    s.windowCalls++;
    s.currentFrameTicks += ticks;
    addContext(s, context, ticks);
}

static std::string functionKey(const CallFrame& frame) {
    std::string key = frame.addon;
    key += "|";
    key += frame.file;
    key += "|";
    key += std::to_string(frame.lineDefined);
    key += "|";
    key += frame.function.empty() ? "<anonymous>" : frame.function;
    return key;
}

static void finalizeWindow(std::uint64_t now) {
    if (gWindowStarted.QuadPart == 0 || gFrequency.QuadPart <= 0) {
        gWindowStarted.QuadPart = static_cast<LONGLONG>(now);
        return;
    }
    const std::uint64_t elapsed = now - static_cast<std::uint64_t>(gWindowStarted.QuadPart);
    if (elapsed < static_cast<std::uint64_t>(gFrequency.QuadPart)) {
        return;
    }

    gLastWindowSeconds = ticksToSeconds(elapsed);
    gLastWindowFrameCount = gWindowFrameCount;
    gLastWindowFrameIntervalTicks = gWindowFrameIntervalTicks;
    gLastWindowPeakFrameIntervalTicks = gWindowPeakFrameIntervalTicks;
    gLastLuaTicks = gWindowLuaTicks;
    gLastAttributedTicks = gWindowAttributedTicks;
    gLastSystemTicks = gWindowSystemTicks;
    gLastUnattributedTicks = gWindowUnattributedTicks;
    gLastHookOverheadTicks = gHookOverheadTicks - gWindowHookOverheadBase;
    gLastExplicitOverheadTicks = gExplicitProfilerWorkTicks - gWindowExplicitOverheadBase;

    for (auto& kv : gAddons) {
        Aggregate& s = kv.second;
        s.lastTicks = s.windowTicks;
        s.lastCalls = s.windowCalls;
        s.lastPeakFrameTicks = s.windowPeakFrameTicks;
        s.lastActiveFrameSamples.swap(s.windowActiveFrameSamples);
        s.eventLastTicks = s.eventWindowTicks;
        s.updateLastTicks = s.updateWindowTicks;
        s.otherLastTicks = s.otherWindowTicks;
        s.eventLastCalls = s.eventWindowCalls;
        s.updateLastCalls = s.updateWindowCalls;
        s.otherLastCalls = s.otherWindowCalls;
        s.windowTicks = 0;
        s.windowCalls = 0;
        s.windowPeakFrameTicks = 0;
        s.windowActiveFrameSamples.clear();
        s.eventWindowTicks = s.updateWindowTicks = s.otherWindowTicks = 0;
        s.eventWindowCalls = s.updateWindowCalls = s.otherWindowCalls = 0;
    }
    for (auto& kv : gFiles) {
        Aggregate& s = kv.second;
        s.lastTicks = s.windowTicks;
        s.lastCalls = s.windowCalls;
        s.lastPeakFrameTicks = s.windowPeakFrameTicks;
        s.windowTicks = 0;
        s.windowCalls = 0;
        s.windowPeakFrameTicks = 0;
    }
    for (auto& kv : gFunctions) {
        Aggregate& s = kv.second;
        s.lastTicks = s.windowTicks;
        s.lastCalls = s.windowCalls;
        s.lastPeakFrameTicks = s.windowPeakFrameTicks;
        s.windowTicks = 0;
        s.windowCalls = 0;
        s.windowPeakFrameTicks = 0;
    }

    gWindowFrameCount = 0;
    gWindowFrameIntervalTicks = 0;
    gWindowPeakFrameIntervalTicks = 0;
    gWindowLuaTicks = 0;
    gWindowAttributedTicks = 0;
    gWindowSystemTicks = 0;
    gWindowUnattributedTicks = 0;
    gWindowHookOverheadBase = gHookOverheadTicks;
    gWindowExplicitOverheadBase = gExplicitProfilerWorkTicks;
    gWindowStarted.QuadPart = static_cast<LONGLONG>(now);
}

static double percentile99(const std::vector<std::uint64_t>& samples) {
    if (samples.empty()) {
        return 0.0;
    }
    std::vector<std::uint64_t> temp = samples;
    std::sort(temp.begin(), temp.end());
    const double raw = 0.99 * static_cast<double>(temp.size() - 1);
    const std::size_t index = static_cast<std::size_t>(std::ceil(raw));
    return ticksToMs(temp[index]);
}

static std::string nowClockText() {
    SYSTEMTIME st{};
    GetLocalTime(&st);
    char buf[32] = {};
    std::snprintf(buf, sizeof(buf), "%02u:%02u:%02u", static_cast<unsigned>(st.wHour), static_cast<unsigned>(st.wMinute), static_cast<unsigned>(st.wSecond));
    return std::string(buf);
}

static double queryLuaMemoryKb(void* L) {
    if (!L) {
        return -1.0;
    }
    const int top = lua_gettop(L);
    double result = -1.0;
    gSuppressHook = true;
    lua_getglobal(L, "gcinfo");
    if (lua_type(L, -1) == LUA_TFUNCTION) {
        if (lua_pcall(L, 0, 1, 0) == 0 && lua_isnumber(L, -1)) {
            result = lua_tonumber(L, -1);
        }
    }
    lua_settop(L, top);
    gSuppressHook = false;
    return result;
}

static void sampleLuaMemory(void* L) {
    const std::uint64_t now = qpcNow();
    const double kb = queryLuaMemoryKb(L);
    if (kb < 0.0) {
        return;
    }
    if (gLastLuaMemoryKb >= 0.0 && gMemorySampleTime.QuadPart > 0) {
        const double seconds = ticksToSeconds(now - static_cast<std::uint64_t>(gMemorySampleTime.QuadPart));
        if (seconds > 0.0) {
            gAllocRateKbSec = (kb - gLastLuaMemoryKb) / seconds;
        }
        if (kb + 1.0 < gLastLuaMemoryKb) {
            gLastGcTime.QuadPart = static_cast<LONGLONG>(now);
            gGcDetectedCount++;
        }
    }
    gLuaMemoryKb = kb;
    gLastLuaMemoryKb = kb;
    gMemorySampleTime.QuadPart = static_cast<LONGLONG>(now);
}

static void clearState(bool keepRunning) {
    gAddons.clear();
    gFiles.clear();
    gFunctions.clear();
    gStack.clear();
    gLongFrames.clear();
    gFunctionOverflow = false;
    gFrameCount = 0;
    gWindowFrameCount = 0;
    gLastWindowFrameCount = 0;
    gWindowFrameIntervalTicks = 0;
    gLastWindowFrameIntervalTicks = 0;
    gWindowPeakFrameIntervalTicks = 0;
    gLastWindowPeakFrameIntervalTicks = 0;
    gLastWindowSeconds = 0.0;
    gWindowLuaTicks = 0;
    gLastLuaTicks = 0;
    gWindowAttributedTicks = 0;
    gLastAttributedTicks = 0;
    gWindowSystemTicks = 0;
    gLastSystemTicks = 0;
    gWindowUnattributedTicks = 0;
    gLastUnattributedTicks = 0;
    gHookOverheadTicks = 0;
    gExplicitProfilerWorkTicks = 0;
    gWindowHookOverheadBase = 0;
    gWindowExplicitOverheadBase = 0;
    gLastHookOverheadTicks = 0;
    gLastExplicitOverheadTicks = 0;
    gLastFrameBoundary.QuadPart = 0;
    QueryPerformanceCounter(&gWindowStarted);
    gLastLuaMemoryKb = -1.0;
    gLuaMemoryKb = -1.0;
    gAllocRateKbSec = 0.0;
    gMemorySampleTime.QuadPart = 0;
    gLastGcTime.QuadPart = 0;
    gGcDetectedCount = 0;
    gRunning = keepRunning;
}

static void markCurrentCallProfilerApi() {
    if (!gStack.empty()) {
        gStack.back().profilerApi = true;
    }
}

static void __fastcall profilerHook(void* L, lua_Debug* ar) {
    LARGE_INTEGER hookEntered{};
    QueryPerformanceCounter(&hookEntered);

    if (!gRunning || gSuppressHook || !ar) {
        return;
    }

    if (ar->event == LUA_HOOKCALL) {
        const CallFrame* parent = gStack.empty() ? nullptr : &gStack.back();
        lua_getinfo(L, gDeep ? "Snl" : "S", ar);

        CallFrame frame{};
        const SourceIdentity src = parseSource(ar->source, parent);
        frame.addon = src.addon;
        frame.file = src.file;
        frame.attributed = src.attributed;
        frame.what = ar->what ? ar->what : "";
        if (gDeep) {
            frame.function = ar->name ? ar->name : "";
            frame.lineDefined = ar->linedefined;
        }
        frame.context = parent ? parent->context : classifyRootContext(L);
        gStack.push_back(std::move(frame));

        LARGE_INTEGER hookLeaving{};
        QueryPerformanceCounter(&hookLeaving);
        const std::uint64_t hookCost = static_cast<std::uint64_t>(hookLeaving.QuadPart - hookEntered.QuadPart);
        gHookOverheadTicks += hookCost;
        gStack.back().started = hookLeaving;
        gStack.back().hookTicksAtStart = gHookOverheadTicks;
        return;
    }

    if (ar->event == LUA_HOOKRET || ar->event == LUA_HOOKTAILRET) {
        if (gStack.empty()) {
            LARGE_INTEGER hookLeaving{};
            QueryPerformanceCounter(&hookLeaving);
            gHookOverheadTicks += static_cast<std::uint64_t>(hookLeaving.QuadPart - hookEntered.QuadPart);
            return;
        }

        CallFrame frame = std::move(gStack.back());
        gStack.pop_back();
        const std::uint64_t raw = hookEntered.QuadPart > frame.started.QuadPart
            ? static_cast<std::uint64_t>(hookEntered.QuadPart - frame.started.QuadPart)
            : 0;
        const std::uint64_t nestedHook = gHookOverheadTicks >= frame.hookTicksAtStart
            ? gHookOverheadTicks - frame.hookTicksAtStart
            : 0;
        const std::uint64_t inclusive = raw > nestedHook ? raw - nestedHook : 0;
        const std::uint64_t exclusive = inclusive > frame.childAdjustedTicks ? inclusive - frame.childAdjustedTicks : 0;

        if (!gStack.empty()) {
            gStack.back().childAdjustedTicks += inclusive;
        }

        if (frame.profilerApi) {
            gExplicitProfilerWorkTicks += inclusive;
        }
        else {
            gWindowLuaTicks += exclusive;
            if (frame.attributed && frame.addon != "Blizzard") {
                gWindowAttributedTicks += exclusive;
                Aggregate& a = gAddons[frame.addon];
                addAggregate(a, exclusive, frame.context);
                const std::string fileKey = frame.addon + "|" + frame.file;
                Aggregate& f = gFiles[fileKey];
                addAggregate(f, exclusive, frame.context);
                if (gDeep) {
                    if (gFunctions.size() < kMaxFunctions || gFunctions.find(functionKey(frame)) != gFunctions.end()) {
                        Aggregate& fn = gFunctions[functionKey(frame)];
                        addAggregate(fn, exclusive, frame.context);
                    }
                    else {
                        gFunctionOverflow = true;
                    }
                }
            }
            else if (frame.attributed && frame.addon == "Blizzard") {
                gWindowSystemTicks += exclusive;
            }
            else {
                gWindowUnattributedTicks += exclusive;
            }
        }

        LARGE_INTEGER hookLeaving{};
        QueryPerformanceCounter(&hookLeaving);
        gHookOverheadTicks += static_cast<std::uint64_t>(hookLeaving.QuadPart - hookEntered.QuadPart);
        return;
    }

    LARGE_INTEGER hookLeaving{};
    QueryPerformanceCounter(&hookLeaving);
    gHookOverheadTicks += static_cast<std::uint64_t>(hookLeaving.QuadPart - hookEntered.QuadPart);
}

static bool startProfiler(void* L, std::string& reason) {
    if (gRunning) {
        reason = "ALREADY_RUNNING";
        return true;
    }
    lua_Hook existing = lua_gethook(L);
    if (existing && existing != &profilerHook) {
        reason = "HOOK_BUSY";
        return false;
    }
    QueryPerformanceFrequency(&gFrequency);
    if (gFrequency.QuadPart <= 0) {
        reason = "QPC_UNAVAILABLE";
        return false;
    }
    gLuaState = L;
    clearState(true);
    const int rc = lua_sethook(L, &profilerHook, LUA_MASKCALL | LUA_MASKRET, 0);
    if (rc != 0) {
        gRunning = false;
        reason = "SETHOOK_FAILED";
        return false;
    }
    reason = "OK";
    return true;
}

static void stopProfiler(void* L) {
    if (lua_gethook(L) == &profilerHook) {
        lua_sethook(L, nullptr, 0, 0);
    }
    gRunning = false;
    gStack.clear();
}

static void pushFieldString(void* L, const char* key, const std::string& value) {
    lua_pushstring(L, key);
    lua_pushstring(L, value);
    lua_settable(L, -3);
}

static void pushFieldNumber(void* L, const char* key, double value) {
    lua_pushstring(L, key);
    lua_pushnumber(L, value);
    lua_settable(L, -3);
}

static void pushFieldBool(void* L, const char* key, bool value) {
    lua_pushstring(L, key);
    lua_pushboolean(L, value ? 1 : 0);
    lua_settable(L, -3);
}

static double msPerFrame(std::uint64_t ticks) {
    if (gLastWindowFrameCount == 0) {
        return 0.0;
    }
    return ticksToMs(ticks) / static_cast<double>(gLastWindowFrameCount);
}

static double callsPerSecond(std::uint64_t calls) {
    if (gLastWindowSeconds <= 0.0) {
        return 0.0;
    }
    return static_cast<double>(calls) / gLastWindowSeconds;
}

static void pushAddonSnapshot(void* L) {
    struct Row { std::string name; Aggregate* stat; };
    std::vector<Row> rows{};
    rows.reserve(gAddons.size());
    for (auto& kv : gAddons) {
        rows.push_back({kv.first, &kv.second});
    }
    std::sort(rows.begin(), rows.end(), [](const Row& a, const Row& b) {
        return a.stat->lastTicks > b.stat->lastTicks;
    });

    lua_newtable(L);
    std::size_t index = 1;
    for (const Row& row : rows) {
        const Aggregate& s = *row.stat;
        if (s.lastTicks == 0 && s.lastCalls == 0) {
            continue;
        }
        lua_pushnumber(L, static_cast<double>(index++));
        lua_newtable(L);
        pushFieldString(L, "name", row.name);
        pushFieldNumber(L, "avgMsFrame", msPerFrame(s.lastTicks));
        pushFieldNumber(L, "peakMs", ticksToMs(s.lastPeakFrameTicks));
        pushFieldNumber(L, "p99Ms", percentile99(s.lastActiveFrameSamples));
        pushFieldNumber(L, "callsPerSec", callsPerSecond(s.lastCalls));
        const double share = gLastAttributedTicks > 0
            ? (static_cast<double>(s.lastTicks) * 100.0 / static_cast<double>(gLastAttributedTicks)) : 0.0;
        pushFieldNumber(L, "performanceShare", share);
        const std::uint64_t classified = s.eventLastTicks + s.updateLastTicks + s.otherLastTicks;
        pushFieldNumber(L, "onEventPct", classified > 0 ? static_cast<double>(s.eventLastTicks) * 100.0 / static_cast<double>(classified) : 0.0);
        pushFieldNumber(L, "onUpdatePct", classified > 0 ? static_cast<double>(s.updateLastTicks) * 100.0 / static_cast<double>(classified) : 0.0);
        pushFieldNumber(L, "otherPct", classified > 0 ? static_cast<double>(s.otherLastTicks) * 100.0 / static_cast<double>(classified) : 0.0);
        pushFieldNumber(L, "onEventCallsPerSec", callsPerSecond(s.eventLastCalls));
        pushFieldNumber(L, "onUpdateCallsPerSec", callsPerSecond(s.updateLastCalls));
        pushFieldNumber(L, "otherCallsPerSec", callsPerSecond(s.otherLastCalls));
        lua_settable(L, -3);
    }
}

static void pushSnapshot(void* L) {
    markCurrentCallProfilerApi();
    sampleLuaMemory(L);
    lua_newtable(L);
    pushFieldString(L, "version", kVersion);
    pushFieldBool(L, "running", gRunning);
    pushFieldBool(L, "deep", gDeep);
    pushFieldString(L, "measurement", "native-call-ret-qpc");
    pushFieldString(L, "contextClassifier", "event-global/arg1-number heuristic v1");
    pushFieldNumber(L, "windowSeconds", gLastWindowSeconds);
    pushFieldNumber(L, "frames", static_cast<double>(gLastWindowFrameCount));
    const double avgFrameMs = gLastWindowFrameCount > 0
        ? ticksToMs(gLastWindowFrameIntervalTicks) / static_cast<double>(gLastWindowFrameCount) : 0.0;
    pushFieldNumber(L, "frameAvgMs", avgFrameMs);
    pushFieldNumber(L, "fps", avgFrameMs > 0.0 ? 1000.0 / avgFrameMs : 0.0);
    pushFieldNumber(L, "framePeakMs", ticksToMs(gLastWindowPeakFrameIntervalTicks));
    pushFieldNumber(L, "luaMsFrame", msPerFrame(gLastLuaTicks));
    pushFieldNumber(L, "systemLuaMsFrame", msPerFrame(gLastSystemTicks));
    pushFieldNumber(L, "unattributedMsFrame", msPerFrame(gLastUnattributedTicks));
    const double coverage = gLastLuaTicks > 0
        ? static_cast<double>(gLastAttributedTicks + gLastSystemTicks) * 100.0 / static_cast<double>(gLastLuaTicks) : 100.0;
    pushFieldNumber(L, "coveragePct", coverage);
    pushFieldNumber(L, "profilerOverheadMsFrame", msPerFrame(gLastHookOverheadTicks + gLastExplicitOverheadTicks));
    pushFieldNumber(L, "hookOverheadMsFrame", msPerFrame(gLastHookOverheadTicks));
    pushFieldNumber(L, "apiOverheadMsFrame", msPerFrame(gLastExplicitOverheadTicks));
    pushFieldNumber(L, "luaMemoryKb", gLuaMemoryKb);
    pushFieldNumber(L, "allocationRateKbSec", gAllocRateKbSec);
    pushFieldNumber(L, "gcDetectedCount", static_cast<double>(gGcDetectedCount));
    double gcAge = -1.0;
    if (gLastGcTime.QuadPart > 0) {
        gcAge = ticksToSeconds(qpcNow() - static_cast<std::uint64_t>(gLastGcTime.QuadPart));
    }
    pushFieldNumber(L, "lastGcAgeSec", gcAge);
    pushFieldNumber(L, "longFrameThresholdMs", gLongFrameMs);
    pushFieldNumber(L, "longFrameCount", static_cast<double>(gLongFrames.size()));
    pushFieldBool(L, "functionOverflow", gFunctionOverflow);
    lua_pushstring(L, "addons");
    pushAddonSnapshot(L);
    lua_settable(L, -3);
}

static std::pair<std::string, std::string> splitComposite(const std::string& key) {
    const auto p = key.find('|');
    if (p == std::string::npos) {
        return {key, ""};
    }
    return {key.substr(0, p), key.substr(p + 1)};
}

static void pushFileRows(void* L, const std::string& addon) {
    struct Row { std::string file; Aggregate* stat; };
    std::vector<Row> rows{};
    for (auto& kv : gFiles) {
        auto parts = splitComposite(kv.first);
        if (parts.first == addon) {
            rows.push_back({parts.second, &kv.second});
        }
    }
    std::sort(rows.begin(), rows.end(), [](const Row& a, const Row& b) { return a.stat->lastTicks > b.stat->lastTicks; });
    lua_newtable(L);
    std::size_t i = 1;
    for (const Row& row : rows) {
        lua_pushnumber(L, static_cast<double>(i++));
        lua_newtable(L);
        pushFieldString(L, "file", row.file);
        pushFieldNumber(L, "avgMsFrame", msPerFrame(row.stat->lastTicks));
        pushFieldNumber(L, "callsPerSec", callsPerSecond(row.stat->lastCalls));
        pushFieldNumber(L, "peakMs", ticksToMs(row.stat->lastPeakFrameTicks));
        lua_settable(L, -3);
    }
}

static void pushFunctionRows(void* L, const std::string& addon) {
    struct Row { std::string key; Aggregate* stat; };
    std::vector<Row> rows{};
    const std::string prefix = addon + "|";
    for (auto& kv : gFunctions) {
        if (kv.first.compare(0, prefix.size(), prefix) == 0) {
            rows.push_back({kv.first.substr(prefix.size()), &kv.second});
        }
    }
    std::sort(rows.begin(), rows.end(), [](const Row& a, const Row& b) { return a.stat->lastTicks > b.stat->lastTicks; });
    lua_newtable(L);
    std::size_t i = 1;
    for (const Row& row : rows) {
        lua_pushnumber(L, static_cast<double>(i++));
        lua_newtable(L);
        pushFieldString(L, "key", row.key);
        pushFieldNumber(L, "avgMsFrame", msPerFrame(row.stat->lastTicks));
        pushFieldNumber(L, "callsPerSec", callsPerSecond(row.stat->lastCalls));
        lua_settable(L, -3);
    }
}

static void pushLongFrames(void* L) {
    lua_newtable(L);
    std::size_t i = 1;
    for (auto it = gLongFrames.rbegin(); it != gLongFrames.rend(); ++it) {
        lua_pushnumber(L, static_cast<double>(i++));
        lua_newtable(L);
        pushFieldString(L, "time", it->time);
        pushFieldNumber(L, "frameMs", it->frameMs);
        pushFieldNumber(L, "luaMs", it->luaMs);
        pushFieldString(L, "addon", it->addon);
        pushFieldString(L, "file", it->file);
        lua_settable(L, -3);
    }
}

} // namespace

void onFrameBoundary() {
    if (!gRunning || gFrequency.QuadPart <= 0) {
        return;
    }
    LARGE_INTEGER workStart{};
    QueryPerformanceCounter(&workStart);
    const std::uint64_t now = static_cast<std::uint64_t>(workStart.QuadPart);

    std::uint64_t frameInterval = 0;
    if (gLastFrameBoundary.QuadPart > 0 && now > static_cast<std::uint64_t>(gLastFrameBoundary.QuadPart)) {
        frameInterval = now - static_cast<std::uint64_t>(gLastFrameBoundary.QuadPart);
    }
    gLastFrameBoundary.QuadPart = static_cast<LONGLONG>(now);
    gFrameCount++;
    gWindowFrameCount++;
    if (frameInterval > 0) {
        gWindowFrameIntervalTicks += frameInterval;
        gWindowPeakFrameIntervalTicks = std::max(gWindowPeakFrameIntervalTicks, frameInterval);
    }

    std::uint64_t frameLua = 0;
    std::string topAddon{};
    std::uint64_t topAddonTicks = 0;
    for (auto& kv : gAddons) {
        Aggregate& s = kv.second;
        frameLua += s.currentFrameTicks;
        if (s.currentFrameTicks > 0) {
            s.windowActiveFrameSamples.push_back(s.currentFrameTicks);
            s.windowPeakFrameTicks = std::max(s.windowPeakFrameTicks, s.currentFrameTicks);
            if (s.currentFrameTicks > topAddonTicks) {
                topAddonTicks = s.currentFrameTicks;
                topAddon = kv.first;
            }
        }
    }

    std::string topFile{};
    std::uint64_t topFileTicks = 0;
    if (!topAddon.empty()) {
        const std::string prefix = topAddon + "|";
        for (auto& kv : gFiles) {
            if (kv.first.compare(0, prefix.size(), prefix) == 0 && kv.second.currentFrameTicks > topFileTicks) {
                topFileTicks = kv.second.currentFrameTicks;
                topFile = kv.first.substr(prefix.size());
            }
        }
    }

    if (frameInterval > 0 && ticksToMs(frameInterval) >= gLongFrameMs) {
        LongFrame lf{};
        lf.time = nowClockText();
        lf.frameMs = ticksToMs(frameInterval);
        lf.luaMs = ticksToMs(frameLua);
        lf.addon = topAddon.empty() ? "未归属/非Lua" : topAddon;
        lf.file = topFile;
        gLongFrames.push_back(std::move(lf));
        while (gLongFrames.size() > kMaxLongFrames) {
            gLongFrames.pop_front();
        }
    }

    for (auto& kv : gAddons) {
        kv.second.currentFrameTicks = 0;
    }
    for (auto& kv : gFiles) {
        if (kv.second.currentFrameTicks > 0) {
            kv.second.windowPeakFrameTicks = std::max(kv.second.windowPeakFrameTicks, kv.second.currentFrameTicks);
        }
        kv.second.currentFrameTicks = 0;
    }
    for (auto& kv : gFunctions) {
        if (kv.second.currentFrameTicks > 0) {
            kv.second.windowPeakFrameTicks = std::max(kv.second.windowPeakFrameTicks, kv.second.currentFrameTicks);
        }
        kv.second.currentFrameTicks = 0;
    }

    finalizeWindow(now);
    LARGE_INTEGER workEnd{};
    QueryPerformanceCounter(&workEnd);
    gExplicitProfilerWorkTicks += static_cast<std::uint64_t>(workEnd.QuadPart - workStart.QuadPart);
}

int handleLua(void* L) {
    const int argc = lua_gettop(L);
    if (argc < 2) {
        lua_pushnil(L);
        return 1;
    }
    const std::string sub = lua_tostring(L, 2);

    if (sub == "start") {
        std::string reason{};
        const bool ok = startProfiler(L, reason);
        lua_pushboolean(L, ok ? 1 : 0);
        lua_pushstring(L, reason);
        return 2;
    }
    if (sub == "stop") {
        markCurrentCallProfilerApi();
        stopProfiler(L);
        lua_pushboolean(L, 1);
        return 1;
    }
    if (sub == "reset") {
        markCurrentCallProfilerApi();
        const bool wasRunning = gRunning;
        clearState(wasRunning);
        lua_pushboolean(L, 1);
        return 1;
    }
    if (sub == "status") {
        markCurrentCallProfilerApi();
        lua_newtable(L);
        pushFieldString(L, "version", kVersion);
        pushFieldBool(L, "running", gRunning);
        pushFieldBool(L, "deep", gDeep);
        pushFieldNumber(L, "thresholdMs", gLongFrameMs);
        pushFieldString(L, "mode", "CALL/RET only; no LINE hook");
        lua_Hook hook = lua_gethook(L);
        pushFieldBool(L, "hookOwned", hook == &profilerHook);
        pushFieldBool(L, "hookBusy", hook != nullptr && hook != &profilerHook);
        return 1;
    }
    if (sub == "snapshot") {
        pushSnapshot(L);
        return 1;
    }
    if (sub == "deep") {
        markCurrentCallProfilerApi();
        if (argc >= 3) {
            gDeep = lua_toboolean(L, 3) != 0;
        }
        lua_pushboolean(L, gDeep ? 1 : 0);
        return 1;
    }
    if (sub == "threshold") {
        markCurrentCallProfilerApi();
        if (argc >= 3 && lua_isnumber(L, 3)) {
            const double v = lua_tonumber(L, 3);
            if (v >= 5.0 && v <= 1000.0) {
                gLongFrameMs = v;
            }
        }
        lua_pushnumber(L, gLongFrameMs);
        return 1;
    }
    if (sub == "files" && argc >= 3) {
        markCurrentCallProfilerApi();
        pushFileRows(L, lua_tostring(L, 3));
        return 1;
    }
    if (sub == "functions" && argc >= 3) {
        markCurrentCallProfilerApi();
        pushFunctionRows(L, lua_tostring(L, 3));
        return 1;
    }
    if (sub == "longframes") {
        markCurrentCallProfilerApi();
        pushLongFrames(L);
        return 1;
    }

    lua_pushnil(L);
    return 1;
}

} // namespace addonProfiler
'''

(root / 'addonProfiler.h').write_text(h, encoding='utf-8', newline='\n')
(root / 'addonProfiler.cpp').write_text(cpp, encoding='utf-8', newline='\n')

makefile = root / 'Makefile'
text = makefile.read_text(encoding='utf-8-sig')
needle = '            performanceProfiling.cpp \\\n'
if '            addonProfiler.cpp \\\n' not in text:
    if needle not in text:
        raise SystemExit('Makefile insertion point not found')
    text = text.replace(needle, needle + '            addonProfiler.cpp \\\n', 1)
makefile.write_text(text, encoding='utf-8', newline='\n')

dllmain = root / 'dllmain.cpp'
text = dllmain.read_text(encoding='utf-8-sig')
if '#include "addonProfiler.h"' not in text:
    needle = '#include "performanceProfiling.h"\n'
    if needle not in text:
        raise SystemExit('dllmain include insertion point not found')
    text = text.replace(needle, needle + '#include "addonProfiler.h"\n', 1)
if 'cmd == "profiler"' not in text:
    needle = '        else if (cmd == "debug") {'
    if needle not in text:
        raise SystemExit('dllmain command insertion point not found')
    block = '''        else if (cmd == "profiler") {\n            return addonProfiler::handleLua(L);\n        }\n'''
    text = text.replace(needle, block + needle, 1)
dllmain.write_text(text, encoding='utf-8', newline='\n')

scene = root / 'sceneBegin_sceneEnd.cpp'
text = scene.read_text(encoding='utf-8-sig')
if '#include "addonProfiler.h"' not in text:
    needle = '#include "FPScap.h"\n'
    if needle not in text:
        raise SystemExit('scene include insertion point not found')
    text = text.replace(needle, needle + '#include "addonProfiler.h"\n', 1)
if 'addonProfiler::onFrameBoundary();' not in text:
    needle = '''    else {\n        scene_isPresenting = false;\n    }\n\n'''
    if needle not in text:
        raise SystemExit('scene frame insertion point not found')
    text = text.replace(needle, needle + '    addonProfiler::onFrameBoundary();\n\n', 1)
scene.write_text(text, encoding='utf-8', newline='\n')

print('AddonProfiler B1 source applied')
