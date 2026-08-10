#include <Windows.h>
#include <d3d9.h>
#include <atomic>
#include <string>

#include "MinHook.h"
#include "AstraCommandRegistry.h"
#include "MoonMarkerRuntimeGuard.h"
#include "Vanilla1121_functions.h"
#include "moonMarker.h"

namespace {
using LuaLOpenLibProc = void(__fastcall*)(void*, const char*, lua_func_reg[], int);
constexpr std::uintptr_t kLuaLOpenLibAddress = 0x006F4DC0u;
LuaLOpenLibProc gOriginalLuaLOpenLib = nullptr;
std::atomic<bool> gRegistered{false};

int __fastcall AstraLuaEntry(void* L) {
    // Re-acquire/refresh the D3D Present vtable hook without depending on another DLL's scene hooks.
    const uint32_t gx = vanilla1121_gxDevice();
    if (gx != 0 && (gx & 1u) == 0u) {
        auto* device = reinterpret_cast<IDirect3DDevice9*>(vanilla1121_d3dDevice(gx));
        if (device) moonMarker::installPresentHook(device);
    }

    if (lua_gettop(L) < 1 || !lua_isstring(L, 1)) {
        lua_pushnil(L);
        lua_pushstring(L, "COMMAND_REQUIRED");
        return 2;
    }
    const std::string command = lua_tostring(L, 1);
    int returns = 0;
    if (astra::dispatchCommand(L, command, returns)) return returns;
    lua_pushnil(L);
    lua_pushstring(L, "UNKNOWN_COMMAND");
    return 2;
}

lua_func_reg kAstraFunctions[] = {
    {"Astra", &AstraLuaEntry},
    {nullptr, nullptr}
};

bool registerAstra(void* L) {
    if (!L || !gOriginalLuaLOpenLib) return false;
    const int oldTop = lua_gettop(L);
    // luaL_openlib(libname=null) registers into the table on top of the stack.
    // Push the Lua globals table so only one global symbol, Astra, is added.
    lua_pushvalue(L, LUA_GLOBALSINDEX);
    gOriginalLuaLOpenLib(L, nullptr, kAstraFunctions, 0);
    lua_settop(L, oldTop);
    gRegistered.store(true);
    return true;
}

void __fastcall detouredLuaLOpenLib(void* L, const char* nameSpace,
                                    lua_func_reg funcs[], int upvalues) {
    gOriginalLuaLOpenLib(L, nameSpace, funcs, upvalues);
    if (!gRegistered.load()) registerAstra(L);
}
}

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID reserved) {
    if (reason == DLL_PROCESS_ATTACH) {
        if (MH_Initialize() != MH_OK) return FALSE;
        astra::initializeCommandRegistry();
        moonMarkerRuntimeGuard::initialize();

        if (moonMarkerRuntimeGuard::enabled()) {
            if (!moonMarker::initializeGroundCursorHook()) {
                moonMarkerRuntimeGuard::markHookInstallFailed("GROUND_CURSOR_HOOK_INSTALL_FAILED");
            }
        }

        if (MH_CreateHook(reinterpret_cast<LPVOID>(kLuaLOpenLibAddress),
                          reinterpret_cast<LPVOID>(&detouredLuaLOpenLib),
                          reinterpret_cast<LPVOID*>(&gOriginalLuaLOpenLib)) != MH_OK) {
            return FALSE;
        }
        if (moonMarkerRuntimeGuard::enabled()) {
            if (MH_EnableHook(reinterpret_cast<LPVOID>(0x006E60F0u)) != MH_OK) return FALSE;
        }
        if (MH_EnableHook(reinterpret_cast<LPVOID>(kLuaLOpenLibAddress)) != MH_OK) return FALSE;

        // Do not call GetContext() from DllMain. Astra registers lazily the first
        // time the client calls luaL_openlib, which avoids touching Lua state
        // during loader-lock / early client initialization.
    } else if (reason == DLL_PROCESS_DETACH && reserved == nullptr) {
        moonMarker::shutdown();
        moonMarker::shutdownGroundCursorHook();
        MH_DisableHook(reinterpret_cast<LPVOID>(kLuaLOpenLibAddress));
        MH_RemoveHook(reinterpret_cast<LPVOID>(kLuaLOpenLibAddress));
        MH_Uninitialize();
    }
    return TRUE;
}
