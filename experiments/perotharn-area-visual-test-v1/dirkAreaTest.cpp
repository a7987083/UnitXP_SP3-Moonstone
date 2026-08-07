#define _USE_MATH_DEFINES
#include "dirkAreaTest.h"
#include <Windows.h>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <sstream>
#include <string>
#include "Vanilla1121_functions.h"

namespace dirkAreaTest {
namespace {

constexpr std::uintptr_t kWorldM2ContextPointerAddress = 0x00C7B298;
constexpr std::uintptr_t kCreateModelAddress = 0x00707350;
constexpr std::uintptr_t kReleaseModelAddress = 0x007103A0;
constexpr std::uintptr_t kEnsureRenderReadyAddress = 0x00710450;
constexpr std::uintptr_t kSetTransformAddress = 0x00710650;
constexpr std::uintptr_t kAttachToRenderListAddress = 0x00710B90;
constexpr std::uintptr_t kSetActiveTimestampAddress = 0x00710C50;
constexpr std::uintptr_t kSetAlphaAddress = 0x00710CB0;
constexpr std::uintptr_t kSetColorAddress = 0x00710CF0;
constexpr std::uintptr_t kSetSequenceAddress = 0x007121A0;
constexpr const char* kPreModelPath = "Spells\\DirkOfTheBeast_Area_PreCast.mdx";
constexpr const char* kCastModelPath = "Spells\\DirkOfTheBeast_Area_Cast.mdx";
constexpr float kLineLengthYards = 100.0f;
constexpr int kDynamicObjectLoopSequence = 0x9E;

using CreateModelProc = void* (__thiscall*)(void*, const char*, std::uint32_t);
using ReleaseModelProc = void (__thiscall*)(void*);
using EnsureRenderReadyProc = int (__thiscall*)(void*, int, int);
using SetTransformProc = void (__thiscall*)(void*, const C3Vector*, float, const C3Vector*, const C3Vector*);
using SetBooleanProc = void (__thiscall*)(void*, int);
using SetAlphaProc = void (__thiscall*)(void*, float);
using SetColorProc = void (__thiscall*)(void*, const C3Vector*);
using SetSequenceProc = void (__thiscall*)(void*, int, int, int, int, float, int, int);

struct AreaSlot {
    void* model = nullptr;
    C3Vector position = {};
    float facing = 0.0f;
    float scale = 1.0f;
    const char* path = nullptr;
    bool active = false;
    bool renderReady = false;
};

enum class FullPhase { idle, pre, cast };
AreaSlot gPre = {};
AreaSlot gCast = {};
void* gContext = nullptr;
FullPhase gFullPhase = FullPhase::idle;
DWORD gPhaseStartMs = 0;
DWORD gPreDelayMs = 2000;
DWORD gCastHoldMs = 2000;
C3Vector gOrigin = {};
float gFacing = 0.0f;
float gFullScale = 1.0f;
std::string gLastStage = "not_started";
unsigned long gCreateCalls = 0, gCreateSuccesses = 0, gReleaseCalls = 0;
unsigned long gReattachCalls = 0, gContextDrops = 0;

template <typename T>
T readField(void* object, std::size_t offset) {
    return *reinterpret_cast<T*>(reinterpret_cast<std::uint8_t*>(object) + offset);
}

void* currentContext() {
    void* p = *reinterpret_cast<void**>(kWorldM2ContextPointerAddress);
    if (p == nullptr || (reinterpret_cast<std::uintptr_t>(p) & 1u) != 0u) return nullptr;
    return p;
}

void dropStaleSlots() {
    gPre = {};
    gCast = {};
    gContext = nullptr;
    gFullPhase = FullPhase::idle;
    ++gContextDrops;
    gLastStage = "world_context_changed";
}

void releaseSlot(AreaSlot& slot) {
    if (slot.model == nullptr) { slot = {}; return; }
    void* live = currentContext();
    if (live == nullptr || live != gContext) {
        slot = {};
        ++gContextDrops;
        return;
    }
    void* owner = readField<void*>(slot.model, 0x2C);
    if (owner == gContext) {
        reinterpret_cast<SetBooleanProc>(kAttachToRenderListAddress)(slot.model, 0);
        reinterpret_cast<ReleaseModelProc>(kReleaseModelAddress)(slot.model);
        ++gReleaseCalls;
    }
    slot = {};
}

void releaseAll() {
    releaseSlot(gPre);
    releaseSlot(gCast);
    gFullPhase = FullPhase::idle;
}

bool validPose(const C3Vector& p, float f) {
    return std::isfinite(p.x) && std::isfinite(p.y) && std::isfinite(p.z) && std::isfinite(f);
}

float sanitizeScale(float scale) {
    if (!std::isfinite(scale)) return 1.0f;
    if (scale < 0.05f) return 0.05f;
    if (scale > 100.0f) return 100.0f;
    return scale;
}

bool playerPose(C3Vector& p, float& f) {
    const std::uint64_t guid = vanilla1121_unitGUID("player");
    const std::uint32_t player = vanilla1121_getVisiableObject(guid);
    if (player == 0 || (player & 1u) != 0u) { gLastStage = "player_not_visible"; return false; }
    p = vanilla1121_unitPosition(player);
    f = vanilla1121_unitFacing(player);
    if (!validPose(p, f)) { gLastStage = "invalid_player_pose"; return false; }
    return true;
}

C3Vector endpoint(const C3Vector& p, float f) {
    C3Vector out = p;
    out.x += std::cos(f) * kLineLengthYards;
    out.y += std::sin(f) * kLineLengthYards;
    return out;
}

void applyTransform(AreaSlot& slot) {
    if (!slot.model) return;
    const C3Vector up = {0.0f, 0.0f, 1.0f};
    const C3Vector scale = {slot.scale, slot.scale, slot.scale};
    reinterpret_cast<SetTransformProc>(kSetTransformAddress)(slot.model, &slot.position, slot.facing, &up, &scale);
}

void armSequence(AreaSlot& slot) {
    if (!slot.model) return;
    // DynamicObject AreaModel visuals use the client's dedicated 0x9E loop.
    // v1 incorrectly forced generic sequence 0, which only exposed a tiny smoke component.
    reinterpret_cast<SetSequenceProc>(kSetSequenceAddress)(
        slot.model, -1, kDynamicObjectLoopSequence, -1, 0, 1.0f, 1, 1);
}

bool createSlot(AreaSlot& slot, const char* path, const C3Vector& p, float f, float scale) {
    if (!path || !validPose(p, f)) { gLastStage = "invalid_spawn_request"; return false; }
    void* live = currentContext();
    if (!live) { gLastStage = "no_world_m2_context"; return false; }
    if (gContext && gContext != live) dropStaleSlots();
    gContext = live;
    releaseSlot(slot);
    slot.position = p;
    slot.facing = f;
    slot.scale = sanitizeScale(scale);
    slot.path = path;

    ++gCreateCalls;
    slot.model = reinterpret_cast<CreateModelProc>(kCreateModelAddress)(gContext, path, 0);
    if (!slot.model) { slot = {}; gLastStage = "create_model_failed"; return false; }
    ++gCreateSuccesses;
    if (readField<void*>(slot.model, 0x2C) != gContext) {
        gLastStage = "model_context_mismatch";
        releaseSlot(slot);
        return false;
    }

    applyTransform(slot);
    const C3Vector white = {1.0f, 1.0f, 1.0f};
    reinterpret_cast<SetAlphaProc>(kSetAlphaAddress)(slot.model, 1.0f);
    reinterpret_cast<SetColorProc>(kSetColorAddress)(slot.model, &white);
    armSequence(slot);
    reinterpret_cast<SetBooleanProc>(kSetActiveTimestampAddress)(slot.model, 1);
    reinterpret_cast<SetBooleanProc>(kAttachToRenderListAddress)(slot.model, 1);
    slot.active = true;
    if (readField<void*>(slot.model, 0x44) == nullptr) {
        gLastStage = "render_list_link_missing";
        releaseSlot(slot);
        return false;
    }
    slot.renderReady = reinterpret_cast<EnsureRenderReadyProc>(kEnsureRenderReadyAddress)(slot.model, 1, 1) != 0;
    gLastStage = slot.renderReady ? "active_ready_seq158" : "active_waiting_resources_seq158";
    return true;
}

void updateSlot(AreaSlot& slot) {
    if (!slot.active || !slot.model) return;
    applyTransform(slot);
    reinterpret_cast<SetBooleanProc>(kSetActiveTimestampAddress)(slot.model, 1);
    if (readField<void*>(slot.model, 0x44) == nullptr) {
        ++gReattachCalls;
        reinterpret_cast<SetBooleanProc>(kAttachToRenderListAddress)(slot.model, 1);
        armSequence(slot);
    }
    if (!slot.renderReady)
        slot.renderReady = reinterpret_cast<EnsureRenderReadyProc>(kEnsureRenderReadyAddress)(slot.model, 0, 1) != 0;
}

DWORD secondsToMs(float seconds, DWORD fallback) {
    if (!std::isfinite(seconds) || seconds <= 0.0f) return fallback;
    if (seconds > 30.0f) seconds = 30.0f;
    return static_cast<DWORD>(seconds * 1000.0f + 0.5f);
}

} // namespace

bool showPre(float scale) {
    releaseAll();
    C3Vector p = {}; float f = 0.0f;
    if (!playerPose(p, f)) return false;
    gOrigin = p; gFacing = f; gFullPhase = FullPhase::idle;
    return createSlot(gPre, kPreModelPath, p, f, scale);
}

bool showCast(float scale) {
    releaseAll();
    C3Vector p = {}; float f = 0.0f;
    if (!playerPose(p, f)) return false;
    gOrigin = p; gFacing = f; gFullPhase = FullPhase::idle;
    return createSlot(gCast, kCastModelPath, endpoint(p, f), f, scale);
}

bool showFull(float preDelaySeconds, float castHoldSeconds, float scale) {
    releaseAll();
    C3Vector p = {}; float f = 0.0f;
    if (!playerPose(p, f)) return false;
    gOrigin = p; gFacing = f;
    gFullScale = sanitizeScale(scale);
    gPreDelayMs = secondsToMs(preDelaySeconds, 2000);
    gCastHoldMs = secondsToMs(castHoldSeconds, 2000);
    if (!createSlot(gPre, kPreModelPath, gOrigin, gFacing, gFullScale)) return false;
    gFullPhase = FullPhase::pre;
    gPhaseStartMs = GetTickCount();
    gLastStage = "full_pre_seq158";
    return true;
}

void clear() { releaseAll(); gLastStage = "cleared"; }

void update() {
    void* live = currentContext();
    if (gContext && live != gContext) { dropStaleSlots(); return; }
    updateSlot(gPre);
    updateSlot(gCast);
    if (gFullPhase == FullPhase::idle) return;

    const DWORD now = GetTickCount();
    const DWORD elapsed = now - gPhaseStartMs;
    if (gFullPhase == FullPhase::pre && elapsed >= gPreDelayMs) {
        releaseSlot(gPre);
        if (createSlot(gCast, kCastModelPath, endpoint(gOrigin, gFacing), gFacing, gFullScale)) {
            gFullPhase = FullPhase::cast;
            gPhaseStartMs = now;
            gLastStage = "full_cast_seq158";
        } else gFullPhase = FullPhase::idle;
    } else if (gFullPhase == FullPhase::cast && elapsed >= gCastHoldMs) {
        releaseSlot(gCast);
        gFullPhase = FullPhase::idle;
        gLastStage = "full_complete";
    }
}

std::string statusText() {
    std::ostringstream ss;
    ss << "stage=" << gLastStage
       << " context=0x" << std::hex << reinterpret_cast<std::uintptr_t>(currentContext())
       << " pre=0x" << reinterpret_cast<std::uintptr_t>(gPre.model)
       << " cast=0x" << reinterpret_cast<std::uintptr_t>(gCast.model) << std::dec
       << " seq=" << kDynamicObjectLoopSequence
       << " preScale=" << gPre.scale
       << " castScale=" << gCast.scale
       << " preReady=" << (gPre.renderReady ? 1 : 0)
       << " castReady=" << (gCast.renderReady ? 1 : 0)
       << " creates=" << gCreateSuccesses << "/" << gCreateCalls
       << " releases=" << gReleaseCalls << " reattach=" << gReattachCalls
       << " staleDrops=" << gContextDrops
       << " origin=(" << gOrigin.x << "," << gOrigin.y << "," << gOrigin.z << ")"
       << " facing=" << gFacing << " length=" << kLineLengthYards;
    return ss.str();
}

} // namespace dirkAreaTest
