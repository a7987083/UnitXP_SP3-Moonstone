#define _USE_MATH_DEFINES

#include "nativeM2Test.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

#include <Windows.h>

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

constexpr std::size_t kSlotCount = 8;
constexpr std::size_t kIconCount = 8;
constexpr float kIconWorldHeight = 8.5f;
constexpr float kBaseIconPixels = 42.0f;
constexpr DWORD kIconFVF = D3DFVF_XYZRHW | D3DFVF_DIFFUSE;

using CreateModelProc = void* (__thiscall*)(void*, const char*, std::uint32_t);
using ReleaseModelProc = void (__thiscall*)(void*);
using EnsureRenderReadyProc = int (__thiscall*)(void*, int, int);
using SetWorldMatrixProc = void (__thiscall*)(void*, const float*);
using SetBooleanProc = void (__thiscall*)(void*, int);
using SetAlphaProc = void (__thiscall*)(void*, float);
using SetColorProc = void (__thiscall*)(void*, const C3Vector*);
using SetSequenceProc = void (__thiscall*)(void*, int, int, int, int, float, int, int);

struct ColorDefinition {
    const char* name;
    C3Vector value;
    int defaultIcon;
};

constexpr std::array<ColorDefinition, kSlotCount> kColors = {{
    {"red",    {1.00f, 0.18f, 0.18f}, 6},
    {"orange", {1.00f, 0.45f, 0.10f}, 1},
    {"yellow", {1.00f, 0.82f, 0.16f}, 0},
    {"green",  {0.15f, 0.92f, 0.28f}, 3},
    {"cyan",   {0.10f, 0.90f, 0.90f}, 4},
    {"blue",   {0.20f, 0.55f, 1.00f}, 5},
    {"purple", {0.68f, 0.28f, 1.00f}, 2},
    {"white",  {0.86f, 0.92f, 1.00f}, 7},
}};

constexpr std::array<const char*, kIconCount> kIconNames = {{
    "star", "circle", "diamond", "triangle",
    "moon", "square", "cross", "skull"
}};

struct Slot {
    void* context = nullptr;
    void* model = nullptr;
    std::uint32_t playerObject = 0;
    C3Vector position = {};
    bool active = false;
    bool renderReady = false;
    int iconIndex = 0;
};

struct ProjectedIcon {
    bool visible = false;
    float x = 0.0f;
    float y = 0.0f;
    float size = 0.0f;
    int colorIndex = 0;
    int iconIndex = 0;
};

struct IconVertex {
    float x;
    float y;
    float z;
    float rhw;
    D3DCOLOR color;
};

std::array<Slot, kSlotCount> gSlots = {};
std::array<ProjectedIcon, kSlotCount> gProjected = {};
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

std::string lowerAscii(std::string value) {
    for (char& c : value) {
        if (c >= 'A' && c <= 'Z') {
            c = static_cast<char>(c - 'A' + 'a');
        }
    }
    return value;
}

int colorIndex(const std::string& colorName) {
    const std::string normalized = lowerAscii(colorName);
    for (std::size_t i = 0; i < kColors.size(); ++i) {
        if (normalized == kColors[i].name) {
            return static_cast<int>(i);
        }
    }
    return -1;
}

int iconIndex(const std::string& iconName) {
    const std::string normalized = lowerAscii(iconName);
    for (std::size_t i = 0; i < kIconNames.size(); ++i) {
        if (normalized == kIconNames[i]) {
            return static_cast<int>(i);
        }
    }
    if (normalized == "x") return 6;
    if (normalized.size() == 1 && normalized[0] >= '1' && normalized[0] <= '8') {
        return normalized[0] - '1';
    }
    return -1;
}

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
    for (float& value : matrix) value = 0.0f;
    matrix[0] = 1.0f;
    matrix[5] = 1.0f;
    matrix[10] = 1.0f;
    matrix[15] = 1.0f;
    matrix[12] = position.x;
    matrix[13] = position.y;
    matrix[14] = position.z;
}

void applyWorldMatrix(Slot& slot) {
    if (slot.model == nullptr) return;
    float matrix[16] = {};
    buildWorldMatrix(slot.position, matrix);
    reinterpret_cast<SetWorldMatrixProc>(kSetWorldMatrixAddress)(slot.model, matrix);
}

void resetSlot(Slot& slot) {
    slot.context = nullptr;
    slot.model = nullptr;
    slot.playerObject = 0;
    slot.position = {};
    slot.active = false;
    slot.renderReady = false;
    slot.iconIndex = 0;
}

void releaseSlot(Slot& slot, bool updateStage) {
    if (slot.model == nullptr) {
        resetSlot(slot);
        if (updateStage) gLastErrorStage = "cleared_no_model";
        return;
    }

    void* liveContext = currentContext();
    void* modelContext = readField<void*>(slot.model, 0x2C);
    if (liveContext != nullptr && liveContext == slot.context && modelContext == slot.context) {
        reinterpret_cast<SetBooleanProc>(kAttachToRenderListAddress)(slot.model, 0);
        reinterpret_cast<ReleaseModelProc>(kReleaseModelAddress)(slot.model);
        ++gReleaseCalls;
        if (updateStage) gLastErrorStage = "cleared";
    }
    else {
        ++gDroppedStalePointers;
        if (updateStage) gLastErrorStage = "cleared_stale_context";
    }
    resetSlot(slot);
}

bool pollRenderReady(Slot& slot, int requestLoad) {
    if (slot.model == nullptr) return false;
    ++gLoadChecks;
    const bool ready = reinterpret_cast<EnsureRenderReadyProc>(kEnsureRenderReadyAddress)(
        slot.model, requestLoad, 1) != 0;
    if (ready && !slot.renderReady) {
        slot.renderReady = true;
        ++gLoadReadyTransitions;
    }
    return ready;
}

bool createModelAt(int selectedColor, int selectedIcon, const C3Vector& position,
                   std::uint32_t playerObject) {
    gLastErrorStage = "validate_world_position";
    if (selectedColor < 0 || selectedColor >= static_cast<int>(kSlotCount)
        || selectedIcon < 0 || selectedIcon >= static_cast<int>(kIconCount)
        || !std::isfinite(position.x) || !std::isfinite(position.y)
        || !std::isfinite(position.z)) {
        return false;
    }

    Slot& slot = gSlots[static_cast<std::size_t>(selectedColor)];
    releaseSlot(slot, false);
    slot.playerObject = playerObject;
    slot.position = position;
    slot.iconIndex = selectedIcon;

    gLastErrorStage = "find_world_context";
    slot.context = currentContext();
    if (slot.context == nullptr) {
        resetSlot(slot);
        return false;
    }

    gLastErrorStage = "create_model";
    ++gCreateCalls;
    slot.model = reinterpret_cast<CreateModelProc>(kCreateModelAddress)(
        slot.context, kMoonBeamPath, 0);
    if (slot.model == nullptr) {
        resetSlot(slot);
        return false;
    }
    ++gCreateSuccesses;

    if (readField<void*>(slot.model, 0x2C) != slot.context) {
        gLastErrorStage = "model_context_mismatch";
        releaseSlot(slot, false);
        return false;
    }

    gLastErrorStage = "set_world_matrix";
    applyWorldMatrix(slot);
    reinterpret_cast<SetAlphaProc>(kSetAlphaAddress)(slot.model, 1.0f);
    reinterpret_cast<SetColorProc>(kSetColorAddress)(
        slot.model, &kColors[static_cast<std::size_t>(selectedColor)].value);
    reinterpret_cast<SetSequenceProc>(kSetSequenceAddress)(
        slot.model, -1, 0, -1, 0, 1.0f, 1, 1);

    gLastErrorStage = "attach_render_list";
    reinterpret_cast<SetBooleanProc>(kSetActiveTimestampAddress)(slot.model, 1);
    reinterpret_cast<SetBooleanProc>(kAttachToRenderListAddress)(slot.model, 1);
    slot.active = true;

    if (readField<void*>(slot.model, 0x44) == nullptr) {
        gLastErrorStage = "render_list_link_missing";
        releaseSlot(slot, false);
        return false;
    }

    gLastErrorStage = "request_model_resources";
    gLastErrorStage = pollRenderReady(slot, 1)
        ? "active_ready" : "active_waiting_resources";
    return true;
}

D3DCOLOR colorValue(int selectedColor, int alpha) {
    const C3Vector& value = kColors[static_cast<std::size_t>(selectedColor)].value;
    const int r = static_cast<int>(std::max(0.0f, std::min(1.0f, value.x)) * 255.0f);
    const int g = static_cast<int>(std::max(0.0f, std::min(1.0f, value.y)) * 255.0f);
    const int b = static_cast<int>(std::max(0.0f, std::min(1.0f, value.z)) * 255.0f);
    return D3DCOLOR_ARGB(alpha, r, g, b);
}

void appendTriangle(std::vector<IconVertex>& output,
                    float ax, float ay, float bx, float by, float cx, float cy,
                    D3DCOLOR color) {
    output.push_back({ax, ay, 0.0f, 1.0f, color});
    output.push_back({bx, by, 0.0f, 1.0f, color});
    output.push_back({cx, cy, 0.0f, 1.0f, color});
}

void appendQuad(std::vector<IconVertex>& output,
                float ax, float ay, float bx, float by,
                float cx, float cy, float dx, float dy,
                D3DCOLOR color) {
    appendTriangle(output, ax, ay, bx, by, cx, cy, color);
    appendTriangle(output, cx, cy, bx, by, dx, dy, color);
}

void appendRect(std::vector<IconVertex>& output, float cx, float cy,
                float width, float height, float angle, D3DCOLOR color) {
    const float cs = std::cos(angle);
    const float sn = std::sin(angle);
    const float hx = width * 0.5f;
    const float hy = height * 0.5f;
    const float localX[4] = {-hx, hx, -hx, hx};
    const float localY[4] = {-hy, -hy, hy, hy};
    float x[4] = {};
    float y[4] = {};
    for (int i = 0; i < 4; ++i) {
        x[i] = cx + localX[i] * cs - localY[i] * sn;
        y[i] = cy + localX[i] * sn + localY[i] * cs;
    }
    appendQuad(output, x[0], y[0], x[1], y[1], x[2], y[2], x[3], y[3], color);
}

void appendDisc(std::vector<IconVertex>& output, float cx, float cy,
                float radius, D3DCOLOR color, int segments = 28) {
    const float step = 2.0f * static_cast<float>(M_PI) / static_cast<float>(segments);
    for (int i = 0; i < segments; ++i) {
        const float a = step * static_cast<float>(i);
        const float b = step * static_cast<float>(i + 1);
        appendTriangle(output, cx, cy,
            cx + std::cos(a) * radius, cy + std::sin(a) * radius,
            cx + std::cos(b) * radius, cy + std::sin(b) * radius,
            color);
    }
}

void appendRing(std::vector<IconVertex>& output, float cx, float cy,
                float outerRadius, float innerRadius, D3DCOLOR color,
                float startAngle = 0.0f,
                float endAngle = 2.0f * static_cast<float>(M_PI),
                int segments = 32) {
    const float step = (endAngle - startAngle) / static_cast<float>(segments);
    for (int i = 0; i < segments; ++i) {
        const float a = startAngle + step * static_cast<float>(i);
        const float b = startAngle + step * static_cast<float>(i + 1);
        const float ax = cx + std::cos(a) * outerRadius;
        const float ay = cy + std::sin(a) * outerRadius;
        const float bx = cx + std::cos(b) * outerRadius;
        const float by = cy + std::sin(b) * outerRadius;
        const float cx0 = cx + std::cos(a) * innerRadius;
        const float cy0 = cy + std::sin(a) * innerRadius;
        const float dx = cx + std::cos(b) * innerRadius;
        const float dy = cy + std::sin(b) * innerRadius;
        appendQuad(output, ax, ay, bx, by, cx0, cy0, dx, dy, color);
    }
}

void appendStar(std::vector<IconVertex>& output, float cx, float cy,
                float radius, D3DCOLOR color) {
    constexpr int points = 10;
    float x[points] = {};
    float y[points] = {};
    for (int i = 0; i < points; ++i) {
        const float angle = -static_cast<float>(M_PI) * 0.5f
            + static_cast<float>(i) * static_cast<float>(M_PI) / 5.0f;
        const float currentRadius = (i % 2 == 0) ? radius : radius * 0.42f;
        x[i] = cx + std::cos(angle) * currentRadius;
        y[i] = cy + std::sin(angle) * currentRadius;
    }
    for (int i = 1; i < points - 1; ++i) {
        appendTriangle(output, x[0], y[0], x[i], y[i], x[i + 1], y[i + 1], color);
    }
}

void appendShape(std::vector<IconVertex>& output, int selectedIcon,
                 float cx, float cy, float size, D3DCOLOR color) {
    const float radius = size * 0.5f;
    switch (selectedIcon) {
    case 0:
        appendStar(output, cx, cy, radius, color);
        break;
    case 1:
        appendRing(output, cx, cy, radius, radius * 0.67f, color);
        break;
    case 2:
        appendQuad(output,
            cx, cy - radius,
            cx + radius, cy,
            cx - radius, cy,
            cx, cy + radius,
            color);
        break;
    case 3:
        appendTriangle(output,
            cx, cy - radius,
            cx - radius * 0.94f, cy + radius * 0.82f,
            cx + radius * 0.94f, cy + radius * 0.82f,
            color);
        break;
    case 4:
        appendRing(output, cx, cy, radius, radius * 0.62f, color,
            -2.25f, 2.25f, 28);
        break;
    case 5:
        appendQuad(output,
            cx - radius, cy - radius,
            cx + radius, cy - radius,
            cx - radius, cy + radius,
            cx + radius, cy + radius,
            color);
        break;
    case 6:
        appendRect(output, cx, cy, size * 0.28f, size * 1.18f,
            static_cast<float>(M_PI) * 0.25f, color);
        appendRect(output, cx, cy, size * 0.28f, size * 1.18f,
            -static_cast<float>(M_PI) * 0.25f, color);
        break;
    case 7:
        appendDisc(output, cx, cy - size * 0.10f, radius * 0.82f, color, 24);
        appendRect(output, cx, cy + size * 0.28f, size * 0.58f, size * 0.38f, 0.0f, color);
        break;
    default:
        break;
    }
}

void appendSkullCutouts(std::vector<IconVertex>& output, float cx, float cy,
                        float size, D3DCOLOR color) {
    appendDisc(output, cx - size * 0.16f, cy - size * 0.12f, size * 0.09f, color, 14);
    appendDisc(output, cx + size * 0.16f, cy - size * 0.12f, size * 0.09f, color, 14);
    appendTriangle(output,
        cx, cy + size * 0.02f,
        cx - size * 0.06f, cy + size * 0.15f,
        cx + size * 0.06f, cy + size * 0.15f,
        color);
    appendRect(output, cx - size * 0.11f, cy + size * 0.33f,
        size * 0.06f, size * 0.22f, 0.0f, color);
    appendRect(output, cx, cy + size * 0.33f,
        size * 0.06f, size * 0.22f, 0.0f, color);
    appendRect(output, cx + size * 0.11f, cy + size * 0.33f,
        size * 0.06f, size * 0.22f, 0.0f, color);
}

void resetProjected() {
    for (ProjectedIcon& icon : gProjected) icon.visible = false;
}

void projectSlot(std::size_t index) {
    ProjectedIcon& projected = gProjected[index];
    projected.visible = false;
    Slot& slot = gSlots[index];
    if (!slot.active || slot.model == nullptr) return;

    C3Vector world = slot.position;
    world.z += kIconWorldHeight;
    C3Vector screen = vanilla1121_worldToScreen(world);
    const RECT client = vanilla1121_gameClientRect();
    const float width = static_cast<float>(client.right - client.left);
    const float height = static_cast<float>(client.bottom - client.top);
    if (!std::isfinite(screen.x) || !std::isfinite(screen.y)
        || width <= 1.0f || height <= 1.0f
        || screen.x < 0.0f || screen.y < 0.0f
        || screen.x > width || screen.y > height) {
        return;
    }

    projected.visible = true;
    projected.x = screen.x;
    projected.y = screen.y;
    projected.size = std::max(30.0f, std::min(58.0f,
        kBaseIconPixels * height / 768.0f));
    projected.colorIndex = static_cast<int>(index);
    projected.iconIndex = slot.iconIndex;
}

} // namespace

bool createNearPlayer(C3Vector& position) {
    gLastErrorStage = "find_player";
    const std::uint64_t playerGuid = vanilla1121_unitGUID("player");
    const std::uint32_t playerObject = vanilla1121_getVisiableObject(playerGuid);
    if (playerObject == 0 || (playerObject & 1u) != 0u) return false;

    const C3Vector playerPosition = vanilla1121_unitPosition(playerObject);
    const float facing = vanilla1121_unitFacing(playerObject);
    if (!std::isfinite(playerPosition.x) || !std::isfinite(playerPosition.y)
        || !std::isfinite(playerPosition.z) || !std::isfinite(facing)) {
        gLastErrorStage = "invalid_player_position";
        return false;
    }

    position.x = playerPosition.x + std::cos(facing) * 4.0f;
    position.y = playerPosition.y + std::sin(facing) * 4.0f;
    position.z = playerPosition.z + 0.05f;
    return createModelAt(7, 0, position, playerObject);
}

bool createAt(const C3Vector& position) {
    return createModelAt(7, 0, position, 0);
}

bool createAt(const std::string& colorName, const std::string& iconName,
              const C3Vector& position) {
    const int selectedColor = colorIndex(colorName);
    if (selectedColor < 0) {
        gLastErrorStage = "unknown_color";
        return false;
    }
    int selectedIcon = iconIndex(iconName);
    if (selectedIcon < 0) {
        selectedIcon = kColors[static_cast<std::size_t>(selectedColor)].defaultIcon;
    }
    return createModelAt(selectedColor, selectedIcon, position, 0);
}

bool clearColor(const std::string& colorName) {
    const int selectedColor = colorIndex(colorName);
    if (selectedColor < 0) return false;
    releaseSlot(gSlots[static_cast<std::size_t>(selectedColor)], true);
    gProjected[static_cast<std::size_t>(selectedColor)].visible = false;
    return true;
}

std::string defaultIconForColor(const std::string& colorName) {
    const int selectedColor = colorIndex(colorName);
    if (selectedColor < 0) return "star";
    return kIconNames[static_cast<std::size_t>(
        kColors[static_cast<std::size_t>(selectedColor)].defaultIcon)];
}

std::string iconForColor(const std::string& colorName) {
    const int selectedColor = colorIndex(colorName);
    if (selectedColor < 0) return "";
    const Slot& slot = gSlots[static_cast<std::size_t>(selectedColor)];
    if (!slot.active || slot.iconIndex < 0 || slot.iconIndex >= static_cast<int>(kIconCount)) {
        return defaultIconForColor(colorName);
    }
    return kIconNames[static_cast<std::size_t>(slot.iconIndex)];
}

void update() {
    resetProjected();
    void* liveContext = currentContext();
    for (std::size_t i = 0; i < gSlots.size(); ++i) {
        Slot& slot = gSlots[i];
        if (!slot.active || slot.model == nullptr) continue;
        if (liveContext == nullptr || liveContext != slot.context) {
            ++gDroppedStalePointers;
            resetSlot(slot);
            gLastErrorStage = "world_context_changed";
            continue;
        }

        ++gUpdateCalls;
        applyWorldMatrix(slot);
        reinterpret_cast<SetBooleanProc>(kSetActiveTimestampAddress)(slot.model, 1);
        if (readField<void*>(slot.model, 0x44) == nullptr) {
            ++gReattachCalls;
            gLastErrorStage = "reattach_render_list";
            reinterpret_cast<SetBooleanProc>(kAttachToRenderListAddress)(slot.model, 1);
            if (readField<void*>(slot.model, 0x44) == nullptr) {
                gLastErrorStage = "reattach_failed";
                continue;
            }
            ++gReattachSuccesses;
        }
        gLastErrorStage = pollRenderReady(slot, 0)
            ? "active_ready" : "active_waiting_resources";
        projectSlot(i);
    }
}

void renderIcons(IDirect3DDevice9* device) {
    if (device == nullptr) return;

    std::vector<IconVertex> vertices;
    vertices.reserve(2400);
    const D3DCOLOR outline = D3DCOLOR_ARGB(210, 8, 8, 12);
    const D3DCOLOR cutout = D3DCOLOR_ARGB(235, 10, 10, 14);
    for (const ProjectedIcon& icon : gProjected) {
        if (!icon.visible) continue;
        appendShape(vertices, icon.iconIndex, icon.x, icon.y,
            icon.size + 6.0f, outline);
        appendShape(vertices, icon.iconIndex, icon.x, icon.y,
            icon.size, colorValue(icon.colorIndex, 245));
        if (icon.iconIndex == 7) {
            appendSkullCutouts(vertices, icon.x, icon.y, icon.size, cutout);
        }
    }
    if (vertices.empty()) return;

    IDirect3DStateBlock9* state = nullptr;
    if (FAILED(device->CreateStateBlock(D3DSBT_ALL, &state)) || state == nullptr) return;
    state->Capture();

    device->SetTexture(0, nullptr);
    device->SetVertexShader(nullptr);
    device->SetPixelShader(nullptr);
    device->SetRenderState(D3DRS_ZENABLE, FALSE);
    device->SetRenderState(D3DRS_ZWRITEENABLE, FALSE);
    device->SetRenderState(D3DRS_LIGHTING, FALSE);
    device->SetRenderState(D3DRS_CULLMODE, D3DCULL_NONE);
    device->SetRenderState(D3DRS_ALPHATESTENABLE, FALSE);
    device->SetRenderState(D3DRS_ALPHABLENDENABLE, TRUE);
    device->SetRenderState(D3DRS_SRCBLEND, D3DBLEND_SRCALPHA);
    device->SetRenderState(D3DRS_DESTBLEND, D3DBLEND_INVSRCALPHA);
    device->SetTextureStageState(0, D3DTSS_COLOROP, D3DTOP_SELECTARG1);
    device->SetTextureStageState(0, D3DTSS_COLORARG1, D3DTA_DIFFUSE);
    device->SetTextureStageState(0, D3DTSS_ALPHAOP, D3DTOP_SELECTARG1);
    device->SetTextureStageState(0, D3DTSS_ALPHAARG1, D3DTA_DIFFUSE);
    device->SetFVF(kIconFVF);
    device->DrawPrimitiveUP(D3DPT_TRIANGLELIST,
        static_cast<UINT>(vertices.size() / 3), vertices.data(), sizeof(IconVertex));

    state->Apply();
    state->Release();
}

void clear() {
    for (Slot& slot : gSlots) releaseSlot(slot, false);
    resetProjected();
    gLastErrorStage = "cleared_all";
}

Status status() {
    Status result = {};
    void* liveContext = currentContext();
    result.contextExists = liveContext != nullptr;
    result.contextPointer = static_cast<std::uint32_t>(
        reinterpret_cast<std::uintptr_t>(liveContext));
    result.createCalls = gCreateCalls;
    result.createSuccesses = gCreateSuccesses;
    result.updateCalls = gUpdateCalls;
    result.reattachCalls = gReattachCalls;
    result.reattachSuccesses = gReattachSuccesses;
    result.releaseCalls = gReleaseCalls;
    result.droppedStalePointers = gDroppedStalePointers;
    result.loadChecks = gLoadChecks;
    result.loadReadyTransitions = gLoadReadyTransitions;
    result.lastErrorStage = gLastErrorStage;

    for (std::size_t i = 0; i < gSlots.size(); ++i) {
        const Slot& slot = gSlots[i];
        if (!slot.active || slot.model == nullptr) continue;
        ++result.activeCount;
        result.active = true;
        if (result.modelPointer != 0) continue;
        result.contextMatches = liveContext != nullptr && liveContext == slot.context;
        result.playerObjectPointer = slot.playerObject;
        result.modelPointer = static_cast<std::uint32_t>(
            reinterpret_cast<std::uintptr_t>(slot.model));
        result.position = slot.position;
        result.color = kColors[i].name;
        result.icon = kIconNames[static_cast<std::size_t>(slot.iconIndex)];
        result.renderReady = slot.renderReady;
        if (result.contextMatches) {
            result.modelContextPointer = static_cast<std::uint32_t>(
                reinterpret_cast<std::uintptr_t>(readField<void*>(slot.model, 0x2C)));
            result.modelRefCount = readField<std::uint32_t>(slot.model, 0x00);
            result.resourceReady = readField<void*>(slot.model, 0x10) != nullptr;
            result.attachedToRenderList = readField<void*>(slot.model, 0x44) != nullptr;
            result.modelUpdateMarker = readField<std::uint32_t>(slot.model, 0x50);
        }
    }
    return result;
}

} // namespace nativeM2Test
