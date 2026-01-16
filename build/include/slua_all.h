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

#endif // slua_all_h
