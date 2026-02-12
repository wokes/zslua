//! SLua Builtins - Type-correct constants for Second Life's Server Lua (SLua)
//!
//! This module provides functionality to parse SLua type declarations from
//! slua_default.d.luau and use them to set globals with the correct SLua types.
//!
//! In SLua mode, some types differ from LSL:
//! - `key` type in LSL becomes `uuid` type in SLua
//! - This module ensures constants like NULL_KEY are pushed as proper uuid userdata
//!
//! The slua_default.d.luau format for globals:
//! - declare NAME: number
//! - declare NAME: string
//! - declare NAME: uuid
//! - declare NAME: vector
//! - declare NAME: quaternion

const std = @import("std");
const lib = @import("lib.zig");
const lsl_builtins = @import("lsl_builtins.zig");
const Lua = lib.Lua;
const Allocator = std.mem.Allocator;

/// Embedded SLua definitions data (loaded at compile time)
pub const embedded_slua_defs: []const u8 = @embedFile("slua_default.d.luau");

/// SLua type enumeration - types available in SLua
pub const SLuaType = enum {
    number,
    string,
    uuid,
    vector,
    quaternion,
    unknown,
};

/// Storage for SLua type information
pub const SLuaTypeDatabase = struct {
    /// Maps constant name to its SLua type
    types: std.StringHashMapUnmanaged(SLuaType),
    /// Arena allocator for string storage
    arena: std.heap.ArenaAllocator,

    pub const empty: SLuaTypeDatabase = .{
        .types = .empty,
        .arena = undefined,
    };

    pub fn init(child_allocator: Allocator) SLuaTypeDatabase {
        return .{
            .types = .empty,
            .arena = std.heap.ArenaAllocator.init(child_allocator),
        };
    }

    pub fn deinit(self: *SLuaTypeDatabase) void {
        self.types.clearAndFree(self.arena.allocator());
        self.arena.deinit();
        self.* = undefined;
    }

    /// Parse a type string to SLuaType enum
    fn parseType(type_str: []const u8) SLuaType {
        if (std.mem.eql(u8, type_str, "number")) {
            return .number;
        } else if (std.mem.eql(u8, type_str, "string")) {
            return .string;
        } else if (std.mem.eql(u8, type_str, "uuid")) {
            return .uuid;
        } else if (std.mem.eql(u8, type_str, "vector")) {
            return .vector;
        } else if (std.mem.eql(u8, type_str, "quaternion") or std.mem.eql(u8, type_str, "rotation")) {
            return .quaternion;
        }
        return .unknown;
    }

    /// Parse SLua type declarations from the .d.luau format
    /// Looks for lines like: declare NAME: type
    pub fn parseDeclarations(self: *SLuaTypeDatabase, source: []const u8) !void {
        const gpa = self.arena.allocator();

        var lines = std.mem.splitAny(u8, source, "\r\n");
        while (lines.next()) |line| {
            // Skip empty lines and comments
            const trimmed = std.mem.trim(u8, line, " \t");
            if (trimmed.len == 0) continue;
            if (std.mem.startsWith(u8, trimmed, "--")) continue;

            // Look for: declare NAME: type
            // Skip function declarations and complex declarations
            if (!std.mem.startsWith(u8, trimmed, "declare ")) continue;
            if (std.mem.indexOf(u8, trimmed, "function") != null) continue;
            if (std.mem.indexOf(u8, trimmed, "extern") != null) continue;
            if (std.mem.indexOf(u8, trimmed, "(") != null) continue;
            if (std.mem.indexOf(u8, trimmed, "{") != null) continue;

            // Parse: declare NAME: type
            const after_declare = trimmed["declare ".len..];
            const colon_pos = std.mem.indexOf(u8, after_declare, ":") orelse continue;

            const name = std.mem.trim(u8, after_declare[0..colon_pos], " \t");
            const type_str = std.mem.trim(u8, after_declare[colon_pos + 1 ..], " \t");

            // Skip empty names or types
            if (name.len == 0 or type_str.len == 0) continue;

            // Skip names that contain invalid characters (like compound expressions)
            var valid_name = true;
            for (name) |ch| {
                if (!std.ascii.isAlphanumeric(ch) and ch != '_') {
                    valid_name = false;
                    break;
                }
            }
            if (!valid_name) continue;

            const slua_type = parseType(type_str);
            if (slua_type == .unknown) continue;

            // Store the name in our arena
            const stored_name = try gpa.dupe(u8, name);
            try self.types.put(gpa, stored_name, slua_type);
        }
    }

    /// Look up the SLua type for a constant name
    pub fn getType(self: *const SLuaTypeDatabase, name: []const u8) ?SLuaType {
        return self.types.get(name);
    }
};

/// Combines LSL constant values with SLua type information
pub const SLuaBuiltinsDatabase = struct {
    /// The underlying LSL constants (values)
    lsl_builtins: lsl_builtins.BuiltinsDatabase,
    /// SLua type overrides
    slua_types: SLuaTypeDatabase,

    pub fn init(allocator: Allocator) SLuaBuiltinsDatabase {
        return .{
            .lsl_builtins = lsl_builtins.BuiltinsDatabase.init(allocator),
            .slua_types = SLuaTypeDatabase.init(allocator),
        };
    }

    pub fn deinit(self: *SLuaBuiltinsDatabase) void {
        self.lsl_builtins.deinit();
        self.slua_types.deinit();
        self.* = undefined;
    }

    /// Parse both LSL constants and SLua type declarations
    pub fn parseBuiltins(self: *SLuaBuiltinsDatabase, lsl_source: []const u8, slua_source: []const u8) !void {
        try self.lsl_builtins.parseBuiltins(lsl_source);
        try self.slua_types.parseDeclarations(slua_source);
    }

    /// Look up a constant by name
    pub fn getConstant(self: *const SLuaBuiltinsDatabase, name: []const u8) ?lsl_builtins.SLConstant {
        return self.lsl_builtins.getConstant(name);
    }

    /// Get the SLua type for a constant (if different from LSL type)
    pub fn getSLuaType(self: *const SLuaBuiltinsDatabase, name: []const u8) ?SLuaType {
        return self.slua_types.getType(name);
    }

    /// Push a constant with the correct SLua type onto the Lua stack
    pub fn pushConstantSLua(self: *const SLuaBuiltinsDatabase, lua: *Lua, name: []const u8, constant: lsl_builtins.SLConstant) void {
        const slua_type = self.slua_types.getType(name);

        // Check if we need to convert the type for SLua
        if (slua_type) |st| {
            switch (st) {
                .uuid => {
                    // In SLua, uuid types should be pushed as uuid userdata
                    // The source value might be a key or string type in LSL
                    switch (constant) {
                        .key => |val| {
                            lua.pushUUID(val);
                            return;
                        },
                        .string => |val| {
                            // String that should be a uuid in SLua
                            lua.pushUUID(val);
                            return;
                        },
                        else => {},
                    }
                },
                .quaternion => {
                    // In SLua, rotation/quaternion types should be pushed as quaternion userdata
                    switch (constant) {
                        .quaternion => |val| {
                            lua.pushQuaternion(val[0], val[1], val[2], val[3]);
                            return;
                        },
                        else => {},
                    }
                },
                .vector => {
                    // Vector types - use standard pushVector
                    switch (constant) {
                        .vector => |val| {
                            lua.pushVector(val[0], val[1], val[2]);
                            return;
                        },
                        else => {},
                    }
                },
                .number => {
                    // Number types - integer or float
                    switch (constant) {
                        .integer => |val| {
                            lua.pushNumber(@floatFromInt(val));
                            return;
                        },
                        .float => |val| {
                            lua.pushNumber(@floatCast(val));
                            return;
                        },
                        else => {},
                    }
                },
                .string => {
                    // String types
                    switch (constant) {
                        .string => |val| {
                            _ = lua.pushString(val);
                            return;
                        },
                        .key => |val| {
                            // Key that should remain as string in SLua
                            _ = lua.pushString(val);
                            return;
                        },
                        else => {},
                    }
                },
                .unknown => {},
            }
        }

        // Fall back to standard LSL constant pushing
        constant.pushToLua(lua);
    }

    /// Set all constants as globals on the Lua state with correct SLua types
    pub fn setConstantGlobals(self: *const SLuaBuiltinsDatabase, lua: *Lua) void {
        var it = self.lsl_builtins.constants.iterator();
        while (it.next()) |entry| {
            const name = entry.key_ptr.*;
            const constant = entry.value_ptr.*;

            // Push the constant value with SLua type awareness
            self.pushConstantSLua(lua, name, constant);

            // Set as global (need null-terminated string)
            const name_z = lua.allocator().dupeZ(u8, name) catch continue;
            defer lua.allocator().free(name_z);
            lua.setGlobal(name_z);
        }
    }
};

/// Thread-local SLua builtins database
threadlocal var global_slua_builtins: ?SLuaBuiltinsDatabase = null;

/// Initialize global SLua builtins from embedded data or files
/// This parses both LSL constants (for values) and SLua declarations (for types).
///
/// If lsl_builtins_file is null, uses embedded LSL builtins data.
/// If slua_defs_file is null, uses embedded SLua definitions data.
pub fn initSLuaBuiltins(allocator: Allocator, lsl_builtins_file: ?[]const u8, slua_defs_file: ?[]const u8) !void {
    if (global_slua_builtins) |*existing| {
        existing.deinit();
    }

    var db = SLuaBuiltinsDatabase.init(allocator);

    // Load LSL builtins (values)
    var lsl_content: []const u8 = lsl_builtins.embedded_builtins_data;
    var lsl_content_owned: ?[]const u8 = null;
    defer if (lsl_content_owned) |c| allocator.free(c);

    if (lsl_builtins_file) |path| {
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            std.debug.print("couldn't open LSL builtins file: {s}\n", .{path});
            return err;
        };
        defer file.close();
        lsl_content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
        lsl_content_owned = lsl_content;
    }

    // Load SLua definitions (types)
    var slua_content: []const u8 = embedded_slua_defs;
    var slua_content_owned: ?[]const u8 = null;
    defer if (slua_content_owned) |c| allocator.free(c);

    if (slua_defs_file) |path| {
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            std.debug.print("couldn't open SLua definitions file: {s}\n", .{path});
            return err;
        };
        defer file.close();
        slua_content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
        slua_content_owned = slua_content;
    }

    try db.parseBuiltins(lsl_content, slua_content);
    global_slua_builtins = db;
}

/// Deinitialize global SLua builtins and free all memory
pub fn deinitSLuaBuiltins() void {
    if (global_slua_builtins) |*db| {
        db.deinit();
        global_slua_builtins = null;
    }
}

/// Set the global SLua builtins constants on a Lua state with correct SLua types
/// This ensures types like uuid are pushed as proper uuid userdata instead of strings.
pub fn setSLuaConstantGlobals(lua: *Lua) void {
    if (global_slua_builtins) |*db| {
        db.setConstantGlobals(lua);
    }
}

/// Look up a constant for compile-time folding (SLua-aware)
pub fn lookupConstant(name: []const u8) ?lsl_builtins.SLConstant {
    if (global_slua_builtins) |*db| {
        return db.getConstant(name);
    }
    return null;
}

/// Look up the SLua type for a constant name
pub fn lookupSLuaType(name: []const u8) ?SLuaType {
    if (global_slua_builtins) |*db| {
        return db.getSLuaType(name);
    }
    return null;
}

// Unit tests
test "parse simple slua declarations" {
    var db = SLuaTypeDatabase.init(std.testing.allocator);
    defer db.deinit();

    try db.parseDeclarations(
        \\declare ACTIVE: number
        \\declare NULL_KEY: uuid
        \\declare EOF: string
        \\declare ZERO_VECTOR: vector
        \\declare ZERO_ROTATION: quaternion
    );

    try std.testing.expectEqual(SLuaType.number, db.getType("ACTIVE").?);
    try std.testing.expectEqual(SLuaType.uuid, db.getType("NULL_KEY").?);
    try std.testing.expectEqual(SLuaType.string, db.getType("EOF").?);
    try std.testing.expectEqual(SLuaType.vector, db.getType("ZERO_VECTOR").?);
    try std.testing.expectEqual(SLuaType.quaternion, db.getType("ZERO_ROTATION").?);
}

test "skip function declarations" {
    var db = SLuaTypeDatabase.init(std.testing.allocator);
    defer db.deinit();

    try db.parseDeclarations(
        \\declare function touuid(val: string | buffer | uuid): uuid?
        \\declare function tovector(val: string | vector): vector?
        \\declare ACTIVE: number
    );

    try std.testing.expect(db.getType("touuid") == null);
    try std.testing.expect(db.getType("tovector") == null);
    try std.testing.expectEqual(SLuaType.number, db.getType("ACTIVE").?);
}

test "skip extern type declarations" {
    var db = SLuaTypeDatabase.init(std.testing.allocator);
    defer db.deinit();

    try db.parseDeclarations(
        \\declare extern type quaternion with
        \\  x: number
        \\  y: number
        \\end
        \\declare ACTIVE: number
    );

    try std.testing.expect(db.getType("quaternion") == null);
    try std.testing.expectEqual(SLuaType.number, db.getType("ACTIVE").?);
}

test "skip comments" {
    var db = SLuaTypeDatabase.init(std.testing.allocator);
    defer db.deinit();

    try db.parseDeclarations(
        \\-- This is a comment
        \\declare ACTIVE: number
        \\-- Another comment
        \\declare NULL_KEY: uuid
    );

    try std.testing.expectEqual(SLuaType.number, db.getType("ACTIVE").?);
    try std.testing.expectEqual(SLuaType.uuid, db.getType("NULL_KEY").?);
}

test "parse embedded slua definitions" {
    var db = SLuaTypeDatabase.init(std.testing.allocator);
    defer db.deinit();

    try db.parseDeclarations(embedded_slua_defs);

    // Verify we parsed a substantial number of type declarations
    try std.testing.expect(db.types.count() > 100);

    // Verify some well-known constants have correct SLua types
    try std.testing.expectEqual(SLuaType.uuid, db.getType("NULL_KEY").?);
    try std.testing.expectEqual(SLuaType.uuid, db.getType("TEXTURE_BLANK").?);
    try std.testing.expectEqual(SLuaType.uuid, db.getType("IMG_USE_BAKED_HEAD").?);

    try std.testing.expectEqual(SLuaType.number, db.getType("ACTIVE").?);
    try std.testing.expectEqual(SLuaType.number, db.getType("PI").?);

    try std.testing.expectEqual(SLuaType.string, db.getType("EOF").?);
    try std.testing.expectEqual(SLuaType.string, db.getType("JSON_ARRAY").?);

    try std.testing.expectEqual(SLuaType.vector, db.getType("ZERO_VECTOR").?);
    try std.testing.expectEqual(SLuaType.quaternion, db.getType("ZERO_ROTATION").?);
}

test "combined slua builtins database" {
    var db = SLuaBuiltinsDatabase.init(std.testing.allocator);
    defer db.deinit();

    const lsl_source =
        \\const integer ACTIVE = 0x2
        \\const key NULL_KEY = "00000000-0000-0000-0000-000000000000"
        \\const string EOF = "\n\n\n"
        \\const vector ZERO_VECTOR = <0.0, 0.0, 0.0>
    ;

    const slua_source =
        \\declare ACTIVE: number
        \\declare NULL_KEY: uuid
        \\declare EOF: string
        \\declare ZERO_VECTOR: vector
    ;

    try db.parseBuiltins(lsl_source, slua_source);

    // Check we have the values from LSL builtins
    const active = db.getConstant("ACTIVE");
    try std.testing.expect(active != null);
    try std.testing.expectEqual(@as(i32, 2), active.?.integer);

    const null_key = db.getConstant("NULL_KEY");
    try std.testing.expect(null_key != null);
    try std.testing.expectEqualStrings("00000000-0000-0000-0000-000000000000", null_key.?.key);

    // Check we have the SLua types
    try std.testing.expectEqual(SLuaType.number, db.getSLuaType("ACTIVE").?);
    try std.testing.expectEqual(SLuaType.uuid, db.getSLuaType("NULL_KEY").?);
    try std.testing.expectEqual(SLuaType.string, db.getSLuaType("EOF").?);
    try std.testing.expectEqual(SLuaType.vector, db.getSLuaType("ZERO_VECTOR").?);
}
