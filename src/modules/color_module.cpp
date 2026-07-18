#include "module_utils.h"
#include "value.h"
#include "vm.h"
#include <cstdlib>
#include <stdexcept>
#include <string>

Value makeColorClass(); // défini plus bas — utilisé par color_random (repli)

// ── helpers ───────────────────────────────────────────────────────────────────

static double colorComponent(const Value& v, const char* name) {
    if (!v.isNumber())
        throw std::runtime_error(std::string("Color.") + name + " must be a number");
    double d = v.asNum();
    if (d < 0.0)
        d = 0.0;
    if (d > 1.0)
        d = 1.0;
    return d;
}

// Classe Color pour les fabriques statiques (random/gray) : la classe globale
// (réutilisée, pas de nouvelle alloc, __class__ == Color), avec repli sur une classe
// fraîche si le global n'est pas encore matérialisé.
static Value colorClass() {
    Value c = VM::current()->getGlobal("Color");
    return c.isClass() ? c : makeColorClass();
}

static Value colorField(const Value& self, const char* name) {
    Value v = self.mapGet(Value(std::string(name)));
    if (v.isNil())
        throw std::runtime_error(std::string("Color: missing field '") + name + "'");
    return v;
}

// ── init ──────────────────────────────────────────────────────────────────────
// args[0] = self ; args[1..] = forme couleur flexible (voir parseColor) :
//   Color(gris) · Color(gris, a) · Color(r, g, b) · Color(r, g, b, a) · Color(autreColor)

static Value color_init(Value* args, int argc) {
    if (argc < 2)
        throw std::runtime_error("Color: expected 1 to 4 numbers (or a Color)");
    Value& self = args[0];
    ColorRGBA c = parseColor(args + 1, argc - 1, "Color");
    self.mapSet(Value(std::string("r")), Value(c.r));
    self.mapSet(Value(std::string("g")), Value(c.g));
    self.mapSet(Value(std::string("b")), Value(c.b));
    self.mapSet(Value(std::string("a")), Value(c.a));
    return Value{};
}

// ── __str ─────────────────────────────────────────────────────────────────────

static Value color_str(Value* args, int argc) {
    if (argc < 1)
        return Value(std::string("Color(0,0,0,1)"));
    const Value& self = args[0];
    auto r = colorField(self, "r").asNum();
    auto g = colorField(self, "g").asNum();
    auto b = colorField(self, "b").asNum();
    auto a = colorField(self, "a").asNum();
    return Value(std::string("Color(") + std::to_string(r) + "," + std::to_string(g) + "," + std::to_string(b) + "," +
                 std::to_string(a) + ")");
}

// ── random ────────────────────────────────────────────────────────────────────
// Méthode STATIQUE : fabrique une Color r,g,b aléatoires dans [0,1], a = 1.
// Comme `static func random() return Color(...) end` en Ollin, elle ne dépend
// d'aucun receveur/argument : la classe vient du global `Color` (repli sur une
// classe fraîche si le global n'est pas encore matérialisé).

static Value color_random(Value* args, int argc) {
    (void)args;
    (void)argc;
    Value cls = colorClass();
    auto rnd = []() { return (double)rand() / ((double)RAND_MAX + 1.0); };
    Value inst = Value::makeMap();
    inst.mapSet(Value(std::string("__class__")), cls);
    inst.mapSet(Value(std::string("r")), Value(rnd()));
    inst.mapSet(Value(std::string("g")), Value(rnd()));
    inst.mapSet(Value(std::string("b")), Value(rnd()));
    inst.mapSet(Value(std::string("a")), Value(1.0));
    return inst;
}

// ── pastel ────────────────────────────────────────────────────────────────────
// args[0] = self  → retourne une nouvelle instance Color pastel (mélange 50% blanc)

static Value color_pastel(Value* args, int argc) {
    (void)argc;
    const Value& self = args[0];
    double r = colorField(self, "r").asNum();
    double g = colorField(self, "g").asNum();
    double b = colorField(self, "b").asNum();
    double a = colorField(self, "a").asNum();
    Value cls = self.mapGet(Value(std::string("__class__")));
    Value inst = Value::makeMap();
    inst.mapSet(Value(std::string("__class__")), cls);
    inst.mapSet(Value(std::string("r")), Value(r * 0.5 + 0.5));
    inst.mapSet(Value(std::string("g")), Value(g * 0.5 + 0.5));
    inst.mapSet(Value(std::string("b")), Value(b * 0.5 + 0.5));
    inst.mapSet(Value(std::string("a")), Value(a));
    return inst;
}

// ── grayscale ─────────────────────────────────────────────────────────────────
// args[0] = self  → retourne une nouvelle instance Color en niveaux de gris (luminance Rec. 601)

static Value color_grayscale(Value* args, int argc) {
    (void)argc;
    const Value& self = args[0];
    double r = colorField(self, "r").asNum();
    double g = colorField(self, "g").asNum();
    double b = colorField(self, "b").asNum();
    double a = colorField(self, "a").asNum();
    double lum = 0.299 * r + 0.587 * g + 0.114 * b;
    Value cls = self.mapGet(Value(std::string("__class__")));
    Value inst = Value::makeMap();
    inst.mapSet(Value(std::string("__class__")), cls);
    inst.mapSet(Value(std::string("r")), Value(lum));
    inst.mapSet(Value(std::string("g")), Value(lum));
    inst.mapSet(Value(std::string("b")), Value(lum));
    inst.mapSet(Value(std::string("a")), Value(a));
    return inst;
}

// ── gray (statique, AVEC paramètre) ──────────────────────────────────────────
// Color.gray(v) → nouvelle Color grise de luminance v (clampée à [0,1]), a = 1.
// Méthode statique avec un paramètre : grâce au flag static builtin, `v` est en
// args[0] que l'appel soit Color.gray(x) OU c.gray(x) (aucun self injecté).
static Value color_gray(Value* args, int argc) {
    if (argc < 1)
        throw std::runtime_error("Color.gray: expected a value");
    double v = colorComponent(args[0], "gray");
    Value cls = colorClass();
    Value inst = Value::makeMap();
    inst.mapSet(Value(std::string("__class__")), cls);
    inst.mapSet(Value(std::string("r")), Value(v));
    inst.mapSet(Value(std::string("g")), Value(v));
    inst.mapSet(Value(std::string("b")), Value(v));
    inst.mapSet(Value(std::string("a")), Value(1.0));
    return inst;
}

// ── makeColorClass ────────────────────────────────────────────────────────────

Value makeColorClass() {
    Value cls = Value::makeClass();
    cls.mapSet(Value(std::string("__name__")), Value(std::string("Color")));
    cls.mapSet(Value(std::string("init")), Value::makeBuiltin(color_init));
    cls.mapSet(Value(std::string("__str")), Value::makeBuiltin(color_str));
    // Fabriques STATIQUES (pas de self) — cohérent avec `static func` en Ollin :
    cls.mapSet(Value(std::string("random")), Value::makeStaticBuiltin(color_random));
    cls.mapSet(Value(std::string("gray")), Value::makeStaticBuiltin(color_gray));
    // Méthodes d'INSTANCE (reçoivent self) :
    cls.mapSet(Value(std::string("pastel")), Value::makeBuiltin(color_pastel));
    cls.mapSet(Value(std::string("grayscale")), Value::makeBuiltin(color_grayscale));
    return cls;
}

// ── makeColorsModule ──────────────────────────────────────────────────────────

// Chaque constante est une vraie instance Color (clé __class__ posée) → les méthodes
// (pastel/grayscale/random) et __str fonctionnent dessus, comme sur Color(...).
static Value makeColorInstance(const Value& cls, double r, double g, double b, double a = 1.0) {
    Value inst = Value::makeMap();
    inst.mapSet(Value(std::string("__class__")), cls);
    inst.mapSet(Value(std::string("r")), Value(r));
    inst.mapSet(Value(std::string("g")), Value(g));
    inst.mapSet(Value(std::string("b")), Value(b));
    inst.mapSet(Value(std::string("a")), Value(a));
    return inst;
}

Value makeColorsModule() {
    Value m = Value::makeMap();
    Value cls = makeColorClass(); // classe Color partagée par toutes les constantes de la palette
    m.mapSet(Value(std::string("BLACK")), makeColorInstance(cls, 0.0, 0.0, 0.0));
    m.mapSet(Value(std::string("WHITE")), makeColorInstance(cls, 1.0, 1.0, 1.0));
    m.mapSet(Value(std::string("RED")), makeColorInstance(cls, 230 / 255.0, 41 / 255.0, 55 / 255.0));
    m.mapSet(Value(std::string("GREEN")), makeColorInstance(cls, 0 / 255.0, 228 / 255.0, 48 / 255.0));
    m.mapSet(Value(std::string("BLUE")), makeColorInstance(cls, 0 / 255.0, 121 / 255.0, 241 / 255.0));
    m.mapSet(Value(std::string("YELLOW")), makeColorInstance(cls, 253 / 255.0, 249 / 255.0, 0 / 255.0));
    m.mapSet(Value(std::string("GRAY")), makeColorInstance(cls, 130 / 255.0, 130 / 255.0, 130 / 255.0));
    m.mapSet(Value(std::string("ORANGE")), makeColorInstance(cls, 255 / 255.0, 161 / 255.0, 0 / 255.0));
    m.mapSet(Value(std::string("PINK")), makeColorInstance(cls, 255 / 255.0, 109 / 255.0, 194 / 255.0));
    m.mapSet(Value(std::string("PURPLE")), makeColorInstance(cls, 200 / 255.0, 122 / 255.0, 255 / 255.0));
    m.mapSet(Value(std::string("BROWN")), makeColorInstance(cls, 127 / 255.0, 106 / 255.0, 79 / 255.0));
    m.mapSet(Value(std::string("DARKGRAY")), makeColorInstance(cls, 80 / 255.0, 80 / 255.0, 80 / 255.0));
    m.mapSet(Value(std::string("SKYBLUE")), makeColorInstance(cls, 102 / 255.0, 191 / 255.0, 255 / 255.0));
    m.mapSet(Value(std::string("LIME")), makeColorInstance(cls, 0 / 255.0, 158 / 255.0, 47 / 255.0));
    m.mapSet(Value(std::string("MAGENTA")), makeColorInstance(cls, 255 / 255.0, 0 / 255.0, 255 / 255.0));
    return m;
}
