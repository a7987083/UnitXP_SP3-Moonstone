#include "dirkNativeCreate.h"

#include <Windows.h>
#include <cstddef>
#include <cstdint>
#include <cmath>
#include <iomanip>
#include <sstream>
#include <string>

#include "Vanilla1121_functions.h"

namespace dirkNativeCreate {
namespace {

// Addresses verified against the user's current 1.12/Turtle client by DirkNativeDump-v4.
constexpr std::uintptr_t kEffectTablePtrAddress = 0x00C0D760;
constexpr std::uintptr_t kEffectTableMaxIndexAddress = 0x00C0D764;
constexpr std::uintptr_t kSMemAllocAddress = 0x006462E0;
constexpr std::uintptr_t kCEffectCtorAddress = 0x0061F490;
constexpr std::uintptr_t kClientTickAddress = 0x0042C010;
constexpr std::uintptr_t kCEffectInitAddress = 0x0061FCF0;
constexpr std::uintptr_t kOneShotCompleteCallback = 0x005FBF50;
constexpr std::uintptr_t kClientAllocFileString = 0x0086FA64;
constexpr int kClientAllocLine = 0x0D82;
constexpr std::size_t kCEffectSize = 0x90;

// CM2 methods already validated by the earlier local M2 experiment.
constexpr std::uintptr_t kSetTransformAddress = 0x00710650;
constexpr std::uintptr_t kSetSequenceAddress = 0x007121A0;
constexpr std::uintptr_t kSetActiveTimestampAddress = 0x00710C50;
constexpr std::uintptr_t kAttachToRenderListAddress = 0x00710B90;
constexpr std::uintptr_t kEnsureRenderReadyAddress = 0x00710450;
constexpr int kDynamicObjectLoopSequence = 0x9E;

constexpr std::uint32_t kPreEffectId = 4501;
constexpr std::uint32_t kCastEffectId = 4502;
constexpr std::uint32_t kPreMetadata5 = 36834;
constexpr std::uint32_t kCastMetadata5 = 36835;

using SMemAllocProc = void* (__cdecl*)(std::size_t, const char*, int, int);
using CEffectCtorProc = void* (__thiscall*)(void*);
using ClientTickProc = std::uint32_t (__cdecl*)();
using SetTransformProc = void (__thiscall*)(void*, const C3Vector*, float, const C3Vector*, const C3Vector*);
using SetSequenceProc = void (__thiscall*)(void*, int, int, int, int, float, int, int);
using SetBooleanProc = void (__thiscall*)(void*, int);
using EnsureRenderReadyProc = int (__thiscall*)(void*, int, int);

// Recovered from the GO-destination call site at 0x6E80F0..0x6E8143 and
// CEffect initializer at 0x61FCF0 (RET 0x28 => ten 32-bit stack args).
// Only the fields proven by the v4 disassembly are named here. arg5 remains opaque.
using CEffectInitProc = void (__thiscall*)(
    void*,
    float, float, float,
    std::uint32_t,
    std::uint32_t,
    std::uint32_t,
    void*,
    const std::uint64_t*,
    std::uint32_t,
    void*);

bool readable(std::uintptr_t address, std::size_t bytes) {
    std::uintptr_t cur = address;
    const std::uintptr_t end = address + bytes;
    while (cur < end) {
        MEMORY_BASIC_INFORMATION mbi = {};
        if (VirtualQuery(reinterpret_cast<LPCVOID>(cur), &mbi, sizeof(mbi)) != sizeof(mbi)) return false;
        if (mbi.State != MEM_COMMIT || (mbi.Protect & PAGE_GUARD) || (mbi.Protect & PAGE_NOACCESS)) return false;
        const DWORD p = mbi.Protect & 0xff;
        const bool ok = p == PAGE_READONLY || p == PAGE_READWRITE || p == PAGE_WRITECOPY ||
                        p == PAGE_EXECUTE_READ || p == PAGE_EXECUTE_READWRITE || p == PAGE_EXECUTE_WRITECOPY;
        if (!ok) return false;
        const std::uintptr_t next = reinterpret_cast<std::uintptr_t>(mbi.BaseAddress) + mbi.RegionSize;
        if (next <= cur) return false;
        cur = next < end ? next : end;
    }
    return true;
}

void* effectRow(std::uint32_t effectId, std::string& why) {
    if (!readable(kEffectTablePtrAddress, sizeof(void*)) ||
        !readable(kEffectTableMaxIndexAddress, sizeof(std::uint32_t))) {
        why = "effect_table_globals_unreadable";
        return nullptr;
    }
    const std::uint32_t maxIndex = *reinterpret_cast<const std::uint32_t*>(kEffectTableMaxIndexAddress);
    void** table = *reinterpret_cast<void***>(kEffectTablePtrAddress);
    if (!table) { why = "effect_table_null"; return nullptr; }
    if (effectId > maxIndex) {
        std::ostringstream ss; ss << "effect_id_out_of_range id=" << effectId << " max=" << maxIndex;
        why = ss.str(); return nullptr;
    }
    if (!readable(reinterpret_cast<std::uintptr_t>(table) + effectId * sizeof(void*), sizeof(void*))) {
        why = "effect_table_slot_unreadable"; return nullptr;
    }
    void* row = table[effectId];
    if (!row || !readable(reinterpret_cast<std::uintptr_t>(row), 20)) {
        why = "effect_row_missing"; return nullptr;
    }
    const std::uint32_t rowId = *reinterpret_cast<const std::uint32_t*>(row);
    if (rowId != effectId) {
        std::ostringstream ss; ss << "effect_row_id_mismatch got=" << rowId << " wanted=" << effectId;
        why = ss.str(); return nullptr;
    }
    return row;
}

bool playerPose(std::uint64_t& guid, C3Vector& pos, float& facing, std::string& why) {
    guid = vanilla1121_unitGUID("player");
    if (!guid) { why = "player_guid_zero"; return false; }
    const std::uint32_t player = vanilla1121_getVisiableObject(guid);
    if (!player || (player & 1u)) { why = "player_object_unavailable"; return false; }
    pos = vanilla1121_unitPosition(player);
    facing = vanilla1121_unitFacing(player);
    if (!std::isfinite(pos.x) || !std::isfinite(pos.y) || !std::isfinite(pos.z) || !std::isfinite(facing)) {
        why = "invalid_player_pose"; return false;
    }
    return true;
}

bool applyDynamicObjectPose(void* node, const C3Vector& pos, float facing, std::string& why, void*& modelOut) {
    modelOut = nullptr;
    if (!node || !readable(reinterpret_cast<std::uintptr_t>(node), sizeof(void*))) {
        why = "ceffect_node_unreadable";
        return false;
    }

    // 0x61FCF0 stores the created CM2 pointer at CEffect+0x00.
    void* model = *reinterpret_cast<void**>(node);
    modelOut = model;
    if (!model || !readable(reinterpret_cast<std::uintptr_t>(model), 0x48)) {
        why = "ceffect_model_unavailable";
        return false;
    }

    const C3Vector up = {0.0f, 0.0f, 1.0f};
    const C3Vector scale = {1.0f, 1.0f, 1.0f};
    reinterpret_cast<SetTransformProc>(kSetTransformAddress)(model, &pos, facing, &up, &scale);

    // DynamicObject Visual A uses Hold/loop sequence 0x9E. Earlier CM2-only tests had
    // this sequence but lacked the ground/decal CEffect path; v2 deliberately combines both.
    reinterpret_cast<SetSequenceProc>(kSetSequenceAddress)(
        model, -1, kDynamicObjectLoopSequence, -1, 0, 1.0f, 1, 1);

    // Keep the CEffect-created model on the live world render list after changing its pose/sequence.
    reinterpret_cast<SetBooleanProc>(kSetActiveTimestampAddress)(model, 1);
    reinterpret_cast<SetBooleanProc>(kAttachToRenderListAddress)(model, 1);
    reinterpret_cast<EnsureRenderReadyProc>(kEnsureRenderReadyAddress)(model, 1, 1);
    return true;
}

bool spawnEffect(std::uint32_t effectId, std::uint32_t opaque5, std::string& status) {
    status.clear();
    std::string why;
    void* row = effectRow(effectId, why);
    if (!row) { status = why; return false; }

    std::uint64_t guid = 0;
    C3Vector pos = {};
    float facing = 0.0f;
    if (!playerPose(guid, pos, facing, why)) { status = why; return false; }

    auto smemAlloc = reinterpret_cast<SMemAllocProc>(kSMemAllocAddress);
    auto ctor = reinterpret_cast<CEffectCtorProc>(kCEffectCtorAddress);
    auto tick = reinterpret_cast<ClientTickProc>(kClientTickAddress);
    auto init = reinterpret_cast<CEffectInitProc>(kCEffectInitAddress);

    void* mem = smemAlloc(kCEffectSize, reinterpret_cast<const char*>(kClientAllocFileString), kClientAllocLine, 0);
    if (!mem) { status = "smemalloc_failed"; return false; }
    void* node = ctor(mem);
    if (!node) { status = "ceffect_ctor_failed"; return false; }

    const std::uint32_t now = tick();

    // First create through the proven destination/world-ground CEffect path. v1 proved this
    // renders the authored ground/decal pieces. We no longer describe arg5 as a spell id;
    // its exact semantic is still unpinned, so the known working value is retained as opaque metadata.
    init(node,
         pos.x, pos.y, pos.z,
         now,
         opaque5,
         0,
         row,
         &guid,
         0,
         reinterpret_cast<void*>(kOneShotCompleteCallback));

    void* model = nullptr;
    const bool posed = applyDynamicObjectPose(node, pos, facing, why, model);

    std::ostringstream ss;
    ss << (posed ? "native_ceffect_dynpose" : "native_ceffect_created_pose_failed")
       << " effect=" << effectId
       << " row=0x" << std::hex << reinterpret_cast<std::uintptr_t>(row)
       << " node=0x" << reinterpret_cast<std::uintptr_t>(node)
       << " model=0x" << reinterpret_cast<std::uintptr_t>(model) << std::dec
       << " pos=(" << pos.x << ',' << pos.y << ',' << pos.z << ')'
       << " facing=" << facing
       << " seq=" << kDynamicObjectLoopSequence
       << " tick=" << now;
    if (!posed) ss << " reason=" << why;
    status = ss.str();
    return posed;
}

} // namespace

bool spawnPre(std::string& status) {
    return spawnEffect(kPreEffectId, kPreMetadata5, status);
}

bool spawnCast(std::string& status) {
    return spawnEffect(kCastEffectId, kCastMetadata5, status);
}

} // namespace dirkNativeCreate
