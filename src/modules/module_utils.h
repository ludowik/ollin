#pragma once
#include "value.h"
#include "vm.h"
#include <algorithm>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

// A script-side handle is an instance of a native class carrying {slot, gen}: `slot` is where the thing lives in the
// module's table, `gen` is bumped when the slot is freed, so a handle kept too long is told from the thing that took
// its place. Never a pointer: a callback may grow the table. read_slot_handle checks the receiver first, because a method
// taken off its object (`var f = t.cancel`) is called with no receiver, and the register that should hold it is
// whatever the call left there.
static inline Value make_slot_handle(const Value& cls, int slot, uint32_t gen) {
    Value h = Value::make_map();
    h.set_class(cls);
    h.map_set(Value(std::string("slot")), Value((int64_t)slot));
    h.map_set(Value(std::string("gen")), Value((int64_t)gen));
    return h;
}

// The slot of a handle of the class, and its generation in `gen`; the caller then tests them against its table. Throws
// "<fn>: expected <what>" ("a request") for anything else.
static inline int read_slot_handle(const Value& v, const Value& cls, const char* fn, const char* what, uint32_t& gen) {
    if (v.is_instance_of(cls)) {
        Value s = v.map_get(Value(std::string("slot")));
        Value g = v.map_get(Value(std::string("gen")));
        if (s.is_integer() && g.is_integer()) {
            gen = (uint32_t)g.as_int();
            return (int)s.as_int();
        }
    }
    throw std::runtime_error(std::string(fn) + ": expected " + what);
}

// The entries of a map whose keys are all strings, sorted by key: a map has no order, and the modules that write one out
// (json, https) need the same text for the same value. A key that is not a string throws "<what> must be a string".
// `say_type` appends the type found, for the callers whose message always did.
static inline std::vector<std::pair<std::string, Value>> sorted_string_entries(const Value& map, const std::string& what,
                                                                                bool say_type = false) {
    std::vector<std::pair<std::string, Value>> entries;
    for (auto& kv : map.mptr->data) {
        if (!kv.first.is_string())
            throw std::runtime_error(what + " must be a string" +
                                     (say_type ? std::string(", got ") + kv.first.type_name() : std::string()));
        entries.emplace_back(kv.first.as_string(), kv.second);
    }
    std::sort(entries.begin(), entries.end(), [](const auto& a, const auto& b) { return a.first < b.first; });
    return entries;
}

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

// A NAME chosen from a list, rendered as its position: the words accepted are spelled once, and so
// are the error messages. `i` is the argument's position, so a primitive anchored on two axes reads
// one list per axis. With no argument the caller's default is returned.
// The size comes from the array's TYPE: passing it as a number would have to be kept in step with
// the list, and one too many would read past its end with nothing to signal it.
template <int N>
static int mode_arg(CallCtx& ctx, int i, const char* fn, const char* const (&names)[N], int dflt) {
    if (i >= ctx.argc)
        return dflt;
    // Built only on the way out, an accepted call having no message to write.
    auto expected = [&names]() {
        std::string out;
        for (int k = 0; k < N; k++)
            out += (k == 0 ? "\"" : (k + 1 == N ? " or \"" : ", \"")) + std::string(names[k]) + "\"";
        return out;
    };
    if (!ctx.args[i].is_string())
        throw std::runtime_error(std::string(fn) + ": expected " + expected());
    const std::string& given = ctx.args[i].as_string();
    for (int k = 0; k < N; k++) {
        if (given == names[k])
            return k;
    }
    throw std::runtime_error(std::string(fn) + ": unknown mode '" + given + "' (expected " + expected() + ")");
}

// A map being built, with the noise removed: `m.map_set(Value(std::string("now")),
// Value::make_builtin(date_now))` becomes `.fn("now", date_now)`. It is a façade over map_set and
// nothing else — same Value, same order, same result — so it can be adopted one module at a time.
struct MapBuilder {
    Value map;

    // A class and an instance are built the same way, only their starting value differs.
    explicit MapBuilder(Value initial = Value::make_map()) : map(std::move(initial)) {
    }

    MapBuilder& set(const char* key, const Value& v) {
        map.map_set(Value(std::string(key)), v);
        return *this;
    }
    // The class of an instance being built (cf. Map::proto): not a field: `set("__class__", …)` would only make a field nobody reads.
    MapBuilder& klass(const Value& cls) {
        map.set_class(cls);
        return *this;
    }
    MapBuilder& fn(const char* key, Value::BuiltinFn f) {
        return set(key, Value::make_builtin(f));
    }
    // A static method receives no self, matching `static func` in Ollin.
    MapBuilder& static_fn(const char* key, Value::BuiltinFn f) {
        return set(key, Value::make_static_builtin(f));
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
