#include "modules.h"
#include "value.h"
#include <stdexcept>

Value makeCoreModule();
Value makeMathModule();
Value makeGraphicsModule();
// Module `blend` : défini dans la paire graphics (graphics_module avec les enums
// raylib BlendMode / graphics_stub → nil), pas ici — modules.cpp compile aussi
// sans raylib, donc ne peut pas référencer l'enum. Voir makeGraphicsModule.
Value makeBlendModule();
Value makeStringModule();
Value makeColorsModule();
Value makeWindowModule();
Value makeImageModule();
Value makeKeyboardModule();
Value makeMouseModule();
Value makeDataModule();

static const struct { const char* name; Value(*make)(); } k_modules[] = {
    { "core",     makeCoreModule     },
    { "math",     makeMathModule     },
    { "graphics", makeGraphicsModule },
    { "string",   makeStringModule   },
    { "colors",   makeColorsModule   },
    { "blend",    makeBlendModule    },
    { "window",   makeWindowModule   },
    { "image",    makeImageModule    },
    { "keyboard", makeKeyboardModule },
    { "mouse",    makeMouseModule    },
    { "data",     makeDataModule     },
};

const std::vector<std::string>& builtinModuleNames() {
    static const std::vector<std::string> names = [] {
        std::vector<std::string> v;
        for (auto& m : k_modules)
            v.push_back(m.name);
        return v;
    }();
    return names;
}

const std::vector<std::string>& builtinFuncNames() {
    static const std::vector<std::string> names = {"print", "printf", "typeof", "assert",
                                                   "time", "mem", "Color", "len"};
    return names;
}

Value makeBuiltinModule(const std::string& name) {
    for (auto& m : k_modules) {
        if (name == m.name) {
            Value mod = m.make();
            if (mod.isMap()) mod.tag = Value::T_MODULE;
            return mod;
        }
    }
    throw std::runtime_error("unknown built-in module: " + name);
}
