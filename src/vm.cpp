#include "vm.h"
#include "modules/array_module.h"
#include "modules/modules.h"
#include "utf8.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <sstream>
#include <stdexcept>
#include <vector>

// mem() : mesure de la mémoire tas utilisée — API par plateforme.
#if defined(__EMSCRIPTEN__)
#include <malloc.h>
#elif defined(__APPLE__)
#include <malloc/malloc.h>
#elif defined(__GLIBC__)
#include <malloc.h>
#elif defined(_WIN32)
#include <windows.h>
#include <psapi.h>
#endif

static VM* s_current_vm = nullptr;

// Validation partagée des bornes d'un range / for numérique. Source de vérité
// unique pour les deux voies d'itération (objet Range via MAKE_RANGE, et chemin
// rapide via FOR_PREP branche float) : le pas doit être non nul, et les bornes
// finies — une borne NaN/infinie ne satisferait jamais la condition de fin et
// ferait boucler l'itération indéfiniment. (La branche int de FOR_PREP n'appelle
// pas cette fonction : les entiers sont finis par construction, elle garde son
// propre test de pas nul.)
static void validate_numeric_range(double start, double end, double step, const std::string& loc) {
    if (step == 0.0)
        throw std::runtime_error(loc + ": runtime: le pas ne peut pas être 0");
    if (!std::isfinite(start) || !std::isfinite(end) || !std::isfinite(step))
        throw std::runtime_error(loc + ": runtime: bornes de range non finies (NaN/infini interdit)");
}

// ── Interned meta-key constants (initialized once, reused across all calls) ───
struct MetaKeys {
    Value class_, parent_, str_, name_, init_;
    Value add_, sub_, mul_, div_, mod_, neg_, eq_, lt_, le_;
    MetaKeys()
        : class_(std::string("__class__")), parent_(std::string("__parent__")), str_(std::string("__str")),
          name_(std::string("__name__")), init_(std::string("init")), add_(std::string("__add")),
          sub_(std::string("__sub")), mul_(std::string("__mul")), div_(std::string("__div")),
          mod_(std::string("__mod")), neg_(std::string("__neg")), eq_(std::string("__eq")), lt_(std::string("__lt")),
          le_(std::string("__le")) {
    }
};
static MetaKeys& MK() {
    static MetaKeys mk;
    return mk;
}

bool VM::is_instance(const Value& v) {
    return (v.is_map() || v.is_class()) && !v.map_get(MK().class_).is_nil();
}

// Pseudo-méthode `len` intégrée des maps : synthétisée par GET_INDEX quand la map
// ne définit pas elle-même "len". Fonction NOMMÉE (pas un lambda) pour que
// CALL_METHOD la reconnaisse par pointeur et lui injecte la map en self — les
// maps n'injectent pas self par défaut (sinon math.noise(x) recevrait le module).
static int builtin_map_len(CallCtx& ctx) {
    return ctx.ret(Value((int64_t)(ctx.argc > 0 ? ctx.args[0].map_size() : 0)));
}

// ── protoChainGet ─────────────────────────────────────────────────────────────
Value VM::proto_chain_get(const Value& obj, const Value& key) {
    if (obj.is_map() || obj.is_class()) {
        Value v = obj.map_get(key);
        if (!v.is_nil())
            return v;
        if (obj.is_map()) {
            Value cls = obj.map_get(MK().class_);
            if (!cls.is_nil())
                return proto_chain_get(cls, key);
        } else {
            Value par = obj.map_get(MK().parent_);
            if (!par.is_nil())
                return proto_chain_get(par, key);
        }
    }
    return Value{};
}

Value VM::proto_chain_rest(const Value& obj, const Value& key) {
    if (obj.is_map()) {
        Value cls = obj.map_get(MK().class_);
        if (!cls.is_nil())
            return proto_chain_get(cls, key);
    } else if (obj.is_class()) {
        Value par = obj.map_get(MK().parent_);
        if (!par.is_nil())
            return proto_chain_get(par, key);
    }
    return Value{};
}

// ── growRegs : croît par doublement, max 4096, size reste exacte ─────────────
void VM::grow_regs(size_t needed) {
    if (regs.size() >= needed)
        return;
    if (needed > 4096)
        throw std::runtime_error("runtime: stack overflow (max 4096 registers)");
    size_t cap = regs.capacity() < 32 ? 32 : regs.capacity();
    while (cap < needed)
        cap *= 2;
    regs.reserve(cap < 4096 ? cap : 4096);
    regs.resize(needed);
}

int VM::invoke_builtin(Value::BuiltinFn fn, Value* results, int argc, int cap) {
    CallCtx ctx{this, results, argc, cap};
    last_results_ = fn(ctx);
    return last_results_;
}

int VM::invoke_builtin_regs(Value::BuiltinFn fn, int result_base, int argc) {
    // cap = reg_count du frame courant - (result_base - reg_base) = varargs_base - result_base.
    return invoke_builtin(fn, &regs[result_base], argc, call_stack.back().varargs_base - result_base);
}

// ── invokeStr : mini-loop to call __str without recursion ─────────────────────
std::string VM::invoke_str(Value obj) { // by value: regs.resize() ne invalide pas obj
    Value cls = obj.map_get(MK().class_);
    if (cls.is_nil())
        return "{map}";
    Value str_fn = proto_chain_get(cls, MK().str_);
    if (str_fn.is_nil() || !str_fn.is_callable()) {
        Value nm = cls.map_get(MK().name_);
        return nm.is_string() ? "{" + nm.as_string() + "}" : "{object}";
    }
    uint8_t fi;
    std::unique_ptr<std::vector<Upvalue*>> frame_upvals;
    switch (str_fn.tag) {
    case Value::T_FUNCTION:
        fi = (uint8_t)str_fn.as_int();
        break;
    case Value::T_CLOSURE: {
        fi = str_fn.as_closure()->func_idx;
        const auto& uvs = str_fn.as_closure()->upvals;
        if (!uvs.empty())
            frame_upvals = std::make_unique<std::vector<Upvalue*>>(uvs);
        break;
    }
    case Value::T_BUILTIN: {
        Value self = obj; // 1 slot dispo (self) ; le builtin y écrit son résultat, relu ensuite
        int n = invoke_builtin(str_fn.as_builtin(), &self, 1, 1);
        return (n >= 1 && self.is_string()) ? self.as_string() : "{object}";
    }
    default: {
        Value nm = cls.map_get(MK().name_);
        return nm.is_string() ? "{" + nm.as_string() + "}" : "{object}";
    }
    }
    int call_base = (int)regs.size();
    grow_regs((size_t)(call_base + std::max((int)ch->funcs[fi].reg_count, 1)));
    regs[call_base] = obj; // self en R[0] avant pushCallFrame
    uint32_t saved_ip = ip;
    ip = push_call_frame(call_base, fi, 1, std::move(frame_upvals), 0);
    run_goto(call_stack.size() - 1);
    std::string result;
    if ((int)regs.size() > call_base) {
        const Value& rv = regs[call_base];
        if (rv.is_string()) {
            result = rv.as_string();
        } else {
            std::ostringstream os;
            if (rv.is_nil())
                os << "nil";
            else if (rv.is_integer())
                os << rv.as_int();
            else if (rv.is_float()) {
                double d = rv.as_float();
                if (d == (long long)d && d >= -1e15 && d <= 1e15)
                    os << (long long)d;
                else
                    os << d;
            }
            result = os.str();
        }
    }
    regs.resize(call_base);
    ip = saved_ip;
    return result;
}

// ── valueToString ─────────────────────────────────────────────────────────────
std::string value_to_string(const Value& v) {
    if (v.is_nil())
        return "nil";
    if (v.is_string())
        return v.as_string();
    if (v.is_class())
        return "{class}";
    if (v.is_map()) {
        VM* vm = VM::current();
        if (vm) {
            Value cls = v.map_get(MK().class_);
            if (!cls.is_nil())
                return vm->invoke_str(v);
        }
        return "{map}";
    }
    if (v.is_array())
        return "{array}";
    if (v.is_iterator())
        return "{iterator}";
    if (v.is_range())
        return "{range}";
    if (v.is_func_val() || v.is_closure() || v.is_builtin())
        return "{function}";
    if (v.is_integer())
        return std::to_string(v.as_int());
    std::ostringstream os;
    double d = v.as_float();
    if (d == (long long)d && d >= -1e15 && d <= 1e15)
        os << (long long)d;
    else
        os << d;
    return os.str();
}

// ── Builtins ──────────────────────────────────────────────────────────────────

static int builtin_assert(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc == 0 || is_falsy(args[0])) {
        std::string msg = (argc >= 2 && args[1].is_string()) ? args[1].as_string() : "assertion failed";
        throw std::runtime_error(msg);
    }
    return ctx.ret(Value{});
}

static int builtin_time(CallCtx& ctx) {
    (void)ctx;
    auto now = std::chrono::system_clock::now();
    return ctx.ret(Value(std::chrono::duration<double>(now.time_since_epoch()).count()));
}

// Mémoire tas en cours d'usage (octets) — par plateforme : octets « in use » de
// l'allocateur (WASM/macOS/glibc) ou working set (Windows) ; 0 si indisponible.
uint64_t ollin_heap_bytes() {
    uint64_t bytes = 0;
#if defined(__EMSCRIPTEN__)
    struct mallinfo mi = mallinfo();            // uordblks (arène) + hblkhd (blocs mmap)
    bytes = (uint64_t)(unsigned)mi.uordblks + (uint64_t)(unsigned)mi.hblkhd;
#elif defined(__APPLE__)
    malloc_statistics_t s;
    malloc_zone_statistics(malloc_default_zone(), &s);
    bytes = (uint64_t)s.size_in_use;
#elif defined(__GLIBC__)
    struct mallinfo2 mi = mallinfo2();          // glibc ≥ 2.33 : champs size_t
    bytes = (uint64_t)mi.uordblks + (uint64_t)mi.hblkhd;   // arène + gros blocs mmap
#elif defined(_WIN32)
    PROCESS_MEMORY_COUNTERS pmc;
    if (GetProcessMemoryInfo(GetCurrentProcess(), &pmc, sizeof(pmc)))
        bytes = (uint64_t)pmc.WorkingSetSize;
#endif
    return bytes;
}

// mem() : octets de tas actuellement utilisés par le process (valeurs Ollin +
// runtime + libs). Renvoie un entier.
static int builtin_mem(CallCtx& ctx) {
    (void)ctx;
    return ctx.ret(Value((int64_t)ollin_heap_bytes()));
}

static int64_t range_len(const Range* r) {
    if (r->step == 0.0)
        return 0;
    double diff = (r->step > 0) ? (r->end - r->start) : (r->start - r->end);
    double absstep = (r->step > 0) ? r->step : -r->step;
    if (diff < 0)
        return 0;
    double n = r->incl_right ? std::floor(diff / absstep) + 1.0 : std::ceil(diff / absstep);
    return n <= 0.0 ? 0 : (int64_t)n;
}

static int builtin_len(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc == 0)
        throw std::runtime_error("len() requires 1 argument");
    const Value& v = args[0];
    if (v.is_nil())
        return ctx.ret(Value((int64_t)0));
    if (v.is_array())
        return ctx.ret(Value((int64_t)v.array_size()));
    if (v.is_map() || v.is_class())
        return ctx.ret(Value(v.map_size()));
    if (v.is_string())
        return ctx.ret(Value((int64_t)utf8_count(v.as_string()))); // longueur en caractères (codepoints), pas en octets
    if (v.is_range())
        return ctx.ret(Value(range_len(v.rptr)));
    return ctx.ret(Value((int64_t)1));
}

static const struct {
    const char* name;
    Value::BuiltinFn fn;
} k_builtins[] = {
    {"assert", builtin_assert},
    {"time", builtin_time},
    {"mem", builtin_mem},
    {"len", builtin_len},
};

// resolveFuncVal : func value → func_idx (+ upvals) ; défini plus bas.
static uint8_t resolve_func_val(const Value& fv, std::unique_ptr<std::vector<Upvalue*>>& out_upvals);

// ── Meta-method dispatch helpers ──────────────────────────────────────────────
// Both helpers push a call frame and return fp.addr (non-zero) on success.
// The caller sets ip = addr, then dispatches (NEXT() or continue in switch).

uint32_t VM::try_meta_binary(const Value& name, int dest, Value lhs, Value rhs, bool negate) {
    Value fn = proto_chain_get(lhs.map_get(MK().class_), name);
    if (!fn.is_callable())
        return 0;
    std::unique_ptr<std::vector<Upvalue*>> fuv;
    uint8_t fi = resolve_func_val(fn, fuv); // fn est callable (garde ci-dessus)
    int nb = (int)regs.size();
    grow_regs((size_t)(nb + std::max((int)ch->funcs[fi].reg_count, 2)));
    regs[nb] = std::move(lhs);
    regs[nb + 1] = std::move(rhs);
    uint32_t addr = push_call_frame(nb, fi, 2, std::move(fuv), ip, false, dest);
    if (negate)
        call_stack.back().negate_result = true;
    return addr;
}

uint32_t VM::try_meta_unary(const Value& name, int dest, Value lhs) {
    Value fn = proto_chain_get(lhs.map_get(MK().class_), name);
    if (!fn.is_callable())
        return 0;
    std::unique_ptr<std::vector<Upvalue*>> fuv;
    uint8_t fi = resolve_func_val(fn, fuv); // fn est callable (garde ci-dessus)
    int nb = (int)regs.size();
    grow_regs((size_t)(nb + std::max((int)ch->funcs[fi].reg_count, 1)));
    regs[nb] = std::move(lhs);
    return push_call_frame(nb, fi, 1, std::move(fuv), ip, false, dest);
}

// ── unwindToHandler : déroulé commun throw / erreur runtime C++ ───────────────
void VM::unwind_to_handler(const Handler& h, Value thrown) {
    while (call_stack.size() > h.call_depth) {
        close_upvals();
        call_stack.pop_back();
    }
    if (regs.size() > h.regs_size)
        regs.resize(h.regs_size);
    regs[h.reg_base + h.catch_reg] = std::move(thrown);
    ip = h.catch_addr;
    // NB : le caller restaure `base` (variable locale de la boucle de dispatch).
}

// ── instantiateClass : partagé par CALL_DYN et CALL_METHOD ────────────────────
uint32_t VM::instantiate_class(int base_reg, int arg_off, int argc, Value cls, bool& done) {
    done = false;
    Value inst = Value::make_map();
    inst.map_set(MK().class_, cls);
    Value init_fn = proto_chain_get(cls, MK().init_);
    if (!init_fn.is_callable()) { // pas de constructeur → l'instance EST le résultat
        regs[base_reg] = std::move(inst);
        last_results_ = 1;
        done = true;
        return 0;
    }
    if (init_fn.is_builtin()) {
        std::vector<Value> bargs(argc + 1);
        bargs[0] = inst;
        for (int i = 0; i < argc; ++i)
            bargs[1 + i] = regs[base_reg + arg_off + i];
        invoke_builtin(init_fn.as_builtin(), bargs.data(), argc + 1, argc + 1); // retour ignoré (l'instance prime)
        regs[base_reg] = std::move(inst);
        last_results_ = 1;
        done = true;
        return 0;
    }
    std::unique_ptr<std::vector<Upvalue*>> fuv;
    uint8_t fi = resolve_func_val(init_fn, fuv);
    int total = argc + 1;
    grow_regs((size_t)(base_reg + std::max((int)ch->funcs[fi].reg_count, total)));
    // Décale les args pour insérer self en base_reg : base_reg+arg_off+i → base_reg+1+i.
    // Sens de parcours selon dest vs src pour éviter d'écraser des args non déplacés.
    if (arg_off >= 1)
        for (int i = 0; i < argc; ++i)
            regs[base_reg + 1 + i] = std::move(regs[base_reg + arg_off + i]);
    else
        for (int i = argc - 1; i >= 0; --i)
            regs[base_reg + 1 + i] = std::move(regs[base_reg + arg_off + i]);
    regs[base_reg + 0] = std::move(inst);
    return push_call_frame(base_reg, fi, total, std::move(fuv), ip, /*is_ctor=*/true);
}

// ── closeUpvals : close and free all open upvalues of the top frame ──────────
void VM::close_upvals() {
    auto& ouv = call_stack.back().open_upvals;
    if (!ouv)
        return;
    for (auto* uv : *ouv) {
        if (!uv->closed) {
            uv->val = regs[uv->frame_base + uv->reg_idx];
            uv->closed = true;
        }
        if (--uv->refcount == 0)
            delete uv;
    }
}

// ── Helper: resolve function value → func_idx + upvals ───────────────────────
static uint8_t resolve_func_val(const Value& fv, std::unique_ptr<std::vector<Upvalue*>>& out_upvals) {
    if (fv.is_func_val())
        return (uint8_t)fv.as_int();
    if (fv.is_closure()) {
        const auto& uvs = fv.as_closure()->upvals;
        if (!uvs.empty())
            out_upvals = std::make_unique<std::vector<Upvalue*>>(uvs);
        return fv.as_closure()->func_idx;
    }
    throw std::runtime_error("runtime: call on non-function value");
}

// ── EQ comparison (shared by op_EQ and op_NEQ) ────────────────────────────────
static bool values_equal(const Value& av, const Value& bv) {
    if (av.is_nil() && bv.is_nil())
        return true;
    if (av.is_nil() || bv.is_nil())
        return false;
    if (av.is_integer() && bv.is_integer())
        return av.as_int() == bv.as_int();
    if (av.is_number() && bv.is_number())
        return av.as_num() == bv.as_num();
    if (av.is_string() && bv.is_string())
        return av.sptr == bv.sptr;
    return (av.is_map() && bv.is_map() && av.mptr == bv.mptr) || (av.is_class() && bv.is_class() && av.mptr == bv.mptr);
}

// ── VM::errLine / VM::current / VM::callValue ────────────────────────────────

std::string VM::err_line() const {
    uint32_t idx = ip > 0 ? ip - 1 : 0;
    if (idx >= ch->lines.size())
        return "?";
    auto& loc = ch->lines[idx];
    const std::string& f = (loc.file_idx < ch->source_files.size()) ? ch->source_files[loc.file_idx] : "?";
    return f + ":" + std::to_string(loc.line);
}

VM* VM::current() {
    return s_current_vm;
}

void VM::set_global(const std::string& name, const Value& value) {
    for (int i = 0; i < (int)owned_chunk.identifiers.size(); ++i) {
        if (owned_chunk.identifiers[i] == name) {
            globals[i] = value;
            globals_init[i] = true;
            return;
        }
    }
}

Value VM::get_global(const std::string& name) const {
    if (!ch)
        return Value{};
    for (int i = 0; i < (int)ch->identifiers.size(); ++i)
        if (ch->identifiers[i] == name && globals_init[i])
            return globals[i];
    return Value{};
}

void VM::run_entry_hooks() {
    // `graphics` peut être nil (stub natif, ou script sans référence à graphics) ou
    // réassigné à un non-map → garde isMap() obligatoire avant mapGet.
    Value gfx = get_global("graphics");
    Value draw = get_global("draw");
    bool graphical = draw.is_callable() && gfx.is_map();

    // setup() : appelée une fois après le chargement, avant la boucle update/draw.
    Value setup = get_global("setup");
    if (setup.is_callable())
        call_value(setup);

    // Canvas IMPLICITE : la seule présence d'un draw() suffit à démarrer une session
    // graphique. Si NI le top-level NI setup() n'ont appelé graphics.canvas(), on le
    // crée aux dimensions W×H (globales moteur, pré-initialisées aux dimensions window).
    // Fait APRÈS setup() — car setup() est un endroit courant pour appeler canvas()
    // (cf. tutoriel) : le créer avant provoquerait un double InitWindow (crash WASM).
    if (graphical && !gfx_canvas_created_) {
        Value canvas_fn = gfx.map_get(Value(std::string("canvas")));
        if (canvas_fn.is_builtin()) {
            // Dimensions de la zone de rendu. On NE lit PAS getGlobal("W") : si le
            // script ne référence pas W/H, ces identifiants n'existent pas dans le
            // chunk → getGlobal renvoie nil → 0. On relit le module `window`
            // directement (source des globales W/H, et en WASM = taille mesurée en JS
            // fournie via __ollinRenderW → fiable, pas de course de layout).
            int w = 0, h = 0;
            Value winm = make_builtin_module("window");
            if (winm.is_map()) {
                Value vw = winm.map_get(Value(std::string("width")));
                Value vh = winm.map_get(Value(std::string("height")));
                if (vw.is_number()) w = (int)vw.as_num();
                if (vh.is_number()) h = (int)vh.as_num();
            }
            // Si la taille reste inexploitable, canvas() sans argument → défauts de
            // gfx_canvas (800×600) plutôt qu'un canvas 0×0 sans contexte GL (crash).
            if (w > 0 && h > 0) {
                Value wh[2] = { Value((int64_t)w), Value((int64_t)h) };
                invoke_builtin(canvas_fn.as_builtin(), wh, 2, 2);
            } else {
                Value none[1] = {};
                invoke_builtin(canvas_fn.as_builtin(), none, 0, 1);
            }
        }
    }

    // draw() présent → lance la boucle graphique via graphics.run(draw).
    if (graphical) {
        Value run_fn = gfx.map_get(Value(std::string("run")));
        if (run_fn.is_builtin())
            invoke_builtin(run_fn.as_builtin(), &draw, 1, 1);
    }
}

Value VM::call_value(const Value& fn, const Value* args, int argc) {
    if (fn.is_builtin()) {
        // Buffer local writable : le builtin y écrit son résultat (args de l'appelant
        // peuvent être en lecture seule). Au moins 1 slot pour recevoir la valeur.
        std::vector<Value> buf(std::max(argc, 1));
        for (int i = 0; i < argc; ++i)
            buf[i] = args[i];
        int n = invoke_builtin(fn.as_builtin(), buf.data(), argc, (int)buf.size());
        return n >= 1 ? buf[0] : Value{};
    }
    uint8_t fi;
    std::unique_ptr<std::vector<Upvalue*>> frame_upvals;
    if (fn.is_func_val()) {
        fi = (uint8_t)fn.as_int();
    } else if (fn.is_closure()) {
        fi = fn.as_closure()->func_idx;
        const auto& uvs = fn.as_closure()->upvals;
        if (!uvs.empty())
            frame_upvals = std::make_unique<std::vector<Upvalue*>>(uvs);
    } else {
        throw std::runtime_error("callValue: not callable");
    }
    int call_base = (int)regs.size();
    if (argc > 0) {
        grow_regs((size_t)(call_base + argc));
        for (int i = 0; i < argc; i++)
            regs[call_base + i] = args[i];
    }
    uint32_t saved_ip = ip;
    ip = push_call_frame(call_base, fi, argc, std::move(frame_upvals), saved_ip);
    run_goto(call_stack.size() - 1);
    Value result = (int)regs.size() > call_base ? regs[call_base] : Value{};
    regs.resize(call_base);
    ip = saved_ip;
    return result;
}

int VM::call_value_multi(const Value& fn, const Value* args, int argc, Value* out, int out_cap) {
    if (out_cap <= 0)
        return 0;
    if (fn.is_builtin()) {
        std::vector<Value> buf(std::max(argc, out_cap));
        for (int i = 0; i < argc; ++i)
            buf[i] = args[i];
        int n = invoke_builtin(fn.as_builtin(), buf.data(), argc, (int)buf.size());
        int m = n < out_cap ? n : out_cap;
        for (int i = 0; i < m; ++i)
            out[i] = buf[i];
        return m;
    }
    uint8_t fi;
    std::unique_ptr<std::vector<Upvalue*>> frame_upvals;
    if (fn.is_func_val()) {
        fi = (uint8_t)fn.as_int();
    } else if (fn.is_closure()) {
        fi = fn.as_closure()->func_idx;
        const auto& uvs = fn.as_closure()->upvals;
        if (!uvs.empty())
            frame_upvals = std::make_unique<std::vector<Upvalue*>>(uvs);
    } else {
        throw std::runtime_error("callValue: not callable");
    }
    int call_base = (int)regs.size();
    if (argc > 0) {
        grow_regs((size_t)(call_base + argc));
        for (int i = 0; i < argc; i++)
            regs[call_base + i] = args[i];
    }
    uint32_t saved_ip = ip;
    ip = push_call_frame(call_base, fi, argc, std::move(frame_upvals), saved_ip);
    run_goto(call_stack.size() - 1);
    // Les valeurs de retour de f sont en regs[call_base..], last_results_ en donne le compte.
    int avail = (int)regs.size() - call_base;
    int n = last_results_ < avail ? last_results_ : avail;
    if (n > out_cap)
        n = out_cap;
    for (int i = 0; i < n; ++i)
        out[i] = regs[call_base + i];
    regs.resize(call_base);
    ip = saved_ip;
    return n;
}

Value VM::call_value(const Value& fn) {
    return call_value(fn, nullptr, 0);
}
Value VM::call_value(const Value& fn, const Value& a) {
    return call_value(fn, &a, 1);
}
Value VM::call_value(const Value& fn, const Value& a, const Value& b) {
    Value args[2] = {a, b};
    return call_value(fn, args, 2);
}
Value VM::call_value(const Value& fn, const Value& a, const Value& b, const Value& c, const Value& d) {
    Value args[4] = {a, b, c, d};
    return call_value(fn, args, 4);
}

// ── pushCallFrame ─────────────────────────────────────────────────────────────
// Point d'entrée unique pour toute construction de frame d'appel :
//   1. growRegs au minimum nécessaire
//   2. rempli les défauts pour les args manquants (argc < n_fixed)
//   3. déplace les varargs au-delà de reg_count
//   4. construit et empile le Frame
//   5. retourne fp.addr (le caller fait ip = pushCallFrame(...))
uint32_t VM::push_call_frame(int new_base, uint8_t fi, int argc, std::unique_ptr<std::vector<Upvalue*>> fuv,
                           uint32_t return_ip, bool is_ctor, int return_dest, int result_base) {
    const FuncProto& fp = ch->funcs[fi];
    grow_regs((size_t)(new_base + std::max((int)fp.reg_count, argc)));
    if (argc < fp.n_fixed) {
        auto& defs = ch->func_defaults[fp.defaults_idx];
        for (int i = argc; i < fp.n_fixed; ++i)
            regs[new_base + i] = (i < (int)defs.size()) ? defs[i] : Value{};
    }
    int n_varargs = 0;
    int va_base = new_base + fp.reg_count;
    if (fp.variadic && argc > fp.n_fixed) {
        n_varargs = argc - fp.n_fixed;
        grow_regs((size_t)(va_base + n_varargs));
        for (int i = n_varargs - 1; i >= 0; --i)
            regs[va_base + i] = std::move(regs[new_base + fp.n_fixed + i]);
    }
    Frame fr;
    fr.return_ip = return_ip;
    fr.reg_base = new_base;
    fr.result_base = (result_base >= 0) ? result_base : new_base;
    fr.varargs_base = va_base;
    fr.n_varargs = n_varargs;
    fr.is_ctor = is_ctor;
    fr.return_dest = return_dest;
    fr.upvals = std::move(fuv);
    call_stack.push_back(std::move(fr));
    return fp.addr;
}

// ── runGoto: dispatch loop, stops when call_stack.size() <= stop_depth ────────
void VM::run_goto(size_t stop_depth) {
// ── Computed-goto dispatch (GCC / Clang) ─────────────────────────────────────
// Table in the exact order of enum Op (chunk.h).
// Each handler ends with NEXT() → direct jump to the next handler.
#define NEXT()                                                                                                         \
    do {                                                                                                               \
        Instr _ni = ch->code[ip++];                                                                                    \
        A = i_a(_ni);                                                                                                   \
        B = i_b(_ni);                                                                                                   \
        C = i_c(_ni);                                                                                                   \
        Bx = i_bx(_ni);                                                                                                 \
        goto* dt[i_op(_ni)];                                                                                            \
    } while (0)

    static const void* const dt[] = {
        &&op_LOAD_K,
        &&op_LOAD_NIL,
        &&op_MOVE,
        &&op_LOAD_GLOBAL,
        &&op_STORE_GLOBAL,
        &&op_ADD,
        &&op_SUB,
        &&op_MUL,
        &&op_DIV,
        &&op_MOD,
        &&op_IDIV,
        &&op_POW,
        &&op_NEGATE,
        &&op_NOT,
        &&op_AND,
        &&op_OR,
        &&op_EQ,
        &&op_NEQ,
        &&op_GT,
        &&op_LT,
        &&op_GE,
        &&op_LE,
        &&op_JUMP,
        &&op_JUMP_IF_FALSE,
        &&op_CALL_FUNC,
        &&op_RETURN,
        &&op_LOAD_VARARGS,
        &&op_RETURN_V,
        &&op_TRY,
        &&op_POP_TRY,
        &&op_THROW,
        &&op_NEW_MAP,
        &&op_GET_INDEX,
        &&op_SET_INDEX,
        &&op_MAKE_ITER,
        &&op_BAND,
        &&op_BOR,
        &&op_BXOR,
        &&op_BNOT,
        &&op_BLSHIFT,
        &&op_BRSHIFT,
        &&op_NEW_ARRAY,
        &&op_ARRAY_PUSH,
        &&op_FOR_ITER_NEXT,
        &&op_FOR_ITER_NEXT1,
        &&op_LOAD_FUNC,
        &&op_CALL_DYN,
        &&op_MAKE_CLOSURE,
        &&op_GET_UPVAL,
        &&op_SET_UPVAL,
        &&op_NEW_CLASS,
        &&op_CALL_METHOD,
        &&op_MAKE_RANGE,
        &&op_FOR_PREP,
        &&op_FOR_LOOP,
        &&op_SPREAD_RESULTS,
        &&op_CALL_VA,
        &&op_CALL_VARARGS,
        &&op_ARRAY_PUSH_SPREAD,
        &&op_ARRAY_PUSH_VARARGS,
        &&op_MOVE_RESULTS,
        &&op_RETURN_SPREAD,
        &&op_HALT,
    };

    uint8_t A, B, C;
    uint16_t Bx;
    int base = call_stack.back().reg_base;
    // Inline cache GET_INDEX dimensionné sur le code courant (un slot par instruction).
    // Réentrance (run_goto imbriqué via call_value) : même ch → taille identique → no-op.
    if (gicache_.size() != ch->code.size())
        gicache_.assign(ch->code.size(), GetIndexCache{});
dispatch_loop:
    try {
        NEXT();

    op_LOAD_K:
        regs[base + A] = ch->constants[Bx];
        NEXT();

    op_LOAD_NIL:
        regs[base + A] = Value{};
        last_results_ = 1; // ex. branche nil d'un appel optionnel f?() (multi-retour)
        NEXT();

    op_MOVE:
        regs[base + A] = regs[base + B];
        NEXT();

    op_LOAD_GLOBAL:
        if (!globals_init[Bx])
            throw std::runtime_error(err_line() + ": undefined: " + ch->identifiers[Bx]);
        regs[base + A] = globals[Bx];
        NEXT();

    op_STORE_GLOBAL:
        globals[Bx] = regs[base + A];
        globals_init[Bx] = true;
        NEXT();

    op_ADD: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (bv.is_integer() && cv.is_integer()) { // chemin chaud : entier + entier
            regs[base + A] = Value(bv.as_int() + cv.as_int());
            NEXT();
        }
        if (bv.is_string() || cv.is_string()) {
            {
                // Copier les opérandes AVANT valueToString : si l'un est une instance
                // avec __str, invokeStr réalloue regs → les références bv/cv pendraient.
                // Bloc interne : Value (destructeur non trivial) hors portée avant NEXT().
                Value b2 = bv;
                Value c2 = cv;
                regs[base + A] = Value(value_to_string(b2) + value_to_string(c2));
            }
            NEXT();
        }
        if (is_instance(bv)) {
            if (uint32_t addr = try_meta_binary(MK().add_, base + A, bv, cv)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        regs[base + A] = Value(as_double(bv) + as_double(cv));
        NEXT();
    }

    op_SUB: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (bv.is_integer() && cv.is_integer()) { // chemin chaud : entier - entier
            regs[base + A] = Value(bv.as_int() - cv.as_int());
            NEXT();
        }
        if (is_instance(bv)) {
            if (uint32_t addr = try_meta_binary(MK().sub_, base + A, bv, cv)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        regs[base + A] = Value(as_double(bv) - as_double(cv));
        NEXT();
    }

    op_MUL: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (bv.is_integer() && cv.is_integer()) { // chemin chaud : entier * entier
            regs[base + A] = Value(bv.as_int() * cv.as_int());
            NEXT();
        }
        if (is_instance(bv)) {
            if (uint32_t addr = try_meta_binary(MK().mul_, base + A, bv, cv)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        regs[base + A] = Value(as_double(bv) * as_double(cv));
        NEXT();
    }

    op_DIV: {
        if (is_instance(regs[base + B])) {
            if (uint32_t addr = try_meta_binary(MK().div_, base + A, regs[base + B], regs[base + C])) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        double dv = as_double(regs[base + C]);
        if (dv == 0.0)
            throw std::runtime_error(err_line() + ": runtime: division by zero");
        regs[base + A] = Value(as_double(regs[base + B]) / dv);
        NEXT();
    }

    op_MOD: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (bv.is_integer() && cv.is_integer()) { // chemin chaud : entier % entier
            if (cv.as_int() == 0)
                throw std::runtime_error(err_line() + ": runtime: modulo by zero");
            regs[base + A] = Value(bv.as_int() % cv.as_int());
            NEXT();
        }
        if (is_instance(bv)) {
            if (uint32_t addr = try_meta_binary(MK().mod_, base + A, bv, cv)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        double dv = as_double(cv);
        if (dv == 0.0)
            throw std::runtime_error(err_line() + ": runtime: modulo by zero");
        regs[base + A] = Value(std::fmod(as_double(bv), dv));
        NEXT();
    }

    op_IDIV: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (bv.is_integer() && cv.is_integer()) {
            if (cv.as_int() == 0)
                throw std::runtime_error(err_line() + ": runtime: division by zero");
            int64_t q = bv.as_int() / cv.as_int();
            // floor division: adjust if signs differ and there is a remainder
            if ((bv.as_int() ^ cv.as_int()) < 0 && q * cv.as_int() != bv.as_int())
                q--;
            regs[base + A] = Value(q);
        } else {
            double dv = as_double(cv);
            if (dv == 0.0)
                throw std::runtime_error(err_line() + ": runtime: division by zero");
            regs[base + A] = Value(std::floor(as_double(bv) / dv));
        }
        NEXT();
    }

    op_POW: {
        {
            const Value& bv = regs[base + B]; // lu avant l'écriture de R[A] → réf sûre
            const Value& cv = regs[base + C];
            if (bv.is_integer() && cv.is_integer() && cv.as_int() >= 0) {
                int64_t b = bv.as_int(), e = cv.as_int(), r = 1;
                while (e > 0) {
                    if (e & 1)
                        r *= b;
                    b *= b;
                    e >>= 1;
                }
                regs[base + A] = Value(r);
            } else {
                regs[base + A] = Value(std::pow(as_double(bv), as_double(cv)));
            }
        }
        NEXT();
    }
    op_NEGATE: {
        if (is_instance(regs[base + B])) {
            if (uint32_t addr = try_meta_unary(MK().neg_, base + A, regs[base + B])) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        const Value& bv = regs[base + B];
        regs[base + A] = bv.is_integer() ? Value(-bv.as_int()) : Value(-as_double(bv));
        NEXT();
    }

    op_NOT:
        regs[base + A] = Value((int64_t)(is_falsy(regs[base + B]) ? 1 : 0));
        NEXT();

    op_AND:
        regs[base + A] = Value((int64_t)(!is_falsy(regs[base + B]) && !is_falsy(regs[base + C]) ? 1 : 0));
        NEXT();

    op_OR:
        regs[base + A] = Value((int64_t)(!is_falsy(regs[base + B]) || !is_falsy(regs[base + C]) ? 1 : 0));
        NEXT();

    op_EQ: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (bv.is_integer() && cv.is_integer()) { // chemin chaud : entier == entier
            regs[base + A] = Value((int64_t)(bv.as_int() == cv.as_int() ? 1 : 0));
            NEXT();
        }
        if (is_instance(bv)) {
            if (uint32_t addr = try_meta_binary(MK().eq_, base + A, bv, cv)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        regs[base + A] = Value((int64_t)(values_equal(bv, cv) ? 1 : 0));
        NEXT();
    }

    op_NEQ: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        // a <> b via __eq puis négation (sinon == et <> seraient vrais en même temps).
        if (is_instance(bv)) {
            if (uint32_t addr = try_meta_binary(MK().eq_, base + A, bv, cv, /*negate=*/true)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        regs[base + A] = Value((int64_t)(values_equal(bv, cv) ? 0 : 1));
        NEXT();
    }

    op_GT: {
        // GT(a,b) == LT(b,a): check __lt on rhs
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (bv.is_integer() && cv.is_integer()) { // chemin chaud : entier > entier
            regs[base + A] = Value((int64_t)(bv.as_int() > cv.as_int()));
            NEXT();
        }
        if (is_instance(cv)) { // instance à droite : a > b == b < a → b.__lt(a)
            if (uint32_t addr = try_meta_binary(MK().lt_, base + A, cv, bv)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        } else if (is_instance(bv)) { // instance à gauche : a > b == not(a <= b) → not a.__le(b)
            if (uint32_t addr = try_meta_binary(MK().le_, base + A, bv, cv, /*negate=*/true)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        if (bv.is_string() && cv.is_string()) { // ordre lexicographique
            regs[base + A] = Value((int64_t)(bv.as_string() > cv.as_string()));
            NEXT();
        }
        regs[base + A] = Value((int64_t)(as_double(bv) > as_double(cv)));
        NEXT();
    }

    op_LT: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (bv.is_integer() && cv.is_integer()) { // chemin chaud : entier < entier
            regs[base + A] = Value((int64_t)(bv.as_int() < cv.as_int()));
            NEXT();
        }
        if (is_instance(bv)) { // instance à gauche : a < b → a.__lt(b)
            if (uint32_t addr = try_meta_binary(MK().lt_, base + A, bv, cv)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        } else if (is_instance(cv)) { // instance à droite : a < b == not(b <= a) → not b.__le(a)
            if (uint32_t addr = try_meta_binary(MK().le_, base + A, cv, bv, /*negate=*/true)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        if (bv.is_string() && cv.is_string()) { // ordre lexicographique
            regs[base + A] = Value((int64_t)(bv.as_string() < cv.as_string()));
            NEXT();
        }
        regs[base + A] = Value((int64_t)(as_double(bv) < as_double(cv)));
        NEXT();
    }

    op_GE: {
        // GE(a,b) == LE(b,a): check __le on rhs
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (bv.is_integer() && cv.is_integer()) { // chemin chaud : entier >= entier
            regs[base + A] = Value((int64_t)(bv.as_int() >= cv.as_int()));
            NEXT();
        }
        if (is_instance(cv)) { // instance à droite : a >= b == b <= a → b.__le(a)
            if (uint32_t addr = try_meta_binary(MK().le_, base + A, cv, bv)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        } else if (is_instance(bv)) { // instance à gauche : a >= b == not(a < b) → not a.__lt(b)
            if (uint32_t addr = try_meta_binary(MK().lt_, base + A, bv, cv, /*negate=*/true)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        if (bv.is_string() && cv.is_string()) { // ordre lexicographique
            regs[base + A] = Value((int64_t)(bv.as_string() >= cv.as_string()));
            NEXT();
        }
        regs[base + A] = Value((int64_t)(as_double(bv) >= as_double(cv)));
        NEXT();
    }

    op_LE: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (bv.is_integer() && cv.is_integer()) { // chemin chaud : entier <= entier
            regs[base + A] = Value((int64_t)(bv.as_int() <= cv.as_int()));
            NEXT();
        }
        if (is_instance(bv)) { // instance à gauche : a <= b → a.__le(b)
            if (uint32_t addr = try_meta_binary(MK().le_, base + A, bv, cv)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        } else if (is_instance(cv)) { // instance à droite : a <= b == not(b < a) → not b.__lt(a)
            if (uint32_t addr = try_meta_binary(MK().lt_, base + A, cv, bv, /*negate=*/true)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        if (bv.is_string() && cv.is_string()) { // ordre lexicographique
            regs[base + A] = Value((int64_t)(bv.as_string() <= cv.as_string()));
            NEXT();
        }
        regs[base + A] = Value((int64_t)(as_double(bv) <= as_double(cv)));
        NEXT();
    }

    op_JUMP:
        ip = Bx;
        NEXT();

    op_JUMP_IF_FALSE:
        if (is_falsy(regs[base + A]))
            ip = Bx;
        NEXT();

    op_CALL_FUNC: {
        ip = push_call_frame(base + A, (uint8_t)B, C, nullptr, ip);
        base = call_stack.back().reg_base;
        NEXT();
    }

    op_RETURN: {
        {
            close_upvals();
            bool is_ctor_ = call_stack.back().is_ctor;
            bool neg_ = call_stack.back().negate_result;
            Value ctor_val;
            if (is_ctor_)
                ctor_val = regs[base + 0]; // save self before potential overwrite
            int ret_dest = call_stack.back().return_dest;
            int wb = call_stack.back().result_base;
            int n = B;
            if (n > 0 && (wb != base || A != 0))
                for (int i = 0; i < n; ++i)
                    regs[wb + i] = std::move(regs[base + A + i]);
            uint32_t rip = call_stack.back().return_ip;
            call_stack.pop_back();
            if (is_ctor_)
                regs[wb + 0] = std::move(ctor_val);
            if (ret_dest >= 0)
                regs[ret_dest] = neg_ ? Value((int64_t)(is_falsy(regs[wb + 0]) ? 1 : 0)) : regs[wb + 0];
            ip = rip;
            last_results_ = is_ctor_ ? 1 : n; // pour SPREAD_RESULTS (multi-retour)
        }
        if (call_stack.size() <= stop_depth)
            return;
        base = call_stack.back().reg_base;
        NEXT();
    }

    op_LOAD_VARARGS: {
        {
            const Frame& fr = call_stack.back();
            int n_va = fr.n_varargs;
            int count = B;                       // 0 = tous ; sinon nombre fixe (padding nil)
            int n = (count == 0) ? n_va : count;
            size_t needed = (size_t)(base + A + n);
            if ((int)regs.size() < (int)needed)
                regs.resize(needed);
            int va_src = fr.varargs_base;
            for (int i = 0; i < n; ++i)
                regs[base + A + i] = (i < n_va) ? regs[va_src + i] : Value{};
            last_results_ = n; // compte publié (spread [..., ...] / CALL_VA)
        }
        NEXT();
    }

    op_RETURN_V: {
        {
            close_upvals();
            bool is_ctor_ = call_stack.back().is_ctor;
            bool neg_ = call_stack.back().negate_result;
            Value ctor_val;
            if (is_ctor_)
                ctor_val = regs[base + 0];
            int ret_dest = call_stack.back().return_dest;
            int n_va = call_stack.back().n_varargs;
            int va_src = call_stack.back().varargs_base;
            int n_expl = B;
            int total = n_expl + n_va;
            std::vector<Value> rvs(total);
            for (int i = 0; i < n_expl; ++i)
                rvs[i] = std::move(regs[base + A + i]);
            for (int i = 0; i < n_va; ++i)
                rvs[n_expl + i] = std::move(regs[va_src + i]);
            uint32_t rip = call_stack.back().return_ip;
            int rbase = call_stack.back().result_base;
            call_stack.pop_back();
            if ((int)regs.size() < rbase + total)
                regs.resize(rbase + total);
            for (int i = 0; i < total; ++i)
                regs[rbase + i] = std::move(rvs[i]);
            if (is_ctor_)
                regs[rbase + 0] = std::move(ctor_val);
            if (ret_dest >= 0)
                regs[ret_dest] = neg_ ? Value((int64_t)(is_falsy(regs[rbase + 0]) ? 1 : 0)) : regs[rbase + 0];
            ip = rip;
            last_results_ = is_ctor_ ? 1 : total; // pour SPREAD_RESULTS (multi-retour)
        }
        if (call_stack.size() <= stop_depth)
            return;
        base = call_stack.back().reg_base;
        NEXT();
    }

    op_TRY:
        handler_stack.push_back({Bx, A, base, regs.size(), call_stack.size()});
        NEXT();

    op_POP_TRY:
        handler_stack.pop_back();
        NEXT();

    op_THROW: {
        {
            Value thrown = regs[base + A];
            if (handler_stack.empty())
                throw std::runtime_error(err_line() + ": unhandled exception: " + value_to_string(thrown));
            Handler h = handler_stack.back();
            handler_stack.pop_back();
            unwind_to_handler(h, std::move(thrown));
        }
        base = call_stack.back().reg_base;
        NEXT();
    }

    op_NEW_MAP:
        regs[base + A] = Value::make_map();
        NEXT();

    op_GET_INDEX: {
        const Value& obj = regs[base + B];
        const Value& key = regs[base + C];
        // Capturer AVANT toute écriture de regs[base+A] : le dest peut aliaser le
        // registre de la clé (A==C) ou de l'objet (A==B) → lire obj/key après
        // `regs[A] = found` lirait la valeur écrasée (bug d'aliasing).
        const Map* obj_map = (obj.is_map() || obj.is_class()) ? obj.mptr : nullptr;
        const InternedStr* key_sptr = key.is_string() ? key.sptr : nullptr;
        // Inline cache (clé string) : hit si même map/classe (mptr), non mutée depuis
        // (version) et même clé internée (sptr). Ne cache que les hits sur la data
        // PROPRE de l'objet (cf. remplissage plus bas).
        if (obj_map && key_sptr) {
            GetIndexCache& c = gicache_[ip - 1];
            if (c.map == obj_map && c.version == obj_map->version && c.key == key_sptr) {
                {
                    // Copie AVANT d'écrire le registre : si dest aliase l'objet (A==B)
                    // et détenait la dernière référence à la map, l'écriture la
                    // détruirait — or c.val pointe DANS cette map. Le temporaire
                    // retient d'abord. Bloc fermé avant NEXT() (règle computed-goto).
                    Value hit = *c.val;
                    regs[base + A] = std::move(hit);
                }
                NEXT();
            }
        }
        if (obj.is_map() || obj.is_class()) {
            // Data PROPRE d'abord (T_MAP et T_CLASS partagent le layout Map).
            const Map* own = obj.mptr;
            const Value* slot = own->find_ptr(key);
            if (slot) {
                // Trouvée directement → sa validité ne dépend QUE de (mptr, version) :
                // cacheable même sur une instance (muter l'instance bump sa version,
                // et sa data propre masque toujours la classe). Pas de test
                // is_instance ici — il coûterait un lookup "__class__" par accès.
                if (key_sptr) {
                    GetIndexCache& c = gicache_[ip - 1];
                    c.map = own;
                    c.version = own->version;
                    c.key = key_sptr;
                    c.val = slot;
                }
                Value hit = *slot;   // lire avant d'écrire le registre (cf. hit du cache)
                regs[base + A] = std::move(hit);
            } else {
                // Absente de la data propre : chaîne de prototypes (__class__ /
                // __parent__). NON cachée — une mutation de la CLASSE ne bump pas la
                // version de l'instance. Le `len` intégré n'est qu'un repli tout-froid
                // (rien trouvé nulle part) → le strcmp reste hors du chemin chaud.
                Value chained = proto_chain_rest(obj, key);
                if (chained.is_nil() && key_sptr && key.as_string() == "len" && !is_instance(obj))
                    regs[base + A] = Value::make_builtin(builtin_map_len);
                else
                    regs[base + A] = std::move(chained);
            }
        } else if (obj.is_string()) {
            // Pseudo-méthodes des chaînes : servies par le module `string`, qui ne
            // change jamais → toujours un hit de cache après le premier passage.
            // (Le module vit aussi longtemps que la VM : pas de risque d'aliasing.)
            const Value* meth = module_member(string_module_, key, key_sptr);
            regs[base + A] = meth ? *meth : Value{};
        } else if (obj.is_array()) {
            if (key_sptr) {
                // Pseudo-méthodes : un seul lookup dans la map construite au démarrage
                // (cf. array_module.cpp), comme pour les chaînes — et cachée par site,
                // la map étant immuable. Absente = erreur, pas nil (un tableau n'a pas
                // de champs libres).
                const Value* meth = module_member(array_module_, key, key_sptr);
                if (!meth)
                    throw std::runtime_error(err_line() + ": runtime: array has no field '" + key.as_string() + "'");
                regs[base + A] = *meth;
            } else {
                if (!key.is_integer())
                    throw std::runtime_error(err_line() + ": runtime: array index must be integer");
                regs[base + A] = obj.array_get(key.as_int());
            }
        } else {
            throw std::runtime_error(err_line() + ": cannot index " +
                                     std::string(obj.type_name()) +
                                     (key.is_string() ? " with field '" + key.as_string() + "'" : ""));
        }
        NEXT();
    }

    op_SET_INDEX: {
        Value& obj = regs[base + A];
        const Value& key = regs[base + B];
        if (obj.is_map() || obj.is_class()) {
            obj.map_set(key, regs[base + C]);
        } else if (obj.is_array()) {
            if (!key.is_integer())
                throw std::runtime_error(err_line() + ": runtime: array index must be integer");
            obj.array_set(key.as_int(), regs[base + C]);
        } else {
            throw std::runtime_error(err_line() + ": cannot assign index on " +
                                     std::string(obj.type_name()) +
                                     (key.is_string() ? " with field '" + key.as_string() + "'" : ""));
        }
        NEXT();
    }

    op_MAKE_ITER:
        regs[base + A] = Value::make_iter_from(regs[base + B]);
        NEXT();

    op_BAND: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (!bv.is_integer() || !cv.is_integer())
            throw std::runtime_error(err_line() + ": runtime: & requires integer operands");
        regs[base + A] = Value(bv.as_int() & cv.as_int());
        NEXT();
    }

    op_BOR: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (!bv.is_integer() || !cv.is_integer())
            throw std::runtime_error(err_line() + ": runtime: | requires integer operands");
        regs[base + A] = Value(bv.as_int() | cv.as_int());
        NEXT();
    }

    op_BXOR: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (!bv.is_integer() || !cv.is_integer())
            throw std::runtime_error(err_line() + ": runtime: ^ requires integer operands");
        regs[base + A] = Value(bv.as_int() ^ cv.as_int());
        NEXT();
    }

    op_BNOT: {
        const Value& bv = regs[base + B];
        if (!bv.is_integer())
            throw std::runtime_error(err_line() + ": runtime: ~ requires integer operand");
        regs[base + A] = Value(~bv.as_int());
        NEXT();
    }

    op_BLSHIFT: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (!bv.is_integer() || !cv.is_integer())
            throw std::runtime_error(err_line() + ": runtime: << requires integer operands");
        regs[base + A] = Value((int64_t)((uint64_t)bv.as_int() << (cv.as_int() & 63)));
        NEXT();
    }

    op_BRSHIFT: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (!bv.is_integer() || !cv.is_integer())
            throw std::runtime_error(err_line() + ": runtime: >> requires integer operands");
        regs[base + A] = Value(bv.as_int() >> (cv.as_int() & 63));
        NEXT();
    }

    op_NEW_ARRAY:
        regs[base + A] = Value::make_array();
        NEXT();

    op_ARRAY_PUSH:
        regs[base + A].array_push(regs[base + B]);
        NEXT();

    op_FOR_ITER_NEXT:
        if (!regs[base + A].iptr->next(regs[base + A + 1], regs[base + A + 2]))
            ip = Bx;
        NEXT();

    op_FOR_ITER_NEXT1: {
        {
            Iterator* it = regs[base + A].iptr;
            Value primary;
            // Cas range dévirtualisé : appel direct (inlinable) à advance(), sans
            // indirection vtable par élément. Les autres itérateurs gardent la voie
            // virtuelle. Même logique d'avancement (advance()), pas de duplication.
            bool ok = (it->kind == Iterator::KIND_RANGE) ? static_cast<RangeIterator*>(it)->advance(primary)
                                                         : it->next_primary(primary);
            if (!ok) {
                ip = Bx;
            } else {
                regs[base + A + 1] = std::move(primary);
            }
        }
        NEXT();
    }

    op_LOAD_FUNC:
        regs[base + A] = Value::make_func((uint8_t)Bx);
        NEXT();

    op_CALL_DYN: {
        // A=arg_base, B=func_val_reg, C=argc
        if (regs[base + B].is_builtin()) {
            invoke_builtin_regs(regs[base + B].as_builtin(), base + A, C);
            NEXT();
        }
        if (regs[base + B].is_class()) {
            // Instanciation (args en ctor_base+0.. → arg_off = 0).
            bool done;
            uint32_t addr = instantiate_class(base + A, 0, C, regs[base + B], done);
            if (!done)
                ip = addr;
            goto call_dyn_done;
        }
        {
            // Regular function/closure call
            std::unique_ptr<std::vector<Upvalue*>> fuv;
            uint8_t fi = resolve_func_val(regs[base + B], fuv);
            ip = push_call_frame(base + A, fi, C, std::move(fuv), ip);
        }
    call_dyn_done:
        base = call_stack.back().reg_base;
        NEXT();
    }

    op_CALL_VA: {
        // Comme CALL_DYN mais argc dynamique : C args fixes + last_results_ valeurs
        // du dernier argument étendu (... ou appel multi-valeurs), déjà matérialisées
        // à la suite des fixes. Le callee (B) est SOUS le bloc d'arguments (jamais
        // écrasé par le nombre variable de valeurs).
        int argc_va = C + last_results_;
        if (regs[base + B].is_builtin()) {
            invoke_builtin_regs(regs[base + B].as_builtin(), base + A, argc_va);
            NEXT();
        }
        if (regs[base + B].is_class()) {
            bool done;
            uint32_t addr = instantiate_class(base + A, 0, argc_va, regs[base + B], done);
            if (!done)
                ip = addr;
            goto call_va_done;
        }
        {
            std::unique_ptr<std::vector<Upvalue*>> fuv;
            uint8_t fi = resolve_func_val(regs[base + B], fuv);
            ip = push_call_frame(base + A, fi, argc_va, std::move(fuv), ip);
        }
    call_va_done:
        base = call_stack.back().reg_base;
        NEXT();
    }

    op_CALL_VARARGS: {
        // A=fixed_base, B=func_reg, C=n_fixe ; dernier argument = `...` (varargs du frame
        // courant). Rassemble fixes + varargs dans une zone FRAÎCHE au-dessus des varargs
        // de l'appelant (jamais écrasés → un `...` ultérieur reste correct), appelle, et
        // renvoie les résultats au registre statique fixed_base (result_base du frame appelé).
        {
            Frame& cur = call_stack.back();
            int n_va = cur.n_varargs;
            int va_src = cur.varargs_base;
            int n_fixed = C;
            int total = n_fixed + n_va;
            int fixed_base = base + A;
            Value fn = regs[base + B];
            int fresh = (int)regs.size();
            if (fresh < va_src + n_va)
                fresh = va_src + n_va;
            grow_regs((size_t)(fresh + (total > 0 ? total : 1)));
            for (int i = 0; i < n_fixed; ++i)
                regs[fresh + i] = regs[fixed_base + i];
            for (int i = 0; i < n_va; ++i)
                regs[fresh + n_fixed + i] = regs[va_src + i];
            if (fn.is_builtin()) {
                int k = invoke_builtin(fn.as_builtin(), &regs[fresh], total, (int)regs.size() - fresh);
                for (int i = 0; i < k; ++i)
                    regs[fixed_base + i] = regs[fresh + i]; // fresh > fixed_base → recopie descendante sûre
            } else if (fn.is_class()) {
                for (int i = 0; i < total; ++i) // repli rare : instancie au registre statique
                    regs[fixed_base + i] = regs[fresh + i];
                bool done;
                uint32_t addr = instantiate_class(fixed_base, 0, total, fn, done);
                if (!done)
                    ip = addr;
            } else {
                std::unique_ptr<std::vector<Upvalue*>> fuv;
                uint8_t fi = resolve_func_val(fn, fuv);
                ip = push_call_frame(fresh, fi, total, std::move(fuv), ip, false, -1, fixed_base);
            }
        }
        base = call_stack.back().reg_base;
        NEXT();
    }

    op_ARRAY_PUSH_SPREAD: {
        {
            int n = last_results_;
            for (int i = 0; i < n; ++i)
                regs[base + A].array_push(regs[base + B + i]);
        }
        NEXT();
    }

    op_ARRAY_PUSH_VARARGS: {
        {
            Frame& cur = call_stack.back();
            int n_va = cur.n_varargs;
            int va_src = cur.varargs_base;
            for (int i = 0; i < n_va; ++i)
                regs[base + A].array_push(regs[va_src + i]);
        }
        NEXT();
    }

    op_MOVE_RESULTS: {
        {
            int n = last_results_;
            if (A != B) // A < B (recopie descendante) → boucle avant sûre
                for (int i = 0; i < n; ++i)
                    regs[base + A + i] = std::move(regs[base + B + i]);
        }
        NEXT();
    }

    op_RETURN_SPREAD: {
        // return <explicites>, <appel> : B explicites + last_results_ valeurs de l'appel,
        // toutes contiguës à base+A. Comme RETURN_V mais source contiguë (pas de varargs).
        {
            close_upvals();
            bool is_ctor_ = call_stack.back().is_ctor;
            bool neg_ = call_stack.back().negate_result;
            Value ctor_val;
            if (is_ctor_)
                ctor_val = regs[base + 0];
            int ret_dest = call_stack.back().return_dest;
            int total = B + last_results_;
            int src = base + A;
            std::vector<Value> rvs(total);
            for (int i = 0; i < total; ++i)
                rvs[i] = std::move(regs[src + i]);
            uint32_t rip = call_stack.back().return_ip;
            int rbase = call_stack.back().result_base;
            call_stack.pop_back();
            if ((int)regs.size() < rbase + total)
                regs.resize(rbase + total);
            for (int i = 0; i < total; ++i)
                regs[rbase + i] = std::move(rvs[i]);
            if (is_ctor_)
                regs[rbase + 0] = std::move(ctor_val);
            if (ret_dest >= 0)
                regs[ret_dest] = neg_ ? Value((int64_t)(is_falsy(regs[rbase + 0]) ? 1 : 0)) : regs[rbase + 0];
            ip = rip;
            last_results_ = is_ctor_ ? 1 : total;
        }
        if (call_stack.size() <= stop_depth)
            return;
        base = call_stack.back().reg_base;
        NEXT();
    }

    op_MAKE_CLOSURE: {
        // Bloc interne : le unique_ptr (destructeur non trivial) doit sortir de
        // portée AVANT NEXT() (règle computed-goto).
        {
        uint8_t fi = (uint8_t)Bx;
        // unique_ptr : si la capture lève (bytecode incohérent), le Closure est
        // libéré au lieu de fuir (RAII sur le chemin d'exception).
        auto cl = std::make_unique<Closure>(fi);
        for (auto& desc : ch->funcs[fi].upvals) {
            Upvalue* uv;
            if (desc.is_local) {
                uv = nullptr;
                auto& frame_ouv = call_stack.back().open_upvals;
                if (frame_ouv) {
                    for (auto* ou : *frame_ouv) {
                        if (!ou->closed && ou->frame_base == base && ou->reg_idx == desc.idx) {
                            uv = ou;
                            break;
                        }
                    }
                }
                if (!uv) {
                    uv = new Upvalue;
                    uv->frame_base = base;
                    uv->reg_idx = desc.idx;
                    if (!frame_ouv)
                        frame_ouv = std::make_unique<std::vector<Upvalue*>>();
                    frame_ouv->push_back(uv);
                }
                uv->refcount++;
            } else {
                if (!call_stack.back().upvals)
                    throw std::runtime_error("runtime: closure captures upvalue from non-closure frame");
                uv = (*call_stack.back().upvals)[desc.idx];
                uv->refcount++;
            }
            cl->upvals.push_back(uv);
        }
        regs[base + A] = Value::make_closure(cl.release());
        }
        NEXT();
    }

    op_GET_UPVAL: {
        Upvalue* uv = (*call_stack.back().upvals)[B];
        regs[base + A] = uv->closed ? uv->val : regs[uv->frame_base + uv->reg_idx];
        NEXT();
    }

    op_SET_UPVAL: {
        Upvalue* uv = (*call_stack.back().upvals)[B];
        if (uv->closed)
            uv->val = regs[base + A];
        else
            regs[uv->frame_base + uv->reg_idx] = regs[base + A];
        NEXT();
    }

    op_NEW_CLASS:
        regs[base + A] = Value::make_class();
        NEXT();

    op_CALL_METHOD: {
        uint32_t fp_addr = 0;
        {
            int cb = base + A;
            int argc = C;
            Value fn = regs[cb + 1];
            if (fn.is_class()) {
                bool done;
                uint32_t addr = instantiate_class(cb, 2, argc, fn, done);
                if (!done)
                    ip = addr;
                goto call_method_done;
            }
            bool fn_is_static = false;
            if (fn.is_func_val())
                fn_is_static = ch->funcs[(uint8_t)fn.as_int()].is_static;
            else if (fn.is_closure())
                fn_is_static = ch->funcs[fn.as_closure()->func_idx].is_static;
            else if (fn.is_static_builtin())
                fn_is_static = true;
            Value& recv = regs[cb];
            // Les maps n'injectent pas self (un module comme `math` ne doit pas se
            // recevoir : math.noise(x) → noise(x)). Exception : la pseudo-méthode
            // `len` intégrée des maps, reconnue par pointeur, a besoin de la map.
            bool map_len_call = recv.is_map() && fn.is_builtin() && fn.as_builtin() == builtin_map_len;
            bool recv_is_instance = is_instance(recv) || recv.is_string() || recv.is_array() || map_len_call;
            bool inject_self = recv_is_instance && !fn_is_static;
            int total;
            if (inject_self) {
                for (int i = 0; i < argc; ++i)
                    regs[cb + 1 + i] = std::move(regs[cb + 2 + i]);
                total = argc + 1;
            } else {
                for (int i = 0; i < argc; ++i)
                    regs[cb + i] = std::move(regs[cb + 2 + i]);
                total = argc;
            }
            if (fn.is_builtin()) {
                invoke_builtin_regs(fn.as_builtin(), cb, total);
                goto call_method_done;
            }
            {
                std::unique_ptr<std::vector<Upvalue*>> fuv;
                uint8_t fi;
                if (fn.is_func_val())
                    fi = (uint8_t)fn.as_int();
                else if (fn.is_closure()) {
                    fi = fn.as_closure()->func_idx;
                    const auto& u = fn.as_closure()->upvals;
                    if (!u.empty())
                        fuv = std::make_unique<std::vector<Upvalue*>>(u);
                } else
                    throw std::runtime_error(err_line() + ": runtime: method call on non-function value");
                fp_addr = push_call_frame(cb, fi, total, std::move(fuv), ip);
            }
        }
        ip = fp_addr;
    call_method_done:
        base = call_stack.back().reg_base;
        NEXT();
    }

    op_MAKE_RANGE: {
        {
            bool has_step = (C >> 1) & 1;
            bool incl_right = C & 1;
            std::string line_ = err_line();
            auto toDouble_ = [&](const Value& v) -> double {
                if (v.is_integer())
                    return (double)v.as_int();
                if (v.is_float())
                    return v.as_float();
                throw std::runtime_error(line_ + ": runtime: range bound must be a number");
            };
            double start = toDouble_(regs[base + B]);
            double end = toDouble_(regs[base + B + 1]);
            double step = has_step ? toDouble_(regs[base + B + 2]) : 1.0;
            validate_numeric_range(start, end, step, line_);
            Range* r = new Range{1, start, end, step, incl_right};
            regs[base + A] = Value::make_range(r);
        }
        NEXT();
    }

    op_FOR_PREP: {
        // for numérique : R[A]=i, R[A+1]=limite, R[A+2]=pas (consécutifs, inclus aux 2 bornes).
        // Valide, fige le type. Si la boucle est vide → ip=Bx (sortie). Sinon tombe dans le
        // corps : i n'est PAS pré-décrémenté (évite le wrap à la borne basse).
        bool empty;
        {
            Value& vi = regs[base + A];
            Value& vl = regs[base + A + 1];
            Value& vs = regs[base + A + 2];
            if (!vi.is_number() || !vl.is_number() || !vs.is_number())
                throw std::runtime_error(err_line() + ": runtime: for: bornes numériques attendues");
            if (vi.is_integer() && vl.is_integer() && vs.is_integer()) {
                int64_t i0 = vi.as_int(), lim = vl.as_int(), st = vs.as_int();
                if (st == 0)
                    throw std::runtime_error(err_line() + ": runtime: for: le pas ne peut pas être 0");
                empty = (st > 0) ? (i0 > lim) : (i0 < lim);
                if (!empty) {
                    // Compteur de tours RESTANTS (après la 1re itération), calculé une seule
                    // fois en arithmétique non signée → sûr au débordement, et FOR_LOOP n'a
                    // plus besoin de garde anti-débordement ni de comparer la limite. La
                    // limite (R[A+1]) est remplacée par ce compteur.
                    uint64_t ustep = (st > 0) ? (uint64_t)st : (0ull - (uint64_t)st);
                    uint64_t urange = (st > 0) ? ((uint64_t)lim - (uint64_t)i0) : ((uint64_t)i0 - (uint64_t)lim);
                    regs[base + A + 1] = Value((int64_t)(urange / ustep));
                }
            } else {
                double di = vi.as_num(), dl = vl.as_num(), ds = vs.as_num();
                validate_numeric_range(di, dl, ds, err_line());
                regs[base + A] = Value(di); // normalise tout en double
                regs[base + A + 1] = Value(dl);
                regs[base + A + 2] = Value(ds);
                empty = (ds > 0) ? (di > dl) : (di < dl);
            }
        }
        if (empty)
            ip = Bx; // boucle vide → sortie ; sinon on tombe dans le corps (1re itération)
        NEXT();
    }

    op_FOR_LOOP: {
        bool cont;
        {
            Value& vi = regs[base + A];
            Value& vl = regs[base + A + 1];
            Value& vs = regs[base + A + 2];
            if (vi.is_integer()) { // type figé par FOR_PREP
                // R[A+1] = compteur de tours restants (posé par FOR_PREP). Tant qu'il est
                // non nul : décrémenter, avancer i. Pas de garde anti-débordement : le
                // compteur garantit que i + st reste dans la plage initiale.
                uint64_t cnt = (uint64_t)vl.as_int();
                if (cnt != 0) {
                    vl = Value((int64_t)(cnt - 1));
                    vi = Value(vi.as_int() + vs.as_int());
                    cont = true;
                } else {
                    cont = false;
                }
            } else {
                double ni = vi.as_num() + vs.as_num();
                cont = (vs.as_num() > 0) ? (ni <= vl.as_num()) : (ni >= vl.as_num());
                if (cont)
                    regs[base + A] = Value(ni);
            }
        }
        if (cont)
            ip = Bx; // → corps ; sinon on tombe sur la sortie
        NEXT();
    }

    op_SPREAD_RESULTS:
        // Destructuration multi-retour : l'appel précédent a laissé last_results_
        // valeurs en R[A..]. Met les cibles restantes (A+last_results_ .. A+B-1) à
        // nil, sinon elles liraient des registres périmés.
        for (int i = last_results_; i < B; ++i)
            regs[base + A + i] = Value{};
        NEXT();

    op_HALT:
        close_upvals();
        call_stack.pop_back();
        return;

    } catch (const std::runtime_error& e) {
        if (handler_stack.empty()) {
            // Erreur NON rattrapée : préfixer la ligne source courante si le message
            // n'en porte pas déjà une (les builtins lèvent sans localisation). Les
            // erreurs rattrapées par try/catch gardent leur message brut (ci-dessous).
            std::string msg = e.what();
            // Un message déjà localisé contient ":<chiffres>:" (pattern file:line:)
            auto has_loc = [&](const std::string& m) {
                auto p = m.find(':');
                while (p != std::string::npos && p + 1 < m.size()) {
                    if (std::isdigit((unsigned char)m[p + 1])) {
                        auto q = m.find(':', p + 1);
                        if (q != std::string::npos)
                            return true;
                    }
                    p = m.find(':', p + 1);
                }
                return false;
            };
            if (!has_loc(msg))
                throw std::runtime_error(err_line() + ": " + msg);
            throw;
        }
        Handler h = handler_stack.back();
        handler_stack.pop_back();
        unwind_to_handler(h, Value(std::string(e.what())));
        // base (local) restauré ici — comme op_THROW ; unwindToHandler a posé ip.
        base = call_stack.back().reg_base;
        goto dispatch_loop;
    }

#undef NEXT
}

// ── execute ───────────────────────────────────────────────────────────────────
void VM::execute(Chunk chunk) {
    owned_chunk = std::move(chunk);
    ch = &owned_chunk;
    ip = 0;
    s_current_vm = this;
    globals.assign(owned_chunk.identifiers.size(), Value{});
    globals_init.assign(owned_chunk.identifiers.size(), false);
    for (int gi = 0; gi < (int)owned_chunk.identifiers.size(); ++gi)
        for (auto& b : k_builtins)
            if (owned_chunk.identifiers[gi] == b.name) {
                globals[gi] = Value::make_builtin(b.fn);
                globals_init[gi] = true;
            }
    for (int gi = 0; gi < (int)owned_chunk.identifiers.size(); ++gi)
        for (auto& name : builtin_module_names())
            if (owned_chunk.identifiers[gi] == name) {
                globals[gi] = make_builtin_module(name);
                globals_init[gi] = true;
            }
    string_module_ = make_builtin_module("string");
    array_module_ = make_array_module();
    {
        Value core = make_builtin_module("core");
        for (auto& [k, v] : core.mptr->data) {
            if (!k.is_string())
                continue;
            const std::string& fname = k.as_string();
            for (int gi = 0; gi < (int)owned_chunk.identifiers.size(); ++gi)
                if (owned_chunk.identifiers[gi] == fname) {
                    globals[gi] = v;
                    globals_init[gi] = true;
                }
        }
    }
    for (int gi = 0; gi < (int)owned_chunk.identifiers.size(); ++gi)
        if (owned_chunk.identifiers[gi] == "deltaTime" || owned_chunk.identifiers[gi] == "elapsedTime") {
            globals[gi] = Value(0.0);
            globals_init[gi] = true;
        }
    // W / H : dimensions de la zone de rendu, injectées par le moteur (défaut :
    // window.width/height selon l'environnement). Lues avant le top-level pour
    // que graphics.canvas(W, H) fonctionne directement.
    {
        int64_t win_w = 0, win_h = 0;
        Value win = make_builtin_module("window");
        if (win.is_map()) {
            Value vw = win.map_get(Value(std::string("width")));
            Value vh = win.map_get(Value(std::string("height")));
            if (vw.is_integer())
                win_w = vw.as_int();
            if (vh.is_integer())
                win_h = vh.as_int();
        }
        for (int gi = 0; gi < (int)owned_chunk.identifiers.size(); ++gi) {
            if (owned_chunk.identifiers[gi] == "W") {
                globals[gi] = Value(win_w);
                globals_init[gi] = true;
            } else if (owned_chunk.identifiers[gi] == "H") {
                globals[gi] = Value(win_h);
                globals_init[gi] = true;
            } else if (owned_chunk.identifiers[gi] == "CW") {
                globals[gi] = Value((double)win_w / 2.0);
                globals_init[gi] = true;
            } else if (owned_chunk.identifiers[gi] == "CH") {
                globals[gi] = Value((double)win_h / 2.0);
                globals_init[gi] = true;
            }
        }
    }
    grow_regs(owned_chunk.top_reg_count);
    call_stack.reserve(1000);
    Frame top;
    top.varargs_base = owned_chunk.top_reg_count; // reg_count du frame top-level → result_cap correct pour les builtins
    call_stack.push_back(std::move(top));

    run_goto(0);
}
