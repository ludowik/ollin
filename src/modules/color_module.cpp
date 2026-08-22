#include "module_utils.h"
#include "value.h"
#include "vm.h"
#include <cstdlib>
#include <stdexcept>
#include <string>

Value make_color_class(); // defined below; used by color_random as a fallback


static double color_component(const Value& v, const char* name) {
    if (!v.is_number())
        throw std::runtime_error(std::string("Color.") + name + " must be a number");
    double d = v.as_num();
    if (d < 0.0)
        d = 0.0;
    if (d > 1.0)
        d = 1.0;
    return d;
}

// The Color class used by the static factories (random, gray): the global one, reused rather than
// allocated anew so that __class__ is Color, falling back to a fresh class when the global is not
// materialized yet.
static Value color_class() {
    Value c = VM::current()->get_global("Color");
    return c.is_class() ? c : make_color_class();
}

static Value color_field(const Value& self, const char* name) {
    Value v = self.map_get(Value(std::string(name)));
    if (v.is_nil())
        throw std::runtime_error(std::string("Color: missing field '") + name + "'");
    return v;
}

// args[0] = self; args[1..] = the flexible colour form (see parse_color):
//   Color(grey) · Color(grey, a) · Color(r, g, b) · Color(r, g, b, a) · Color(otherColor)

static int color_init(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    if (argc < 2)
        throw std::runtime_error("Color: expected 1 to 4 numbers (or a Color)");
    Value& self = args[0];
    ColorRGBA c = parse_color(args + 1, argc - 1, "Color");
    self.map_set(Value(std::string("r")), Value(c.r));
    self.map_set(Value(std::string("g")), Value(c.g));
    self.map_set(Value(std::string("b")), Value(c.b));
    self.map_set(Value(std::string("a")), Value(c.a));
    return ctx.ret(Value{});
}


static int color_str(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    if (argc < 1)
        return ctx.ret(Value(std::string("Color(0,0,0,1)")));
    const Value& self = args[0];
    auto r = color_field(self, "r").as_num();
    auto g = color_field(self, "g").as_num();
    auto b = color_field(self, "b").as_num();
    auto a = color_field(self, "a").as_num();
    return ctx.ret(Value(std::string("Color(") + std::to_string(r) + "," + std::to_string(g) + "," + std::to_string(b) + "," +
                 std::to_string(a) + ")"));
}

// STATIC method: builds a Color with random r,g,b in [0,1] and a = 1. Like
// `static func random() return Color(...) end` in Ollin it depends on no receiver and no
// argument; the class comes from the `Color` global.

static int color_random(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    (void)args;
    (void)argc;
    Value cls = color_class();
    auto rnd = []() { return (double)rand() / ((double)RAND_MAX + 1.0); };
    Value inst = Value::make_map();
    inst.map_set(Value(std::string("__class__")), cls);
    inst.map_set(Value(std::string("r")), Value(rnd()));
    inst.map_set(Value(std::string("g")), Value(rnd()));
    inst.map_set(Value(std::string("b")), Value(rnd()));
    inst.map_set(Value(std::string("a")), Value(1.0));
    return ctx.ret(inst);
}

// args[0] is self; returns a new pastel Color instance, mixed 50 % with white.

static int color_pastel(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    (void)argc;
    const Value& self = args[0];
    double r = color_field(self, "r").as_num();
    double g = color_field(self, "g").as_num();
    double b = color_field(self, "b").as_num();
    double a = color_field(self, "a").as_num();
    Value cls = self.map_get(Value(std::string("__class__")));
    Value inst = Value::make_map();
    inst.map_set(Value(std::string("__class__")), cls);
    inst.map_set(Value(std::string("r")), Value(r * 0.5 + 0.5));
    inst.map_set(Value(std::string("g")), Value(g * 0.5 + 0.5));
    inst.map_set(Value(std::string("b")), Value(b * 0.5 + 0.5));
    inst.map_set(Value(std::string("a")), Value(a));
    return ctx.ret(inst);
}

// args[0] is self; returns a new greyscale Color instance, using Rec. 601 luminance.

static int color_grayscale(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    (void)argc;
    const Value& self = args[0];
    double r = color_field(self, "r").as_num();
    double g = color_field(self, "g").as_num();
    double b = color_field(self, "b").as_num();
    double a = color_field(self, "a").as_num();
    double lum = 0.299 * r + 0.587 * g + 0.114 * b;
    Value cls = self.map_get(Value(std::string("__class__")));
    Value inst = Value::make_map();
    inst.map_set(Value(std::string("__class__")), cls);
    inst.map_set(Value(std::string("r")), Value(lum));
    inst.map_set(Value(std::string("g")), Value(lum));
    inst.map_set(Value(std::string("b")), Value(lum));
    inst.map_set(Value(std::string("a")), Value(a));
    return ctx.ret(inst);
}

// Color.gray(v): a new grey Color of luminance v, clamped to [0,1], with a = 1. A static method
// with a parameter: thanks to the static-builtin flag, `v` is in args[0] whether the call is
// Color.gray(x) or c.gray(x), since no self is injected.
static int color_gray(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    if (argc < 1)
        throw std::runtime_error("Color.gray: expected a value");
    double v = color_component(args[0], "gray");
    Value cls = color_class();
    Value inst = Value::make_map();
    inst.map_set(Value(std::string("__class__")), cls);
    inst.map_set(Value(std::string("r")), Value(v));
    inst.map_set(Value(std::string("g")), Value(v));
    inst.map_set(Value(std::string("b")), Value(v));
    inst.map_set(Value(std::string("a")), Value(1.0));
    return ctx.ret(inst);
}


Value make_color_class() {
    Value cls = Value::make_class();
    cls.map_set(Value(std::string("__name__")), Value(std::string("Color")));
    cls.map_set(Value(std::string("init")), Value::make_builtin(color_init));
    cls.map_set(Value(std::string("__str")), Value::make_builtin(color_str));
    // STATIC factories, which receive no self, matching `static func` in Ollin:
    cls.map_set(Value(std::string("random")), Value::make_static_builtin(color_random));
    cls.map_set(Value(std::string("gray")), Value::make_static_builtin(color_gray));
    // INSTANCE methods, which do receive self:
    cls.map_set(Value(std::string("pastel")), Value::make_builtin(color_pastel));
    cls.map_set(Value(std::string("grayscale")), Value::make_builtin(color_grayscale));
    return cls;
}


// Every constant is a real Color instance, with __class__ set, so the methods (pastel, grayscale,
// random) and __str work on it exactly as on Color(...).
static Value make_color_instance(const Value& cls, double r, double g, double b, double a = 1.0) {
    Value inst = Value::make_map();
    inst.map_set(Value(std::string("__class__")), cls);
    inst.map_set(Value(std::string("r")), Value(r));
    inst.map_set(Value(std::string("g")), Value(g));
    inst.map_set(Value(std::string("b")), Value(b));
    inst.map_set(Value(std::string("a")), Value(a));
    return inst;
}

Value make_colors_module() {
    Value m = Value::make_map();
    Value cls = make_color_class(); // the Color class, shared by every constant of the palette
    m.map_set(Value(std::string("BLACK")), make_color_instance(cls, 0.0, 0.0, 0.0));
    m.map_set(Value(std::string("WHITE")), make_color_instance(cls, 1.0, 1.0, 1.0));
    m.map_set(Value(std::string("RED")), make_color_instance(cls, 230 / 255.0, 41 / 255.0, 55 / 255.0));
    m.map_set(Value(std::string("GREEN")), make_color_instance(cls, 0 / 255.0, 228 / 255.0, 48 / 255.0));
    m.map_set(Value(std::string("BLUE")), make_color_instance(cls, 0 / 255.0, 121 / 255.0, 241 / 255.0));
    m.map_set(Value(std::string("YELLOW")), make_color_instance(cls, 253 / 255.0, 249 / 255.0, 0 / 255.0));
    m.map_set(Value(std::string("GRAY")), make_color_instance(cls, 130 / 255.0, 130 / 255.0, 130 / 255.0));
    m.map_set(Value(std::string("ORANGE")), make_color_instance(cls, 255 / 255.0, 161 / 255.0, 0 / 255.0));
    m.map_set(Value(std::string("PINK")), make_color_instance(cls, 255 / 255.0, 109 / 255.0, 194 / 255.0));
    m.map_set(Value(std::string("PURPLE")), make_color_instance(cls, 200 / 255.0, 122 / 255.0, 255 / 255.0));
    m.map_set(Value(std::string("BROWN")), make_color_instance(cls, 127 / 255.0, 106 / 255.0, 79 / 255.0));
    m.map_set(Value(std::string("DARKGRAY")), make_color_instance(cls, 80 / 255.0, 80 / 255.0, 80 / 255.0));
    m.map_set(Value(std::string("SKYBLUE")), make_color_instance(cls, 102 / 255.0, 191 / 255.0, 255 / 255.0));
    m.map_set(Value(std::string("LIME")), make_color_instance(cls, 0 / 255.0, 158 / 255.0, 47 / 255.0));
    m.map_set(Value(std::string("MAGENTA")), make_color_instance(cls, 255 / 255.0, 0 / 255.0, 255 / 255.0));
    return m;
}
