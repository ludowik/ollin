#include "modules.h"
#include "value.h"
#include <stdexcept>

// Constantes de mode de fusion (valeurs = enum BlendMode de raylib). Définies ici
// en littéraux → pas de dépendance à raylib.h (compile aussi dans le build stub).
static Value makeBlendModule() {
    Value m = Value::makeMap();
    m.mapSet(Value(std::string("ALPHA")), Value((int64_t)0));       // BLEND_ALPHA
    m.mapSet(Value(std::string("ADD")), Value((int64_t)1));         // BLEND_ADDITIVE
    m.mapSet(Value(std::string("MULTIPLY")), Value((int64_t)2));    // BLEND_MULTIPLIED
    m.mapSet(Value(std::string("ADD_COLORS")), Value((int64_t)3));  // BLEND_ADD_COLORS
    m.mapSet(Value(std::string("SUBTRACT")), Value((int64_t)4));    // BLEND_SUBTRACT_COLORS
    m.mapSet(Value(std::string("PREMULTIPLY")), Value((int64_t)5)); // BLEND_ALPHA_PREMULTIPLY
    return m;
}

Value makeCoreModule();
Value makeMathModule();
Value makeGraphicsModule();
Value makeStringModule();
Value makeColorsModule();
Value makeWindowModule();
Value makeImageModule();
Value makeKeyboardModule();
Value makeMouseModule();

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
    static const std::vector<std::string> names = {"print", "printf", "typeof", "assert", "time", "Color", "len"};
    return names;
}

Value makeBuiltinModule(const std::string& name) {
    for (auto& m : k_modules)
        if (name == m.name)
            return m.make();
    throw std::runtime_error("unknown built-in module: " + name);
}
