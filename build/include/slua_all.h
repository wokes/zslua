#ifndef slua_all_h
#define slua_all_h

// Use the patched lua.h that has C++ headers commented out
#include "lua.h"
#include "lualib.h"
#include "luaconf.h"
#include "luacode.h"

// LSL-specific library opening functions
// These are declared in lualib.h but we ensure they're visible here
int luaopen_lsl(struct lua_State* L);
int luaopen_sl(struct lua_State* L, int expose_internal_funcs);
int luaopen_ll(struct lua_State* L, int testing_funcs);

// LLEvents - event manager for LSL scripts
void luaSL_setup_llevents_metatable(struct lua_State *L, int expose_internal_funcs);
void luaSL_setup_detectedevent_metatable(struct lua_State *L);
int luaSL_createeventmanager(struct lua_State *L);
int luaSL_pushdetectedevent(struct lua_State *L, int index, int valid, int can_change_damage);

// LLTimers - timer manager for LSL scripts
void luaSL_setup_llltimers_metatable(struct lua_State *L, int expose_internal_funcs);
int luaSL_createtimermanager(struct lua_State *L);

// UUID/Quaternion helpers
int luaSL_pushuuidlstring(struct lua_State *L, const char *str, size_t len);
int luaSL_pushuuidstring(struct lua_State *L, const char *str);
int luaSL_pushuuidbytes(struct lua_State *L, const unsigned char *bytes);
int luaSL_pushquaternion(struct lua_State *L, double x, double y, double z, double s);
const char *luaSL_checkuuid(struct lua_State *L, int num_arg, int *compressed);
const float *luaSL_checkquaternion(struct lua_State *L, int num_arg);

// LSL type helpers
int luaSL_pushnativeinteger(struct lua_State *L, int val);
void luaSL_pushindexlike(struct lua_State *L, int index);
int luaSL_checkindexlike(struct lua_State *L, int index);
void luaSL_pushboollike(struct lua_State *L, int val);
unsigned char luaSL_lsl_type(struct lua_State *L, int idx);
int luaSL_ismethodstyle(struct lua_State *L, int idx);

#endif // slua_all_h
