//! LSL Builtins - Constants parsing and loading for Second Life's Linden Scripting Language
//!
//! This module provides functionality to parse LSL constants from a builtins.txt file
//! and set them as global variables in a Lua state. This is compatible with the
//! format used by slua's LSLBuiltins.cpp.
//!
//! The builtins.txt format supports:
//! - const integer NAME = VALUE
//! - const float NAME = VALUE
//! - const string NAME = "VALUE"
//! - const key NAME = "UUID"
//! - const vector NAME = <x, y, z>
//! - const rotation NAME = <x, y, z, s>

const std = @import("std");
const lib = @import("lib.zig");
const Lua = lib.Lua;
const Allocator = std.mem.Allocator;

/// Embedded builtins data (loaded at compile time from builtins_data.txt)
pub const embedded_builtins_data: []const u8 = @embedFile("builtins_data.txt");

/// LSL type enumeration matching slua's LSLIType
pub const LSLType = enum {
    null,
    integer,
    float,
    string,
    key,
    vector,
    quaternion,
    list,
    @"error",
};

/// An LSL constant value, similar to slua's SLConstant struct
pub const SLConstant = union(LSLType) {
    null: void,
    integer: i32,
    float: f32,
    string: []const u8,
    key: []const u8,
    vector: [3]f32,
    quaternion: [4]f32,
    list: void, // Lists are not supported as constants
    @"error": void,

    /// Push this constant value onto the Lua stack
    pub fn pushToLua(self: SLConstant, lua: *Lua) void {
        switch (self) {
            .integer => |val| lua.pushNumber(@floatFromInt(val)),
            .float => |val| lua.pushNumber(@floatCast(val)),
            .string => |val| _ = lua.pushString(val),
            .key => |val| {
                // For keys (UUIDs), we should use the uuid function from the lsl library
                // For now, push as string - the lsl library handles UUID type internally
                // In the full slua implementation, this calls luaSL_pushuuidlstring
                _ = lua.pushString(val);
            },
            .vector => |val| lua.pushVector(val[0], val[1], val[2]),
            .quaternion => |val| {
                // Quaternions in slua are pushed using luaSL_pushquaternion
                // which is a 4-component vector. In Luau, we use a 4-vector or
                // call the toquaternion function. For now, push as 4-vector.
                // Note: luau_vector_size might be 3, so we may need to handle this
                // through the Lua API instead
                if (lib.luau_vector_size == 4) {
                    lua.pushVector(val[0], val[1], val[2], val[3]);
                } else {
                    // For 3-vector builds, we need to use toquaternion from Lua
                    // For now, push the x,y,z components only (lossy for quaternions)
                    // A proper implementation would call the quaternion constructor
                    lua.pushVector(val[0], val[1], val[2]);
                }
            },
            else => lua.pushNil(),
        }
    }
};

/// Storage for parsed LSL constants
pub const BuiltinsDatabase = struct {
    constants: std.StringHashMapUnmanaged(SLConstant),
    /// Arena allocator for string storage
    arena: std.heap.ArenaAllocator,

    pub const empty: BuiltinsDatabase = .{
        .constants = .empty,
        .arena = undefined,
    };

    pub fn init(child_allocator: Allocator) BuiltinsDatabase {
        return .{
            .constants = .empty,
            .arena = std.heap.ArenaAllocator.init(child_allocator),
        };
    }

    pub fn deinit(self: *BuiltinsDatabase) void {
        // Clear the hashmap first (frees its internal storage via the arena allocator)
        self.constants.clearAndFree(self.arena.allocator());
        // Then free all arena memory
        self.arena.deinit();
        self.* = undefined;
    }

    /// Parse a constant value from string based on its type
    fn parseConstantValue(self: *BuiltinsDatabase, type_str: []const u8, value: []const u8) !?SLConstant {
        const arena_alloc = self.arena.allocator();

        if (std.mem.eql(u8, type_str, "integer")) {
            // Try decimal first, then hex
            const val = std.fmt.parseInt(i32, value, 10) catch blk: {
                // Try hex format (0x...)
                if (value.len > 2 and std.mem.startsWith(u8, value, "0x")) {
                    break :blk std.fmt.parseInt(i32, value[2..], 16) catch return null;
                }
                return null;
            };
            return .{ .integer = val };
        } else if (std.mem.eql(u8, type_str, "float")) {
            const val = std.fmt.parseFloat(f32, value) catch return null;
            return .{ .float = val };
        } else if (std.mem.eql(u8, type_str, "string") or std.mem.eql(u8, type_str, "key")) {
            // String/key values should be quoted
            if (value.len < 2 or value[0] != '"' or value[value.len - 1] != '"') {
                return null;
            }
            // Parse escape sequences
            const content = value[1 .. value.len - 1];
            var result: std.ArrayListUnmanaged(u8) = .empty;
            var i: usize = 0;
            while (i < content.len) : (i += 1) {
                if (content[i] == '\\' and i + 1 < content.len) {
                    i += 1;
                    switch (content[i]) {
                        'n' => try result.append(arena_alloc, '\n'),
                        't' => try result.append(arena_alloc, '\t'),
                        'r' => try result.append(arena_alloc, '\r'),
                        '\\' => try result.append(arena_alloc, '\\'),
                        '"' => try result.append(arena_alloc, '"'),
                        else => try result.append(arena_alloc, content[i]),
                    }
                } else {
                    try result.append(arena_alloc, content[i]);
                }
            }
            const stored_str = try result.toOwnedSlice(arena_alloc);

            // Check if this is a UUID (for key type detection)
            if (std.mem.eql(u8, type_str, "key") or isUUID(stored_str)) {
                return .{ .key = stored_str };
            } else {
                return .{ .string = stored_str };
            }
        } else if (std.mem.eql(u8, type_str, "vector")) {
            // Vector format: <x, y, z>
            const trimmed = std.mem.trim(u8, value, " \t");
            if (trimmed.len < 2 or trimmed[0] != '<' or trimmed[trimmed.len - 1] != '>') {
                return null;
            }
            const content = trimmed[1 .. trimmed.len - 1];
            var components: [3]f32 = .{ 0, 0, 0 };
            var it = std.mem.splitScalar(u8, content, ',');
            var idx: usize = 0;
            while (it.next()) |part| {
                if (idx >= 3) break;
                const trimmed_part = std.mem.trim(u8, part, " \t");
                components[idx] = std.fmt.parseFloat(f32, trimmed_part) catch return null;
                idx += 1;
            }
            if (idx != 3) return null;
            return .{ .vector = components };
        } else if (std.mem.eql(u8, type_str, "rotation")) {
            // Rotation/quaternion format: <x, y, z, s>
            const trimmed = std.mem.trim(u8, value, " \t");
            if (trimmed.len < 2 or trimmed[0] != '<' or trimmed[trimmed.len - 1] != '>') {
                return null;
            }
            const content = trimmed[1 .. trimmed.len - 1];
            var components: [4]f32 = .{ 0, 0, 0, 1 };
            var it = std.mem.splitScalar(u8, content, ',');
            var idx: usize = 0;
            while (it.next()) |part| {
                if (idx >= 4) break;
                const trimmed_part = std.mem.trim(u8, part, " \t");
                components[idx] = std.fmt.parseFloat(f32, trimmed_part) catch return null;
                idx += 1;
            }
            if (idx != 4) return null;
            return .{ .quaternion = components };
        }
        return null;
    }

    /// Parse builtins from source text (builtins.txt format)
    pub fn parseBuiltins(self: *BuiltinsDatabase, source: []const u8) !void {
        const gpa = self.arena.allocator();

        var lines = std.mem.splitAny(u8, source, "\r\n");
        while (lines.next()) |line| {
            // Skip empty lines and comments
            const trimmed = std.mem.trim(u8, line, " \t");
            if (trimmed.len == 0) continue;
            if (std.mem.startsWith(u8, trimmed, "//")) continue;

            // Parse: const <type> <name> = <value>
            var parts = std.mem.tokenizeAny(u8, trimmed, " \t");

            const first = parts.next() orelse continue;
            if (!std.mem.eql(u8, first, "const")) continue;

            const type_str = parts.next() orelse continue;
            const name = parts.next() orelse continue;

            // Skip TRUE and FALSE (they're handled differently in Lua)
            if (std.mem.eql(u8, name, "TRUE") or std.mem.eql(u8, name, "FALSE")) continue;

            const eq = parts.next() orelse continue;
            if (!std.mem.eql(u8, eq, "=")) continue;

            // The value is everything after '='
            const eq_pos = std.mem.indexOf(u8, trimmed, "=") orelse continue;
            const value_str = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t");

            if (self.parseConstantValue(type_str, value_str)) |maybe_const| {
                if (maybe_const) |constant| {
                    // Store the name in our arena
                    const stored_name = try gpa.dupe(u8, name);
                    try self.constants.put(gpa, stored_name, constant);
                }
            } else |err| {
                return err;
            }
        }
    }

    /// Look up a constant by name
    pub fn getConstant(self: *const BuiltinsDatabase, name: []const u8) ?SLConstant {
        return self.constants.get(name);
    }

    /// Set all constants as globals on the Lua state
    pub fn setConstantGlobals(self: *const BuiltinsDatabase, lua: *Lua) void {
        var it = self.constants.iterator();
        while (it.next()) |entry| {
            const name = entry.key_ptr.*;
            const constant = entry.value_ptr.*;

            // Push the constant value
            constant.pushToLua(lua);

            // Set as global (need null-terminated string)
            const name_z = lua.allocator().dupeZ(u8, name) catch continue;
            defer lua.allocator().free(name_z);
            lua.setGlobal(name_z);
        }
    }
};

/// Check if a string matches UUID format (8-4-4-4-12 hex chars)
fn isUUID(str: []const u8) bool {
    if (str.len != 36) return false;
    // Format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    const expected_dashes = [_]usize{ 8, 13, 18, 23 };
    for (expected_dashes) |pos| {
        if (str[pos] != '-') return false;
    }
    for (str, 0..) |char, i| {
        // Skip dash positions
        var is_dash_pos = false;
        for (expected_dashes) |pos| {
            if (i == pos) {
                is_dash_pos = true;
                break;
            }
        }
        if (is_dash_pos) continue;
        // Must be hex digit
        if (!std.ascii.isHex(char)) return false;
    }
    return true;
}

/// Thread-local builtins database (matches slua's static globals)
threadlocal var global_builtins: ?BuiltinsDatabase = null;

/// Initialize global builtins from embedded data or file
/// This matches slua's luauSL_init_global_builtins()
/// If builtins_file is null, uses embedded builtins data.
pub fn initGlobalBuiltins(allocator: Allocator, builtins_file: ?[]const u8) !void {
    if (global_builtins) |*existing| {
        existing.deinit();
    }

    var db = BuiltinsDatabase.init(allocator);

    if (builtins_file) |path| {
        // Load from file
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            std.debug.print("couldn't open builtins file: {s}\n", .{path});
            return err;
        };
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
        defer allocator.free(content);

        try db.parseBuiltins(content);
    } else {
        // Use embedded data
        try db.parseBuiltins(embedded_builtins_data);
    }

    global_builtins = db;
}

/// Deinitialize global builtins and free all memory
pub fn deinitGlobalBuiltins() void {
    if (global_builtins) |*db| {
        db.deinit();
        global_builtins = null;
    }
}

/// Set the global builtins constants on a Lua state
/// This matches slua's luaSL_set_constant_globals()
pub fn setConstantGlobals(lua: *Lua) void {
    if (global_builtins) |*db| {
        db.setConstantGlobals(lua);
    }
}

/// Look up a constant for compile-time folding
/// This can be used to implement the luauSL_lookup_constant_cb callback
pub fn lookupConstant(name: []const u8) ?SLConstant {
    if (global_builtins) |*db| {
        return db.getConstant(name);
    }
    return null;
}

// Unit tests
test "parse integer constant" {
    var db = BuiltinsDatabase.init(std.testing.allocator);
    defer db.deinit();

    try db.parseBuiltins("const integer TEST = 42");
    const val = db.getConstant("TEST");
    try std.testing.expect(val != null);
    try std.testing.expectEqual(@as(i32, 42), val.?.integer);
}

test "parse hex integer constant" {
    var db = BuiltinsDatabase.init(std.testing.allocator);
    defer db.deinit();

    try db.parseBuiltins("const integer HEX_TEST = 0xFF");
    const val = db.getConstant("HEX_TEST");
    try std.testing.expect(val != null);
    try std.testing.expectEqual(@as(i32, 255), val.?.integer);
}

test "parse float constant" {
    var db = BuiltinsDatabase.init(std.testing.allocator);
    defer db.deinit();

    try db.parseBuiltins("const float PI = 3.14159265");
    const val = db.getConstant("PI");
    try std.testing.expect(val != null);
    try std.testing.expectApproxEqRel(@as(f32, 3.14159265), val.?.float, 0.0001);
}

test "parse string constant" {
    var db = BuiltinsDatabase.init(std.testing.allocator);
    defer db.deinit();

    try db.parseBuiltins("const string EOF = \"\\n\\n\\n\"");
    const val = db.getConstant("EOF");
    try std.testing.expect(val != null);
    try std.testing.expectEqualStrings("\n\n\n", val.?.string);
}

test "parse key constant (UUID)" {
    var db = BuiltinsDatabase.init(std.testing.allocator);
    defer db.deinit();

    try db.parseBuiltins("const key NULL_KEY = \"00000000-0000-0000-0000-000000000000\"");
    const val = db.getConstant("NULL_KEY");
    try std.testing.expect(val != null);
    try std.testing.expectEqualStrings("00000000-0000-0000-0000-000000000000", val.?.key);
}

test "parse vector constant" {
    var db = BuiltinsDatabase.init(std.testing.allocator);
    defer db.deinit();

    try db.parseBuiltins("const vector ZERO_VECTOR = <0.0, 0.0, 0.0>");
    const val = db.getConstant("ZERO_VECTOR");
    try std.testing.expect(val != null);
    try std.testing.expectEqual([3]f32{ 0.0, 0.0, 0.0 }, val.?.vector);
}

test "parse rotation constant" {
    var db = BuiltinsDatabase.init(std.testing.allocator);
    defer db.deinit();

    try db.parseBuiltins("const rotation ZERO_ROTATION = <0.0, 0.0, 0.0, 1.0>");
    const val = db.getConstant("ZERO_ROTATION");
    try std.testing.expect(val != null);
    try std.testing.expectEqual([4]f32{ 0.0, 0.0, 0.0, 1.0 }, val.?.quaternion);
}

test "parse multiple constants" {
    var db = BuiltinsDatabase.init(std.testing.allocator);
    defer db.deinit();

    const source =
        \\// Generated by gen_definitions.py
        \\const integer ACTIVE = 0x2
        \\const integer AGENT = 0x1
        \\const float DEG_TO_RAD = 0.017453293
        \\const string EOF = "\n\n\n"
        \\const vector ZERO_VECTOR = <0.0, 0.0, 0.0>
        \\const rotation ZERO_ROTATION = <0.0, 0.0, 0.0, 1.0>
    ;

    try db.parseBuiltins(source);

    try std.testing.expect(db.getConstant("ACTIVE") != null);
    try std.testing.expect(db.getConstant("AGENT") != null);
    try std.testing.expect(db.getConstant("DEG_TO_RAD") != null);
    try std.testing.expect(db.getConstant("EOF") != null);
    try std.testing.expect(db.getConstant("ZERO_VECTOR") != null);
    try std.testing.expect(db.getConstant("ZERO_ROTATION") != null);
}

test "skip TRUE and FALSE" {
    var db = BuiltinsDatabase.init(std.testing.allocator);
    defer db.deinit();

    try db.parseBuiltins(
        \\const integer TRUE = 1
        \\const integer FALSE = 0
    );

    try std.testing.expect(db.getConstant("TRUE") == null);
    try std.testing.expect(db.getConstant("FALSE") == null);
}

test "skip comments and empty lines" {
    var db = BuiltinsDatabase.init(std.testing.allocator);
    defer db.deinit();

    try db.parseBuiltins(
        \\// This is a comment
        \\
        \\const integer VALUE = 42
        \\// Another comment
    );

    try std.testing.expect(db.getConstant("VALUE") != null);
    try std.testing.expectEqual(@as(i32, 42), db.getConstant("VALUE").?.integer);
}

test "isUUID function" {
    try std.testing.expect(isUUID("00000000-0000-0000-0000-000000000000"));
    try std.testing.expect(isUUID("12345678-1234-1234-1234-123456789abc"));
    try std.testing.expect(!isUUID("not-a-uuid"));
    try std.testing.expect(!isUUID("00000000-0000-0000-0000-00000000000")); // too short
    try std.testing.expect(!isUUID("00000000-0000-0000-0000-0000000000000")); // too long
    try std.testing.expect(!isUUID("0000000000000000000000000000000000000")); // no dashes
}

test "parse entire builtins_data.txt" {
    var db = BuiltinsDatabase.init(std.testing.allocator);
    defer db.deinit();

    // Parse the entire embedded builtins file
    try db.parseBuiltins(embedded_builtins_data);

    // Verify we parsed a substantial number of constants
    // The builtins_data.txt file has 974 lines, with many constants
    try std.testing.expect(db.constants.count() > 100);

    // Verify some well-known LSL constants exist and have correct values

    // Math constants
    const pi = db.getConstant("PI");
    try std.testing.expect(pi != null);
    try std.testing.expectApproxEqRel(@as(f32, 3.14159265), pi.?.float, 0.0001);

    const deg_to_rad = db.getConstant("DEG_TO_RAD");
    try std.testing.expect(deg_to_rad != null);
    try std.testing.expectApproxEqRel(@as(f32, 0.017453293), deg_to_rad.?.float, 0.0001);

    // Zero values
    const zero_vector = db.getConstant("ZERO_VECTOR");
    try std.testing.expect(zero_vector != null);
    try std.testing.expectEqual([3]f32{ 0.0, 0.0, 0.0 }, zero_vector.?.vector);

    const zero_rotation = db.getConstant("ZERO_ROTATION");
    try std.testing.expect(zero_rotation != null);
    try std.testing.expectEqual([4]f32{ 0.0, 0.0, 0.0, 1.0 }, zero_rotation.?.quaternion);

    const null_key = db.getConstant("NULL_KEY");
    try std.testing.expect(null_key != null);
    try std.testing.expectEqualStrings("00000000-0000-0000-0000-000000000000", null_key.?.key);

    // String constants
    const eof = db.getConstant("EOF");
    try std.testing.expect(eof != null);
    try std.testing.expectEqualStrings("\n\n\n", eof.?.string);

    // Integer constants (hex values)
    const active = db.getConstant("ACTIVE");
    try std.testing.expect(active != null);
    try std.testing.expectEqual(@as(i32, 0x2), active.?.integer);

    const agent = db.getConstant("AGENT");
    try std.testing.expect(agent != null);
    try std.testing.expectEqual(@as(i32, 0x1), agent.?.integer);

    // Verify TRUE and FALSE are skipped (as intended)
    try std.testing.expect(db.getConstant("TRUE") == null);
    try std.testing.expect(db.getConstant("FALSE") == null);
}
