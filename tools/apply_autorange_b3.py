#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "upstream")
make_path = root / "Makefile"
dll_path = root / "dllmain.cpp"
native_h = root / "nativeM2Test.h"
native_cpp = root / "nativeM2Test.cpp"
for p in (make_path, dll_path, native_h, native_cpp):
    if not p.is_file():
        raise SystemExit(f"missing required source: {p}")

def replace_once(text, needle, replacement, label):
    count = text.count(needle)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one marker, got {count}")
    return text.replace(needle, replacement, 1)

# ---------- AutoRange native DBC resolver ----------
auto_h = r'''#pragma once

#include <string>

namespace autoRange {

std::string resolve(unsigned int spellId);
std::string status();

} // namespace autoRange
'''

auto_cpp = r'''#include "AutoRange.h"

#include <Windows.h>

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <iomanip>
#include <sstream>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace autoRange {
namespace {

constexpr std::uintptr_t kSFileOpenArchiveAddress = 0x00648DD0u;
constexpr std::uintptr_t kSFileOpenFileExAddress = 0x006477C0u;
constexpr std::uintptr_t kSFileReadFileAddress = 0x00648460u;
constexpr std::uintptr_t kSFileGetFileSizeAddress = 0x006487F0u;
constexpr std::uintptr_t kSFileCloseFileAddress = 0x00648730u;
constexpr std::uintptr_t kSFileCloseArchiveAddress = 0x00648EF0u;
constexpr DWORD kInvalidFileSize = 0xFFFFFFFFu;
constexpr DWORD kMaxDbcBytes = 64u * 1024u * 1024u;

using SFileOpenArchiveProc = BOOL (__stdcall*)(const char*, DWORD, DWORD, void**);
using SFileOpenFileExProc = BOOL (__stdcall*)(void*, const char*, DWORD, void**);
using SFileReadFileProc = BOOL (__stdcall*)(void*, void*, DWORD, DWORD*, void*, DWORD);
using SFileGetFileSizeProc = DWORD (__stdcall*)(void*, DWORD*);
using SFileCloseFileProc = BOOL (__stdcall*)(void*);
using SFileCloseArchiveProc = BOOL (__stdcall*)(void*);

std::string lowerAscii(std::string value) {
    for (char& c : value) {
        if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
    }
    return value;
}

std::string parentDirectory(std::string path) {
    for (char& c : path) if (c == '/') c = '\\';
    const std::size_t slash = path.find_last_of('\\');
    return slash == std::string::npos ? std::string(".") : path.substr(0, slash);
}

std::string baseName(std::string path) {
    for (char& c : path) if (c == '/') c = '\\';
    const std::size_t slash = path.find_last_of('\\');
    return slash == std::string::npos ? path : path.substr(slash + 1u);
}

void collectMpqArchives(const std::string& directory, int depth,
                        std::vector<std::string>& archives) {
    if (depth < 0) return;
    WIN32_FIND_DATAA data = {};
    HANDLE find = FindFirstFileA((directory + "\\*").c_str(), &data);
    if (find == INVALID_HANDLE_VALUE) return;
    do {
        const std::string name = data.cFileName;
        if (name == "." || name == "..") continue;
        const std::string full = directory + "\\" + name;
        if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
            collectMpqArchives(full, depth - 1, archives);
            continue;
        }
        const std::string lowered = lowerAscii(name);
        if (lowered.size() >= 4u
            && lowered.compare(lowered.size() - 4u, 4u, ".mpq") == 0) {
            archives.push_back(full);
        }
    } while (FindNextFileA(find, &data));
    FindClose(find);
}

bool readFileFromArchive(const std::string& archivePath, const char* internalPath,
                         std::vector<std::uint8_t>& bytes) {
    const auto openArchive = reinterpret_cast<SFileOpenArchiveProc>(kSFileOpenArchiveAddress);
    const auto openFile = reinterpret_cast<SFileOpenFileExProc>(kSFileOpenFileExAddress);
    const auto readFile = reinterpret_cast<SFileReadFileProc>(kSFileReadFileAddress);
    const auto getFileSize = reinterpret_cast<SFileGetFileSizeProc>(kSFileGetFileSizeAddress);
    const auto closeFile = reinterpret_cast<SFileCloseFileProc>(kSFileCloseFileAddress);
    const auto closeArchive = reinterpret_cast<SFileCloseArchiveProc>(kSFileCloseArchiveAddress);

    void* archive = nullptr;
    if (!openArchive(archivePath.c_str(), 0, 0, &archive) || archive == nullptr) return false;
    void* file = nullptr;
    if (!openFile(archive, internalPath, 0, &file) || file == nullptr) {
        closeArchive(archive);
        return false;
    }
    DWORD high = 0;
    const DWORD size = getFileSize(file, &high);
    if (size == kInvalidFileSize || high != 0 || size < 20u || size > kMaxDbcBytes) {
        closeFile(file); closeArchive(archive); return false;
    }
    bytes.resize(size);
    DWORD read = 0;
    const BOOL ok = readFile(file, bytes.data(), size, &read, nullptr, 0);
    closeFile(file); closeArchive(archive);
    if (!ok || read != size) { bytes.clear(); return false; }
    return true;
}

std::vector<std::string> clientArchives() {
    char exePath[MAX_PATH] = {};
    const DWORD length = GetModuleFileNameA(nullptr, exePath, MAX_PATH);
    if (length == 0 || length >= MAX_PATH) return {};
    std::vector<std::string> archives;
    collectMpqArchives(parentDirectory(std::string(exePath, length)) + "\\Data", 2, archives);
    std::sort(archives.begin(), archives.end(), [](const std::string& a, const std::string& b) {
        return lowerAscii(a) > lowerAscii(b);
    });
    archives.erase(std::unique(archives.begin(), archives.end(),
        [](const std::string& a, const std::string& b) {
            return lowerAscii(a) == lowerAscii(b);
        }), archives.end());
    return archives;
}

std::uint32_t le32(const std::uint8_t* p) {
    return static_cast<std::uint32_t>(p[0])
        | (static_cast<std::uint32_t>(p[1]) << 8u)
        | (static_cast<std::uint32_t>(p[2]) << 16u)
        | (static_cast<std::uint32_t>(p[3]) << 24u);
}

struct DbcTable {
    std::vector<std::uint8_t> bytes;
    std::unordered_map<std::uint32_t, std::uint32_t> byId;
    std::uint32_t records = 0;
    std::uint32_t fields = 0;
    std::uint32_t recordSize = 0;
    std::uint32_t stringSize = 0;
    std::string source;

    bool load(const std::vector<std::string>& archives, const char* path) {
        bytes.clear(); byId.clear(); source.clear();
        for (const std::string& archive : archives) {
            if (readFileFromArchive(archive, path, bytes)) {
                source = baseName(archive);
                break;
            }
        }
        if (bytes.size() < 20u || std::memcmp(bytes.data(), "WDBC", 4u) != 0) return false;
        records = le32(bytes.data() + 4u);
        fields = le32(bytes.data() + 8u);
        recordSize = le32(bytes.data() + 12u);
        stringSize = le32(bytes.data() + 16u);
        if (records == 0u || fields == 0u || recordSize < 4u || recordSize < fields * 4u) return false;
        const std::uint64_t recordBytes = static_cast<std::uint64_t>(records) * recordSize;
        if (20ull + recordBytes + stringSize > bytes.size()) return false;
        for (std::uint32_t i = 0; i < records; ++i) {
            const std::uint8_t* r = bytes.data() + 20u + static_cast<std::size_t>(i) * recordSize;
            byId[le32(r)] = i;
        }
        return true;
    }

    const std::uint8_t* record(std::uint32_t id) const {
        const auto it = byId.find(id);
        if (it == byId.end()) return nullptr;
        return bytes.data() + 20u + static_cast<std::size_t>(it->second) * recordSize;
    }

    std::uint32_t u32(const std::uint8_t* r, std::uint32_t field) const {
        if (r == nullptr || field >= fields || (field + 1u) * 4u > recordSize) return 0u;
        return le32(r + field * 4u);
    }

    std::int32_t i32(const std::uint8_t* r, std::uint32_t field) const {
        return static_cast<std::int32_t>(u32(r, field));
    }

    float f32(const std::uint8_t* r, std::uint32_t field) const {
        const std::uint32_t bits = u32(r, field);
        float out = 0.0f;
        std::memcpy(&out, &bits, sizeof(out));
        return out;
    }
};

struct Cache {
    bool attempted = false;
    bool ready = false;
    DbcTable spell;
    DbcTable radius;
    DbcTable duration;
    std::string error;
};
Cache gCache;

bool ensureCache() {
    if (gCache.attempted) return gCache.ready;
    gCache.attempted = true;
    const std::vector<std::string> archives = clientArchives();
    if (archives.empty()) { gCache.error = "NO_MPQ"; return false; }
    if (!gCache.spell.load(archives, "DBFilesClient\\Spell.dbc")) {
        gCache.error = "SPELL_DBC"; return false;
    }
    if (!gCache.radius.load(archives, "DBFilesClient\\SpellRadius.dbc")) {
        gCache.error = "RADIUS_DBC"; return false;
    }
    if (!gCache.duration.load(archives, "DBFilesClient\\SpellDuration.dbc")) {
        gCache.error = "DURATION_DBC"; return false;
    }
    if (gCache.spell.fields <= 114u || gCache.radius.fields < 2u || gCache.duration.fields < 2u) {
        gCache.error = "DBC_SCHEMA"; return false;
    }
    gCache.ready = true;
    return true;
}

enum class Mode { Unknown, Caster, Ground, Cone };
const char* modeName(Mode m) {
    switch (m) {
        case Mode::Caster: return "CASTER";
        case Mode::Ground: return "GROUND";
        case Mode::Cone: return "CONE";
        default: return "UNKNOWN";
    }
}

Mode classifyTarget(std::uint32_t target) {
    switch (target) {
        case 24u: return Mode::Cone;
        case 8u:
        case 16u:
        case 28u:
        case 29u:
            return Mode::Ground;
        case 1u:
        case 7u:
        case 15u:
        case 20u:
        case 22u:
            return Mode::Caster;
        default:
            return Mode::Unknown;
    }
}

Mode combineMode(Mode a, Mode b) {
    if (a == Mode::Cone || b == Mode::Cone) return Mode::Cone;
    if (a == Mode::Ground || b == Mode::Ground) return Mode::Ground;
    if (a == Mode::Caster || b == Mode::Caster) return Mode::Caster;
    return Mode::Unknown;
}

Mode spellHint(const std::uint8_t* r) {
    Mode result = Mode::Unknown;
    for (std::uint32_t i = 0; i < 3u; ++i) {
        result = combineMode(result, classifyTarget(gCache.spell.u32(r, 85u + i)));
        result = combineMode(result, classifyTarget(gCache.spell.u32(r, 88u + i)));
    }
    return result;
}

float radiusValue(std::uint32_t radiusId) {
    if (radiusId == 0u) return 0.0f;
    const std::uint8_t* r = gCache.radius.record(radiusId);
    if (r == nullptr) return 0.0f;
    const float value = gCache.radius.f32(r, 1u);
    return (value > 0.0f && value < 1000.0f) ? value : 0.0f;
}

std::uint32_t durationMs(std::uint32_t spellId) {
    const std::uint8_t* spell = gCache.spell.record(spellId);
    if (spell == nullptr) return 0u;
    const std::uint32_t durationId = gCache.spell.u32(spell, 30u);
    const std::uint8_t* d = gCache.duration.record(durationId);
    if (d == nullptr) return 0u;
    const std::int32_t value = gCache.duration.i32(d, 1u);
    return value > 0 ? static_cast<std::uint32_t>(value) : 0u;
}

struct Candidate {
    bool valid = false;
    std::uint32_t castSpell = 0;
    std::uint32_t geometrySpell = 0;
    float radius = 0.0f;
    Mode mode = Mode::Unknown;
    std::uint32_t radiusIndex = 0;
    std::uint32_t targetA = 0;
    std::uint32_t targetB = 0;
    std::uint32_t depth = 0;
};

int modeScore(Mode m) {
    switch (m) {
        case Mode::Caster: return 4;
        case Mode::Ground: return 4;
        case Mode::Cone: return 2;
        default: return 1;
    }
}

bool better(const Candidate& a, const Candidate& b) {
    if (!b.valid) return true;
    const int as = modeScore(a.mode), bs = modeScore(b.mode);
    if (as != bs) return as > bs;
    if (a.depth != b.depth) return a.depth < b.depth;
    return a.radius > b.radius;
}

void walkSpell(std::uint32_t castSpell, std::uint32_t spellId,
               std::uint32_t depth, Mode inherited,
               std::unordered_set<std::uint32_t>& visited,
               Candidate& best) {
    if (spellId == 0u || depth > 4u || visited.count(spellId) != 0u) return;
    visited.insert(spellId);
    const std::uint8_t* r = gCache.spell.record(spellId);
    if (r == nullptr) return;
    const Mode hint = combineMode(spellHint(r), inherited);

    for (std::uint32_t i = 0; i < 3u; ++i) {
        const std::uint32_t effect = gCache.spell.u32(r, 61u + i);
        const std::uint32_t rid = gCache.spell.u32(r, 91u + i);
        if (effect == 0u || rid == 0u) continue;
        const float rv = radiusValue(rid);
        if (rv <= 0.0f) continue;
        const std::uint32_t ta = gCache.spell.u32(r, 85u + i);
        const std::uint32_t tb = gCache.spell.u32(r, 88u + i);
        Mode specific = combineMode(classifyTarget(ta), classifyTarget(tb));
        if (specific == Mode::Unknown) specific = hint;
        Candidate c;
        c.valid = true; c.castSpell = castSpell; c.geometrySpell = spellId;
        c.radius = rv; c.mode = specific; c.radiusIndex = rid;
        c.targetA = ta; c.targetB = tb; c.depth = depth;
        if (better(c, best)) best = c;
    }

    for (std::uint32_t i = 0; i < 3u; ++i) {
        const std::uint32_t child = gCache.spell.u32(r, 112u + i);
        if (child != 0u && child != spellId) {
            walkSpell(castSpell, child, depth + 1u, hint, visited, best);
        }
    }
}

std::string safeSource(const std::string& s) {
    std::string out = s;
    for (char& c : out) if (c == '|') c = '_';
    return out;
}

} // namespace

std::string status() {
    if (!ensureCache()) return std::string("E|") + gCache.error;
    return std::string("OK|Spell=") + safeSource(gCache.spell.source)
        + "|Radius=" + safeSource(gCache.radius.source)
        + "|Duration=" + safeSource(gCache.duration.source);
}

std::string resolve(unsigned int spellId) {
    if (spellId == 0u) return "E|INVALID_SPELL";
    if (!ensureCache()) return std::string("E|") + gCache.error;
    if (gCache.spell.record(spellId) == nullptr) return "E|SPELL_NOT_FOUND";

    Candidate best;
    std::unordered_set<std::uint32_t> visited;
    walkSpell(spellId, spellId, 0u, Mode::Unknown, visited, best);
    if (!best.valid) {
        std::ostringstream miss;
        miss << "E|NO_RADIUS|" << spellId << '|' << durationMs(spellId) << '|'
             << safeSource(gCache.spell.source);
        return miss.str();
    }

    std::uint32_t duration = durationMs(spellId);
    if (duration == 0u && best.geometrySpell != spellId)
        duration = durationMs(best.geometrySpell);
    const char* source = best.depth == 0u ? "DIRECT" : "TRIGGER";

    std::ostringstream out;
    out.setf(std::ios::fixed);
    out << std::setprecision(3);
    out << "A|" << spellId << '|' << best.geometrySpell << '|'
        << best.radius << '|' << duration << '|'
        << modeName(best.mode) << '|' << source << '|'
        << best.radiusIndex << '|' << best.targetA << '|' << best.targetB << '|'
        << best.depth << '|'
        << safeSource(gCache.spell.source) << '|'
        << safeSource(gCache.radius.source) << '|'
        << safeSource(gCache.duration.source);
    return out.str();
}

} // namespace autoRange
'''
(root / "AutoRange.h").write_text(auto_h, encoding="utf-8", newline="\n")
(root / "AutoRange.cpp").write_text(auto_cpp, encoding="utf-8", newline="\n")

m = make_path.read_text(encoding="utf-8")
if "AutoRange.cpp" not in m:
    m = replace_once(m, "            GroundProbe.cpp \\\n", "            GroundProbe.cpp \\\n            AutoRange.cpp \\\n", "Makefile GroundProbe source")
make_path.write_text(m, encoding="utf-8", newline="\n")

h = native_h.read_text(encoding="utf-8")
if "setAutoRangeVisual(" not in h:
    marker = "// Returns a canonical icon name. The one-argument compatibility form returns\n"
    decl = r'''// Dedicated local danger visuals used by AutoRange. Keys let several enemy
// skills coexist without touching MoonMarker's placement/advanced preview slots.
bool setAutoRangeVisual(const std::string& key,
                        const std::string& modelPath,
                        const C3Vector& position,
                        float scale,
                        float yawDegrees,
                        std::string& normalizedPath);
bool moveAutoRangeVisual(const std::string& key,
                         const C3Vector& position,
                         float scale,
                         float yawDegrees);
void clearAutoRangeVisual(const std::string& key);
void clearAllAutoRangeVisuals();

'''
    h = replace_once(h, marker, decl + marker, "nativeM2Test.h canonical icon marker")
native_h.write_text(h, encoding="utf-8", newline="\n")

c = native_cpp.read_text(encoding="utf-8")
if "AutoRangePreviewSlot" not in c:
    marker = "struct ProjectedIcon {\n"
    addition = r'''constexpr std::size_t kAutoRangePreviewCount = 16;
struct AutoRangePreviewSlot {
    PreviewSlot preview = {};
    std::string key;
};

'''
    c = replace_once(c, marker, addition + marker, "nativeM2Test.cpp ProjectedIcon marker")
    c = replace_once(c,
        "PreviewSlot gPlacementPreview = {};\n",
        "PreviewSlot gPlacementPreview = {};\nstd::array<AutoRangePreviewSlot, kAutoRangePreviewCount> gAutoRangePreviews = {};\n",
        "nativeM2Test.cpp preview globals")

if "findAutoRangePreview(" not in c:
    marker = "void resetSlot(Slot& slot) {\n"
    helpers = r'''AutoRangePreviewSlot* findAutoRangePreview(const std::string& key) {
    if (key.empty()) return nullptr;
    for (AutoRangePreviewSlot& slot : gAutoRangePreviews) {
        if (slot.key == key && slot.preview.active && slot.preview.model != nullptr)
            return &slot;
    }
    return nullptr;
}

AutoRangePreviewSlot* allocateAutoRangePreview(const std::string& key) {
    if (AutoRangePreviewSlot* existing = findAutoRangePreview(key)) return existing;
    for (AutoRangePreviewSlot& slot : gAutoRangePreviews) {
        if (!slot.preview.active || slot.preview.model == nullptr) {
            resetPreview(slot.preview);
            slot.key = key;
            return &slot;
        }
    }
    return nullptr;
}

void resetAutoRangePreview(AutoRangePreviewSlot& slot) {
    resetPreview(slot.preview);
    slot.key.clear();
}

'''
    c = replace_once(c, marker, helpers + marker, "nativeM2Test.cpp resetSlot marker")

if "bool setAutoRangeVisual(" not in c:
    marker = "std::string defaultIconForColor(const std::string& colorName) {\n"
    funcs = r'''bool setAutoRangeVisual(const std::string& key,
                        const std::string& modelPath,
                        const C3Vector& position,
                        float scale,
                        float yawDegrees,
                        std::string& normalizedPath) {
    if (!runtimeReady("unsupported_client") || key.empty()) return false;
    gLastErrorStage = "autorange_validate";
    if (!moonMarkerAdvancedState::normalizeModelPath(modelPath, normalizedPath)
        || !std::isfinite(position.x) || !std::isfinite(position.y)
        || !std::isfinite(position.z) || !std::isfinite(scale)
        || !std::isfinite(yawDegrees)
        || scale < moonMarkerAdvancedState::kMinScale
        || scale > moonMarkerAdvancedState::kMaxScale) {
        return false;
    }
    AutoRangePreviewSlot* slot = allocateAutoRangePreview(key);
    if (slot == nullptr) { gLastErrorStage = "autorange_slots_full"; return false; }
    const C3Vector white = {1.0f, 1.0f, 1.0f};
    if (!createPreview(slot->preview, normalizedPath, position, scale, yawDegrees,
            1.0f, white,
            "autorange_no_world_context", "autorange_create_failed",
            "autorange_context_mismatch", "autorange_render_list_missing",
            "autorange_ready", "autorange_waiting_resources")) {
        slot->key.clear();
        return false;
    }
    slot->key = key;
    return true;
}

bool moveAutoRangeVisual(const std::string& key,
                         const C3Vector& position,
                         float scale,
                         float yawDegrees) {
    if (!runtimeReady("unsupported_client")) return false;
    AutoRangePreviewSlot* slot = findAutoRangePreview(key);
    if (slot == nullptr || !std::isfinite(position.x) || !std::isfinite(position.y)
        || !std::isfinite(position.z) || !std::isfinite(scale)
        || !std::isfinite(yawDegrees)
        || scale < moonMarkerAdvancedState::kMinScale
        || scale > moonMarkerAdvancedState::kMaxScale) {
        gLastErrorStage = "autorange_move_invalid";
        return false;
    }
    slot->preview.position = position;
    slot->preview.scale = scale;
    slot->preview.yawDegrees = yawDegrees;
    applyPreviewWorldMatrix(slot->preview);
    gLastErrorStage = "autorange_moved";
    return true;
}

void clearAutoRangeVisual(const std::string& key) {
    for (AutoRangePreviewSlot& slot : gAutoRangePreviews) {
        if (slot.key != key) continue;
        releasePreview(slot.preview, false, "", "", "");
        slot.key.clear();
        gLastErrorStage = "autorange_cleared";
        return;
    }
}

void clearAllAutoRangeVisuals() {
    for (AutoRangePreviewSlot& slot : gAutoRangePreviews) {
        releasePreview(slot.preview, false, "", "", "");
        slot.key.clear();
    }
    gLastErrorStage = "autorange_cleared_all";
}

'''
    c = replace_once(c, marker, funcs + marker, "nativeM2Test.cpp defaultIcon marker")

if "resetAutoRangePreview(autoRangeSlot)" not in c:
    c = replace_once(c,
        "        resetPreview(gAdvancedPreview);\n        moonMarkerAdvancedState::clearAll();\n",
        "        resetPreview(gAdvancedPreview);\n        for (AutoRangePreviewSlot& autoRangeSlot : gAutoRangePreviews)\n            resetAutoRangePreview(autoRangeSlot);\n        moonMarkerAdvancedState::clearAll();\n",
        "nativeM2Test.cpp world-not-ready reset")

if "updatePreview(autoRangeSlot.preview" not in c:
    c = replace_once(c,
        "    updatePreview(gAdvancedPreview, liveContext,\n        \"advanced_world_context_changed\", \"advanced_ready\",\n        \"advanced_waiting_resources\");\n",
        "    updatePreview(gAdvancedPreview, liveContext,\n        \"advanced_world_context_changed\", \"advanced_ready\",\n        \"advanced_waiting_resources\");\n    for (AutoRangePreviewSlot& autoRangeSlot : gAutoRangePreviews) {\n        updatePreview(autoRangeSlot.preview, liveContext,\n            \"autorange_world_context_changed\", \"autorange_ready\",\n            \"autorange_waiting_resources\");\n        if (!autoRangeSlot.preview.active || autoRangeSlot.preview.model == nullptr)\n            autoRangeSlot.key.clear();\n    }\n",
        "nativeM2Test.cpp update previews")

if "resetAutoRangePreview(autoRangeSlot);\n        resetProjected();\n        gLastErrorStage = \"cleared_all_world_not_ready\"" not in c:
    c = replace_once(c,
        "        resetPreview(gAdvancedPreview);\n        resetProjected();\n        gLastErrorStage = \"cleared_all_world_not_ready\";\n",
        "        resetPreview(gAdvancedPreview);\n        for (AutoRangePreviewSlot& autoRangeSlot : gAutoRangePreviews)\n            resetAutoRangePreview(autoRangeSlot);\n        resetProjected();\n        gLastErrorStage = \"cleared_all_world_not_ready\";\n",
        "nativeM2Test.cpp clear no-world")
if "releasePreview(autoRangeSlot.preview" not in c:
    c = replace_once(c,
        "    releasePreview(gAdvancedPreview, false, \"\", \"\", \"\");\n    resetProjected();\n",
        "    releasePreview(gAdvancedPreview, false, \"\", \"\", \"\");\n    for (AutoRangePreviewSlot& autoRangeSlot : gAutoRangePreviews) {\n        releasePreview(autoRangeSlot.preview, false, \"\", \"\", \"\");\n        autoRangeSlot.key.clear();\n    }\n    resetProjected();\n",
        "nativeM2Test.cpp clear live")
native_cpp.write_text(c, encoding="utf-8", newline="\n")

d = dll_path.read_text(encoding="utf-8")
if '#include "AutoRange.h"' not in d:
    d = replace_once(d, '#include "GroundProbe.h"\n', '#include "GroundProbe.h"\n#include "AutoRange.h"\n', "dllmain include")
if 'AutoRange.Resolve' not in d:
    marker = "    // MoonMarker runtime commands are handled before the legacy >=2 argument gate.\n"
    bridge = r'''    // AutoRange B3: DBC-based range resolver + dedicated local patch-O visuals.
    if (argumentCount >= 1 && lua_isstring(L, 1)) {
        const string autoRangeCommand{ lua_tostring(L, 1) };
        if (autoRangeCommand == "AutoRange.Status") {
            const std::string record = autoRange::status();
            lua_pushstring(L, record.c_str());
            return 1;
        }
        if (autoRangeCommand == "AutoRange.Resolve" && argumentCount >= 2
            && lua_isnumber(L, 2)) {
            const unsigned int spellId = static_cast<unsigned int>(lua_tonumber(L, 2));
            const std::string record = autoRange::resolve(spellId);
            lua_pushstring(L, record.c_str());
            return 1;
        }
        if (autoRangeCommand == "AutoRange.VisualSet" && argumentCount >= 7
            && lua_isstring(L, 2) && lua_isstring(L, 3)
            && lua_isnumber(L, 4) && lua_isnumber(L, 5)
            && lua_isnumber(L, 6) && lua_isnumber(L, 7)) {
            C3Vector pos = { static_cast<float>(lua_tonumber(L, 4)),
                             static_cast<float>(lua_tonumber(L, 5)),
                             static_cast<float>(lua_tonumber(L, 6)) };
            const float scale = static_cast<float>(lua_tonumber(L, 7));
            float yaw = 0.0f;
            if (argumentCount >= 8 && lua_isnumber(L, 8))
                yaw = static_cast<float>(lua_tonumber(L, 8));
            std::string normalized;
            const bool ok = nativeM2Test::setAutoRangeVisual(
                lua_tostring(L, 2), lua_tostring(L, 3), pos, scale, yaw, normalized);
            lua_pushboolean(L, ok ? 1 : 0);
            lua_pushstring(L, normalized.c_str());
            lua_pushstring(L, nativeM2Test::lastErrorStage().c_str());
            return 3;
        }
        if (autoRangeCommand == "AutoRange.VisualMove" && argumentCount >= 6
            && lua_isstring(L, 2) && lua_isnumber(L, 3) && lua_isnumber(L, 4)
            && lua_isnumber(L, 5) && lua_isnumber(L, 6)) {
            C3Vector pos = { static_cast<float>(lua_tonumber(L, 3)),
                             static_cast<float>(lua_tonumber(L, 4)),
                             static_cast<float>(lua_tonumber(L, 5)) };
            const float scale = static_cast<float>(lua_tonumber(L, 6));
            float yaw = 0.0f;
            if (argumentCount >= 7 && lua_isnumber(L, 7))
                yaw = static_cast<float>(lua_tonumber(L, 7));
            lua_pushboolean(L, nativeM2Test::moveAutoRangeVisual(
                lua_tostring(L, 2), pos, scale, yaw) ? 1 : 0);
            return 1;
        }
        if (autoRangeCommand == "AutoRange.VisualClear" && argumentCount >= 2
            && lua_isstring(L, 2)) {
            nativeM2Test::clearAutoRangeVisual(lua_tostring(L, 2));
            return 0;
        }
        if (autoRangeCommand == "AutoRange.VisualClearAll") {
            nativeM2Test::clearAllAutoRangeVisuals();
            return 0;
        }
    }

'''
    d = replace_once(d, marker, bridge + marker, "dllmain MoonMarker marker")
dll_path.write_text(d, encoding="utf-8", newline="\n")

checks = {
    make_path: ["AutoRange.cpp"],
    dll_path: ["AutoRange.Resolve", "AutoRange.VisualSet", "AutoRange.VisualMove", '#include "AutoRange.h"'],
    native_h: ["setAutoRangeVisual", "clearAllAutoRangeVisuals"],
    native_cpp: ["AutoRangePreviewSlot", "setAutoRangeVisual", "updatePreview(autoRangeSlot.preview"],
    root / "AutoRange.cpp": ["DBFilesClient\\\\Spell.dbc", "112u + i", "91u + i"],
}
for p, needles in checks.items():
    text = p.read_text(encoding="utf-8")
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"postcondition failed: {needle} missing from {p}")
print("AutoRange B3 deterministic injection: OK")
