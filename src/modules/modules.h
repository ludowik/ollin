#pragma once
#include "value.h"
#include <string>
#include <vector>

const std::vector<std::string>& builtin_module_names();
const std::vector<std::string>& builtin_func_names();
Value make_builtin_module(const std::string& name);
// Forgets what the modules keep from one program to the next: called when a program starts.
void modules_reset();
