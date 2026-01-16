// Minimal manual C API bindings for slua
// This avoids using translate-c which cannot handle C++ headers

// Re-export types and functions from the C library
// Note: Since we're linking against the C++ library, we need to use extern declarations

pub const LUA_OK = 0;
pub const LUA_YIELD = 1;
pub const LUA_ERRRUN = 2;
pub const LUA_ERRSYNTAX = 3;
pub const LUA_ERRMEM = 4;
pub const LUA_ERRERR = 5;

// For now, just provide a placeholder that satisfies the module requirement
// The actual bindings would need to match ziglua's expected interface
pub const lua_State = opaque {};
