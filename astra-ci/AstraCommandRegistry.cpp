#include "AstraCommandRegistry.h"

#include <unordered_map>

#include "MoonMarkerDreamAvatar.h"
#include "MoonMarkerGuildAuth.h"
#include "MoonMarkerRuntimeGuard.h"
#include "GroundProbe.h"
#include "AutoRange.h"
#include "Vanilla1121_functions.h"
#include "moonMarker.h"
#include "nativeM2Test.h"

namespace astra {
namespace {
std::unordered_map<std::string, CommandHandler> gCommands;

int handleVersion(void* L) {
    lua_pushstring(L, "Astra 0.1.0-migration");
    lua_pushnumber(L, 1);
    lua_pushnumber(L, 0);
    lua_pushnumber(L, 0);
    return 4;
}

int handleRuntimeStatus(void* L) {
    lua_pushboolean(L, moonMarkerRuntimeGuard::enabled() ? 1 : 0);
    lua_pushstring(L, moonMarkerRuntimeGuard::statusCode());
    lua_pushstring(L, moonMarkerRuntimeGuard::userMessage());
    lua_pushstring(L, moonMarkerRuntimeGuard::detail());
    const std::string& fingerprint = moonMarkerRuntimeGuard::fingerprint();
    if (fingerprint.empty()) lua_pushnil(L); else lua_pushstring(L, fingerprint);
    return 5;
}

int handleGroundProbeStatus(void* L) {
    lua_pushboolean(L, moonMarkerRuntimeGuard::enabled() ? 1 : 0);
    lua_pushstring(L, moonMarkerRuntimeGuard::statusCode());
    lua_pushstring(L, moonMarkerRuntimeGuard::userMessage());
    return 3;
}

int handleGroundProbeSnapshot(void* L) {
    const int n = lua_gettop(L);
    float range = 120.0f;
    bool includeGameObjects = true;
    if (n >= 2 && lua_isnumber(L, 2)) range = static_cast<float>(lua_tonumber(L, 2));
    if (n >= 3) includeGameObjects = lua_toboolean(L, 3) != 0;
    lua_pushstring(L, groundProbe::snapshot(range, includeGameObjects));
    return 1;
}

int handleGroundProbeUnitByGuid(void* L) {
    if (lua_gettop(L) < 2 || !lua_isstring(L, 2)) {
        lua_pushstring(L, "E|GUID_INVALID|caster GUID is required");
        return 1;
    }
    lua_pushstring(L, groundProbe::unitByGuid(lua_tostring(L, 2)));
    return 1;
}

int handleAutoRangeStatus(void* L) {
    lua_pushstring(L, autoRange::status());
    return 1;
}

int handleAutoRangeResolve(void* L) {
    if (lua_gettop(L) < 2 || !lua_isnumber(L, 2)) {
        lua_pushstring(L, "E|INVALID_SPELL");
        return 1;
    }
    const unsigned int spellId = static_cast<unsigned int>(lua_tonumber(L, 2));
    lua_pushstring(L, autoRange::resolve(spellId));
    return 1;
}

int handleAutoRangeVisualSet(void* L) {
    const int n = lua_gettop(L);
    if (n < 7 || !lua_isstring(L, 2) || !lua_isstring(L, 3)
        || !lua_isnumber(L, 4) || !lua_isnumber(L, 5)
        || !lua_isnumber(L, 6) || !lua_isnumber(L, 7)) {
        lua_pushboolean(L, 0); lua_pushstring(L, ""); lua_pushstring(L, "autorange_invalid_arguments");
        return 3;
    }
    C3Vector pos = {static_cast<float>(lua_tonumber(L, 4)),
                    static_cast<float>(lua_tonumber(L, 5)),
                    static_cast<float>(lua_tonumber(L, 6))};
    const float scale = static_cast<float>(lua_tonumber(L, 7));
    float yaw = 0.0f;
    if (n >= 8 && lua_isnumber(L, 8)) yaw = static_cast<float>(lua_tonumber(L, 8));
    std::string normalized;
    const bool ok = nativeM2Test::setAutoRangeVisual(lua_tostring(L, 2), lua_tostring(L, 3),
                                                      pos, scale, yaw, normalized);
    lua_pushboolean(L, ok ? 1 : 0);
    lua_pushstring(L, normalized);
    lua_pushstring(L, nativeM2Test::lastErrorStage());
    return 3;
}

int handleAutoRangeVisualMove(void* L) {
    const int n = lua_gettop(L);
    if (n < 6 || !lua_isstring(L, 2) || !lua_isnumber(L, 3) || !lua_isnumber(L, 4)
        || !lua_isnumber(L, 5) || !lua_isnumber(L, 6)) {
        lua_pushboolean(L, 0); return 1;
    }
    C3Vector pos = {static_cast<float>(lua_tonumber(L, 3)),
                    static_cast<float>(lua_tonumber(L, 4)),
                    static_cast<float>(lua_tonumber(L, 5))};
    const float scale = static_cast<float>(lua_tonumber(L, 6));
    float yaw = 0.0f;
    if (n >= 7 && lua_isnumber(L, 7)) yaw = static_cast<float>(lua_tonumber(L, 7));
    lua_pushboolean(L, nativeM2Test::moveAutoRangeVisual(lua_tostring(L, 2), pos, scale, yaw) ? 1 : 0);
    return 1;
}

int handleAutoRangeVisualClear(void* L) {
    if (lua_gettop(L) >= 2 && lua_isstring(L, 2)) nativeM2Test::clearAutoRangeVisual(lua_tostring(L, 2));
    return 0;
}

int handleAutoRangeVisualClearAll(void* L) {
    nativeM2Test::clearAllAutoRangeVisuals();
    return 0;
}

int handlePlace(void* L) {
    const int n = lua_gettop(L);
    if (n < 3 || !lua_isstring(L, 2) || !lua_isstring(L, 3)) return 0;
    C3Vector placed = {};
    std::string normalizedColor;
    const std::string color = lua_tostring(L, 2);
    const std::string icon = lua_tostring(L, 3);
    if (!moonMarker::placeAtCursor(color, placed, normalizedColor, false)) return 0;
    C3Vector modelPosition = placed;
    modelPosition.z += 0.05f;
    if (!nativeM2Test::createAt(normalizedColor, icon, modelPosition)) {
        moonMarker::remove(normalizedColor);
        return 0;
    }
    lua_pushnumber(L, placed.x);
    lua_pushnumber(L, placed.y);
    lua_pushnumber(L, placed.z);
    lua_pushstring(L, normalizedColor);
    lua_pushstring(L, nativeM2Test::iconForColor(normalizedColor, icon));
    return 5;
}

int handleRemote(void* L) {
    const int n = lua_gettop(L);
    if (n < 6 || !lua_isstring(L, 2) || !lua_isnumber(L, 3)
        || !lua_isnumber(L, 4) || !lua_isnumber(L, 5) || !lua_isstring(L, 6)) {
        lua_pushboolean(L, 0);
        return 1;
    }
    C3Vector position = {
        static_cast<float>(lua_tonumber(L, 3)),
        static_cast<float>(lua_tonumber(L, 4)),
        static_cast<float>(lua_tonumber(L, 5))
    };
    const std::string color = lua_tostring(L, 2);
    const std::string icon = lua_tostring(L, 6);
    if (!moonMarker::placeRemote(color, position, false)) {
        lua_pushboolean(L, 0);
        return 1;
    }
    C3Vector modelPosition = position;
    modelPosition.z += 0.05f;
    if (!nativeM2Test::createAt(color, icon, modelPosition)) {
        moonMarker::remove(color);
        lua_pushboolean(L, 0);
        return 1;
    }
    lua_pushboolean(L, 1);
    return 1;
}

int handleClear(void* L) {
    nativeM2Test::clear();
    moonMarker::clearAll();
    lua_pushboolean(L, 1);
    return 1;
}
}

void initializeCommandRegistry() {
    if (!gCommands.empty()) return;
    gCommands.emplace("version", &handleVersion);
    gCommands.emplace("MoonMarker.Runtime.Status", &handleRuntimeStatus);
    gCommands.emplace("GroundProbe.Status", &handleGroundProbeStatus);
    gCommands.emplace("GroundProbe.Snapshot", &handleGroundProbeSnapshot);
    gCommands.emplace("GroundProbe.UnitByGuid", &handleGroundProbeUnitByGuid);
    gCommands.emplace("AutoRange.Status", &handleAutoRangeStatus);
    gCommands.emplace("AutoRange.Resolve", &handleAutoRangeResolve);
    gCommands.emplace("AutoRange.VisualSet", &handleAutoRangeVisualSet);
    gCommands.emplace("AutoRange.VisualMove", &handleAutoRangeVisualMove);
    gCommands.emplace("AutoRange.VisualClear", &handleAutoRangeVisualClear);
    gCommands.emplace("AutoRange.VisualClearAll", &handleAutoRangeVisualClearAll);
    gCommands.emplace("MoonMarker.Place", &handlePlace);
    gCommands.emplace("MoonMarker.Remote", &handleRemote);
    gCommands.emplace("MoonMarker.Clear", &handleClear);
}

bool dispatchCommand(void* L, const std::string& command, int& returnCount) {
    initializeCommandRegistry();

    // Preserve the historical runtime guard for every MoonMarker command except
    // the status probe itself. Auth aliases (for example MMAuth) are handled
    // below using the same guard.
    if (command != "MoonMarker.Runtime.Status"
        && command.size() >= 11 && command.compare(0, 11, "MoonMarker.") == 0
        && !moonMarkerRuntimeGuard::enabled()) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, moonMarkerRuntimeGuard::statusCode());
        lua_pushstring(L, moonMarkerRuntimeGuard::userMessage());
        returnCount = 3;
        return true;
    }

    const auto it = gCommands.find(command);
    if (it != gCommands.end()) {
        returnCount = it->second(L);
        return true;
    }

    // DreamAvatar commands retain their exact historical names/arguments.
    // Sync commands are intentionally not gated by guild authorization; the
    // DreamAvatar packet layer performs its own signed sender/timestamp checks.
    if (moonMarkerDreamAvatar::isCommand(command)) {
        if (!moonMarkerRuntimeGuard::enabled()) {
            lua_pushboolean(L, 0);
            lua_pushstring(L, moonMarkerRuntimeGuard::statusCode());
            lua_pushstring(L, moonMarkerRuntimeGuard::userMessage());
            returnCount = 3;
            return true;
        }
        if (!moonMarkerDreamAvatar::isSyncCommand(command)
            && !moonMarkerGuildAuth::isAuthorized(L)) {
            returnCount = moonMarkerGuildAuth::denyAdvanced(L);
            return true;
        }
        returnCount = moonMarkerDreamAvatar::handleLuaCommand(L, command);
        return true;
    }

    // Existing MoonMarker subcommands keep their original names/arguments.
    if (!moonMarkerRuntimeGuard::enabled()
        && moonMarkerGuildAuth::isAuthQuery(command)) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, moonMarkerRuntimeGuard::statusCode());
        lua_pushstring(L, moonMarkerRuntimeGuard::userMessage());
        returnCount = 3;
        return true;
    }
    if (moonMarkerGuildAuth::isAuthQuery(command)) {
        returnCount = moonMarkerGuildAuth::pushAuthStatus(L);
        return true;
    }
    if (moonMarkerGuildAuth::isPublicCommand(command)) {
        returnCount = moonMarkerGuildAuth::handlePublicCommand(L, command);
        return true;
    }
    if (moonMarkerGuildAuth::isAdvancedCommand(command)) {
        if (!moonMarkerGuildAuth::isAuthorized(L))
            returnCount = moonMarkerGuildAuth::denyAdvanced(L);
        else
            returnCount = moonMarkerGuildAuth::handleAdvancedCommand(L, command);
        return true;
    }
    return false;
}
}
