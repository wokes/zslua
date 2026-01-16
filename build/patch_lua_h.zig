const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 3) {
        std.debug.print("Usage: {s} <input_file> <output_file>\n", .{args[0]});
        return error.InvalidArgs;
    }

    const input_path = args[1];
    const output_path = args[2];

    // Read input file
    const input_file = try std.fs.cwd().openFile(input_path, .{});
    defer input_file.close();
    const content = try input_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    // Patch C++ includes
    var patched = std.ArrayList(u8){};
    try patched.ensureTotalCapacity(allocator, content.len + 1000);
    defer patched.deinit(allocator);

    var it = std.mem.splitScalar(u8, content, '\n');
    var added_typedef = false;
    var in_sl_runtime_state = false;
    while (it.next()) |line| {
        // Comment out C++ includes
        if (std.mem.indexOf(u8, line, "#include <istream>") != null or
            std.mem.indexOf(u8, line, "#include <ostream>") != null or
            std.mem.indexOf(u8, line, "#include <unordered_set>") != null)
        {
            try patched.appendSlice(allocator, "// ");
            try patched.appendSlice(allocator, line);
            try patched.append(allocator, '\n');
            continue;
        }

        // Skip the original typedef line since we'll add our own
        if (std.mem.indexOf(u8, line, "typedef std::unordered_set<void*> lua_OpaqueGCObjectSet;") != null) {
            try patched.appendSlice(allocator, "// ");
            try patched.appendSlice(allocator, line);
            try patched.append(allocator, '\n');
            continue;
        }

        // Skip eris_dump and eris_undump functions that use C++ types
        if (std.mem.indexOf(u8, line, "eris_dump") != null or
            std.mem.indexOf(u8, line, "eris_undump") != null)
        {
            try patched.appendSlice(allocator, "// ");
            try patched.appendSlice(allocator, line);
            try patched.append(allocator, '\n');
            continue;
        }

        // Comment out the entire lua_SLRuntimeState struct (has C++ initializers)
        if (std.mem.indexOf(u8, line, "typedef struct lua_SLRuntimeState") != null) {
            in_sl_runtime_state = true;
        }
        if (in_sl_runtime_state) {
            try patched.appendSlice(allocator, "// ");
            try patched.appendSlice(allocator, line);
            try patched.append(allocator, '\n');
            if (std.mem.indexOf(u8, line, "} lua_SLRuntimeState;") != null) {
                in_sl_runtime_state = false;
            }
            continue;
        }

        // Replace nullptr with NULL and std:: references
        var modified_line = std.ArrayList(u8){};
        defer modified_line.deinit(allocator);
        var pos: usize = 0;
        while (pos < line.len) {
            if (pos + 7 <= line.len and std.mem.eql(u8, line[pos .. pos + 7], "nullptr")) {
                try modified_line.appendSlice(allocator, "NULL");
                pos += 7;
            } else if (pos + 13 <= line.len and std.mem.eql(u8, line[pos .. pos + 13], "std::ostream")) {
                try modified_line.appendSlice(allocator, "void");
                pos += 13;
            } else if (pos + 13 <= line.len and std.mem.eql(u8, line[pos .. pos + 13], "std::istream")) {
                try modified_line.appendSlice(allocator, "void");
                pos += 13;
            } else {
                try modified_line.append(allocator, line[pos]);
                pos += 1;
            }
        }

        try patched.appendSlice(allocator, modified_line.items);
        try patched.append(allocator, '\n');

        // Add C-compatible typedefs after including luaconf.h
        if (!added_typedef and std.mem.indexOf(u8, line, "#include \"luaconf.h\"") != null) {
            try patched.appendSlice(allocator, "\n#include <stdbool.h>\n");
            try patched.appendSlice(allocator, "\n// Forward declare lua_State\n");
            try patched.appendSlice(allocator, "struct lua_State;\ntypedef struct lua_State lua_State;\n");
            try patched.appendSlice(allocator, "\n// C-compatible typedef for C++ type\n");
            try patched.appendSlice(allocator, "typedef void* lua_OpaqueGCObjectSet;\n");
            added_typedef = true;
        }
    }

    // Write output
    const output_file = try std.fs.cwd().createFile(output_path, .{});
    defer output_file.close();
    try output_file.writeAll(patched.items);
}
