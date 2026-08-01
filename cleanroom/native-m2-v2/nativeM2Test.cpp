#define _USE_MATH_DEFINES

#include "nativeM2Test.h"

#include <cmath>
#include <cstddef>
#include <cstdint>

namespace nativeM2Test {
namespace {

constexpr std::uintptr_t kWorldM2ContextPointerAddress = 0x00C7B298;
constexpr std::uintptr_t kCreateModelAddress = 0x00707350;
constexpr std::uintptr_t kReleaseModelAddress = 0x007103A0;
constexpr std::uintptr_t kEnsureRenderReadyAddress = 0x00710450;
constexpr std::uintptr_t kSetWorldMatrixAddress = 0x00710620;
constexpr std::uintptr_t kAttachToRenderListAddress = 0x00710B90;
constexpr std::uintptr_t kSetActiveTimestampAddress = 0x00710C50;
constexpr std::uintptr_t kSetAlphaAddress = 0x00710CB0;
constexpr std::uintptr_t kSetColorAddress = 0x00710CF0;
constexpr std::uintptr_t kSetSequenceAddress = 0x007121A0;
constexpr const char* kMoonBeamPath = "Spells\\MoonBeam_Impact_Base.mdx";

using CreateModelProc = void* (__thiscall*)(void*, const char*, std::uint32_t);
using ReleaseModelProc = void (__thiscall*)(void*);
using EnsureRenderReadyProc = int (__thiscall*)(void*, int, int);
using SetWorldMatrixProc = void (__thiscall*)(void*, const float*);
using SetBooleanProc = void (__thiscall*)(void*, int);
using SetAlphaProc = void (__thiscall*)(void*, float);
using SetColorProc = void (__thiscall*)(void*, const C3Vector*);
using SetSequenceProc = void (__thiscall*)(void*, int, int, int, int, float, int, int);

void* gContext = nullptr;
void* gModel = nullptr;
std::uint32_t gPlayerObject = 0;
C3Vector gPosition = {};
bool gActive = false;
bool gRenderReady = false;
unsigned long gCreateCalls = 0;
unsigned long gCreateSuccesses = 0;
unsigned long gUpdateCalls = 0;
unsigned long gReattachCalls = 0;
unsigned long gReattachSuccesses = 0;
unsigned long gReleaseCalls = 0;
unsigned long gDroppedStalePointers = 0;
unsigned long gLoadChecks = 0;
unsigned long gLoadReadyTransitions = 0;
std::string gLastErrorStage = "not_started";

template <typename T>
T readField(void* object, std::size_t offset) {
    return *reinterpret_cast<T*>(reinterpret_cast<std::uint8_t*>(object) + offset);
}

void* currentContext() {
    void* context = *reinterpret_cast<void**>(kWorldM2ContextPointerAddress);
    if (context == nullptr || (reinterpret_cast<std::uintptr_t>(context) & 1u) != 0u) {
        return nullptr;
    }
    return context;
}

void buildWorldMatrix(const C3Vector& position, float (&matrix)[16]) {
    for (float& value : matrix) {
        value = 0.0f;
    }
    matrix[0] = 1.0f;
    matrix[5] = 1.0f;
    matrix[10] = 1.0f;
    matrix[15] = 1.0f;
    matrix[12] = position.x;
    matrix[13] = position.y;
    matrix[14] = position.z;
}

void applyWorldMatrix() {
    if (gModel == nullptr) {
        return;
    }
    float matrix[16] = {};
    buildWorldMatrix(gPosition, matrix);
    reinterpret_cast<SetWorldMatrixProc>(kSetWorldMatrixAddress)(gModel, matrix);
}

void releaseCurrent(bool updateStage) {
    if (gModel == nullptr) {
        gActive = false;
        gRenderReady = false;
        if (updateStage) {
            gLastErrorStage = "cleared_no_model";
        }
        return;
    }

    void* liveContext = currentContext();
    void* modelContext = readField<void*>(gModel, 0x2C);
    if (liveContext != nullptr && liveContext == gContext && modelContext == gContext) {
        reinterpret_cast<SetBooleanProc>(kAttachToRenderListAddress)(gModel, 0);
        reinterpret_cast<ReleaseModelProc>(kReleaseModelAddress)(gModel);
        ++gReleaseCalls;
        if (updateStage) {
            gLastErrorStage = "cleared";
        }
    }
    else {
        // A loading screen can destroy the old scene and every model it owned.
        // Never dereference or release a pointer owned by that stale context.
        ++gDroppedStalePointers;
        if (updateStage) {
            gLastErrorStage = "cleared_stale_context";
        }
    }

    gModel = nullptr;
    gContext = nullptr;
    gPlayerObject = 0;
    gPosition = {};
    gActive = false;
    gRenderReady = false;
}

bool pollRenderReady(int requestLoad) {
    if (gModel == nullptr) {
        return false;
    }
    ++gLoadChecks;
    const bool ready = reinterpret_cast<EnsureRenderReadyProc>(kEnsureRenderReadyAddress)(
        gModel, requestLoad, 1) != 0;
    if (ready && !gRenderReady) {
        gRenderReady = true;
        ++gLoadReadyTransitions;
    }
    return ready;
}

bool createModelAt(const C3Vector& position, std::uint32_t playerObject) {
    gLastErrorStage = "validate_world_position";
    if (!std::isfinite(position.x) || !std::isfinite(position.y)
        || !std::isfinite(position.z)) {
        return false;
    }

    gPlayerObject = playerObject;
    gPosition = position;

    gLastErrorStage = "find_world_context";
    gContext = currentContext();
    if (gContext == nullptr) {
        return false;
    }

    gLastErrorStage = "create_model";
    ++gCreateCalls;
    gModel = reinterpret_cast<CreateModelProc>(kCreateModelAddress)(
        gContext, kMoonBeamPath, 0);
    if (gModel == nullptr) {
        return false;
    }
    ++gCreateSuccesses;

    if (readField<void*>(gModel, 0x2C) != gContext) {
        gLastErrorStage = "model_context_mismatch";
        releaseCurrent(false);
        return false;
    }

    gLastErrorStage = "set_world_matrix";
    applyWorldMatrix();

    const C3Vector white = {1.0f, 1.0f, 1.0f};
    reinterpret_cast<SetAlphaProc>(kSetAlphaAddress)(gModel, 1.0f);
    reinterpret_cast<SetColorProc>(kSetColorAddress)(gModel, &white);
    reinterpret_cast<SetSequenceProc>(kSetSequenceAddress)(
        gModel, -1, 0, -1, 0, 1.0f, 1, 1);

    // These two calls are present in the client's real world-effect path.
    // 0x710B90 links the model into M2Scene's active render list; merely
    // creating it only links it into the general ownership list.
    gLastErrorStage = "attach_render_list";
    reinterpret_cast<SetBooleanProc>(kSetActiveTimestampAddress)(gModel, 1);
    reinterpret_cast<SetBooleanProc>(kAttachToRenderListAddress)(gModel, 1);
    gActive = true;

    if (readField<void*>(gModel, 0x44) == nullptr) {
        gLastErrorStage = "render_list_link_missing";
        releaseCurrent(false);
        return false;
    }

    gLastErrorStage = "request_model_resources";
    if (pollRenderReady(1)) {
        gLastErrorStage = "active_ready";
    }
    else {
        gLastErrorStage = "active_waiting_resources";
    }
    return true;
}

} // namespace

bool createNearPlayer(C3Vector& position) {
    releaseCurrent(false);
    gLastErrorStage = "find_player";

    const std::uint64_t playerGuid = vanilla1121_unitGUID("player");
    gPlayerObject = vanilla1121_getVisiableObject(playerGuid);
    if (gPlayerObject == 0 || (gPlayerObject & 1u) != 0u) {
        gPlayerObject = 0;
        return false;
    }

    C3Vector playerPosition = vanilla1121_unitPosition(gPlayerObject);
    const float facing = vanilla1121_unitFacing(gPlayerObject);
    if (!std::isfinite(playerPosition.x) || !std::isfinite(playerPosition.y)
        || !std::isfinite(playerPosition.z) || !std::isfinite(facing)) {
        gLastErrorStage = "invalid_player_position";
        return false;
    }

    C3Vector testPosition = {};
    testPosition.x = playerPosition.x + std::cos(facing) * 4.0f;
    testPosition.y = playerPosition.y + std::sin(facing) * 4.0f;
    testPosition.z = playerPosition.z + 0.05f;
    position = testPosition;
    return createModelAt(testPosition, gPlayerObject);
}

bool createAt(const C3Vector& position) {
    releaseCurrent(false);
    return createModelAt(position, 0);
}

void update() {
    if (!gActive || gModel == nullptr) {
        return;
    }

    void* liveContext = currentContext();
    if (liveContext == nullptr || liveContext != gContext) {
        ++gDroppedStalePointers;
        gModel = nullptr;
        gContext = nullptr;
        gActive = false;
        gRenderReady = false;
        gLastErrorStage = "world_context_changed";
        return;
    }

    ++gUpdateCalls;
    applyWorldMatrix();
    reinterpret_cast<SetBooleanProc>(kSetActiveTimestampAddress)(gModel, 1);

    // One-shot impact models can unlink themselves from M2Scene's active list
    // while the CM2Model object and its loaded resources remain alive. Keep
    // this test deliberately narrow: re-use the already validated attach call
    // without changing sequence state or touching another unknown interface.
    if (readField<void*>(gModel, 0x44) == nullptr) {
        ++gReattachCalls;
        gLastErrorStage = "reattach_render_list";
        reinterpret_cast<SetBooleanProc>(kAttachToRenderListAddress)(gModel, 1);
        if (readField<void*>(gModel, 0x44) == nullptr) {
            gLastErrorStage = "reattach_failed";
            return;
        }
        ++gReattachSuccesses;
    }

    if (pollRenderReady(0)) {
        gLastErrorStage = "active_ready";
    }
    else {
        gLastErrorStage = "active_waiting_resources";
    }
}

void clear() {
    releaseCurrent(true);
}

Status status() {
    Status result = {};
    void* liveContext = currentContext();
    result.active = gActive;
    result.contextExists = liveContext != nullptr;
    result.contextMatches = liveContext != nullptr && liveContext == gContext;
    result.contextPointer = static_cast<std::uint32_t>(reinterpret_cast<std::uintptr_t>(liveContext));
    result.playerObjectPointer = gPlayerObject;
    result.modelPointer = static_cast<std::uint32_t>(reinterpret_cast<std::uintptr_t>(gModel));
    result.createCalls = gCreateCalls;
    result.createSuccesses = gCreateSuccesses;
    result.updateCalls = gUpdateCalls;
    result.reattachCalls = gReattachCalls;
    result.reattachSuccesses = gReattachSuccesses;
    result.releaseCalls = gReleaseCalls;
    result.droppedStalePointers = gDroppedStalePointers;
    result.loadChecks = gLoadChecks;
    result.loadReadyTransitions = gLoadReadyTransitions;
    result.position = gPosition;
    result.lastErrorStage = gLastErrorStage;
    result.renderReady = gRenderReady;

    if (gModel != nullptr && result.contextMatches) {
        result.modelContextPointer = static_cast<std::uint32_t>(
            reinterpret_cast<std::uintptr_t>(readField<void*>(gModel, 0x2C)));
        result.modelRefCount = readField<std::uint32_t>(gModel, 0x00);
        result.resourceReady = readField<void*>(gModel, 0x10) != nullptr;
        result.attachedToRenderList = readField<void*>(gModel, 0x44) != nullptr;
        result.modelUpdateMarker = readField<std::uint32_t>(gModel, 0x50);
    }
    return result;
}

} // namespace nativeM2Test
