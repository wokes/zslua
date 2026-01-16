// Wrapper for lua.h that skips C++ includes for translate-c
#ifndef lua_wrapper_h
#define lua_wrapper_h

#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>

// Skip C++ headers
#define istream void
#define ostream void
#define unordered_set void

// Mock the C++ types lua.h uses
typedef void* lua_OpaqueGCObjectSet;

// Now include the rest of lua.h by defining a guard to skip the problematic includes
#define LUAU_LUA_H_INCLUDED_HEADERS 1

// #include "../../../.zig-cache/o/46825c18471c3f83c466350cc2f7c925/lua.h"

#endif // lua_wrapper_h
