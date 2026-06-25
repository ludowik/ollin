#pragma once
#include "value.h"
#include <string>
#include <vector>

const std::vector<std::string>& builtinModuleNames();
const std::vector<std::string>& builtinFuncNames();
Value makeBuiltinModule(const std::string& name);
