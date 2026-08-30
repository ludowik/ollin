#pragma once
#include "value.h"
#include "vm.h"
#include <stdexcept>

// The parser desugars `ref x` into {__ref: true, get: func, set: func} (parser.cpp, ref_expr),
// and a native module reads and writes the referenced variable through those two closures. The
// `__ref` marker tells a REAL reference from a map that merely happens to have get/set members —
// the `data` module has some.
static inline bool is_ref(const Value& v) {
    if (!v.is_map())
        return false;
    return !v.map_get(Value(std::string("__ref"))).is_nil() &&
           v.map_get(Value(std::string("get"))).is_callable() &&
           v.map_get(Value(std::string("set"))).is_callable();
}

static inline Value ref_get(const Value& r) {
    return VM::current()->call_value(r.map_get(Value(std::string("get"))));
}

static inline void ref_set(const Value& r, const Value& value) {
    VM::current()->call_value(r.map_get(Value(std::string("set"))), value);
}

// Precondition: the caller MUST have ensured i < argc. This fast form does no bound check and is
// meant for use after an argc guard; for a built-in check, use the (args, argc, i, fn) overload
// below.
static inline double num_arg(const Value* args, int i, const char* fn) {
    const Value& v = args[i];
    if (v.is_integer())
        return (double)v.as_int();
    if (v.is_float())
        return v.as_float();
    throw std::runtime_error(std::string(fn) + ": argument " + std::to_string(i + 1) + " expected number, got " +
                             v.type_name());
}

static inline double num_arg(const Value* args, int argc, int i, const char* fn) {
    if (i >= argc)
        throw std::runtime_error(std::string(fn) + ": missing argument");
    return num_arg(args, i, fn);
}

static inline const std::string& str_arg(const Value* args, int argc, int i, const char* fn) {
    if (i >= argc)
        throw std::runtime_error(std::string(fn) + ": missing argument");
    if (!args[i].is_string())
        throw std::runtime_error(std::string(fn) + ": expected string");
    return args[i].as_string();
}

// A map being built, with the noise removed: `m.map_set(Value(std::string("now")),
// Value::make_builtin(date_now))` becomes `.fn("now", date_now)`. It is a façade over map_set and
// nothing else — same Value, same order, same result — so it can be adopted one module at a time.
struct MapBuilder {
    Value map = Value::make_map();

    MapBuilder& set(const char* key, const Value& v) {
        map.map_set(Value(std::string(key)), v);
        return *this;
    }
    MapBuilder& fn(const char* key, Value::BuiltinFn f) {
        return set(key, Value::make_builtin(f));
    }
    MapBuilder& num(const char* key, double v) {
        return set(key, Value(v));
    }
    MapBuilder& int_num(const char* key, int64_t v) {
        return set(key, Value(v));
    }
    MapBuilder& str(const char* key, const std::string& v) {
        return set(key, Value(v));
    }
    // Named rather than an implicit conversion: the hand-over is where the map leaves the builder,
    // and an implicit one would let a copy slip in unnoticed.
    Value done() {
        return map;
    }
};

// Colour components normalized to [0,1].
struct ColorRGBA {
    double r, g, b, a;
};

static inline double color_clamp01(double v) {
    return v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);
}

// Reads "flexible" colour arguments into [0,1] components. The same signature serves the Color
// constructor and graphics.clear/fill/stroke:
//   a Color instance   -> its r,g,b,a fields
//   1 number  n        -> (n,n,n,1)   grey
//   2 numbers n,a      -> (n,n,n,a)   grey plus alpha
//   3 numbers r,g,b    -> (r,g,b,1)
//   4 numbers r,g,b,a  -> (r,g,b,a)
// Precondition: argc >= 1. Throws when the shape is invalid.
static inline ColorRGBA parse_color(const Value* args, int argc, const char* fn) {
    if (args[0].is_map() || args[0].is_class()) {
        auto field = [&](const char* k, double def) -> double {
            Value f = args[0].map_get(Value(std::string(k)));
            return f.is_number() ? color_clamp01(f.as_num()) : def;
        };
        return {field("r", 0.0), field("g", 0.0), field("b", 0.0), field("a", 1.0)};
    }
    if (!args[0].is_number())
        throw std::runtime_error(std::string(fn) + ": expected a number or a Color");
    double n0 = color_clamp01(args[0].as_num());
    if (argc == 1)
        return {n0, n0, n0, 1.0};                                  // grey
    for (int i = 1; i < argc && i < 4; i++) {
        if (!args[i].is_number())
            throw std::runtime_error(std::string(fn) + ": expected numbers");
    }
    if (argc == 2)
        return {n0, n0, n0, color_clamp01(args[1].as_num())};        // grey + alpha
    double g = color_clamp01(args[1].as_num());
    double b = color_clamp01(args[2].as_num());
    double a = argc >= 4 ? color_clamp01(args[3].as_num()) : 1.0;
    return {n0, g, b, a};                                          // r,g,b[,a]
}
