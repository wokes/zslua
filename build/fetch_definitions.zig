//! Build-time definition file fetcher
//!
//! Downloads LSL and SLua definition files from GitHub and places them
//! in the src directory for embedding at compile time.

const std = @import("std");

const BUILTINS_URL = "https://raw.githubusercontent.com/secondlife/slua/main/builtins.txt";
const SLUA_DEFS_URL = "https://raw.githubusercontent.com/secondlife/lsl-definitions/main/generated/slua_default.d.luau";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        std.debug.print("Usage: {s} <builtins_output> <slua_defs_output>\n", .{args[0]});
        return error.InvalidArgs;
    }

    const builtins_output = args[1];
    const slua_defs_output = args[2];

    // Download builtins.txt
    std.debug.print("Fetching builtins.txt from {s}...\n", .{BUILTINS_URL});
    try fetchWithCurl(allocator, BUILTINS_URL, builtins_output);

    // Download slua_default.d.luau
    std.debug.print("Fetching slua_default.d.luau from {s}...\n", .{SLUA_DEFS_URL});
    try fetchWithCurl(allocator, SLUA_DEFS_URL, slua_defs_output);

    std.debug.print("Definition files updated successfully.\n", .{});
}

fn fetchWithCurl(allocator: std.mem.Allocator, url: []const u8, output_path: []const u8) !void {
    var child = std.process.Child.init(&.{ "curl", "-fsSL", "-o", output_path, url }, allocator);
    child.stderr_behavior = .Inherit;
    child.stdout_behavior = .Inherit;

    _ = try child.spawnAndWait();

    // Verify the file was created
    const file = std.fs.cwd().openFile(output_path, .{}) catch |err| {
        std.debug.print("Failed to download {s}: {}\n", .{ output_path, err });
        return error.DownloadFailed;
    };
    const stat = try file.stat();
    file.close();

    std.debug.print("  -> Wrote {d} bytes to {s}\n", .{ stat.size, output_path });
}
