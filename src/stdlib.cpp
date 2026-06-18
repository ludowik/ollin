#include "stdlib.h"
#include <stdexcept>

Value makeMathModule();

const std::vector<std::string>& builtinModuleNames() {
    static const std::vector<std::string> names = { "math" };
    return names;
}

Value makeBuiltinModule(const std::string& name) {
    if (name == "math") return makeMathModule();
    throw std::runtime_error("unknown built-in module: " + name);
}
