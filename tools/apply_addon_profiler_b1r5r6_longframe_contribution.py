#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else 'upstream')
cpp_path = root / 'addonProfilerLite.cpp'
text = cpp_path.read_text(encoding='utf-8')


def once(old, new, label):
    global text
    n = text.count(old)
    if n != 1:
        raise SystemExit(f'{label}: expected exactly 1 match, got {n}')
    text = text.replace(old, new, 1)

once(
'''    std::uint64_t windowLongHits = 0;\n    std::uint64_t lastLongHits = 0;\n    std::uint64_t totalLongHits = 0;\n''',
'''    std::uint64_t windowLongHits = 0;\n    std::uint64_t lastLongHits = 0;\n    std::uint64_t totalLongHits = 0;\n    std::uint64_t windowLongContribHits = 0;\n    std::uint64_t lastLongContribHits = 0;\n    std::uint64_t totalLongContribHits = 0;\n''',
'WindowStat long contribution counters')

once(
'''    double associatedAddonMs = 0.0;\n    double unmeasuredMs = 0.0;\n};\n''',
'''    double associatedAddonMs = 0.0;\n    double associatedAddonPct = 0.0;\n    double measuredLuaPct = 0.0;\n    double unmeasuredMs = 0.0;\n    int contributionLevel = 0;\n    std::string contributionLabel;\n};\n''',
'LongFrame contribution fields')

once(
'''static double p99(const std::vector<std::uint64_t>& samples) {\n''',
'''static int longFrameContributionLevel(double frameMs, double addonMs) {\n    if (frameMs <= 0.0 || addonMs <= 0.0) return 0;\n    const double pct = addonMs * 100.0 / frameMs;\n    if (addonMs >= 10.0 && pct >= 50.0) return 3;\n    if (addonMs >= 5.0 && pct >= 25.0) return 2;\n    if (addonMs >= 2.0 && pct >= 10.0) return 1;\n    return 0;\n}\n\nstatic const char* longFrameContributionLabel(int level) {\n    if (level >= 3) return "高度解释";\n    if (level == 2) return "主要贡献";\n    if (level == 1) return "有效贡献";\n    return "仅伴随";\n}\n\nstatic double p99(const std::vector<std::uint64_t>& samples) {\n''',
'contribution classifier helpers')

once(
'''    s.windowLongHits = s.lastLongHits = s.totalLongHits = 0;\n''',
'''    s.windowLongHits = s.lastLongHits = s.totalLongHits = 0;\n    s.windowLongContribHits = s.lastLongContribHits = s.totalLongContribHits = 0;\n''',
'resetOne contribution counters')

once(
'''        x.windowLongHits = 0;\n''',
'''        x.windowLongHits = 0;\n        x.windowLongContribHits = 0;\n''',
'discardActiveWindow contribution counters')

once(
'''        s.lastLongHits = s.windowLongHits;\n        s.windowTicks = s.windowCalls = s.windowPeakFrameTicks = 0;\n''',
'''        s.lastLongHits = s.windowLongHits;\n        s.lastLongContribHits = s.windowLongContribHits;\n        s.windowTicks = s.windowCalls = s.windowPeakFrameTicks = 0;\n''',
'finalize last contribution counters')

once(
'''        s.windowLongHits = 0;\n    }\n''',
'''        s.windowLongHits = 0;\n        s.windowLongContribHits = 0;\n    }\n''',
'finalize reset contribution counters')

once(
'''        pushNumberField(L, "longFrameHits", (double)s.lastLongHits);\n        pushNumberField(L, "totalLongFrameHits", (double)s.totalLongHits);\n''',
'''        pushNumberField(L, "longFrameHits", (double)s.lastLongHits);\n        pushNumberField(L, "totalLongFrameHits", (double)s.totalLongHits);\n        pushNumberField(L, "longFrameContributionHits", (double)s.lastLongContribHits);\n        pushNumberField(L, "totalLongFrameContributionHits", (double)s.totalLongContribHits);\n''',
'push addon contribution counters')

once(
'''    pushNumberField(L, "longFrameThresholdMs", gLongFrameMs);\n    pushNumberField(L, "longFrameCount", (double)gTotalLongFrames);\n''',
'''    pushNumberField(L, "longFrameThresholdMs", gLongFrameMs);\n    pushNumberField(L, "longFrameContributionMinMs", 2.0);\n    pushNumberField(L, "longFrameContributionMinPct", 10.0);\n    pushNumberField(L, "longFrameCount", (double)gTotalLongFrames);\n''',
'push snapshot contribution criteria')

once(
'''        pushStringField(L,"addon",it->addon); pushStringField(L,"file",it->file);\n        pushNumberField(L,"associatedAddonMs",it->associatedAddonMs); pushNumberField(L,"unmeasuredMs",it->unmeasuredMs);\n''',
'''        pushStringField(L,"addon",it->addon); pushStringField(L,"file",it->file);\n        pushNumberField(L,"associatedAddonMs",it->associatedAddonMs);\n        pushNumberField(L,"associatedAddonPct",it->associatedAddonPct);\n        pushNumberField(L,"measuredLuaPct",it->measuredLuaPct);\n        pushNumberField(L,"contributionLevel",(double)it->contributionLevel);\n        pushStringField(L,"contributionLabel",it->contributionLabel);\n        pushBoolField(L,"effectiveContribution",it->contributionLevel >= 1);\n        pushNumberField(L,"unmeasuredMs",it->unmeasuredMs);\n''',
'push long frame contribution fields')

once(
'''    if (interval && ticksMs(interval)>=gLongFrameMs) {\n        gTotalLongFrames++;\n        if (!topAddon.empty()) {\n            auto ai=gAddonIndex.find(topAddon); if (ai!=gAddonIndex.end()) {gAddons[ai->second].s.windowLongHits++;gAddons[ai->second].s.totalLongHits++;}\n        }\n        LongFrame lf; lf.time=clockText();lf.frameMs=ticksMs(interval);lf.measuredLuaMs=ticksMs(measuredFrame);lf.addon=topAddon.empty()?"未归属/非监控Lua":topAddon;lf.file=topFile;\n        lf.associatedAddonMs=ticksMs(topTicks);\n        lf.unmeasuredMs=lf.frameMs>lf.measuredLuaMs?lf.frameMs-lf.measuredLuaMs:0.0;\n        gLongFrames.push_back(std::move(lf)); while(gLongFrames.size()>kMaxLongFrames)gLongFrames.pop_front();\n    }\n''',
'''    if (interval && ticksMs(interval)>=gLongFrameMs) {\n        gTotalLongFrames++;\n        const double frameMs = ticksMs(interval);\n        const double measuredLuaMs = ticksMs(measuredFrame);\n        const double associatedAddonMs = ticksMs(topTicks);\n        const int contributionLevel = longFrameContributionLevel(frameMs, associatedAddonMs);\n        if (!topAddon.empty()) {\n            auto ai=gAddonIndex.find(topAddon);\n            if (ai!=gAddonIndex.end()) {\n                gAddons[ai->second].s.windowLongHits++;\n                gAddons[ai->second].s.totalLongHits++;\n                if (contributionLevel >= 1) {\n                    gAddons[ai->second].s.windowLongContribHits++;\n                    gAddons[ai->second].s.totalLongContribHits++;\n                }\n            }\n        }\n        LongFrame lf; lf.time=clockText();lf.frameMs=frameMs;lf.measuredLuaMs=measuredLuaMs;lf.addon=topAddon.empty()?"未归属/非监控Lua":topAddon;lf.file=topFile;\n        lf.associatedAddonMs=associatedAddonMs;\n        lf.associatedAddonPct=frameMs>0.0?associatedAddonMs*100.0/frameMs:0.0;\n        lf.measuredLuaPct=frameMs>0.0?measuredLuaMs*100.0/frameMs:0.0;\n        lf.unmeasuredMs=frameMs>measuredLuaMs?frameMs-measuredLuaMs:0.0;\n        lf.contributionLevel=contributionLevel;\n        lf.contributionLabel=longFrameContributionLabel(contributionLevel);\n        gLongFrames.push_back(std::move(lf)); while(gLongFrames.size()>kMaxLongFrames)gLongFrames.pop_front();\n    }\n''',
'onFrameBoundary contribution classification')

once(
'''    pushStringField(L, "mode", "LIGHT_ENTRY_WRAPPER");\n''',
'''    pushStringField(L, "mode", "LIGHT_ENTRY_WRAPPER_B1R5R6_LONGFRAME_CONTRIBUTION");\n''',
'B1R5R6 mode marker')

cpp_path.write_text(text, encoding='utf-8')
print('B1R5R6 long-frame contribution patch OK')
