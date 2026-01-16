const std = @import("std");

const Build = std.Build;
const Step = std.Build.Step;

pub fn configure(b: *Build, target: Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, upstream: *Build.Dependency, luau_use_4_vector: bool) *Step.Compile {
    const lib = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
    });
    const library = b.addLibrary(.{
        .name = "slua",
        .linkage = .static,
        .version = std.SemanticVersion{ .major = 0, .minor = 653, .patch = 0 },
        .root_module = lib,
    });

    lib.addIncludePath(upstream.path("Common/include"));
    lib.addIncludePath(upstream.path("Compiler/include"));
    lib.addIncludePath(upstream.path("Ast/include"));
    lib.addIncludePath(upstream.path("VM/include"));
    lib.addIncludePath(upstream.path("VM/src/cjson")); // For strbuf.h header

    const flags = [_][]const u8{
        "-DLUA_API=extern\"C\"",
        "-DLUACODE_API=extern\"C\"",
        "-DLUACODEGEN_API=extern\"C\"",
        "-Wno-return-type-c-linkage",
        "-Wno-unknown-attributes",
        if (luau_use_4_vector) "-DLUA_VECTOR_SIZE=4" else "",
    };

    lib.addCSourceFiles(.{
        .root = .{ .dependency = .{
            .dependency = upstream,
            .sub_path = "",
        } },
        .files = &luau_source_files,
        .flags = &flags,
    });
    lib.addCSourceFile(.{ .file = b.path("src/luau.cpp"), .flags = &flags });
    // Patched strbuf.cpp for 64-bit Windows compatibility (fixes pointer-to-long cast errors)
    lib.addCSourceFile(.{ .file = b.path("src/cjson/strbuf.cpp"), .flags = &flags });

    library.installHeader(upstream.path("VM/include/lua.h"), "lua.h");
    library.installHeader(upstream.path("VM/include/lualib.h"), "lualib.h");
    library.installHeader(upstream.path("VM/include/luaconf.h"), "luaconf.h");
    library.installHeader(upstream.path("Compiler/include/luacode.h"), "luacode.h");

    return library;
}

const luau_source_files = [_][]const u8{
    "Compiler/src/BuiltinFolding.cpp",
    "Compiler/src/Builtins.cpp",
    "Compiler/src/BytecodeBuilder.cpp",
    "Compiler/src/Compiler.cpp",
    "Compiler/src/ConstantFolding.cpp",
    "Compiler/src/CostModel.cpp",
    "Compiler/src/TableShape.cpp",
    "Compiler/src/Types.cpp",
    "Compiler/src/ValueTracking.cpp",
    "Compiler/src/lcode.cpp",

    "VM/src/lapi.cpp",
    "VM/src/laux.cpp",
    "VM/src/lbaselib.cpp",
    "VM/src/lbitlib.cpp",
    "VM/src/lbuffer.cpp",
    "VM/src/lbuflib.cpp",
    "VM/src/lbuiltins.cpp",
    "VM/src/lcorolib.cpp",
    "VM/src/ldblib.cpp",
    "VM/src/ldebug.cpp",
    "VM/src/ldo.cpp",
    "VM/src/lfunc.cpp",
    "VM/src/lgc.cpp",
    "VM/src/lgcdebug.cpp",
    "VM/src/linit.cpp",
    "VM/src/lmathlib.cpp",
    "VM/src/lmem.cpp",
    "VM/src/lnumprint.cpp",
    "VM/src/lobject.cpp",
    "VM/src/loslib.cpp",
    "VM/src/lperf.cpp",
    "VM/src/lstate.cpp",
    "VM/src/lstring.cpp",
    "VM/src/lstrlib.cpp",
    "VM/src/ltable.cpp",
    "VM/src/ltablib.cpp",
    "VM/src/ltm.cpp",
    "VM/src/ludata.cpp",
    "VM/src/lutf8lib.cpp",
    "VM/src/lveclib.cpp",
    "VM/src/lvmexecute.cpp",
    "VM/src/lvmload.cpp",
    "VM/src/lvmutils.cpp",

    // ServerLua/slua-specific additions
    "VM/src/ares.cpp", // Eris persistence library
    "VM/src/lgcgraph.cpp", // GC graphing utilities
    "VM/src/lgctraverse.cpp", // GC traversal utilities
    "VM/src/lll.cpp", // Low-level Lua extensions
    "VM/src/lllbase64.cpp", // Base64 library
    "VM/src/lllevents.cpp", // Event system
    "VM/src/llltimers.cpp", // Timer system
    "VM/src/llsl.cpp", // LSL (Linden Scripting Language) support
    "VM/src/mono_floats.cpp", // Number formatting utilities
    "VM/src/mono_strings.cpp", // String utilities
    "VM/src/apr/apr_base64.cpp", // APR base64 encoding/decoding (needed by cjson)
    "VM/src/cjson/lua_cjson.cpp", // JSON library (lljson)
    "VM/src/cjson/fpconv.cpp", // Floating point conversion for cjson
    // Note: strbuf.cpp is compiled separately from zslua sources with 64-bit Windows fix

    "Ast/src/Allocator.cpp",
    "Ast/src/Ast.cpp",
    "Ast/src/Confusables.cpp",
    "Ast/src/Cst.cpp", // Concrete Syntax Tree implementation
    "Ast/src/Lexer.cpp",
    "Ast/src/Location.cpp",
    "Ast/src/Parser.cpp",

    // Common utilities needed by slua
    "Common/src/StringUtils.cpp",
};
