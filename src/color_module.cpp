#include "chunk.h"
#include "module_utils.h"
#include <stdexcept>
#include <string>

// ── helpers ───────────────────────────────────────────────────────────────────

static double colorComponent(const Value& v, const char* name) {
    if (!v.isNumber()) throw std::runtime_error(std::string("Color.") + name + " must be a number");
    double d = v.asNum();
    if (d < 0.0) d = 0.0;
    if (d > 1.0) d = 1.0;
    return d;
}

static Value colorField(const Value& self, const char* name) {
    Value v = self.mapGet(Value(std::string(name)));
    if (v.isNil()) throw std::runtime_error(std::string("Color: missing field '") + name + "'");
    return v;
}

// ── init ──────────────────────────────────────────────────────────────────────
// args[0] = self, args[1]=r, args[2]=g, args[3]=b, args[4]=a (opt, default 1.0)

static Value color_init(Value* args, int argc) {
    if (argc < 4) throw std::runtime_error("Color: expected r, g, b [, a]");
    Value& self = args[0];
    self.mapSet(Value(std::string("r")), Value(colorComponent(args[1], "r")));
    self.mapSet(Value(std::string("g")), Value(colorComponent(args[2], "g")));
    self.mapSet(Value(std::string("b")), Value(colorComponent(args[3], "b")));
    self.mapSet(Value(std::string("a")), Value(argc > 4 ? colorComponent(args[4], "a") : 1.0));
    return Value{};
}

// ── __str ─────────────────────────────────────────────────────────────────────

static Value color_str(Value* args, int argc) {
    if (argc < 1) return Value(std::string("Color(0,0,0,1)"));
    const Value& self = args[0];
    auto r = colorField(self, "r").asNum();
    auto g = colorField(self, "g").asNum();
    auto b = colorField(self, "b").asNum();
    auto a = colorField(self, "a").asNum();
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

// ── makeColorsModule ──────────────────────────────────────────────────────────

static Value makeColorInstance(double r, double g, double b, double a = 1.0) {
    Value inst = Value::makeMap();
    inst.mapSet(Value(std::string("r")), Value(r));
    inst.mapSet(Value(std::string("g")), Value(g));
    inst.mapSet(Value(std::string("b")), Value(b));
    inst.mapSet(Value(std::string("a")), Value(a));
    return inst;
}

Value makeColorsModule() {
    Value m = Value::makeMap();
    m.mapSet(Value(std::string("BLACK")),   makeColorInstance(0.0,        0.0,       0.0));
    m.mapSet(Value(std::string("WHITE")),   makeColorInstance(1.0,        1.0,       1.0));
    m.mapSet(Value(std::string("RED")),     makeColorInstance(230/255.0,  41/255.0,  55/255.0));
    m.mapSet(Value(std::string("GREEN")),   makeColorInstance(0/255.0,   228/255.0,  48/255.0));
    m.mapSet(Value(std::string("BLUE")),    makeColorInstance(0/255.0,   121/255.0, 241/255.0));
    m.mapSet(Value(std::string("YELLOW")),  makeColorInstance(253/255.0, 249/255.0,   0/255.0));
    m.mapSet(Value(std::string("GRAY")),    makeColorInstance(130/255.0, 130/255.0, 130/255.0));
    m.mapSet(Value(std::string("ORANGE")),  makeColorInstance(255/255.0, 161/255.0,   0/255.0));
    m.mapSet(Value(std::string("PINK")),    makeColorInstance(255/255.0, 109/255.0, 194/255.0));
    m.mapSet(Value(std::string("PURPLE")),  makeColorInstance(200/255.0, 122/255.0, 255/255.0));
    m.mapSet(Value(std::string("BROWN")),   makeColorInstance(127/255.0, 106/255.0,  79/255.0));
    m.mapSet(Value(std::string("DARKGRAY")),makeColorInstance( 80/255.0,  80/255.0,  80/255.0));
    m.mapSet(Value(std::string("SKYBLUE")), makeColorInstance(102/255.0, 191/255.0, 255/255.0));
    m.mapSet(Value(std::string("LIME")),    makeColorInstance(  0/255.0, 158/255.0,  47/255.0));
    m.mapSet(Value(std::string("MAGENTA")), makeColorInstance(255/255.0,   0/255.0, 255/255.0));
    return m;
}
