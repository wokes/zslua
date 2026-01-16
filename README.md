# ZSLua
Zig bindings for [SLua](https://github.com/secondlife/slua)

## Work In Progress
At the moment it might not expose everything it needs to and might need further changes.

## Contributing
Please make suggestions, create PRs, report bugs!

Everyone is welcome to contribute.

## Usage
A quick little test program might look something like this:
```zig
const std = @import("std");
const zslua = @import("zslua");
const Allocator = std.mem.Allocator;
const slua = zslua.Lua;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const L = try slua.init(allocator);
    defer L.deinit();

    try L.initLSLThreadData(allocator);
    defer L.deinitLSLThreadData();

    slua.openLibs(L);
    slua.openSL(L, true);

    slua.openLSL(L);
    slua.pop(L, 1);

    slua.openLL(L, true);
    slua.pop(L, 1);

    slua.openLLJson(L);
    slua.pop(L, 1);

    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);

    const builtins_path = try std.fs.path.join(allocator, &[_][]const u8{ cwd, "builtins.txt" });
    defer allocator.free(builtins_path);

    try slua.initLSLBuiltins(allocator, builtins_path);
    defer slua.deinitLSLBuiltins();

    slua.setLSLConstantGlobals(L);

    try slua.doString(L, "ll.OwnerSay(lljson.encode({ Hello={'from', 'zslua!'}}))");
}
```

Output:
```
> ./zig-out/bin/zsl_vm.exe
{"Hello":["from","zslua!"]}
Script finished with status: 0, stack size: 0
```
