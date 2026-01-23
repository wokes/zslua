const std = @import("std");

const Build = std.Build;
const Step = std.Build.Step;

const slua_setup = @import("build/slua.zig");

pub fn build(b: *Build) void {
    // Remove the default install and uninstall steps
    b.top_level_steps = .{};

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lang = .slua;

    // Zig module
    const zslua = b.addModule("zslua", .{
        .root_source_file = b.path("src/lib.zig"),
    });

    const vector_size: usize = 3;
    zslua.addCMacro("LUA_VECTOR_SIZE", b.fmt("{}", .{vector_size}));

    if (b.lazyDependency(@tagName(lang), .{})) |upstream| {
        // Get tailslide library from zig-tailslide dependency
        var tailslide_lib: ?*Step.Compile = null;
        var tailslide_dep: ?*Build.Dependency = null;
        if (b.lazyDependency("zig_tailslide", .{})) |ts_dep| {
            tailslide_lib = ts_dep.artifact("tailslide");
            tailslide_dep = ts_dep;
        }

        const lib = slua_setup.configureWithTailslide(b, target, optimize, upstream, false, tailslide_lib, tailslide_dep);

        // Expose the Lua artifact, and get an install step that header translation can refer to
        const install_lib = b.addInstallArtifact(lib, .{});
        b.getInstallStep().dependOn(&install_lib.step);

        zslua.addIncludePath(upstream.path("Common/include"));
        zslua.addIncludePath(upstream.path("Compiler/include"));
        zslua.addIncludePath(upstream.path("Ast/include"));
        zslua.addIncludePath(upstream.path("VM/include"));

        zslua.linkLibrary(lib);

        // Create patched lua.h for translate-c (removes C++ headers)
        const native_target = b.resolveTargetQuery(.{});
        const patch_exe = b.addExecutable(.{
            .name = "patch_lua_h",
            .root_module = b.createModule(.{
                .root_source_file = b.path("build/patch_lua_h.zig"),
                .target = native_target,
            }),
        });
        const run_patch = b.addRunArtifact(patch_exe);
        run_patch.addFileArg(upstream.path("VM/include/lua.h"));
        const patched_lua_h = run_patch.addOutputFileArg("lua.h");

        // Collect all headers (patched + copies) in one directory using Zig's build system
        const headers = b.addWriteFiles();
        headers.step.dependOn(&run_patch.step);
        _ = headers.addCopyFile(patched_lua_h, "lua.h");
        _ = headers.addCopyFile(upstream.path("VM/include/lualib.h"), "lualib.h");
        _ = headers.addCopyFile(upstream.path("VM/include/luaconf.h"), "luaconf.h");
        _ = headers.addCopyFile(upstream.path("Compiler/include/luacode.h"), "luacode.h");

        // lib must expose all headers included by these root headers
        const c_header_path = b.path("build/include/slua_all.h");
        const c_headers = b.addTranslateC(.{
            .root_source_file = c_header_path,
            .target = target,
            .optimize = optimize,
        });
        // Patched headers MUST come first to shadow library headers
        c_headers.addIncludePath(headers.getDirectory());
        c_headers.step.dependOn(&headers.step);
        c_headers.step.dependOn(&install_lib.step);

        const zslua_c = c_headers.createModule();
        b.modules.put("zslua-c", zslua_c) catch @panic("OOM");

        zslua.addImport("c", zslua_c);

        // Tests - must be inside lazyDependency block to access lib
        const tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/tests.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        tests.root_module.addImport("zslua", zslua);
        // Explicitly link slua to ensure LSLCompiler.cpp is included
        tests.root_module.linkLibrary(lib);

        const run_tests = b.addRunArtifact(tests);
        const test_step = b.step("test", "Run zslua tests");
        test_step.dependOn(&run_tests.step);

        // LSL-specific tests
        const lsl_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/lsl_tests.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        lsl_tests.root_module.addImport("zslua", zslua);
        // Explicitly link slua to ensure LSLCompiler.cpp is included
        lsl_tests.root_module.linkLibrary(lib);

        const run_lsl_tests = b.addRunArtifact(lsl_tests);
        const lsl_test_step = b.step("test-lsl", "Run LSL-specific tests");
        lsl_test_step.dependOn(&run_lsl_tests.step);
    }

    const docs = b.addObject(.{
        .name = "zslua",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Build and install the documentation");
    docs_step.dependOn(&install_docs.step);
}
