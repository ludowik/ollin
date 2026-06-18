#include "chunk.h"
#include <cmath>
#include <stdexcept>

static Value math_abs(Value* args, int argc) {
    if (argc < 1) throw std::runtime_error("math.abs: missing argument");
    if (args[0].isInteger()) {
        int64_t n = args[0].asInt();
        return Value(n < 0 ? -n : n);
    }
    if (args[0].isFloat()) return Value(std::fabs(args[0].asFloat()));
    throw std::runtime_error("math.abs: expected number");
}

static Value math_sign(Value* args, int argc) {
    if (argc < 1) throw std::runtime_error("math.sign: missing argument");
    if (args[0].isInteger()) {
        int64_t n = args[0].asInt();
        return Value(n > 0 ? int64_t(1) : n < 0 ? int64_t(-1) : int64_t(0));
    }
    if (args[0].isFloat()) {
        double d = args[0].asFloat();
        return Value(d > 0.0 ? int64_t(1) : d < 0.0 ? int64_t(-1) : int64_t(0));
    }
    throw std::runtime_error("math.sign: expected number");
}

Value makeMathModule() {
    Value m = Value::makeMap();
    m.mapSet(Value(std::string("PI")),   Value(3.141592653589793));
    m.mapSet(Value(std::string("TAU")),  Value(6.283185307179586));
    m.mapSet(Value(std::string("abs")),  Value::makeBuiltin(math_abs));
    m.mapSet(Value(std::string("sign")), Value::makeBuiltin(math_sign));
    return m;
}
