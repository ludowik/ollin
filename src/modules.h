#pragma once
#include "chunk.h"
#include <string>
#include <vector>

const std::vector<std::string>& builtinModuleNames();
Value makeBuiltinModule(const std::string& name);
