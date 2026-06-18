#include "chunk.h"
#include <cmath>
#include <stdexcept>

static inline double numArg(const Value* args, int argc, int i, const char* fn) {
    if (i >= argc) throw std::runtime_error(std::string(fn) + ": missing argument");
    const Value& v = args[i];
    if (v.isInteger()) return (double)v.asInt();
    if (v.isFloat())   return v.asFloat();
    throw std::runtime_error(std::string(fn) + ": expected number");
}

#define MATH1(name, expr) \
    static Value math_##name(Value* args, int argc) { \
        double x = numArg(args, argc, 0, "math." #name); \
        return numValue(expr); \
    }

MATH1(abs,  std::fabs(x))
MATH1(sign, x > 0.0 ? 1.0 : x < 0.0 ? -1.0 : 0.0)

Value makeMathModule() {
    Value m = Value::makeMap();
    m.mapSet(Value(std::string("PI")),   Value(3.141592653589793));
    m.mapSet(Value(std::string("TAU")),  Value(6.283185307179586));
    m.mapSet(Value(std::string("abs")),  Value::makeBuiltin(math_abs));
    m.mapSet(Value(std::string("sign")), Value::makeBuiltin(math_sign));
    return m;
}
