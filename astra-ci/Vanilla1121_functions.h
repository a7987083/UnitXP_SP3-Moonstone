#pragma once

#include <Windows.h>
#include <cstdint>
#include <string>

// Minimal WoW 1.12.1 / Lua bridge used by Astra custom modules.
// This intentionally contains only the minimal client/Lua bridge needed by Astra.

typedef int(__fastcall* LUA_CFUNCTION)(void* L);

typedef struct {
    const char* name;
    LUA_CFUNCTION func;
} lua_func_reg;

typedef struct structC3Vector {
    float x = 0.0f;
    float y = 0.0f;
    float z = 0.0f;
} C3Vector;

enum InGameObjectType {
    OBJECT_TYPE_Null,
    OBJECT_TYPE_Item,
    OBJECT_TYPE_Container,
    OBJECT_TYPE_Unit,
    OBJECT_TYPE_Player,
    OBJECT_TYPE_GameObject,
    OBJECT_TYPE_DynamicObject,
    OBJECT_TYPE_Corpse
};

#define LUA_GLOBALSINDEX (-10001)

void* GetContext(void);
void lua_pushstring(void* L, std::string str);
std::string lua_tostring(void* L, int index);
double lua_tonumber(void* L, int index);
int lua_toboolean(void* L, int index);
int lua_gettop(void* L);
void lua_pushnil(void* L);
void lua_pushboolean(void* L, int boolean_value);
void lua_pushnumber(void* L, double n);
int lua_isnumber(void* L, int index);
int lua_isstring(void* L, int index);
void lua_settop(void* L, int index);
#define lua_pop(L,n) lua_settop(L, -(n)-1)
void lua_pushvalue(void* L, int index);
void lua_gettable(void* L, int index);
#define lua_getglobal(L, name) (lua_pushstring(L, name), lua_gettable(L, LUA_GLOBALSINDEX))
int lua_pcall(void* L, int nArgs, int nResults, int errFunction);

uint64_t vanilla1121_unitGUID(const char* unitID);
uint32_t vanilla1121_getVisiableObject(uint64_t targetGUID);
int vanilla1121_objectType(uint32_t targetObject);
C3Vector vanilla1121_unitPosition(uint32_t unit);
RECT vanilla1121_gameClientRect();
uint32_t vanilla1121_gxDevice();
void* vanilla1121_d3dDevice(uint32_t gxDevice);
