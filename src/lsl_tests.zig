const std = @import("std");
const testing = std.testing;

const zslua = @import("zslua");

const Lua = zslua.Lua;

const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectEqualStrings = testing.expectEqualStrings;
const expectError = testing.expectError;

// Helper function to initialize Lua with LSL libraries
fn initLSLState(allocator: std.mem.Allocator) !*Lua {
    const lua: *Lua = try .init(allocator);
    // Set up thread data to mark this as an LSL VM before opening libs
    try lua.initLSLThreadData(allocator);
    lua.openLibs();

    lua.openSL(true); // Open SL library with internal functions for testing
    lua.openLSL(); // Open LSL-specific functions (tovector, toquaternion, uuid, etc.)
    lua.pop(1); // Pop the lsl module table
    lua.openLL(true); // Open ll library functions with testing functions
    lua.pop(1); // Pop the ll module table
    return lua;
}

// LSL-specific tests translated from slua/tests/LSL.test.cpp

test "LSL vector type" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test creating and casting vectors
    try lua.doString(
        \\local v = tovector(1, 2, 3)
        \\return typeof(v) == "vector"
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL quaternion type" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test creating and casting quaternions
    try lua.doString(
        \\local q = toquaternion(1, 2, 3, 4)
        \\return typeof(q) == "vector"
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL UUID type" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test UUID creation and comparison
    try lua.doString(
        \\local u1 = uuid("00000000-0000-0000-0000-000000000001")
        \\local u2 = uuid("00000000-0000-0000-0000-000000000001")
        \\return u1 == u2
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL integer cast" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test integer() cast function
    try lua.doString(
        \\return integer(5.7) == 5
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL vector arithmetic" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test vector addition
    try lua.doString(
        \\local v1 = tovector(1, 2, 3)
        \\local v2 = tovector(4, 5, 6)
        \\local result = v1 + v2
        \\return result.x == 5 and result.y == 7 and result.z == 9
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL vector scalar multiplication" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test vector * scalar
    try lua.doString(
        \\local v = tovector(1, 2, 3)
        \\local result = v * 2
        \\return result.x == 2 and result.y == 4 and result.z == 6
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL quaternion multiplication" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test identity quaternion multiplication
    try lua.doString(
        \\local v = tovector(1, 2, 3)
        \\local q = toquaternion(0, 0, 0, 1) -- identity quaternion
        \\local result = v * q
        \\return result.x == 1 and result.y == 2 and result.z == 3
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL list operations" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test list concatenation
    try lua.doString(
        \\local list1 = {1, 2, 3}
        \\local list2 = {4, 5, 6}
        \\local result = {}
        \\for i, v in ipairs(list1) do result[i] = v end
        \\for i, v in ipairs(list2) do result[#list1 + i] = v end
        \\return #result == 6
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL string cast" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test casting various types to string
    try lua.doString(
        \\local num_str = tostring(42)
        \\local float_str = tostring(3.14)
        \\return num_str == "42" and float_str == "3.14"
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL vector string cast" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test vector to string conversion
    try lua.doString(
        \\local v = tovector(1, 2, 3)
        \\local str = tostring(v)
        \\-- LSL format: "<1.00000, 2.00000, 3.00000>"
        \\return string.find(str, "1") ~= nil and string.find(str, "2") ~= nil and string.find(str, "3") ~= nil
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL type checking" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test typeof() for different LSL types
    try lua.doString(
        \\local v = tovector(1, 2, 3)
        \\local q = toquaternion(1, 2, 3, 4)
        \\local u = uuid("00000000-0000-0000-0000-000000000001")
        \\return typeof(v) == "vector" and typeof(q) == "vector" and typeof(u) == "uuid"
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL comparison operators" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test basic comparison operators (from conformance/comparison.lsl)
    try lua.doString(
        \\return (1 == 1) and not (1 == 2) and (1 ~= 2) and (1 < 2) and not (1 > 2) and not (1 >= 2) and (1 <= 2) and (2 <= 2) and (2 >= 2)
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL boolean operators" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test boolean AND/OR operators
    try lua.doString(
        \\local t = true
        \\local f = false
        \\return (t and t) and not (t and f) and not (f and t) and not (f and f) and (t or t) and (t or f) and (f or t) and not (f or f)
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL bitwise operators" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test bitwise operations
    try lua.doString(
        \\return (3 & 2) == 2 and (0xFFaaAAaa | 0x000000F0) == 0xFFaaAAfa and (0x000000F0 ~ 0xF0F0F0F0) == 0xF0F0F000
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL NULL_KEY constant" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test NULL_KEY constant
    try lua.doString(
        \\return NULL_KEY == uuid("00000000-0000-0000-0000-000000000000")
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL vector component access" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test accessing vector components
    try lua.doString(
        \\local v = tovector(1, 2, 3)
        \\return v.x == 1 and v.y == 2 and v.z == 3
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL quaternion component access" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test accessing quaternion components
    try lua.doString(
        \\local q = toquaternion(1, 2, 3, 4)
        \\return q.x == 1 and q.y == 2 and q.z == 3 and q.s == 4
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL vector component mutation" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test mutating vector components
    try lua.doString(
        \\local v = tovector(1, 2, 3)
        \\v.x = 5
        \\return v.x == 5 and v.y == 2 and v.z == 3
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL for loop" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test for loop (from conformance/for.lsl)
    try lua.doString(
        \\local results = {}
        \\for i = 0, 2 do
        \\  table.insert(results, i)
        \\end
        \\return #results == 3 and results[1] == 0 and results[2] == 1 and results[3] == 2
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL while loop" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test while loop
    try lua.doString(
        \\local i = 0
        \\local sum = 0
        \\while i < 3 do
        \\  sum = sum + i
        \\  i = i + 1
        \\end
        \\return sum == 3 and i == 3
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL do-while loop" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test do-while loop (simulated with repeat-until in Lua)
    try lua.doString(
        \\local i = 0
        \\local sum = 0
        \\repeat
        \\  sum = sum + i
        \\  i = i + 1
        \\until i >= 3
        \\return sum == 3 and i == 3
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL if statement" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test if/else statement
    try lua.doString(
        \\local function test(x)
        \\  if x > 0 then
        \\    return "positive"
        \\  elseif x < 0 then
        \\    return "negative"
        \\  else
        \\    return "zero"
        \\  end
        \\end
        \\return test(5) == "positive" and test(-5) == "negative" and test(0) == "zero"
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL function return values" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test functions returning different types (from conformance1.lsl)
    try lua.doString(
        \\local function returnInteger()
        \\  return 42
        \\end
        \\local function returnFloat()
        \\  return 1.5
        \\end
        \\local function returnString()
        \\  return "test"
        \\end
        \\local function returnVector()
        \\  return tovector(1, 2, 3)
        \\end
        \\return returnInteger() == 42 and returnFloat() == 1.5 and returnString() == "test" and returnVector().x == 1
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL nested function calls" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test nested function calls
    try lua.doString(
        \\local function double(x)
        \\  return x * 2
        \\end
        \\local function add(a, b)
        \\  return a + b
        \\end
        \\return add(double(2), double(3)) == 10
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL recursion" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test recursive function
    try lua.doString(
        \\local function factorial(n)
        \\  if n <= 0 then
        \\    return 1
        \\  else
        \\    return n * factorial(n - 1)
        \\  end
        \\end
        \\return factorial(5) == 120
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL constant folding" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test constant arithmetic optimization
    try lua.doString(
        \\-- These should be folded at compile time
        \\local a = 2.5 + 4.5  -- 7.0
        \\local b = 10 - 5     -- 5
        \\local c = 4 * 5      -- 20
        \\local d = 10 / 4     -- 2.5
        \\return a == 7.0 and b == 5 and c == 20 and d == 2.5
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL type conversion" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test implicit and explicit type conversions
    try lua.doString(
        \\local i = 42
        \\local f = 3.14
        \\local s_from_int = tostring(i)
        \\local s_from_float = tostring(f)
        \\local i_from_string = tonumber("100")
        \\return s_from_int == "42" and s_from_float == "3.14" and i_from_string == 100
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL list manipulation" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test list operations
    try lua.doString(
        \\local list = {1, 2, 3}
        \\table.insert(list, 4)
        \\table.insert(list, 2, 99) -- insert at position 2
        \\local removed = table.remove(list, 3) -- remove position 3
        \\return #list == 4 and list[2] == 99 and removed == 2
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL increment/decrement" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test increment and decrement operations
    try lua.doString(
        \\local x = 5
        \\x = x + 1  -- pre-increment equivalent
        \\local y = x
        \\x = x - 1  -- post-decrement equivalent
        \\return y == 6 and x == 5
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL compound assignment" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test compound assignment operators
    try lua.doString(
        \\local x = 10
        \\x = x + 5  -- +=
        \\local y = x
        \\x = x - 3  -- -=
        \\local z = x
        \\x = x * 2  -- *=
        \\local w = x
        \\x = x / 4  -- /=
        \\return y == 15 and z == 12 and w == 24 and x == 6
    );
    try expectEqual(true, lua.toBoolean(-1));
}

// ll.GetSubString tests (from slua's lll.cpp)

test "ll.GetSubString basic" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test basic substring extraction with 0-based (LSL compat) indexing
    // ll.GetSubString is registered from lltestcompateligiblelib when testing_funcs=true
    try lua.doString(
        \\return ll.GetSubString("hello world", 0, 4) == "hello"
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "ll.GetSubString UTF-8" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test UTF-8 aware substring extraction
    // ll.GetSubString operates on codepoints, not bytes
    try lua.doString(
        \\return ll.GetSubString("héllo", 0, 1) == "hé"
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "ll.GetSubString wraparound" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test wraparound (start > end returns both ends)
    try lua.doString(
        \\return ll.GetSubString("abcdefghij", 8, 1) == "abij"
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "ll.GetSubString negative indices" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Test negative indices (from end of string)
    try lua.doString(
        \\return ll.GetSubString("hello", -2, -1) == "lo"
    );
    try expectEqual(true, lua.toBoolean(-1));
}

// LSL Builtins tests

test "LSL builtins: initialize and set constant globals" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    // Initialize builtins from embedded data
    try Lua.initLSLBuiltins(testing.allocator, null);
    defer Lua.deinitLSLBuiltins();

    // Set constants as globals
    lua.setLSLConstantGlobals();

    // Test that PI is defined
    try lua.doString(
        \\return PI
    );
    const pi_val = try lua.toNumber(-1);
    try expect(@abs(pi_val - 3.14159265) < 0.0001);
}

test "LSL builtins: NULL_KEY constant" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    try Lua.initLSLBuiltins(testing.allocator, null);
    defer Lua.deinitLSLBuiltins();
    lua.setLSLConstantGlobals();

    // Test NULL_KEY is the correct UUID
    try lua.doString(
        \\return NULL_KEY
    );
    const null_key = try lua.toString(-1);
    try expectEqualStrings("00000000-0000-0000-0000-000000000000", null_key);
}

test "LSL builtins: ZERO_VECTOR constant" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    try Lua.initLSLBuiltins(testing.allocator, null);
    defer Lua.deinitLSLBuiltins();
    lua.setLSLConstantGlobals();

    // Test ZERO_VECTOR is <0,0,0>
    try lua.doString(
        \\return ZERO_VECTOR.x == 0 and ZERO_VECTOR.y == 0 and ZERO_VECTOR.z == 0
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL builtins: ZERO_ROTATION constant" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    try Lua.initLSLBuiltins(testing.allocator, null);
    defer Lua.deinitLSLBuiltins();
    lua.setLSLConstantGlobals();

    // Test ZERO_ROTATION is <0,0,0,1>
    try lua.doString(
        \\return ZERO_ROTATION.x == 0 and ZERO_ROTATION.y == 0 and ZERO_ROTATION.z == 0 and ZERO_ROTATION.w == 1
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL builtins: integer constants" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    try Lua.initLSLBuiltins(testing.allocator, null);
    defer Lua.deinitLSLBuiltins();
    lua.setLSLConstantGlobals();

    // Test various integer constants
    try lua.doString(
        \\return STATUS_PHYSICS == 0x1 and STATUS_ROTATE_X == 0x2 and PERMISSION_DEBIT == 0x2
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL builtins: math constants" {
    const lua: *Lua = try initLSLState(testing.allocator);
    defer lua.deinit();

    try Lua.initLSLBuiltins(testing.allocator, null);
    defer Lua.deinitLSLBuiltins();
    lua.setLSLConstantGlobals();

    // Test math constants
    try lua.doString(
        \\return TWO_PI > PI and DEG_TO_RAD < 1 and RAD_TO_DEG > 50
    );
    try expectEqual(true, lua.toBoolean(-1));
}

test "LSL builtins: lookupConstant" {
    try Lua.initLSLBuiltins(testing.allocator, null);
    defer Lua.deinitLSLBuiltins();

    const lsl_builtins = zslua.lsl_builtins;

    // Test looking up known constants
    const pi = lsl_builtins.lookupConstant("PI");
    try expect(pi != null);
    try expect(pi.? == .float);

    const null_key = lsl_builtins.lookupConstant("NULL_KEY");
    try expect(null_key != null);
    try expect(null_key.? == .key);

    const zero_vec = lsl_builtins.lookupConstant("ZERO_VECTOR");
    try expect(zero_vec != null);
    try expect(zero_vec.? == .vector);

    // Test unknown constant returns null
    const unknown = lsl_builtins.lookupConstant("NOT_A_CONSTANT");
    try expect(unknown == null);
}
