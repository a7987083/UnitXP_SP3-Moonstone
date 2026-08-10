#include "Vanilla1121_functions.h"

namespace {
using GETCONTEXT = void* (__fastcall*)();
using LUA_PUSHSTRING = void(__fastcall*)(void*, const char*);
using LUA_TOSTRING = const char* (__fastcall*)(void*, int);
using LUA_TONUMBER = double(__fastcall*)(void*, int);
using LUA_TOBOOLEAN = int(__fastcall*)(void*, int);
using LUA_GETTOP = int(__fastcall*)(void*);
using LUA_PUSHNIL = void(__fastcall*)(void*);
using LUA_PUSHBOOLEAN = void(__fastcall*)(void*, int);
using LUA_PUSHNUMBER = void(__fastcall*)(void*, double);
using LUA_ISNUMBER = int(__fastcall*)(void*, int);
using LUA_ISSTRING = int(__fastcall*)(void*, int);
using LUA_SETTOP = void(__fastcall*)(void*, int);
using LUA_PUSHVALUE = void(__fastcall*)(void*, int);
using LUA_GETTABLE = void(__fastcall*)(void*, int);
using LUA_PCALL = int(__fastcall*)(void*, int, int, int);
using UNITGUID = uint64_t(__fastcall*)(const char*);
using GETOBJECT_BYGUID = uint32_t(__fastcall*)(uint64_t);

constexpr std::uintptr_t kGetContext = 0x007040D0u;
constexpr std::uintptr_t kLuaPushString = 0x006F3890u;
constexpr std::uintptr_t kLuaToString = 0x006F3690u;
constexpr std::uintptr_t kLuaToNumber = 0x006F3620u;
constexpr std::uintptr_t kLuaToBoolean = 0x006F3660u;
constexpr std::uintptr_t kLuaGetTop = 0x006F3070u;
constexpr std::uintptr_t kLuaPushNil = 0x006F37F0u;
constexpr std::uintptr_t kLuaPushBoolean = 0x006F39F0u;
constexpr std::uintptr_t kLuaPushNumber = 0x006F3810u;
constexpr std::uintptr_t kLuaIsNumber = 0x006F34D0u;
constexpr std::uintptr_t kLuaIsString = 0x006F3510u;
constexpr std::uintptr_t kLuaSetTop = 0x006F3080u;
constexpr std::uintptr_t kLuaPushValue = 0x006F3350u;
constexpr std::uintptr_t kLuaGetTable = 0x006F3A40u;
constexpr std::uintptr_t kLuaPCall = 0x006F41A0u;
constexpr std::uintptr_t kUnitGuid = 0x00515970u;
constexpr std::uintptr_t kObjectByGuid = 0x00464870u;
}

void* GetContext(void) {
    return reinterpret_cast<GETCONTEXT>(kGetContext)();
}
void lua_pushstring(void* L, std::string str) {
    reinterpret_cast<LUA_PUSHSTRING>(kLuaPushString)(L, str.c_str());
}
std::string lua_tostring(void* L, int index) {
    const char* p = reinterpret_cast<LUA_TOSTRING>(kLuaToString)(L, index);
    return p ? std::string(p) : std::string();
}
double lua_tonumber(void* L, int index) {
    return reinterpret_cast<LUA_TONUMBER>(kLuaToNumber)(L, index);
}
int lua_toboolean(void* L, int index) {
    return reinterpret_cast<LUA_TOBOOLEAN>(kLuaToBoolean)(L, index);
}
int lua_gettop(void* L) {
    return reinterpret_cast<LUA_GETTOP>(kLuaGetTop)(L);
}
void lua_pushnil(void* L) {
    reinterpret_cast<LUA_PUSHNIL>(kLuaPushNil)(L);
}
void lua_pushboolean(void* L, int value) {
    reinterpret_cast<LUA_PUSHBOOLEAN>(kLuaPushBoolean)(L, value);
}
void lua_pushnumber(void* L, double n) {
    reinterpret_cast<LUA_PUSHNUMBER>(kLuaPushNumber)(L, n);
}
int lua_isnumber(void* L, int index) {
    return reinterpret_cast<LUA_ISNUMBER>(kLuaIsNumber)(L, index);
}
int lua_isstring(void* L, int index) {
    return reinterpret_cast<LUA_ISSTRING>(kLuaIsString)(L, index);
}
void lua_settop(void* L, int index) {
    reinterpret_cast<LUA_SETTOP>(kLuaSetTop)(L, index);
}
void lua_pushvalue(void* L, int index) {
    reinterpret_cast<LUA_PUSHVALUE>(kLuaPushValue)(L, index);
}
void lua_gettable(void* L, int index) {
    reinterpret_cast<LUA_GETTABLE>(kLuaGetTable)(L, index);
}
int lua_pcall(void* L, int nArgs, int nResults, int errFunction) {
    return reinterpret_cast<LUA_PCALL>(kLuaPCall)(L, nArgs, nResults, errFunction);
}
uint64_t vanilla1121_unitGUID(const char* unitID) {
    return reinterpret_cast<UNITGUID>(kUnitGuid)(unitID);
}
uint32_t vanilla1121_getVisiableObject(uint64_t targetGUID) {
    return reinterpret_cast<GETOBJECT_BYGUID>(kObjectByGuid)(targetGUID);
}
int vanilla1121_objectType(uint32_t targetObject) {
    if (targetObject == 0) return OBJECT_TYPE_Null;
    return *reinterpret_cast<int*>(static_cast<std::uintptr_t>(targetObject) + 0x14u);
}
C3Vector vanilla1121_unitPosition(uint32_t unit) {
    C3Vector result = {};
    if (unit == 0 || (unit & 1u) != 0u) return result;
    const uint32_t vtable = *reinterpret_cast<uint32_t*>(unit);
    if (vtable == 0 || (vtable & 1u) != 0u) return result;
    const uint32_t fn = *reinterpret_cast<uint32_t*>(vtable + 0x14u);
    if (fn == 0 || (fn & 1u) != 0u) return result;
    using GETPOSITION = C3Vector* (__thiscall*)(uint32_t, C3Vector*);
    reinterpret_cast<GETPOSITION>(fn)(unit, &result);
    return result;
}
RECT vanilla1121_gameClientRect() {
    RECT result = {};
    using GETGAMEWINDOW = HWND(__fastcall*)(int);
    HWND hwnd = reinterpret_cast<GETGAMEWINDOW>(0x00435C30u)(0);
    if (hwnd) GetClientRect(hwnd, &result);
    return result;
}
uint32_t vanilla1121_gxDevice() {
    return *reinterpret_cast<uint32_t*>(0x00C0ED38u);
}
void* vanilla1121_d3dDevice(uint32_t gxDevice) {
    if (gxDevice == 0 || (gxDevice & 1u) != 0u) return nullptr;
    return *reinterpret_cast<void**>(gxDevice + 0x38A8u);
}
