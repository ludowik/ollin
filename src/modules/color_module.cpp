#include "module_utils.h"
#include "value.h"
#include "vm.h"
#include <cstdlib>
#include <stdexcept>
#include <string>

Value make_color_class(); // defined below; used by color_random as a fallback

// Every colour built by this module — a palette constant as much as the result of pastel(),
// grayscale() or gray() — is a real Color instance, with __class__ set, so the methods and __str
// work on it exactly as on Color(...). Defined at the bottom, next to the palette.
static Value make_color_instance(const Value& cls, double r, double g, double b, double a = 1.0);


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
    (void)ctx.args;
    (void)ctx.argc;
    auto rnd = []() { return (double)rand() / ((double)RAND_MAX + 1.0); };
    return ctx.ret(make_color_instance(color_class(), rnd(), rnd(), rnd()));
}

// args[0] is self; returns a new pastel Color instance, mixed 50 % with white.

static int color_pastel(CallCtx& ctx) {
    (void)ctx.argc;
    const Value& self = ctx.args[0];
    double r = color_field(self, "r").as_num();
    double g = color_field(self, "g").as_num();
    double b = color_field(self, "b").as_num();
    double a = color_field(self, "a").as_num();
    Value cls = self.map_get(Value(std::string("__class__")));
    return ctx.ret(make_color_instance(cls, r * 0.5 + 0.5, g * 0.5 + 0.5, b * 0.5 + 0.5, a));
}

// args[0] is self; returns a new greyscale Color instance, using Rec. 601 luminance.

static int color_grayscale(CallCtx& ctx) {
    (void)ctx.argc;
    const Value& self = ctx.args[0];
    double r = color_field(self, "r").as_num();
    double g = color_field(self, "g").as_num();
    double b = color_field(self, "b").as_num();
    double a = color_field(self, "a").as_num();
    double lum = 0.299 * r + 0.587 * g + 0.114 * b;
    Value cls = self.map_get(Value(std::string("__class__")));
    return ctx.ret(make_color_instance(cls, lum, lum, lum, a));
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
    return ctx.ret(make_color_instance(color_class(), v, v, v));
}


Value make_color_class() {
    return MapBuilder(Value::make_class())
        .str("__name__", "Color")
        .fn("init", color_init)
        .fn("__str", color_str)
        .static_fn("random", color_random)   // STATIC factories, which receive no self
        .static_fn("gray", color_gray)
        .fn("pastel", color_pastel)          // INSTANCE methods, which do receive self
        .fn("grayscale", color_grayscale)
        .done();
}


static Value make_color_instance(const Value& cls, double r, double g, double b, double a) {
    return MapBuilder().set("__class__", cls).num("r", r).num("g", g).num("b", b).num("a", a).done();
}

Value make_colors_module() {
    Value cls = make_color_class(); // the Color class, shared by every constant of the palette
    auto rgb = [&](int r, int g, int b) { return make_color_instance(cls, r / 255.0, g / 255.0, b / 255.0); };
    return MapBuilder()
        .set("BLACK", rgb(0, 0, 0))
        .set("WHITE", rgb(255, 255, 255))
        .set("RED", rgb(230, 41, 55))
        .set("GREEN", rgb(0, 228, 48))
        .set("BLUE", rgb(0, 121, 241))
        .set("YELLOW", rgb(253, 249, 0))
        .set("GRAY", rgb(130, 130, 130))
        .set("ORANGE", rgb(255, 161, 0))
        .set("PINK", rgb(255, 109, 194))
        .set("PURPLE", rgb(200, 122, 255))
        .set("BROWN", rgb(127, 106, 79))
        .set("DARKGRAY", rgb(80, 80, 80))
        .set("SKYBLUE", rgb(102, 191, 255))
        .set("LIME", rgb(0, 158, 47))
        .set("MAGENTA", rgb(255, 0, 255))
        .done();
}
