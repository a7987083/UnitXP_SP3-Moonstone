#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else 'upstream')
cpp_path = root / 'addonProfilerLite.cpp'
h_path = root / 'addonProfilerLite.h'
if not cpp_path.exists() or not h_path.exists():
    raise SystemExit('B1R5R4 lite profiler source/header missing')

s = cpp_path.read_text(encoding='utf-8', errors='replace')
s = s.replace('AddonProfiler B1R4 Calibrated', 'AddonProfiler B1R5R5 Light-Isolated', 1)

anchor = 'static std::size_t gTargetedDeepAddonIndex = static_cast<std::size_t>(-1);\n'
if anchor not in s:
    raise SystemExit('targeted deep index marker missing')
if 'static bool deepIsolationActive()' not in s:
    s = s.replace(anchor, anchor + '''\nstatic bool deepIsolationActive() {\n    return gTargetedDeepAddonIndex != static_cast<std::size_t>(-1);\n}\n''', 1)

marker = 'static void resetStats() {\n'
if marker not in s:
    raise SystemExit('resetStats marker missing')
if 'discardActiveWindowKeepLast' not in s:
    helper = r'''static void discardActiveWindowKeepLast() {
    for (auto& a : gAddons) {
        auto& x = a.s;
        x.windowTicks = x.windowCalls = 0;
        x.currentFrameTicks = x.windowPeakFrameTicks = 0;
        x.windowSamples.clear();
        x.updateWindowTicks = x.eventWindowTicks = x.otherWindowTicks = 0;
        x.updateWindowCalls = x.eventWindowCalls = x.otherWindowCalls = 0;
        x.windowLongHits = 0;
    }
    for (auto& f : gFiles) {
        auto& x = f.s;
        x.windowTicks = x.windowCalls = 0;
        x.currentFrameTicks = x.windowPeakFrameTicks = 0;
        x.windowSamples.clear();
    }
    for (auto& h : gHandlers) {
        auto& x = h.s;
        x.windowTicks = x.windowCalls = 0;
        x.currentFrameTicks = x.windowPeakFrameTicks = 0;
        x.windowSamples.clear();
    }
    gWindowMeasuredTicks = 0;
    gWindowUnattributedTicks = 0;
    gWindowBookkeepingTicks = 0;
    gWindowBoundaryTicks = 0;
    gWindowFrames = 0;
    gWindowFrameTicks = 0;
    gWindowPeakFrameTicks = 0;
    LARGE_INTEGER now{};
    QueryPerformanceCounter(&now);
    gWindowStarted = now;
    gLastFrameBoundary = now;
}

'''
    s = s.replace(marker, helper + marker, 1)

old = '''    const bool deepCandidate = (gTargetedDeepAddonIndex == h.addonIndex);\n    const bool deepScope = deepCandidate ? addonProfilerDeep::beginTargetScope(L) : false;\n\n    const std::uint64_t bookkeepingStart = qpc();\n'''
new = '''    const bool deepIsolation = deepIsolationActive();\n    const bool deepCandidate = (gTargetedDeepAddonIndex == h.addonIndex);\n    const bool deepScope = deepCandidate ? addonProfilerDeep::beginTargetScope(L) : false;\n\n    const std::uint64_t bookkeepingStart = qpc();\n'''
if old not in s:
    raise SystemExit('wrapped handler targeted block missing')
s = s.replace(old, new, 1)

old = '''    addStat(h.s, h.kind, elapsed);\n    if (h.addonIndex < gAddons.size()) addStat(gAddons[h.addonIndex].s, h.kind, elapsed);\n    if (h.fileIndex < gFiles.size()) addStat(gFiles[h.fileIndex].s, h.kind, elapsed);\n    gWindowMeasuredTicks += elapsed;\n    const std::uint64_t bookkeepingEnd = qpc();\n    const std::uint64_t pre = callStart >= bookkeepingStart ? callStart - bookkeepingStart : 0;\n    const std::uint64_t post = bookkeepingEnd >= callEnd ? bookkeepingEnd - callEnd : 0;\n    gWindowBookkeepingTicks += pre + post;\n'''
new = '''    const std::uint64_t bookkeepingEnd = qpc();\n    if (!deepIsolation) {\n        addStat(h.s, h.kind, elapsed);\n        if (h.addonIndex < gAddons.size()) addStat(gAddons[h.addonIndex].s, h.kind, elapsed);\n        if (h.fileIndex < gFiles.size()) addStat(gFiles[h.fileIndex].s, h.kind, elapsed);\n        gWindowMeasuredTicks += elapsed;\n        const std::uint64_t pre = callStart >= bookkeepingStart ? callStart - bookkeepingStart : 0;\n        const std::uint64_t post = bookkeepingEnd >= callEnd ? bookkeepingEnd - callEnd : 0;\n        gWindowBookkeepingTicks += pre + post;\n    }\n'''
if old not in s:
    raise SystemExit('wrapped handler stat block missing')
s = s.replace(old, new, 1)

old = '''bool setTargetedDeepAddon(const char* addon) {\n    if (!addon || !*addon) { gTargetedDeepAddonIndex = static_cast<std::size_t>(-1); return false; }\n    const auto it = gAddonIndex.find(std::string(addon));\n    if (it == gAddonIndex.end()) { gTargetedDeepAddonIndex = static_cast<std::size_t>(-1); return false; }\n    gTargetedDeepAddonIndex = it->second;\n    return true;\n}\n\nvoid clearTargetedDeepAddon() {\n    gTargetedDeepAddonIndex = static_cast<std::size_t>(-1);\n}\n'''
new = '''bool setTargetedDeepAddon(const char* addon) {\n    if (!addon || !*addon) { gTargetedDeepAddonIndex = static_cast<std::size_t>(-1); return false; }\n    const auto it = gAddonIndex.find(std::string(addon));\n    if (it == gAddonIndex.end()) { gTargetedDeepAddonIndex = static_cast<std::size_t>(-1); return false; }\n    discardActiveWindowKeepLast();\n    gTargetedDeepAddonIndex = it->second;\n    return true;\n}\n\nvoid clearTargetedDeepAddon() {\n    discardActiveWindowKeepLast();\n    gTargetedDeepAddonIndex = static_cast<std::size_t>(-1);\n}\n'''
if old not in s:
    raise SystemExit('set/clear targeted block missing')
s = s.replace(old, new, 1)

old = '''void onFrameBoundary() {\n    if (!gRunning || gFrequency.QuadPart <= 0) return;\n    const std::uint64_t boundaryStart=qpc();\n'''
new = '''void onFrameBoundary() {\n    if (!gRunning || gFrequency.QuadPart <= 0) return;\n    if (deepIsolationActive()) {\n        const std::uint64_t now = qpc();\n        gLastFrameBoundary.QuadPart = static_cast<LONGLONG>(now);\n        gWindowStarted.QuadPart = static_cast<LONGLONG>(now);\n        return;\n    }\n    const std::uint64_t boundaryStart=qpc();\n'''
if old not in s:
    raise SystemExit('onFrameBoundary marker missing')
s = s.replace(old, new, 1)

status_old = 'pushBoolField(L,"hookOwned",false);pushNumberField(L,"hookMask",0);pushNumberField(L,"wrappedHandlerCount",(double)gHandlers.size());return 1;'
status_new = 'pushBoolField(L,"hookOwned",false);pushNumberField(L,"hookMask",0);pushNumberField(L,"wrappedHandlerCount",(double)gHandlers.size());pushBoolField(L,"deepIsolation",deepIsolationActive());return 1;'
if status_old not in s:
    raise SystemExit('status field marker missing')
s = s.replace(status_old, status_new, 1)

snap_marker = 'pushStringField(L, "mode", "LIGHT_ENTRY_WRAPPER");'
if snap_marker in s and '"deepIsolation"' not in s[s.index(snap_marker):s.index(snap_marker)+500]:
    s = s.replace(snap_marker, snap_marker + '\n    pushBoolField(L, "deepIsolation", deepIsolationActive());', 1)

cpp_path.write_text(s, encoding='utf-8', newline='\n')
check = cpp_path.read_text(encoding='utf-8', errors='replace')
assert 'AddonProfiler B1R5R5 Light-Isolated' in check
assert 'if (!deepIsolation)' in check
assert 'if (deepIsolationActive())' in check
assert 'discardActiveWindowKeepLast();' in check
assert 'pushBoolField(L,"deepIsolation",deepIsolationActive())' in check
assert 'lua_sethook' not in check, 'light profiler must remain hook-free'
print('B1R5R5 light/deep isolation patch OK')
