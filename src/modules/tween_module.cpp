#include "tween_module.h"
#include "module_utils.h"
#include <cmath>
#include <string>
#include <vector>

// Module `tween` : fait évoluer un champ d'objet (ou une variable passée par `ref`) de sa
// valeur COURANTE vers une valeur cible, sur une durée, selon une courbe.
//
// Le moteur avance les tweens à chaque frame (tween_update_all) : rien à câbler dans
// draw(), et c'est la raison d'être d'un module natif — une classe Ollin devrait réclamer
// un appel par frame, dont l'oubli est le premier bug d'une bibliothèque de ce genre.
//
// Aucune dépendance graphique : le module tourne à l'identique en natif headless, où
// tween.update(dt) le pilote à la main (tests).

namespace {

// ── Courbes ─────────────────────────────────────────────────────────────────────
// Toutes prennent et rendent une progression normalisée sur [0;1]. Les noms exposés
// vivent dans des littéraux de chaîne, donc en camelCase comme le reste de l'API Ollin.

double ease_linear(double t) {
    return t;
}

double ease_in_quad(double t) {
    return t * t;
}

double ease_out_quad(double t) {
    return t * (2.0 - t);
}

double ease_in_out_quad(double t) {
    return t < 0.5 ? 2.0 * t * t : 1.0 - 2.0 * (1.0 - t) * (1.0 - t);
}

double ease_in_cubic(double t) {
    return t * t * t;
}

double ease_out_cubic(double t) {
    double u = 1.0 - t;
    return 1.0 - u * u * u;
}

double ease_in_out_cubic(double t) {
    if (t < 0.5)
        return 4.0 * t * t * t;
    double u = 1.0 - t;
    return 1.0 - 4.0 * u * u * u;
}

double ease_in_sine(double t) {
    return 1.0 - std::cos(t * 1.5707963267948966);
}

double ease_out_sine(double t) {
    return std::sin(t * 1.5707963267948966);
}

double ease_in_out_sine(double t) {
    return 0.5 * (1.0 - std::cos(t * 3.141592653589793));
}

double ease_in_expo(double t) {
    return t <= 0.0 ? 0.0 : std::pow(2.0, 10.0 * t - 10.0);
}

double ease_out_expo(double t) {
    return t >= 1.0 ? 1.0 : 1.0 - std::pow(2.0, -10.0 * t);
}

double ease_in_out_expo(double t) {
    if (t <= 0.0)
        return 0.0;
    if (t >= 1.0)
        return 1.0;
    if (t < 0.5)
        return 0.5 * std::pow(2.0, 20.0 * t - 10.0);
    return 1.0 - 0.5 * std::pow(2.0, 10.0 - 20.0 * t);
}

// Le dépassement de `back` vient de la constante 1,70158 du modèle de Penner.
double ease_in_back(double t) {
    return t * t * (2.70158 * t - 1.70158);
}

double ease_out_back(double t) {
    double u = t - 1.0;
    return 1.0 + u * u * (2.70158 * u + 1.70158);
}

double ease_in_out_back(double t) {
    const double c = 1.70158 * 1.525;
    if (t < 0.5)
        return 0.5 * (4.0 * t * t * ((c + 1.0) * 2.0 * t - c));
    double u = 2.0 * t - 2.0;
    return 0.5 * (u * u * ((c + 1.0) * u + c) + 2.0);
}

double ease_out_elastic(double t) {
    if (t <= 0.0)
        return 0.0;
    if (t >= 1.0)
        return 1.0;
    return std::pow(2.0, -10.0 * t) * std::sin((10.0 * t - 0.75) * 2.0943951023931953) + 1.0;
}

double ease_out_bounce(double t) {
    const double n = 7.5625;
    const double d = 2.75;
    if (t < 1.0 / d)
        return n * t * t;
    if (t < 2.0 / d) {
        double u = t - 1.5 / d;
        return n * u * u + 0.75;
    }
    if (t < 2.5 / d) {
        double u = t - 2.25 / d;
        return n * u * u + 0.9375;
    }
    double u = t - 2.625 / d;
    return n * u * u + 0.984375;
}

struct CurveEntry {
    const char* name;
    double (*fn)(double);
};

const CurveEntry k_curves[] = {
    {"linear", ease_linear},
    {"easeInQuad", ease_in_quad},
    {"easeOutQuad", ease_out_quad},
    {"easeInOutQuad", ease_in_out_quad},
    {"easeInCubic", ease_in_cubic},
    {"easeOutCubic", ease_out_cubic},
    {"easeInOutCubic", ease_in_out_cubic},
    {"easeInSine", ease_in_sine},
    {"easeOutSine", ease_out_sine},
    {"easeInOutSine", ease_in_out_sine},
    {"easeInExpo", ease_in_expo},
    {"easeOutExpo", ease_out_expo},
    {"easeInOutExpo", ease_in_out_expo},
    {"easeInBack", ease_in_back},
    {"easeOutBack", ease_out_back},
    {"easeInOutBack", ease_in_out_back},
    {"easeOutElastic", ease_out_elastic},
    {"easeOutBounce", ease_out_bounce},
};

const int k_curve_default = 3;   // easeInOutQuad

std::string curve_names() {
    std::string s;
    for (const auto& c : k_curves) {
        if (!s.empty())
            s += ", ";
        s += c.name;
    }
    return s;
}

int curve_index(const std::string& name, const char* fn) {
    for (int i = 0; i < (int)(sizeof(k_curves) / sizeof(k_curves[0])); i++) {
        if (name == k_curves[i].name)
            return i;
    }
    throw std::runtime_error(std::string(fn) + ": courbe inconnue '" + name + "' — disponibles : " + curve_names());
}

// ── État ────────────────────────────────────────────────────────────────────────

// Un canal = UN champ numérique animé. Une cible structurée (un Color, un Vec2) en
// produit un par composante, si bien que le reste du module ne connaît que des nombres.
struct Chan {
    Value holder;   // map/instance dont on écrit la clé ; nil quand la cible est une `ref`
    Value ref;      // référence (`ref x`) ; nil quand holder est posé
    Value key;
    double from = 0.0;
    double to = 0.0;
    bool integral = false;   // départ ET cible entiers → on arrondit (pas de dérive en float)
};

struct Tw {
    std::vector<Chan> chans;
    double dur = 0.0;
    double elapsed = 0.0;
    double delay = 0.0;
    int curve = k_curve_default;
    Value curve_fn;   // courbe fournie par le script (prioritaire sur `curve`)
    Value on_done;
    bool started = false;
    bool paused = false;
    bool alive = false;
    uint64_t born_pass = 0;   // passe d'avancement où le tween est né (cf. advance)
    uint32_t gen = 1;   // incrémentée à la libération → un handle périmé est détecté
};

std::vector<Tw> s_tweens;
std::vector<int> s_free;
bool s_engine_driven = false;
// Numéro de la passe d'avancement en cours. Un tween déclaré PENDANT une passe (par une
// courbe ou un rappel) ne doit pas y être avancé : il consommerait un pas de temps
// antérieur à sa naissance. Sans ce compteur, le résultat dépendrait du slot obtenu —
// au-dessus de l'index courant il était avancé, sur un slot recyclé plus bas il ne
// l'était pas.
uint64_t s_pass = 0;

void advance(double dt);

bool tween_alive(int slot, uint32_t gen) {
    return slot >= 0 && slot < (int)s_tweens.size() && s_tweens[slot].alive && s_tweens[slot].gen == gen;
}

int alloc_tween() {
    int slot;
    if (!s_free.empty()) {
        slot = s_free.back();
        s_free.pop_back();
    } else {
        s_tweens.push_back(Tw{});
        slot = (int)s_tweens.size() - 1;
    }
    Tw& t = s_tweens[slot];
    uint32_t gen = t.gen;
    t = Tw{};
    t.gen = gen;
    t.alive = true;
    t.born_pass = s_pass;
    return slot;
}

void free_tween(int slot) {
    Tw& t = s_tweens[slot];
    t.alive = false;
    t.gen++;
    t.chans.clear();       // relâche les Value retenues : sans cela le module garderait
    t.curve_fn = Value{};  // l'objet animé vivant longtemps après la fin de l'animation
    t.on_done = Value{};
    s_free.push_back(slot);
}

// ── Handles côté script : instance de classe native portant {slot, gen} ─────────
// Jamais un pointeur : déclarer un tween depuis un rappel de fin fait push_back sur
// s_tweens, ce qui invaliderait toute référence conservée.

Value tween_class();

Value make_handle(int slot) {
    Value h = Value::make_map();
    h.map_set(Value(std::string("__class__")), tween_class());
    h.map_set(Value(std::string("slot")), Value((int64_t)slot));
    h.map_set(Value(std::string("gen")), Value((int64_t)s_tweens[slot].gen));
    return h;
}

// Slot d'un handle, ou -1 si le tween est terminé/annulé (un handle périmé n'est PAS une
// faute : garder le handle d'une animation finie est normal).
int handle_slot(const Value& self, const char* fn) {
    Value slot = self.map_get(Value(std::string("slot")));
    Value gen = self.map_get(Value(std::string("gen")));
    if (!slot.is_integer() || !gen.is_integer())
        throw std::runtime_error(std::string(fn) + ": expected a tween");
    if (!tween_alive((int)slot.as_int(), (uint32_t)gen.as_int()))
        return -1;
    return (int)slot.as_int();
}

// ── Construction des canaux ─────────────────────────────────────────────────────

bool is_object(const Value& v) {
    return v.is_map() || v.is_class();
}

// Champs numériques communs à deux instances de MÊME classe (Color → r,g,b,a ; un Vec2
// utilisateur → x,y). L'interpolation est donc structurelle : aucun type n'est câblé ici.
// Écrit DANS l'instance courante (`cur`), qui joue elle-même le rôle de holder : le tween
// modifie l'objet, il ne le remplace pas.
void add_struct_chans(std::vector<Chan>& out, const Value& cur, const Value& tgt, const std::string& field,
                      const char* fn) {
    Value cls_a = cur.map_get(Value(std::string("__class__")));
    Value cls_b = tgt.map_get(Value(std::string("__class__")));
    if (cls_a.is_nil() || !cls_b.is_class() || cls_a.as_map() != cls_b.as_map()) {
        throw std::runtime_error(std::string(fn) + ": '" + field +
                                 "' : les deux valeurs doivent être des instances de la même classe");
    }
    int added = 0;
    for (const auto& kv : tgt.as_map()->data) {
        if (!kv.second.is_number() || !kv.first.is_string())
            continue;
        Value from = cur.map_get(kv.first);
        if (!from.is_number())
            continue;
        Chan c;
        c.holder = cur;   // on écrit DANS l'instance : le tween modifie l'objet, il ne le remplace pas
        c.key = kv.first;
        c.from = from.as_num();
        c.to = kv.second.as_num();
        c.integral = from.is_integer() && kv.second.is_integer();
        out.push_back(c);
        added++;
    }
    if (added == 0) {
        throw std::runtime_error(std::string(fn) + ": '" + field + "' : aucun champ numérique à animer");
    }
}

void add_chan(std::vector<Chan>& out, const Value& holder, const Value& key, const Value& cur, const Value& tgt,
              const char* fn) {
    // Copie, PAS une référence : les deux branches du ternaire ont des types différents,
    // donc le résultat est un temporaire — une `const std::string&` serait pendante dès la
    // fin de l'instruction, et les messages d'erreur ci-dessous liraient n'importe quoi.
    std::string field = key.is_string() ? key.as_string() : std::string("(ref)");
    if (cur.is_number() && tgt.is_number()) {
        Chan c;
        c.holder = holder;
        c.key = key;
        c.from = cur.as_num();
        c.to = tgt.as_num();
        c.integral = cur.is_integer() && tgt.is_integer();
        out.push_back(c);
        return;
    }
    if (is_object(cur) && is_object(tgt)) {
        add_struct_chans(out, cur, tgt, field, fn);
        return;
    }
    throw std::runtime_error(std::string(fn) + ": '" + field + "' n'est pas interpolable (" + cur.type_name() +
                             " → " + tgt.type_name() + ") — attendu un nombre ou une instance de classe");
}

// Annule les canaux qui visent déjà (holder, key) : sans cela deux tweens se battraient
// pour le même champ et le résultat dépendrait de l'ordre d'itération. Un tween qui perd
// tous ses canaux est libéré, mais son rappel de fin n'est PAS appelé (il n'a pas fini).
void drop_conflicts(const std::vector<Chan>& chans) {
    for (int i = 0; i < (int)s_tweens.size(); i++) {
        if (!s_tweens[i].alive)
            continue;
        auto& mine = s_tweens[i].chans;
        for (int c = (int)mine.size() - 1; c >= 0; c--) {
            if (!is_object(mine[c].holder))
                continue;
            for (const auto& nc : chans) {
                // Même champ = même objet (identité du Map*) ET même clé (chaînes internées
                // → comparaison de pointeur suffisante, mais map_get reste explicite).
                if (is_object(nc.holder) && mine[c].holder.as_map() == nc.holder.as_map() &&
                    mine[c].key.is_string() && nc.key.is_string() && mine[c].key.as_string() == nc.key.as_string()) {
                    mine.erase(mine.begin() + c);
                    break;
                }
            }
        }
        if (mine.empty())
            free_tween(i);
    }
}

// Reconnaît les deux derniers arguments par leur TYPE (chaîne/fonction = courbe,
// fonction = rappel de fin), donc aucun ordre imposé — comme ui.slider.
void read_options(const Value* args, int argc, int first, int& curve, Value& curve_fn, Value& on_done,
                  const char* fn) {
    for (int i = first; i < argc; i++) {
        if (args[i].is_string()) {
            curve = curve_index(args[i].as_string(), fn);
        } else if (args[i].is_callable()) {
            if (curve_fn.is_nil() && on_done.is_nil() && i == first) {
                curve_fn = args[i];   // 1re fonction = courbe, 2e = rappel de fin
            } else if (on_done.is_nil()) {
                on_done = args[i];
            } else {
                throw std::runtime_error(std::string(fn) + ": trop de fonctions en argument");
            }
        } else if (!args[i].is_nil()) {
            throw std::runtime_error(std::string(fn) + ": argument " + std::to_string(i + 1) +
                                     " attendu : nom de courbe, fonction, ou nil");
        }
    }
}

double duration_arg(const Value* args, int argc, int i, const char* fn) {
    double d = num_arg(args, argc, i, fn);
    if (!(d > 0.0))
        throw std::runtime_error(std::string(fn) + ": la durée doit être > 0");
    return d;
}

// ── API ─────────────────────────────────────────────────────────────────────────

// tween.to(objet, {champ: cible, …}, durée [, courbe] [, surFin])
int tween_to(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    if (argc < 3)
        throw std::runtime_error("tween.to: expected objet, {champ: cible}, durée");
    if (!is_object(args[0]))
        throw std::runtime_error("tween.to: le premier argument doit être un objet");
    if (!args[1].is_map())
        throw std::runtime_error("tween.to: le deuxième argument doit être une map {champ: cible}");
    if (args[1].map_size() == 0)
        throw std::runtime_error("tween.to: aucune valeur cible");
    double dur = duration_arg(args, argc, 2, "tween.to");
    int curve = k_curve_default;
    Value curve_fn;
    Value on_done;
    read_options(args, argc, 3, curve, curve_fn, on_done, "tween.to");

    std::vector<Chan> chans;
    for (const auto& kv : args[1].as_map()->data) {
        if (!kv.first.is_string())
            throw std::runtime_error("tween.to: les clés doivent être des noms de champs");
        Value cur = args[0].map_get(kv.first);
        if (cur.is_nil()) {
            throw std::runtime_error("tween.to: le champ '" + kv.first.as_string() + "' est absent de l'objet");
        }
        add_chan(chans, args[0], kv.first, cur, kv.second, "tween.to");
    }
    drop_conflicts(chans);
    int slot = alloc_tween();
    Tw& t = s_tweens[slot];
    t.chans = std::move(chans);
    t.dur = dur;
    t.curve = curve;
    t.curve_fn = curve_fn;
    t.on_done = on_done;
    return ctx.ret(make_handle(slot));
}

// tween.value(ref v, cible, durée [, courbe] [, surFin])
int tween_value(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    if (argc < 3)
        throw std::runtime_error("tween.value: expected ref variable, cible, durée");
    if (!is_ref(args[0]))
        throw std::runtime_error("tween.value: le premier argument doit être une référence — écrire `ref maVariable`");
    double dur = duration_arg(args, argc, 2, "tween.value");
    int curve = k_curve_default;
    Value curve_fn;
    Value on_done;
    read_options(args, argc, 3, curve, curve_fn, on_done, "tween.value");

    std::vector<Chan> chans;
    Value cur = ref_get(args[0]);
    if (cur.is_number() && args[1].is_number()) {
        Chan c;
        c.ref = args[0];
        c.from = cur.as_num();
        c.to = args[1].as_num();
        c.integral = cur.is_integer() && args[1].is_integer();
        chans.push_back(c);
    } else if (is_object(cur) && is_object(args[1])) {
        add_struct_chans(chans, cur, args[1], "(ref)", "tween.value");
    } else {
        throw std::runtime_error(std::string("tween.value: valeur non interpolable (") + cur.type_name() + " → " +
                                 args[1].type_name() + ")");
    }
    // Deux `ref x` distincts sont deux maps différentes : on ne peut pas reconnaître
    // qu'ils désignent la même variable, donc pas d'écrasement automatique ici (les
    // canaux structurés, qui écrivent dans une instance, sont eux bien dédoublonnés).
    drop_conflicts(chans);
    int slot = alloc_tween();
    Tw& t = s_tweens[slot];
    t.chans = std::move(chans);
    t.dur = dur;
    t.curve = curve;
    t.curve_fn = curve_fn;
    t.on_done = on_done;
    return ctx.ret(make_handle(slot));
}

int tween_cancel_all(CallCtx& ctx) {
    for (int i = 0; i < (int)s_tweens.size(); i++) {
        if (s_tweens[i].alive)
            free_tween(i);
    }
    return ctx.ret(Value{});
}

int tween_count(CallCtx& ctx) {
    int64_t n = 0;
    for (const auto& t : s_tweens) {
        if (t.alive)
            n++;
    }
    return ctx.ret(Value(n));
}

int tween_curves(CallCtx& ctx) {
    Value a = Value::make_array();
    for (const auto& c : k_curves)
        a.array_push(Value(std::string(c.name)));
    return ctx.ret(a);
}

// tween.update(dt) — pilotage manuel, pour un programme SANS boucle graphique (tests,
// natif headless). No-op dès que le moteur avance les tweens lui-même, sinon un appel
// laissé dans draw() doublerait la vitesse.
int tween_update(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    double dt = num_arg(args, argc, 0, "tween.update");
    if (!s_engine_driven)
        advance(dt);
    return ctx.ret(Value{});
}

// ── Méthodes du handle ──────────────────────────────────────────────────────────

// CALL_METHOD injecte le receveur en args[0] pour une instance : les arguments
// utilisateur commencent donc à args[1], comme dans ui_module.
int method_pause(CallCtx& ctx) {
    int slot = handle_slot(ctx.args[0], "tween.pause");
    if (slot >= 0)
        s_tweens[slot].paused = true;
    return ctx.ret(ctx.args[0]);
}

int method_resume(CallCtx& ctx) {
    int slot = handle_slot(ctx.args[0], "tween.resume");
    if (slot >= 0)
        s_tweens[slot].paused = false;
    return ctx.ret(ctx.args[0]);
}

int method_cancel(CallCtx& ctx) {
    int slot = handle_slot(ctx.args[0], "tween.cancel");
    if (slot >= 0)
        free_tween(slot);
    return ctx.ret(ctx.args[0]);
}

int method_is_done(CallCtx& ctx) {
    int slot = handle_slot(ctx.args[0], "tween.isDone");
    return ctx.ret(Value(slot < 0 ? 1.0 : 0.0));
}

int method_progress(CallCtx& ctx) {
    int slot = handle_slot(ctx.args[0], "tween.progress");
    if (slot < 0)
        return ctx.ret(Value(1.0));
    const Tw& t = s_tweens[slot];
    double p = t.dur > 0.0 ? t.elapsed / t.dur : 1.0;
    return ctx.ret(Value(p < 0.0 ? 0.0 : (p > 1.0 ? 1.0 : p)));
}

// Retarde le DÉMARRAGE : la valeur de départ est lue au premier avancement réel, donc
// après le délai — un tween retardé part de la valeur qu'aura la variable à ce moment.
int method_delay(CallCtx& ctx) {
    double d = num_arg(ctx.args, ctx.argc, 1, "tween.delay");
    if (d < 0.0)
        throw std::runtime_error("tween.delay: le délai doit être >= 0");
    int slot = handle_slot(ctx.args[0], "tween.delay");
    if (slot >= 0)
        s_tweens[slot].delay = d;
    return ctx.ret(ctx.args[0]);
}

Value make_tween_class() {
    Value cls = Value::make_class();
    cls.map_set(Value(std::string("__name__")), Value(std::string("Tween")));
    cls.map_set(Value(std::string("pause")), Value::make_builtin(method_pause));
    cls.map_set(Value(std::string("resume")), Value::make_builtin(method_resume));
    cls.map_set(Value(std::string("cancel")), Value::make_builtin(method_cancel));
    cls.map_set(Value(std::string("isDone")), Value::make_builtin(method_is_done));
    cls.map_set(Value(std::string("progress")), Value::make_builtin(method_progress));
    cls.map_set(Value(std::string("delay")), Value::make_builtin(method_delay));
    return cls;
}

Value tween_class() {
    static Value cls = make_tween_class();
    return cls;
}

// ── Avancement ──────────────────────────────────────────────────────────────────

// Prend la courbe PAR VALEUR (copie de la Value) et non une référence sur le tween : une
// courbe fournie par le script peut déclarer un tween, donc réallouer s_tweens, et toute
// référence sur un élément serait alors pendante.
double eased(Value curve_fn, int curve, double p) {
    if (curve_fn.is_callable()) {
        Value r = VM::current()->call_value(curve_fn, Value(p));
        return r.is_number() ? r.as_num() : p;
    }
    return k_curves[curve].fn(p);
}

void write_chan(const Chan& c, double v) {
    Value out = c.integral ? Value((int64_t)std::llround(v)) : Value(v);
    if (c.ref.is_map()) {
        ref_set(c.ref, out);
        return;
    }
    Value holder = c.holder;   // map_set mute la map : une copie de la Value suffit (même Map*)
    holder.map_set(c.key, out);
}

void advance(double dt) {
    if (dt <= 0.0 || s_tweens.empty())
        return;
    s_pass++;
    // Rappels de fin COLLECTÉS puis appelés après la passe : un rappel peut créer ou
    // annuler des tweens, donc faire push_back sur s_tweens pendant qu'on l'itère.
    std::vector<Value> finished;
    for (int i = 0; i < (int)s_tweens.size(); i++) {
        if (!s_tweens[i].alive || s_tweens[i].paused || s_tweens[i].born_pass == s_pass)
            continue;
        double step = dt;
        {
            Tw& t = s_tweens[i];
            if (t.delay > 0.0) {
                t.delay -= step;
                if (t.delay > 0.0)
                    continue;
                step = -t.delay;   // le reliquat du pas sert à l'animation
                t.delay = 0.0;
            }
            // Valeur de départ relue AU DÉMARRAGE : le tween part de la valeur courante,
            // pas de celle qu'avait la variable à la déclaration.
            if (!t.started) {
                t.started = true;
                for (auto& c : t.chans) {
                    Value cur = c.ref.is_map() ? ref_get(c.ref) : c.holder.map_get(c.key);
                    if (cur.is_number())
                        c.from = cur.as_num();
                }
            }
            t.elapsed += step;
        }
        double p = 1.0;
        bool ends = true;
        {
            const Tw& t = s_tweens[i];
            if (t.elapsed < t.dur) {
                p = t.elapsed / t.dur;
                ends = false;
            }
        }
        // Écritures et rappel de courbe : ils exécutent du code Ollin (setter d'une `ref`,
        // courbe personnalisée), donc plus aucune référence à s_tweens ne doit survivre.
        {
            std::vector<Chan> chans = s_tweens[i].chans;
            Value curve_fn = s_tweens[i].curve_fn;
            int curve = s_tweens[i].curve;
            double f = ends ? 1.0 : eased(curve_fn, curve, p);
            for (const auto& c : chans) {
                // À la fin, on pose la valeur cible EXACTE : une courbe à dépassement
                // (back, elastic) ne rend pas 1 en 1, et un arrondi laisserait 0,999.
                write_chan(c, ends ? c.to : c.from + (c.to - c.from) * f);
            }
        }
        if (ends && tween_alive(i, s_tweens[i].gen)) {
            Value cb = s_tweens[i].on_done;
            free_tween(i);
            if (cb.is_callable())
                finished.push_back(cb);
        }
    }
    for (auto& cb : finished)
        VM::current()->call_value(cb);
}

} // namespace

void tween_update_all(double dt) {
    s_engine_driven = true;   // le moteur pilote → tween.update côté script devient no-op
    advance(dt);
}

void tween_reset() {
    s_tweens.clear();
    s_free.clear();
    s_engine_driven = false;
    s_pass = 0;
}

Value make_tween_module() {
    Value m = Value::make_map();
    m.map_set(Value(std::string("to")), Value::make_builtin(tween_to));
    m.map_set(Value(std::string("value")), Value::make_builtin(tween_value));
    m.map_set(Value(std::string("update")), Value::make_builtin(tween_update));
    m.map_set(Value(std::string("cancelAll")), Value::make_builtin(tween_cancel_all));
    m.map_set(Value(std::string("count")), Value::make_builtin(tween_count));
    m.map_set(Value(std::string("curves")), Value::make_builtin(tween_curves));
    return m;
}
