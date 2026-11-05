#pragma once
#include "value.h"
#include <string>

// The JSON of the json module, for the modules that keep values as text (data). `who` names the caller in the errors
// ("data.set"), which are runtime_error. A map written has its keys sorted, so that a value always gives the same text.
std::string json_encode(const Value& v, const char* who);
Value json_decode(const std::string& text, const char* who);
