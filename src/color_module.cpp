#include "chunk.h"
#include "module_utils.h"
#include <stdexcept>
#include <string>

// ── helpers ───────────────────────────────────────────────────────────────────

static uint8_t colorComponent(const Value& v, const char* name) {
    if (!v.isNumber()) throw std::runtime_error(std::string("Color.") + name + " must be a number");
    double d = v.asNum();
    if (d < 0) d = 0; if (d > 255) d = 255;
    return (uint8_t)d;
}

static Value colorField(const Value& self, const char* name) {
    Value v = self.mapGet(Value(std::string(name)));
    if (v.isNil()) throw std::runtime_error(std::string("Color: missing field '") + name + "'");
    return v;
}

// ── init ──────────────────────────────────────────────────────────────────────
// args[0] = self, args[1]=r, args[2]=g, args[3]=b, args[4]=a (opt, default 255)

static Value color_init(Value* args, int argc) {
    if (argc < 4) throw std::runtime_error("Color: expected r, g, b [, a]");
    Value& self = args[0];
    self.mapSet(Value(std::string("r")), Value((int64_t)colorComponent(args[1], "r")));
    self.mapSet(Value(std::string("g")), Value((int64_t)colorComponent(args[2], "g")));
    self.mapSet(Value(std::string("b")), Value((int64_t)colorComponent(args[3], "b")));
    self.mapSet(Value(std::string("a")), Value((int64_t)(argc > 4 ? colorComponent(args[4], "a") : 255)));
    return Value{};
}

// ── __str ─────────────────────────────────────────────────────────────────────

static Value color_str(Value* args, int argc) {
    if (argc < 1) return Value(std::string("Color(0,0,0,255)"));
    const Value& self = args[0];
    auto r = colorField(self, "r").asInt();
    auto g = colorField(self, "g").asInt();
    auto b = colorField(self, "b").asInt();
    auto a = colorField(self, "a").asInt();
    return Value(std::string("Color(") + std::to_string(r) + "," +
                 std::to_string(g) + "," + std::to_string(b) + "," +
                 std::to_string(a) + ")");
}

// ── makeColorClass ────────────────────────────────────────────────────────────

Value makeColorClass() {
    Value cls = Value::makeClass();
    cls.mapSet(Value(std::string("__name__")), Value(std::string("Color")));
    cls.mapSet(Value(std::string("init")),    Value::makeBuiltin(color_init));
    cls.mapSet(Value(std::string("__str")),   Value::makeBuiltin(color_str));
    return cls;
}
