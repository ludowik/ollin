#define _USE_MATH_DEFINES
#include "chunk.h"
#include <cmath>
#include <cstdlib>
#include <ctime>
#include <stdexcept>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

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
MATH1(floor, std::floor(x))
MATH1(ceil,  std::ceil(x))
MATH1(sqrt,  std::sqrt(x))
MATH1(sin,   std::sin(x))
MATH1(cos,   std::cos(x))

static Value math_rand(Value* args, int argc) {
    (void)args; (void)argc;
    return Value((double)rand() / ((double)RAND_MAX + 1.0));
}

Value makeMathModule() {
    srand((unsigned)time(nullptr));
    Value m = Value::makeMap();
    m.mapSet(Value(std::string("PI")),    Value(M_PI));
    m.mapSet(Value(std::string("TAU")),   Value(2.0 * M_PI));
    m.mapSet(Value(std::string("abs")),   Value::makeBuiltin(math_abs));
    m.mapSet(Value(std::string("sign")),  Value::makeBuiltin(math_sign));
    m.mapSet(Value(std::string("floor")), Value::makeBuiltin(math_floor));
    m.mapSet(Value(std::string("ceil")),  Value::makeBuiltin(math_ceil));
    m.mapSet(Value(std::string("sqrt")),  Value::makeBuiltin(math_sqrt));
    m.mapSet(Value(std::string("sin")),   Value::makeBuiltin(math_sin));
    m.mapSet(Value(std::string("cos")),   Value::makeBuiltin(math_cos));
    m.mapSet(Value(std::string("rand")),  Value::makeBuiltin(math_rand));
    return m;
}
