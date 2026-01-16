// Minimal C-compatible wrapper for slua's lua.h
// This file provides only C-compatible declarations for use with translate-c
#ifndef slua_c_compat_h
#define slua_c_compat_h

#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>

// Forward declare opaque types used in C++ parts
typedef struct lua_OpaqueGCObjectSet_s* lua_OpaqueGCObjectSet;

// Include luaconf for basic configuration
#include "luaconf.h"

// Copy all the C-compatible parts from lua.h manually
// (This would need to be a substantial subset of lua.h without the C++ parts)

// For now, let's see if we can just skip translate-c entirely

#endif // slua_c_compat_h
