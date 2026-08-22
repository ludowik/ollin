#include "tween_module.h"
#include "module_utils.h"
#include <algorithm>
#include <cmath>
#include <string>
#include <vector>

// The `tween` module moves an object's field — or a variable passed by `ref` — from its CURRENT
// value to a target, over a duration, along a curve.
//
// The engine advances the tweens every frame (tween_update_all), so nothing has to be wired into
// draw(), and that is the very reason for a native module: an Ollin class would require a call per
// frame, and forgetting it is the first bug of any library of this kind.
//
// No graphics dependency: the module runs identically in the headless native build, where
// tween.update(dt) drives it by hand for the tests.

namespace {

// They all take and return a progress normalized to [0;1]. The exposed names live in string
// literals, hence camelCase like the rest of the Ollin API.

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

// The overshoot of `back` comes from the 1.70158 constant of Penner's model.
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
    throw std::runtime_error(std::string(fn) + ": unknown curve '" + name + "' — available: " + curve_names());
}


// A channel is ONE animated numeric field. A structured target (a Color, a Vec2) produces one per
// component, so the rest of the module only ever deals with numbers.
struct Chan {
    Value holder;   // the map or instance whose key is written; nil when the target is a `ref`
    Value ref;      // the reference (`ref x`); nil when holder is set
    Value key;
    double from = 0.0;
    double to = 0.0;
    bool integral = false;   // the start AND the target are integers, so we round, with no float drift
};

// A STEP of the sequence: the channels it animates, its duration and its curve. A step with no
// channel is a pure wait ({delay: 0.2} inside a sequence). tween.to and tween.value create a
// one-step sequence, so the whole module knows a single path and a sequence is not a special
// case.
struct Step {
    std::vector<Chan> chans;
    bool is_wait = false;   // a step declared without `to`: it merely lets time pass
    bool started = false;  // have the bounds been read? On the FIRST pass only — a return trip
                            // replays the same bounds, otherwise it goes nowhere)
    double dur = 0.0;
    int curve = k_curve_default;
    Value curve_fn;   // curve fournie par le script (prioritaire sur `curve`)
};

// PLAYBACK plan: one segment per pass over the SEQUENCE, +1 in the declared direction and -1
// backwards. repeat(n) repeats the list; its second parameter appends the mirror of the whole plan
// (list reversed, directions flipped). Two calls COMPOSE, each acting on the plan built so far, so
// the order matters:
//   .repeat(2)                    -> +1 +1          (two forward passes)
//   .repeat(2, true)              -> +1 +1 -1 -1    (two forward, then the two back)
//   .repeat(nil, true).repeat(2)  -> +1 -1 +1 -1    (two round trips)
// An empty plan does not exist: every tween starts with one segment. A -1 segment replays the steps
// in REVERSE order, each one backwards.
struct Tw {
    std::vector<Step> steps;
    size_t pos = 0;      // the current step, counted in the current segment's order
    std::vector<int8_t> plan{1};
    size_t seg = 0;      // segment en cours dans le plan
    double cycle = 0.0;  // the duration of one full pass, frozen at construction
    bool endless = false;   // the plan is replayed endlessly
    double elapsed = 0.0;
    double delay = 0.0;
    Value on_done;
    bool paused = false;
    bool alive = false;
    uint64_t born_pass = 0;   // the advancing pass the tween was born in (see advance)
    uint32_t gen = 1;   // incremented on release, which makes a stale handle detectable
};

std::vector<Tw> s_tweens;
std::vector<int> s_free;
bool s_engine_driven = false;
// Number of the advance pass under way. A tween declared DURING a pass — by a curve or a callback —
// must not be advanced in it: it would consume a time step from before it existed. Without this
// counter the outcome depended on the slot obtained: above the current index it was advanced, on a
// recycled slot lower down it was not.
uint64_t s_pass = 0;

void advance(double dt);

// Duration of one full pass over the sequence, the same in both directions.
double cycle_duration(const Tw& t) {
    double d = 0.0;
    for (const auto& e : t.steps)
        d += e.dur;
    return d;
}

// REAL index of the k-th step of the current segment: a -1 segment replays the sequence in reverse,
// so the k-th played is the last but one, and so on.
size_t step_index(const Tw& t, size_t k) {
    return t.plan[t.seg] > 0 ? k : t.steps.size() - 1 - k;
}

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
    t.steps.clear();      // releases the Values held: without this the module would keep
    t.on_done = Value{};   // the animated object alive long after the animation ended
    s_free.push_back(slot);
}

// Script-side handles: a native class instance carrying {slot, gen}.
// Never a pointer: declaring a tween from a completion callback push_backs onto s_tweens, which
// would invalidate any reference kept.

Value tween_class();

Value make_handle(int slot) {
    Value h = Value::make_map();
    h.map_set(Value(std::string("__class__")), tween_class());
    h.map_set(Value(std::string("slot")), Value((int64_t)slot));
    h.map_set(Value(std::string("gen")), Value((int64_t)s_tweens[slot].gen));
    return h;
}

// A handle's slot, or -1 when the tween is finished or cancelled. A stale handle is NOT a mistake:
// keeping the handle of a finished animation is perfectly normal.
int handle_slot(const Value& self, const char* fn) {
    Value slot = self.map_get(Value(std::string("slot")));
    Value gen = self.map_get(Value(std::string("gen")));
    if (!slot.is_integer() || !gen.is_integer())
        throw std::runtime_error(std::string(fn) + ": expected a tween");
    if (!tween_alive((int)slot.as_int(), (uint32_t)gen.as_int()))
        return -1;
    return (int)slot.as_int();
}

// A tween handle is a map like any other: without this test it would be taken for the object to
// animate, and the refusal would complain about a missing '__class__' field instead of naming the
// real cause, which is that nesting is not supported.
bool is_tween_handle(const Value& v) {
    if (!v.is_map())
        return false;
    Value cls = v.map_get(Value(std::string("__class__")));
    return cls.is_class() && cls.as_map() == tween_class().as_map();
}


bool is_object(const Value& v) {
    return v.is_map() || v.is_class();
}

// Numeric fields common to two instances of the SAME class: r,g,b,a for a Color, x,y for a
// user-defined Vec2. The interpolation is therefore structural, and no type is hard-wired here. It
// writes INTO the current instance (`cur`), which acts as its own holder: the tween modifies the
// object, it does not replace it.
void add_struct_chans(std::vector<Chan>& out, const Value& cur, const Value& tgt, const std::string& field,
                      const char* fn) {
    Value cls_a = cur.map_get(Value(std::string("__class__")));
    Value cls_b = tgt.map_get(Value(std::string("__class__")));
    if (cls_a.is_nil() || !cls_b.is_class() || cls_a.as_map() != cls_b.as_map()) {
        throw std::runtime_error(std::string(fn) + ": '" + field +
                                 "': both values must be instances of the same class");
    }
    int added = 0;
    for (const auto& kv : tgt.as_map()->data) {
        if (!kv.second.is_number() || !kv.first.is_string())
            continue;
        Value from = cur.map_get(kv.first);
        if (!from.is_number())
            continue;
        Chan c;
        c.holder = cur;   // we write INTO the instance: the tween mutates the object, it does not replace it
        c.key = kv.first;
        c.from = from.as_num();
        c.to = kv.second.as_num();
        c.integral = from.is_integer() && kv.second.is_integer();
        out.push_back(c);
        added++;
    }
    if (added == 0) {
        throw std::runtime_error(std::string(fn) + ": '" + field + "': no numeric field to animate");
    }
}

void add_chan(std::vector<Chan>& out, const Value& holder, const Value& key, const Value& cur, const Value& tgt,
              const char* fn) {
    // A copy, NOT a reference: the two branches of the ternary have different types, so the result
    // is a temporary — a const std::string& would dangle at the end of the statement, and the error
    // messages below would read garbage.
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
                             " → " + tgt.type_name() + ") — expected a number or a class instance");
}

// Cancels the channels already targeting (holder, key): without this two tweens would fight over the
// same field and the outcome would depend on the iteration order. A tween that loses all its channels
// is freed, but its completion callback is NOT called — it did not finish.
void drop_conflicts(const std::vector<Chan>& chans) {
    for (int i = 0; i < (int)s_tweens.size(); i++) {
        if (!s_tweens[i].alive)
            continue;
        bool reste = false;
        for (auto& step : s_tweens[i].steps) {
            auto& mine = step.chans;
            for (int c = (int)mine.size() - 1; c >= 0; c--) {
                if (!is_object(mine[c].holder))
                    continue;
                for (const auto& nc : chans) {
                    // Same field means the same object (Map* identity) AND the same key. Interned
                    // strings would make a pointer comparison enough, but map_get stays explicit.
                    if (is_object(nc.holder) && mine[c].holder.as_map() == nc.holder.as_map() &&
                        mine[c].key.is_string() && nc.key.is_string() &&
                        mine[c].key.as_string() == nc.key.as_string()) {
                        mine.erase(mine.begin() + c);
                        break;
                    }
                }
            }
            // A WAIT step legitimately has no channel: it counts as work remaining, otherwise
            // overwriting one field would cancel the whole sequence.
            if (!mine.empty() || step.is_wait)
                reste = true;
        }
        if (!reste)
            free_tween(i);
    }
}

// Channels from a {field: target} table onto an object: key validation and reading the start values,
// which used to be written twice. `fn` prefixes the messages — "tween.to" for one caller,
// "tween.sequence: step N" for the other.
void add_map_chans(std::vector<Chan>& out, const Value& objet, const Value& vers, const char* fn) {
    // The only two ways to pass a tween where numbers are expected. Without these tests the handle
    // would be animated like an ordinary map, and the refusal would complain about a missing
    // '__class__' field.
    if (is_tween_handle(vers))
        throw std::runtime_error(std::string(fn) +
                                 ": a tween cannot be a target — sequences do not nest");
    if (is_tween_handle(objet))
        throw std::runtime_error(std::string(fn) + ": a tween cannot be the animated object");
    for (const auto& kv : vers.as_map()->data) {
        if (!kv.first.is_string())
            throw std::runtime_error(std::string(fn) + ": keys must be field names");
        Value cur = objet.map_get(kv.first);
        if (cur.is_nil())
            throw std::runtime_error(std::string(fn) + ": le champ '" + kv.first.as_string() +
                                     "' est absent de l'objet");
        add_chan(out, objet, kv.first, cur, kv.second, fn);
    }
}

// Sorting out a curve given by the script: either a name or a function.
void read_curve(const Value& v, int& curve, Value& curve_fn, const char* fn) {
    if (v.is_string())
        curve = curve_index(v.as_string(), fn);
    else if (v.is_callable())
        curve_fn = v;
    else
        throw std::runtime_error(std::string(fn) + ": expected a curve: a name or a function");
}

// Recognizes the last two arguments by their TYPE — a string or function is the curve, a function the
// completion callback — so no order is imposed, as in ui.slider.
void read_options(const Value* args, int argc, int first, int& curve, Value& curve_fn, Value& on_done,
                  const char* fn) {
    for (int i = first; i < argc; i++) {
        if (args[i].is_string()) {
            curve = curve_index(args[i].as_string(), fn);
        } else if (args[i].is_callable()) {
            if (curve_fn.is_nil() && on_done.is_nil() && i == first) {
                curve_fn = args[i];   // 1re fonction = curve, 2e = rappel de fin
            } else if (on_done.is_nil()) {
                on_done = args[i];
            } else {
                throw std::runtime_error(std::string(fn) + ": trop de fonctions en argument");
            }
        } else if (!args[i].is_nil()) {
            throw std::runtime_error(std::string(fn) + ": argument " + std::to_string(i + 1) +
                                     " expected: curve name, function, or nil");
        }
    }
}

// The tail shared by tween.to, tween.value and tween.sequence: allocate, install the steps and the
// completion callback, return the handle. All three used to write it identically.
int creer_tween(std::vector<Step>&& steps, const Value& on_done) {
    int slot = alloc_tween();
    Tw& t = s_tweens[slot];
    t.steps = std::move(steps);
    t.on_done = on_done;
    t.cycle = cycle_duration(t);
    return slot;
}

// The single step of ONE animation: the tween.to and tween.value case.
Step etape_simple(std::vector<Chan>&& chans, double dur, int curve, const Value& curve_fn) {
    Step e;
    e.chans = std::move(chans);
    e.dur = dur;
    e.curve = curve;
    e.curve_fn = curve_fn;
    return e;
}

double duration_arg(const Value* args, int argc, int i, const char* fn) {
    double d = num_arg(args, argc, i, fn);
    if (!(d > 0.0))
        throw std::runtime_error(std::string(fn) + ": duration must be > 0");
    return d;
}


// tween.to(object, {field: target, …}, duration [, curve] [, onDone])
int tween_to(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    if (argc < 3)
        throw std::runtime_error("tween.to: expected object, {field: target}, duration");
    if (!is_object(args[0]))
        throw std::runtime_error("tween.to: first argument must be an object");
    if (!args[1].is_map())
        throw std::runtime_error("tween.to: second argument must be a map {field: target}");
    if (args[1].map_size() == 0)
        throw std::runtime_error("tween.to: no target value");
    double dur = duration_arg(args, argc, 2, "tween.to");
    int curve = k_curve_default;
    Value curve_fn;
    Value on_done;
    read_options(args, argc, 3, curve, curve_fn, on_done, "tween.to");

    std::vector<Chan> chans;
    add_map_chans(chans, args[0], args[1], "tween.to");
    drop_conflicts(chans);
    std::vector<Step> steps;
    steps.push_back(etape_simple(std::move(chans), dur, curve, curve_fn));
    return ctx.ret(make_handle(creer_tween(std::move(steps), on_done)));
}

// tween.value(ref v, target, duration [, curve] [, onDone])
int tween_value(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    if (argc < 3)
        throw std::runtime_error("tween.value: expected ref variable, target, duration");
    if (!is_ref(args[0]))
        throw std::runtime_error("tween.value: first argument must be a reference — write `ref myVariable`");
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
    // Two distinct `ref x` are two different maps: we cannot tell that they denote the same
    // variable, so there is no automatic overwrite here. Structured channels, which write into an
    // instance, are properly deduplicated.
    drop_conflicts(chans);
    std::vector<Step> steps;
    steps.push_back(etape_simple(std::move(chans), dur, curve, curve_fn));
    return ctx.ret(make_handle(creer_tween(std::move(steps), on_done)));
}

// tween.sequence(object, [ {to: {field: target}, delay: seconds [, curve: name] [, target: object]}, … ])
//
// A SEQUENCE of steps played one after another. The time key is `delay` in both roles: the animation's
// duration when the step carries `to`, a plain wait otherwise — a single time key, whose meaning is
// read from the presence of `to`.
//
// Any unknown key is REFUSED along with the list of accepted ones: without that refusal a mistaken
// `duration` or `easing` would be silently ignored and the step would start with no duration. That is
// the mistake one hunts for the longest.
int tween_sequence(CallCtx& ctx) {
    static constexpr const char* FN = "tween.sequence";
    Value* args = ctx.args;
    int argc = ctx.argc;
    if (argc < 2)
        throw std::runtime_error(std::string(FN) + ": expected object, [steps]");
    if (!is_object(args[0]))
        throw std::runtime_error(std::string(FN) + ": first argument must be an object");
    if (!args[1].is_array())
        throw std::runtime_error(std::string(FN) + ": second argument must be an array of steps");
    int64_t nb = args[1].array_size();
    if (nb == 0)
        throw std::runtime_error(std::string(FN) + ": the sequence is empty");

    // After the list only ONE argument is accepted: the completion callback. We do not go through
    // read_options, which would take a string for a curve — and the curve is declared per step, so a
    // string naming a default curve used to be accepted there with no effect.
    Value on_done;
    for (int i = 2; i < argc; i++) {
        if (args[i].is_nil())
            continue;
        if (args[i].is_string())
            throw std::runtime_error(std::string(FN) + ": the curve is declared per step (`curve` key)");
        if (!args[i].is_callable())
            throw std::runtime_error(std::string(FN) + ": argument " + std::to_string(i + 1) +
                                     " expected: completion callback, or nil");
        if (!on_done.is_nil())
            throw std::runtime_error(std::string(FN) + ": un seul rappel de fin");
        on_done = args[i];
    }

    std::vector<Step> steps;
    std::vector<Chan> tous;   // tous les canaux de la suite, pour une seule passe d'annulation
    for (int64_t k = 1; k <= nb; k++) {   // Ollin arrays are 1-based
        Value brut = args[1].array_get(k);
        const std::string ou = std::string(FN) + ": step " + std::to_string(k);
        if (!brut.is_map())
            throw std::runtime_error(ou + " must be a map {to: …, delay: …}");
        Value cible = args[0], vers, curve;
        double delai = -1.0;
        for (const auto& kv : brut.as_map()->data) {
            if (!kv.first.is_string())
                throw std::runtime_error(ou + ": keys must be names");
            const std::string& key = kv.first.as_string();
            if (key == "to") {
                vers = kv.second;
            } else if (key == "delay") {
                if (!kv.second.is_number())
                    throw std::runtime_error(ou + ": `delay` must be a number of seconds");
                delai = kv.second.as_num();
            } else if (key == "curve") {
                curve = kv.second;
            } else if (key == "target") {
                cible = kv.second;
            } else {
                throw std::runtime_error(ou + ": unknown key '" + key + "' — allowed: to, delay, curve, target");
            }
        }
        if (!(delai > 0.0))
            throw std::runtime_error(ou + " : `delay` manquant ou <= 0");
        Step e;
        e.dur = delai;
        if (!curve.is_nil())
            read_curve(curve, e.curve, e.curve_fn, ou.c_str());
        e.is_wait = vers.is_nil();
        if (!vers.is_nil()) {
            if (!is_object(cible))
                throw std::runtime_error(ou + ": `target` must be an object");
            if (!vers.is_map() || vers.map_size() == 0)
                throw std::runtime_error(ou + ": `to` must be a non-empty map {field: target}");
            add_map_chans(e.chans, cible, vers, ou.c_str());
            tous.insert(tous.end(), e.chans.begin(), e.chans.end());
        }
        steps.push_back(std::move(e));
    }

    // A single cancellation pass for the WHOLE sequence: called per step, it could free a tween that
    // still had channels targeted by a later step.
    drop_conflicts(tous);
    return ctx.ret(make_handle(creer_tween(std::move(steps), on_done)));
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

// tween.update(dt) drives the module by hand, for a program with NO render loop (tests, headless
// native). It is a no-op as soon as the engine advances the tweens itself, otherwise a call left in
// draw() would double the speed.
int tween_update(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    double dt = num_arg(args, argc, 0, "tween.update");
    if (!s_engine_driven)
        advance(dt);
    return ctx.ret(Value{});
}


// CALL_METHOD injects the receiver as args[0] for an instance, so the user arguments start at
// args[1], as in ui_module.
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
    return ctx.ret(Value::make_bool(slot < 0));
}

int method_progress(CallCtx& ctx) {
    int slot = handle_slot(ctx.args[0], "tween.progress");
    if (slot < 0)
        return ctx.ret(Value(1.0));
    const Tw& t = s_tweens[slot];
    // Progress over the WHOLE plan, measured in TIME: a sequence's steps do not share one duration,
    // so counting the steps crossed would give a progress that jumps. The last segment overshoots its
    // duration while waiting for the pass that will finish the tween, hence the ceiling before the
    // division; after that (base + p) / total is at most 1 by construction, and only the floor
    // remains to be applied, for a delay or a negative time. An endless plan reports the progress of
    // its current pass.
    double cycle = t.cycle;
    double fait = 0.0;
    for (size_t k = 0; k < t.pos && k < t.steps.size(); k++)
        fait += t.steps[step_index(t, k)].dur;
    double p = cycle > 0.0 ? std::min((fait + t.elapsed) / cycle, 1.0) : 1.0;
    double total = t.endless ? 1.0 : (double)t.plan.size();
    double base = t.endless ? 0.0 : (double)t.seg;
    p = (base + p) / total;
    return ctx.ret(Value(p < 0.0 ? 0.0 : p));
}

// ONE method for every kind of repetition: repeat([count] [, pingPong]).
//
//   .repeat()             forward, forward, …                   endless
//   .repeat(2)            forward, forward
//   .repeat(2, true)      forward, forward, back, back          (the return covers the WHOLE plan)
//   .repeat(nil, true)    forward, back, forward, back, …       endless
//
// The count is recognized by its POSITION rather than its type: `true` used to equal 1 in Ollin, which
// had no boolean type, so repeat(true) would have been indistinguishable from repeat(1). Hence the
// explicit nil to say "no count" while still asking for the round trip.
//
// The round trip appends the plan's mirror: the vector reversed, the directions flipped. Two
// successive calls therefore compose, each acting on the plan built so far.
int method_repeat(CallCtx& ctx) {
    static constexpr const char* FN = "tween.repeat";
    double n = 0.0;   // 0 = aucun compte fourni ⇒ sans fin
    if (ctx.argc > 1 && !ctx.args[1].is_nil()) {
        if (!ctx.args[1].is_number())
            throw std::runtime_error(std::string(FN) + ": repeat count must be a number or nil");
        n = ctx.args[1].as_num();
        if (n < 1.0 || n != std::floor(n))
            throw std::runtime_error(std::string(FN) + ": repeat count must be an integer >= 1");
    }
    bool ping_pong = ctx.argc > 2 && !is_falsy(ctx.args[2]);
    int slot = handle_slot(ctx.args[0], FN);
    if (slot >= 0) {
        Tw& t = s_tweens[slot];
        std::vector<int8_t> bloc = t.plan;
        for (int k = 1; k < (int)n; k++)
            t.plan.insert(t.plan.end(), bloc.begin(), bloc.end());
        if (ping_pong) {
            for (size_t i = t.plan.size(); i > 0; i--)
                t.plan.push_back((int8_t)-t.plan[i - 1]);
        }
        t.endless = (n == 0.0);
    }
    return ctx.ret(ctx.args[0]);
}

// Delays the START: the initial value is read at the first real advance, hence after the delay, so a
// delayed tween starts from whatever the variable holds at that moment.
int method_delay(CallCtx& ctx) {
    double d = num_arg(ctx.args, ctx.argc, 1, "tween.delay");
    if (d < 0.0)
        throw std::runtime_error("tween.delay: delay must be >= 0");
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
    cls.map_set(Value(std::string("repeat")), Value::make_builtin(method_repeat));
    return cls;
}

Value tween_class() {
    static Value cls = make_tween_class();
    return cls;
}


// Takes the curve BY VALUE (a copy of the Value) rather than a reference into the tween: a curve
// supplied by the script can declare a tween, hence reallocate s_tweens, and any reference to an
// element would then dangle.
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
    Value holder = c.holder;   // map_set mutates the map, so a copy of the Value is enough: the same Map*
    holder.map_set(c.key, out);
}

// Reads a step's start values, once: it begins from whatever the previous step left. On later passes
// — a repetition, or going backwards — the bounds are kept, otherwise a return trip goes nowhere.
void start_step(Tw& t, size_t idx) {
    if (t.steps[idx].started)
        return;
    t.steps[idx].started = true;
    for (auto& c : t.steps[idx].chans) {
        Value cur = c.ref.is_map() ? ref_get(c.ref) : c.holder.map_get(c.key);
        if (cur.is_number())
            c.from = cur.as_num();
    }
}

// Settles a step's channels at the end it aims for, in the current segment's direction. Called when
// the step is crossed within a single time step: without it, a step shorter than the step would leave
// no trace. `idx` is the step's REAL index, as for start_step — two index conventions in the same
// caller would be a trap.
void settle_step_end(Tw& t, size_t idx) {
    int8_t sens = t.plan[t.seg];
    std::vector<Chan> chans = t.steps[idx].chans;
    for (const auto& c : chans)
        write_chan(c, sens > 0 ? c.to : c.from);
}

void advance(double dt) {
    if (dt <= 0.0 || s_tweens.empty())
        return;
    s_pass++;
    // Completion callbacks are COLLECTED and only called after the pass: a callback can create or
    // cancel tweens, hence push_back onto s_tweens while we iterate it.
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
                step = -t.delay;   // the step's remainder feeds the animation
                t.delay = 0.0;
            }
            t.elapsed += step;
        }
        // End of a STEP: we move to the next one keeping the leftover time, otherwise a short
        // animation would lose a fraction of a second on every pass. When the sequence is exhausted,
        // the next plan segment replays it, backwards for a -1 segment.
        // The tween's generation is taken at the START of its advance: every liveness test below
        // compares against it, because `alive` alone cannot tell "still here" from "cancelled, then
        // slot taken over by another tween" (see alloc_tween, which sets alive = true again).
        uint32_t gen0 = s_tweens[i].gen;
        double p = 1.0;
        bool ends = true;      // the last segment is over, so the tween has finished
        bool seg_ends = true;  // the current step is over
        int8_t sens = 1;
        size_t idx = 0;
        // This loop calls Ollin code: a `ref` getter in start_step, a setter in settle_step_end. That
        // code can declare a tween, hence push_back onto s_tweens and REALLOCATE the vector, so no
        // Tw& reference may cross these calls and the slot's liveness is rechecked after each one.
        {
            while (true) {
                if (!tween_alive(i, gen0))
                    break;
                Tw& t = s_tweens[i];
                double dur = t.steps[step_index(t, t.pos)].dur;
                if (dur <= 0.0 || t.elapsed < dur)
                    break;
                // Last step of the last segment: we leave WITHOUT subtracting, keeping
                // elapsed >= dur. That overshoot is what says "finished" below — subtracting it made
                // the tween believe it was restarting this step, and it then rewrote the START value
                // instead of the target (observed).
                if (t.pos + 1 >= t.steps.size() && t.seg + 1 >= t.plan.size() && !t.endless)
                    break;
                size_t franchie = step_index(t, t.pos);
                // The crossed step is STARTED and then SETTLED at its exact end before we leave it:
                // otherwise a step shorter than one time step would be skipped without ever reading
                // its bounds or writing its target. Each call goes back to s_tweens[i], because the
                // first may run an Ollin getter that reallocates the vector, which would leave `t`
                // dangling for the second.
                //
                // Liveness is checked on the GENERATION and not on `alive` alone: the code called can
                // cancel this tween AND THEN declare another, which takes the freed slot and marks it
                // alive again. The crossed index would then address a stranger's steps, possibly
                // fewer of them.
                start_step(s_tweens[i], franchie);
                if (!tween_alive(i, gen0))
                    break;
                settle_step_end(s_tweens[i], franchie);
                if (!tween_alive(i, gen0))
                    break;   // the code called cancelled this tween
                Tw& t2 = s_tweens[i];                 // the reference is READ AGAIN after the calls
                t2.elapsed -= t2.steps[franchie].dur;
                if (t2.pos + 1 < t2.steps.size()) {
                    t2.pos++;
                } else if (t2.seg + 1 < t2.plan.size()) {
                    t2.seg++;
                    t2.pos = 0;
                } else {
                    t2.seg = 0;   // sans fin : on rejoue le plan depuis son premier segment
                    t2.pos = 0;
                }
            }
            if (!tween_alive(i, gen0))
                continue;   // cancelled while being crossed: there is nothing left to write
            Tw& t = s_tweens[i];
            sens = t.plan[t.seg];
            idx = step_index(t, t.pos);
            double dur = t.steps[idx].dur;
            if (t.elapsed < dur) {
                p = dur > 0.0 ? t.elapsed / dur : 1.0;
                seg_ends = false;
                ends = false;
            }
        }
        start_step(s_tweens[i], idx);   // outside of any reference held
        if (!tween_alive(i, gen0))
            continue;
        // The writes and the curve callback run Ollin code — a `ref` setter, a custom curve — so no
        // reference into s_tweens may survive here.
        {
            std::vector<Chan> chans = s_tweens[i].steps[idx].chans;
            Value curve_fn = s_tweens[i].steps[idx].curve_fn;
            int curve = s_tweens[i].steps[idx].curve;
            double f = seg_ends ? 1.0 : eased(curve_fn, curve, p);
            for (const auto& c : chans) {
                // A -1 segment plays from the target back to the start. At a step's end we write the
                // EXACT value of its endpoint: an overshooting curve (back, elastic) does not return 1
                // at 1, and rounding would leave 0.999.
                double a = sens > 0 ? c.from : c.to;
                double b = sens > 0 ? c.to : c.from;
                write_chan(c, seg_ends ? b : a + (b - a) * f);
            }
        }
        if (ends && tween_alive(i, gen0)) {
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
    s_engine_driven = true;   // the engine drives, so tween.update becomes a no-op on the script side
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
    m.map_set(Value(std::string("sequence")), Value::make_builtin(tween_sequence));
    m.map_set(Value(std::string("value")), Value::make_builtin(tween_value));
    m.map_set(Value(std::string("update")), Value::make_builtin(tween_update));
    m.map_set(Value(std::string("cancelAll")), Value::make_builtin(tween_cancel_all));
    m.map_set(Value(std::string("count")), Value::make_builtin(tween_count));
    m.map_set(Value(std::string("curves")), Value::make_builtin(tween_curves));
    return m;
}
