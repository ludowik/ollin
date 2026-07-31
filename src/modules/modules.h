#pragma once
#include "value.h"
#include <string>
#include <vector>

const std::vector<std::string>& builtin_module_names();
const std::vector<std::string>& builtin_func_names();
Value make_builtin_module(const std::string& name);
