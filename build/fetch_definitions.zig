//! Build-time definition file fetcher
//!
//! Downloads LSL and SLua definition files from GitHub and places them
//! in the src directory for embedding at compile time.
//! Falls back to existing local copies with a warning if download fails.

const std = @import("std");

const BUILTINS_URL = "https://raw.githubusercontent.com/secondlife/lsl-definitions/main/generated/builtins.txt";
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

    var any_missing = false;
    if (!fetchOrFallback(allocator, BUILTINS_URL, args[1])) any_missing = true;
    if (!fetchOrFallback(allocator, SLUA_DEFS_URL, args[2])) any_missing = true;

    if (any_missing) {
        std.debug.print("Error: Required definition files are missing and could not be downloaded.\n", .{});
        std.debug.print("Please check your internet connection and try again.\n", .{});
        return error.MissingDefinitions;
    }
}

/// Attempts to download the file from url to output_path.
/// On failure, checks if a local copy exists as fallback.
/// Returns true if the file is available (fresh or cached), false if missing entirely.
fn fetchOrFallback(allocator: std.mem.Allocator, url: []const u8, output_path: []const u8) bool {
    fetchWithCurl(allocator, url, output_path) catch {
        // Download failed — check if existing local copy can be used as fallback
        if (fileExists(output_path)) {
            std.debug.print("Warning: Could not fetch latest {s}, using existing local copy\n", .{output_path});
            return true;
        }
        std.debug.print("Error: Could not fetch {s} and no local copy exists\n", .{output_path});
        return false;
    };
    return true;
}

fn fetchWithCurl(allocator: std.mem.Allocator, url: []const u8, output_path: []const u8) !void {
    // Download to a temp file to avoid corrupting existing copy on failure
    const tmp_path = try std.fmt.allocPrint(allocator, "{s}.tmp", .{output_path});
    defer allocator.free(tmp_path);
    errdefer {
        std.fs.cwd().deleteFile(tmp_path) catch {};
    }

    var child = std.process.Child.init(&.{
        "curl",              "-fsSL",
        "--connect-timeout", "5",
        "--max-time",        "15",
        "-o",                tmp_path,
        url,
    }, allocator);
    child.stderr_behavior = .Ignore;
    child.stdout_behavior = .Ignore;

    _ = child.spawnAndWait() catch return error.CurlFailed;

    // Verify the download produced a non-empty file
    const size = blk: {
        const file = std.fs.cwd().openFile(tmp_path, .{}) catch return error.DownloadFailed;
        defer file.close();
        const stat = file.stat() catch return error.DownloadFailed;
        break :blk stat.size;
    };
    if (size == 0) return error.DownloadFailed;

    // Replace the existing file with the downloaded one
    std.fs.cwd().rename(tmp_path, output_path) catch |err| {
        std.debug.print("Failed to replace {s}: {}\n", .{ output_path, err });
        return error.RenameFailed;
    };

    std.debug.print("Updated {s} ({d} bytes)\n", .{ output_path, size });
}

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}
