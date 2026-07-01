#pragma once
#include "value.h"
#include <stdexcept>

static inline double numArg(const Value* args, int i, const char* fn) {
    const Value& v = args[i];
    if (v.isInteger())
        return (double)v.asInt();
    if (v.isFloat())
        return v.asFloat();
    throw std::runtime_error(std::string(fn) + ": expected number");
}

static inline double numArg(const Value* args, int argc, int i, const char* fn) {
    if (i >= argc)
        throw std::runtime_error(std::string(fn) + ": missing argument");
    return numArg(args, i, fn);
}

static inline const std::string& strArg(const Value* args, int argc, int i, const char* fn) {
    if (i >= argc)
        throw std::runtime_error(std::string(fn) + ": missing argument");
    if (!args[i].isString())
        throw std::runtime_error(std::string(fn) + ": expected string");
    return args[i].asString();
}
