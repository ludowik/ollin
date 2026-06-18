#include "modules.h"
#include <stdexcept>

Value makeMathModule();
#ifndef OLLIN_WASM
Value makeGraphicsModule();
#endif

static const struct { const char* name; Value(*make)(); } k_modules[] = {
    { "math",     makeMathModule     },
#ifndef OLLIN_WASM
    { "graphics", makeGraphicsModule },
#endif
};

const std::vector<std::string>& builtinModuleNames() {
    static const std::vector<std::string> names = [] {
        std::vector<std::string> v;
        for (auto& m : k_modules) v.push_back(m.name);
        return v;
    }();
    return names;
}

Value makeBuiltinModule(const std::string& name) {
    for (auto& m : k_modules)
        if (name == m.name) return m.make();
    throw std::runtime_error("unknown built-in module: " + name);
}
