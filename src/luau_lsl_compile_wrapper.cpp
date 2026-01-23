// C wrapper for luau_lsl_compile that provides extern "C" linkage
// This is needed because LSLCompiler.cpp doesn't include luacode.h which has
// the extern "C" declaration, so the symbol is C++ mangled instead of C.

#include "luacode.h"  // Get the extern "C" declaration
#include "Luau/BytecodeBuilder.h"  // For getBytecode()
#include "Luau/ParseResult.h"  // For ParseErrors
#include "Luau/Compiler.h"  // For CompileError
#include "Luau/LSLCompiler.h"  // For compileLSLOrThrow

#include <string>
#include <cstring>
#include <cstdlib>

// The C API wrapper - matches the original implementation
extern "C" {

LUACODE_API char* luau_lsl_compile(const char* source, size_t size, size_t* outsize, bool* is_error) {
    *outsize = 0;
    Luau::BytecodeBuilder bcb;
    std::string result;

    try {
        compileLSLOrThrow(bcb, std::string(source, size));
        result = bcb.getBytecode();
        *is_error = false;
    }
    catch (Luau::ParseErrors& e) {
        // Format error message like the original
        std::string msg = ": Parse Errors:";
        for (const Luau::ParseError& error : e.getErrors()) {
            char line_msg[256];
            snprintf(line_msg, sizeof(line_msg), "\nLine %d: %s",
                     error.getLocation().begin.line, error.what());
            msg += line_msg;
        }
        result = msg;
        *is_error = true;
    }
    catch (Luau::CompileError& e) {
        char line_msg[512];
        snprintf(line_msg, sizeof(line_msg), ":%d: %s",
                 e.getLocation().begin.line, e.what());
        result = line_msg;
        *is_error = true;
    }
    catch (...) {
        result = "Unknown compilation error";
        *is_error = true;
    }

    char* copy = static_cast<char*>(malloc(result.size()));
    if (!copy)
        return nullptr;

    memcpy(copy, result.data(), result.size());
    *outsize = result.size();
    return copy;
}

} // extern "C"
