#include "MoonMarkerGuildAuth.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>

#include <Windows.h>

#include "Vanilla1121_functions.h"

namespace moonMarkerGuildAuth {
namespace {

using LuaIsCFunctionProc = int (__fastcall*)(void*, int);
using LuaToCFunctionProc = LUA_CFUNCTION (__fastcall*)(void*, int);

constexpr std::uintptr_t kLuaIsCFunctionAddress = 0x006F34A0;
constexpr std::uintptr_t kLuaToCFunctionAddress = 0x006F3720;

const auto luaIsCFunction =
    reinterpret_cast<LuaIsCFunctionProc>(kLuaIsCFunctionAddress);
const auto luaToCFunction =
    reinterpret_cast<LuaToCFunctionProc>(kLuaToCFunctionAddress);

LUA_CFUNCTION originalGetGuildInfo = nullptr;

template <std::size_t N>
std::string decode(const std::array<std::uint8_t, N>& bytes,
                   const std::uint8_t key) {
    std::string result;
    result.reserve(N);
    for (const auto value : bytes) {
        result.push_back(static_cast<char>(value ^ key));
    }
    return result;
}

const std::string& allowedGuildName() {
    // UTF-8 guild name is XOR encoded so it is not stored as plain text in the DLL.
    static const std::array<std::uint8_t, 12> encoded = {{
        191, 254, 240, 179, 194, 233, 189, 255, 196, 188, 244, 229
    }};
    static const std::string value = decode(encoded, 0x5A);
    return value;
}

const std::string& authQueryCommand() {
    static const std::array<std::uint8_t, 6> encoded = {{
        32, 32, 44, 24, 25, 5
    }};
    static const std::string value = decode(encoded, 0x6D);
    return value;
}

const std::string& advancedPrefix() {
    static const std::array<std::uint8_t, 20> encoded = {{
        122, 88, 88, 89, 122, 86, 69, 92, 82, 69,
        25, 118, 83, 65, 86, 89, 84, 82, 83, 25
    }};
    static const std::string value = decode(encoded, 0x37);
    return value;
}

const std::string& advancedPingCommand() {
    static const std::array<std::uint8_t, 24> encoded = {{
        97, 67, 67, 66, 97, 77, 94, 71, 73, 94, 2, 109,
        72, 90, 77, 66, 79, 73, 72, 2, 124, 69, 66, 75
    }};
    static const std::string value = decode(encoded, 0x2C);
    return value;
}

struct AuthResult {
    bool allowed = false;
    std::string guildName;
    const char* reason = "GUILD_NOT_READY";
};

AuthResult queryTrustedGuild(void* luaState) {
    AuthResult result;
    if (!luaState || !luaIsCFunction || !luaToCFunction) {
        result.reason = "AUTH_UNAVAILABLE";
        return result;
    }

    const int oldTop = lua_gettop(luaState);
    lua_getglobal(luaState, "GetGuildInfo");

    // A Lua replacement is still LUA_TFUNCTION, so type checking alone is not enough.
    // The client Lua 5.0 C API verifies that this is a native C closure.
    if (!luaIsCFunction(luaState, -1)) {
        lua_settop(luaState, oldTop);
        result.reason = "FUNCTION_TAMPERED";
        return result;
    }

    const LUA_CFUNCTION currentGetGuildInfo = luaToCFunction(luaState, -1);
    if (!currentGetGuildInfo) {
        lua_settop(luaState, oldTop);
        result.reason = "FUNCTION_TAMPERED";
        return result;
    }

    // Once a successful native call establishes the pointer, every later check must
    // resolve to the exact same client function.
    if (originalGetGuildInfo && currentGetGuildInfo != originalGetGuildInfo) {
        lua_settop(luaState, oldTop);
        result.reason = "FUNCTION_TAMPERED";
        return result;
    }

    lua_pushstring(luaState, "player");
    if (lua_pcall(luaState, 1, 3, 0) != 0) {
        lua_settop(luaState, oldTop);
        result.reason = "GUILD_NOT_READY";
        return result;
    }

    result.guildName = lua_tostring(luaState, oldTop + 1);
    lua_settop(luaState, oldTop);

    if (result.guildName.empty()) {
        result.reason = "GUILD_NOT_READY";
        return result;
    }

    if (!originalGetGuildInfo) {
        originalGetGuildInfo = currentGetGuildInfo;
    }

    result.allowed = result.guildName == allowedGuildName();
    result.reason = result.allowed ? "AUTHORIZED" : "WRONG_GUILD";
    return result;
}

} // namespace

bool isAuthQuery(const std::string& command) {
    return command == authQueryCommand();
}

bool isAdvancedCommand(const std::string& command) {
    const std::string& prefix = advancedPrefix();
    return command.size() >= prefix.size() &&
           command.compare(0, prefix.size(), prefix) == 0;
}

bool isAuthorized(void* luaState) {
    return queryTrustedGuild(luaState).allowed;
}

int pushAuthStatus(void* luaState) {
    const AuthResult result = queryTrustedGuild(luaState);
    lua_pushboolean(luaState, result.allowed ? 1 : 0);
    if (result.guildName.empty()) {
        lua_pushnil(luaState);
    } else {
        lua_pushstring(luaState, result.guildName);
    }
    lua_pushstring(luaState, result.reason);
    return 3;
}

int denyAdvanced(void* luaState) {
    lua_pushboolean(luaState, 0);
    lua_pushstring(luaState, "ACCESS_DENIED");
    return 2;
}

int handleAdvancedCommand(void* luaState, const std::string& command) {
    // Deliberate second check inside the protected handler. Future advanced
    // implementations must stay behind this function or repeat this guard.
    if (!isAuthorized(luaState)) {
        return denyAdvanced(luaState);
    }

    if (command == advancedPingCommand()) {
        lua_pushboolean(luaState, 1);
        lua_pushstring(luaState, "AUTHORIZED");
        return 2;
    }

    lua_pushboolean(luaState, 0);
    lua_pushstring(luaState, "NOT_IMPLEMENTED");
    return 2;
}

} // namespace moonMarkerGuildAuth
