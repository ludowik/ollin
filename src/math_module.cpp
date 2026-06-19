#define _USE_MATH_DEFINES
#include "chunk.h"
#include <cmath>
#include <cstdlib>
#include <ctime>
#include <limits>
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

MATH1(abs,   std::fabs(x))
MATH1(sign,  x > 0.0 ? 1.0 : x < 0.0 ? -1.0 : 0.0)
MATH1(floor, std::floor(x))
MATH1(ceil,  std::ceil(x))
MATH1(round, std::round(x))
MATH1(trunc, std::trunc(x))
MATH1(sqrt,  std::sqrt(x))
MATH1(exp,   std::exp(x))
MATH1(log,   std::log(x))
MATH1(log2,  std::log2(x))
MATH1(log10, std::log10(x))
MATH1(sin,   std::sin(x))
MATH1(cos,   std::cos(x))
MATH1(tan,   std::tan(x))
MATH1(asin,  std::asin(x))
MATH1(acos,  std::acos(x))
MATH1(atan,  std::atan(x))

static Value math_atan2(Value* args, int argc) {
    double y = numArg(args, argc, 0, "math.atan2");
    double x = numArg(args, argc, 1, "math.atan2");
    return Value(std::atan2(y, x));
}

static Value math_pow(Value* args, int argc) {
    double x = numArg(args, argc, 0, "math.pow");
    double n = numArg(args, argc, 1, "math.pow");
    return Value(std::pow(x, n));
}

static Value math_clamp(Value* args, int argc) {
    double x  = numArg(args, argc, 0, "math.clamp");
    double lo = numArg(args, argc, 1, "math.clamp");
    double hi = numArg(args, argc, 2, "math.clamp");
    return Value(x < lo ? lo : x > hi ? hi : x);
}

static Value math_seed(Value* args, int argc) {
    int64_t s = (int64_t)numArg(args, argc, 0, "math.seed");
    srand((unsigned)s);
    return Value();
}

static Value math_logn(Value* args, int argc) {
    double x = numArg(args, argc, 0, "math.logn");
    double n = numArg(args, argc, 1, "math.logn");
    return Value(std::log(x) / std::log(n));
}

static Value math_min(Value* args, int argc) {
    if (argc == 0) throw std::runtime_error("math.min: at least one argument required");
    bool all_int = true;
    for (int i = 0; i < argc; i++) if (!args[i].isInteger()) { all_int = false; break; }
    if (all_int) {
        int64_t result = args[0].asInt();
        for (int i = 1; i < argc; i++) { int64_t v = args[i].asInt(); if (v < result) result = v; }
        return Value(result);
    }
    double result = numArg(args, argc, 0, "math.min");
    for (int i = 1; i < argc; i++) { double v = numArg(args, argc, i, "math.min"); if (v < result) result = v; }
    return Value(result);
}

static Value math_max(Value* args, int argc) {
    if (argc == 0) throw std::runtime_error("math.max: at least one argument required");
    bool all_int = true;
    for (int i = 0; i < argc; i++) if (!args[i].isInteger()) { all_int = false; break; }
    if (all_int) {
        int64_t result = args[0].asInt();
        for (int i = 1; i < argc; i++) { int64_t v = args[i].asInt(); if (v > result) result = v; }
        return Value(result);
    }
    double result = numArg(args, argc, 0, "math.max");
    for (int i = 1; i < argc; i++) { double v = numArg(args, argc, i, "math.max"); if (v > result) result = v; }
    return Value(result);
}

static Value math_rand(Value* args, int argc) {
    double r = (double)rand() / ((double)RAND_MAX + 1.0);
    if (argc == 0) return Value(r);
    if (argc == 1) return Value(r * numArg(args, argc, 0, "math.rand"));
    double lo = numArg(args, argc, 0, "math.rand");
    double hi = numArg(args, argc, 1, "math.rand");
    return Value(lo + r * (hi - lo));
}

static Value math_rand_int(Value* args, int argc) {
    if (argc == 0) throw std::runtime_error("math.rand_int: at least one argument required");
    if (argc == 1) {
        int64_t hi = (int64_t)numArg(args, argc, 0, "math.rand_int");
        return Value((int64_t)(1 + rand() % hi));
    }
    int64_t lo = (int64_t)numArg(args, argc, 0, "math.rand_int");
    int64_t hi = (int64_t)numArg(args, argc, 1, "math.rand_int");
    return Value(lo + (int64_t)(rand() % (hi - lo + 1)));
}

Value makeMathModule() {
    srand((unsigned)time(nullptr));
    Value m = Value::makeMap();
    // constantes
    m.mapSet(Value(std::string("PI")),  Value(M_PI));
    m.mapSet(Value(std::string("TAU")), Value(2.0 * M_PI));
    m.mapSet(Value(std::string("E")),   Value(2.718281828459045235360));
    m.mapSet(Value(std::string("INF")), Value(std::numeric_limits<double>::infinity()));
    // arithmétique
    m.mapSet(Value(std::string("abs")),   Value::makeBuiltin(math_abs));
    m.mapSet(Value(std::string("sign")),  Value::makeBuiltin(math_sign));
    m.mapSet(Value(std::string("floor")), Value::makeBuiltin(math_floor));
    m.mapSet(Value(std::string("ceil")),  Value::makeBuiltin(math_ceil));
    m.mapSet(Value(std::string("round")), Value::makeBuiltin(math_round));
    m.mapSet(Value(std::string("trunc")), Value::makeBuiltin(math_trunc));
    m.mapSet(Value(std::string("sqrt")),  Value::makeBuiltin(math_sqrt));
    m.mapSet(Value(std::string("pow")),   Value::makeBuiltin(math_pow));
    m.mapSet(Value(std::string("clamp")), Value::makeBuiltin(math_clamp));
    m.mapSet(Value(std::string("min")),   Value::makeBuiltin(math_min));
    m.mapSet(Value(std::string("max")),   Value::makeBuiltin(math_max));
    // logarithmes / exponentielle
    m.mapSet(Value(std::string("exp")),   Value::makeBuiltin(math_exp));
    m.mapSet(Value(std::string("log")),   Value::makeBuiltin(math_log));
    m.mapSet(Value(std::string("log2")),  Value::makeBuiltin(math_log2));
    m.mapSet(Value(std::string("log10")), Value::makeBuiltin(math_log10));
    m.mapSet(Value(std::string("logn")),  Value::makeBuiltin(math_logn));
    // trigonométrie
    m.mapSet(Value(std::string("sin")),   Value::makeBuiltin(math_sin));
    m.mapSet(Value(std::string("cos")),   Value::makeBuiltin(math_cos));
    m.mapSet(Value(std::string("tan")),   Value::makeBuiltin(math_tan));
    m.mapSet(Value(std::string("asin")),  Value::makeBuiltin(math_asin));
    m.mapSet(Value(std::string("acos")),  Value::makeBuiltin(math_acos));
    m.mapSet(Value(std::string("atan")),  Value::makeBuiltin(math_atan));
    m.mapSet(Value(std::string("atan2")), Value::makeBuiltin(math_atan2));
    // aléatoire
    m.mapSet(Value(std::string("rand")),     Value::makeBuiltin(math_rand));
    m.mapSet(Value(std::string("rand_int")), Value::makeBuiltin(math_rand_int));
    m.mapSet(Value(std::string("seed")),     Value::makeBuiltin(math_seed));
    return m;
}
