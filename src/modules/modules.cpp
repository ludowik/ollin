#include "modules.h"
#include <stdexcept>

Value makeCoreModule();
Value makeMathModule();
Value makeGraphicsModule();
Value makeStringModule();
Value makeColorsModule();
Value makeWindowModule();

static const struct { const char* name; Value(*make)(); } k_modules[] = {
    { "core",     makeCoreModule     },
    { "math",     makeMathModule     },
    { "graphics", makeGraphicsModule },
    { "string",   makeStringModule   },
    { "colors",   makeColorsModule   },
    { "window",   makeWindowModule   },
};

const std::vector<std::string>& builtinModuleNames() {
    static const std::vector<std::string> names = [] {
        std::vector<std::string> v;
        for (auto& m : k_modules) v.push_back(m.name);
        return v;
    }();
    return names;
}

const std::vector<std::string>& builtinFuncNames() {
    static const std::vector<std::string> names = {
        "print", "printf", "typeof", "assert", "time", "Color", "len"
    };
    return names;
}

Value makeBuiltinModule(const std::string& name) {
    for (auto& m : k_modules)
        if (name == m.name) return m.make();
    throw std::runtime_error("unknown built-in module: " + name);
}
