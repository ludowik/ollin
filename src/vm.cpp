#include "vm.h"
#include "modules/modules.h"
#include "utf8.h"
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
static void validateNumericRange(double start, double end, double step, int line) {
    if (step == 0.0)
        throw std::runtime_error("line " + std::to_string(line) + ": runtime: le pas ne peut pas être 0");
    if (!std::isfinite(start) || !std::isfinite(end) || !std::isfinite(step))
        throw std::runtime_error("line " + std::to_string(line) +
                                 ": runtime: bornes de range non finies (NaN/infini interdit)");
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

bool VM::isInstance(const Value& v) {
    return (v.isMap() || v.isClass()) && !v.mapGet(MK().class_).isNil();
}

// ── protoChainGet ─────────────────────────────────────────────────────────────
Value VM::protoChainGet(const Value& obj, const Value& key) {
    if (obj.isMap() || obj.isClass()) {
        Value v = obj.mapGet(key);
        if (!v.isNil())
            return v;
        if (obj.isMap()) {
            Value cls = obj.mapGet(MK().class_);
            if (!cls.isNil())
                return protoChainGet(cls, key);
        } else {
            Value par = obj.mapGet(MK().parent_);
            if (!par.isNil())
                return protoChainGet(par, key);
        }
    }
    return Value{};
}

// ── growRegs : croît par doublement, max 4096, size reste exacte ─────────────
void VM::growRegs(size_t needed) {
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

// ── invokeStr : mini-loop to call __str without recursion ─────────────────────
std::string VM::invokeStr(Value obj) { // by value: regs.resize() ne invalide pas obj
    Value cls = obj.mapGet(MK().class_);
    if (cls.isNil())
        return "{map}";
    Value str_fn = protoChainGet(cls, MK().str_);
    if (str_fn.isNil() || !str_fn.isCallable()) {
        Value nm = cls.mapGet(MK().name_);
        return nm.isString() ? "{" + nm.asString() + "}" : "{object}";
    }
    uint8_t fi;
    std::unique_ptr<std::vector<Upvalue*>> frame_upvals;
    switch (str_fn.tag) {
    case Value::T_FUNCTION:
        fi = (uint8_t)str_fn.asInt();
        break;
    case Value::T_CLOSURE: {
        fi = str_fn.asClosure()->func_idx;
        const auto& uvs = str_fn.asClosure()->upvals;
        if (!uvs.empty())
            frame_upvals = std::make_unique<std::vector<Upvalue*>>(uvs);
        break;
    }
    case Value::T_BUILTIN: {
        Value self = obj;
        Value result = str_fn.asBuiltin()(&self, 1);
        return result.isString() ? result.asString() : "{object}";
    }
    default: {
        Value nm = cls.mapGet(MK().name_);
        return nm.isString() ? "{" + nm.asString() + "}" : "{object}";
    }
    }
    int call_base = (int)regs.size();
    growRegs((size_t)(call_base + std::max((int)ch->funcs[fi].reg_count, 1)));
    regs[call_base] = obj; // self en R[0] avant pushCallFrame
    uint32_t saved_ip = ip;
    ip = pushCallFrame(call_base, fi, 1, std::move(frame_upvals), 0);
    runGoto(call_stack.size() - 1);
    std::string result;
    if ((int)regs.size() > call_base) {
        const Value& rv = regs[call_base];
        if (rv.isString()) {
            result = rv.asString();
        } else {
            std::ostringstream os;
            if (rv.isNil())
                os << "nil";
            else if (rv.isInteger())
                os << rv.asInt();
            else if (rv.isFloat()) {
                double d = rv.asFloat();
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
std::string valueToString(const Value& v) {
    if (v.isNil())
        return "nil";
    if (v.isString())
        return v.asString();
    if (v.isClass())
        return "{class}";
    if (v.isMap()) {
        VM* vm = VM::current();
        if (vm) {
            Value cls = v.mapGet(MK().class_);
            if (!cls.isNil())
                return vm->invokeStr(v);
        }
        return "{map}";
    }
    if (v.isArray())
        return "{array}";
    if (v.isIterator())
        return "{iterator}";
    if (v.isRange())
        return "{range}";
    if (v.isFuncVal() || v.isClosure() || v.isBuiltin())
        return "{function}";
    if (v.isInteger())
        return std::to_string(v.asInt());
    std::ostringstream os;
    double d = v.asFloat();
    if (d == (long long)d && d >= -1e15 && d <= 1e15)
        os << (long long)d;
    else
        os << d;
    return os.str();
}

// ── Builtins ──────────────────────────────────────────────────────────────────

static Value builtin_assert(Value* args, int argc) {
    if (argc == 0 || isFalsy(args[0])) {
        std::string msg = (argc >= 2 && args[1].isString()) ? args[1].asString() : "assertion failed";
        throw std::runtime_error(msg);
    }
    return Value{};
}

static Value builtin_time(Value* args, int argc) {
    (void)args;
    (void)argc;
    auto now = std::chrono::system_clock::now();
    return Value(std::chrono::duration<double>(now.time_since_epoch()).count());
}

// Mémoire tas en cours d'usage (octets) — par plateforme : octets « in use » de
// l'allocateur (WASM/macOS/glibc) ou working set (Windows) ; 0 si indisponible.
uint64_t ollinHeapBytes() {
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
static Value builtin_mem(Value* args, int argc) {
    (void)args;
    (void)argc;
    return Value((int64_t)ollinHeapBytes());
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

static Value builtin_len(Value* args, int argc) {
    if (argc == 0)
        throw std::runtime_error("len() requires 1 argument");
    const Value& v = args[0];
    if (v.isNil())
        return Value((int64_t)0);
    if (v.isArray())
        return Value((int64_t)v.arraySize());
    if (v.isMap() || v.isClass())
        return Value(v.mapSize());
    if (v.isString())
        return Value((int64_t)utf8Count(v.asString())); // longueur en caractères (codepoints), pas en octets
    if (v.isRange())
        return Value(range_len(v.rptr));
    return Value((int64_t)1);
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
static uint8_t resolveFuncVal(const Value& fv, std::unique_ptr<std::vector<Upvalue*>>& out_upvals);

// ── Meta-method dispatch helpers ──────────────────────────────────────────────
// Both helpers push a call frame and return fp.addr (non-zero) on success.
// The caller sets ip = addr, then dispatches (NEXT() or continue in switch).

uint32_t VM::tryMetaBinary(const Value& name, int dest, Value lhs, Value rhs, bool negate) {
    Value fn = protoChainGet(lhs.mapGet(MK().class_), name);
    if (!fn.isCallable())
        return 0;
    std::unique_ptr<std::vector<Upvalue*>> fuv;
    uint8_t fi = resolveFuncVal(fn, fuv); // fn est callable (garde ci-dessus)
    int nb = (int)regs.size();
    growRegs((size_t)(nb + std::max((int)ch->funcs[fi].reg_count, 2)));
    regs[nb] = std::move(lhs);
    regs[nb + 1] = std::move(rhs);
    uint32_t addr = pushCallFrame(nb, fi, 2, std::move(fuv), ip, false, dest);
    if (negate)
        call_stack.back().negate_result = true;
    return addr;
}

uint32_t VM::tryMetaUnary(const Value& name, int dest, Value lhs) {
    Value fn = protoChainGet(lhs.mapGet(MK().class_), name);
    if (!fn.isCallable())
        return 0;
    std::unique_ptr<std::vector<Upvalue*>> fuv;
    uint8_t fi = resolveFuncVal(fn, fuv); // fn est callable (garde ci-dessus)
    int nb = (int)regs.size();
    growRegs((size_t)(nb + std::max((int)ch->funcs[fi].reg_count, 1)));
    regs[nb] = std::move(lhs);
    return pushCallFrame(nb, fi, 1, std::move(fuv), ip, false, dest);
}

// ── unwindToHandler : déroulé commun throw / erreur runtime C++ ───────────────
void VM::unwindToHandler(const Handler& h, Value thrown) {
    while (call_stack.size() > h.call_depth) {
        closeUpvals();
        call_stack.pop_back();
    }
    if (regs.size() > h.regs_size)
        regs.resize(h.regs_size);
    regs[h.reg_base + h.catch_reg] = std::move(thrown);
    ip = h.catch_addr;
    // NB : le caller restaure `base` (variable locale de la boucle de dispatch).
}

// ── instantiateClass : partagé par CALL_DYN et CALL_METHOD ────────────────────
uint32_t VM::instantiateClass(int base_reg, int arg_off, int argc, Value cls, bool& done) {
    done = false;
    Value inst = Value::makeMap();
    inst.mapSet(MK().class_, cls);
    Value init_fn = protoChainGet(cls, MK().init_);
    if (!init_fn.isCallable()) { // pas de constructeur → l'instance EST le résultat
        regs[base_reg] = std::move(inst);
        last_results_ = 1;
        done = true;
        return 0;
    }
    if (init_fn.isBuiltin()) {
        std::vector<Value> bargs(argc + 1);
        bargs[0] = inst;
        for (int i = 0; i < argc; ++i)
            bargs[1 + i] = regs[base_reg + arg_off + i];
        init_fn.asBuiltin()(bargs.data(), argc + 1);
        regs[base_reg] = std::move(inst);
        last_results_ = 1;
        done = true;
        return 0;
    }
    std::unique_ptr<std::vector<Upvalue*>> fuv;
    uint8_t fi = resolveFuncVal(init_fn, fuv);
    int total = argc + 1;
    growRegs((size_t)(base_reg + std::max((int)ch->funcs[fi].reg_count, total)));
    // Décale les args pour insérer self en base_reg : base_reg+arg_off+i → base_reg+1+i.
    // Sens de parcours selon dest vs src pour éviter d'écraser des args non déplacés.
    if (arg_off >= 1)
        for (int i = 0; i < argc; ++i)
            regs[base_reg + 1 + i] = std::move(regs[base_reg + arg_off + i]);
    else
        for (int i = argc - 1; i >= 0; --i)
            regs[base_reg + 1 + i] = std::move(regs[base_reg + arg_off + i]);
    regs[base_reg + 0] = std::move(inst);
    return pushCallFrame(base_reg, fi, total, std::move(fuv), ip, /*is_ctor=*/true);
}

// ── closeUpvals : close and free all open upvalues of the top frame ──────────
void VM::closeUpvals() {
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
static uint8_t resolveFuncVal(const Value& fv, std::unique_ptr<std::vector<Upvalue*>>& out_upvals) {
    if (fv.isFuncVal())
        return (uint8_t)fv.asInt();
    if (fv.isClosure()) {
        const auto& uvs = fv.asClosure()->upvals;
        if (!uvs.empty())
            out_upvals = std::make_unique<std::vector<Upvalue*>>(uvs);
        return fv.asClosure()->func_idx;
    }
    throw std::runtime_error("runtime: call on non-function value");
}

// ── EQ comparison (shared by op_EQ and op_NEQ) ────────────────────────────────
static bool valuesEqual(const Value& av, const Value& bv) {
    if (av.isNil() && bv.isNil())
        return true;
    if (av.isNil() || bv.isNil())
        return false;
    if (av.isInteger() && bv.isInteger())
        return av.asInt() == bv.asInt();
    if (av.isNumber() && bv.isNumber())
        return av.asNum() == bv.asNum();
    if (av.isString() && bv.isString())
        return av.sptr == bv.sptr;
    return (av.isMap() && bv.isMap() && av.mptr == bv.mptr) || (av.isClass() && bv.isClass() && av.mptr == bv.mptr);
}

// ── VM::errLine / VM::current / VM::callValue ────────────────────────────────

int VM::errLine() const {
    uint32_t idx = ip > 0 ? ip - 1 : 0;
    return (idx < (uint32_t)ch->lines.size()) ? ch->lines[idx] : 0;
}

VM* VM::current() {
    return s_current_vm;
}

void VM::setGlobal(const std::string& name, const Value& value) {
    for (int i = 0; i < (int)owned_chunk.identifiers.size(); ++i) {
        if (owned_chunk.identifiers[i] == name) {
            globals[i] = value;
            globals_init[i] = true;
            return;
        }
    }
}

Value VM::getGlobal(const std::string& name) const {
    if (!ch)
        return Value{};
    for (int i = 0; i < (int)ch->identifiers.size(); ++i)
        if (ch->identifiers[i] == name && globals_init[i])
            return globals[i];
    return Value{};
}

void VM::runEntryHooks() {
    // setup() : appelée une fois après le chargement, avant la boucle update/draw.
    Value setup = getGlobal("setup");
    if (setup.isCallable())
        callValue(setup);
    // draw() présent → lance la boucle graphique via graphics.run(draw).
    Value draw = getGlobal("draw");
    if (draw.isCallable()) {
        // `graphics` peut être nil (stub natif, ou script sans référence à graphics)
        // ou réassigné à un non-map → garde isMap() obligatoire avant mapGet.
        Value gfx = getGlobal("graphics");
        if (gfx.isMap()) {
            Value run_fn = gfx.mapGet(Value(std::string("run")));
            if (run_fn.isBuiltin())
                run_fn.asBuiltin()(&draw, 1);
        }
    }
}

Value VM::callValue(const Value& fn) {
    if (fn.isBuiltin())
        return fn.asBuiltin()(nullptr, 0);
    uint8_t fi;
    std::unique_ptr<std::vector<Upvalue*>> frame_upvals;
    if (fn.isFuncVal()) {
        fi = (uint8_t)fn.asInt();
    } else if (fn.isClosure()) {
        fi = fn.asClosure()->func_idx;
        const auto& uvs = fn.asClosure()->upvals;
        if (!uvs.empty())
            frame_upvals = std::make_unique<std::vector<Upvalue*>>(uvs);
    } else {
        throw std::runtime_error("callValue: not callable");
    }
    int call_base = (int)regs.size();
    uint32_t saved_ip = ip;
    ip = pushCallFrame(call_base, fi, 0, std::move(frame_upvals), saved_ip);
    runGoto(call_stack.size() - 1);
    Value result = (int)regs.size() > call_base ? regs[call_base] : Value{};
    regs.resize(call_base);
    ip = saved_ip;
    return result;
}

Value VM::callValue(const Value& fn, const Value& arg) {
    if (fn.isBuiltin()) {
        Value a = arg;
        return fn.asBuiltin()(&a, 1);
    }
    uint8_t fi;
    std::unique_ptr<std::vector<Upvalue*>> frame_upvals;
    if (fn.isFuncVal()) {
        fi = (uint8_t)fn.asInt();
    } else if (fn.isClosure()) {
        fi = fn.asClosure()->func_idx;
        const auto& uvs = fn.asClosure()->upvals;
        if (!uvs.empty())
            frame_upvals = std::make_unique<std::vector<Upvalue*>>(uvs);
    } else {
        throw std::runtime_error("callValue: not callable");
    }
    int call_base = (int)regs.size();
    growRegs((size_t)(call_base + 1));
    regs[call_base] = arg; // R[0] du nouveau frame = argument
    uint32_t saved_ip = ip;
    ip = pushCallFrame(call_base, fi, 1, std::move(frame_upvals), saved_ip);
    runGoto(call_stack.size() - 1);
    Value result = (int)regs.size() > call_base ? regs[call_base] : Value{};
    regs.resize(call_base);
    ip = saved_ip;
    return result;
}

Value VM::callValue(const Value& fn, const Value& a, const Value& b) {
    if (fn.isBuiltin()) {
        Value args[2] = {a, b};
        return fn.asBuiltin()(args, 2);
    }
    uint8_t fi;
    std::unique_ptr<std::vector<Upvalue*>> frame_upvals;
    if (fn.isFuncVal()) {
        fi = (uint8_t)fn.asInt();
    } else if (fn.isClosure()) {
        fi = fn.asClosure()->func_idx;
        const auto& uvs = fn.asClosure()->upvals;
        if (!uvs.empty())
            frame_upvals = std::make_unique<std::vector<Upvalue*>>(uvs);
    } else {
        throw std::runtime_error("callValue: not callable");
    }
    int call_base = (int)regs.size();
    growRegs((size_t)(call_base + 2));
    regs[call_base] = a;     // R[0] = 1er argument
    regs[call_base + 1] = b; // R[1] = 2e argument
    uint32_t saved_ip = ip;
    ip = pushCallFrame(call_base, fi, 2, std::move(frame_upvals), saved_ip);
    runGoto(call_stack.size() - 1);
    Value result = (int)regs.size() > call_base ? regs[call_base] : Value{};
    regs.resize(call_base);
    ip = saved_ip;
    return result;
}

// ── pushCallFrame ─────────────────────────────────────────────────────────────
// Point d'entrée unique pour toute construction de frame d'appel :
//   1. growRegs au minimum nécessaire
//   2. rempli les défauts pour les args manquants (argc < n_fixed)
//   3. déplace les varargs au-delà de reg_count
//   4. construit et empile le Frame
//   5. retourne fp.addr (le caller fait ip = pushCallFrame(...))
uint32_t VM::pushCallFrame(int new_base, uint8_t fi, int argc, std::unique_ptr<std::vector<Upvalue*>> fuv,
                           uint32_t return_ip, bool is_ctor, int return_dest) {
    const FuncProto& fp = ch->funcs[fi];
    growRegs((size_t)(new_base + std::max((int)fp.reg_count, argc)));
    if (argc < fp.n_fixed) {
        auto& defs = ch->func_defaults[fp.defaults_idx];
        for (int i = argc; i < fp.n_fixed; ++i)
            regs[new_base + i] = (i < (int)defs.size()) ? defs[i] : Value{};
    }
    int n_varargs = 0;
    int va_base = new_base + fp.reg_count;
    if (fp.variadic && argc > fp.n_fixed) {
        n_varargs = argc - fp.n_fixed;
        growRegs((size_t)(va_base + n_varargs));
        for (int i = n_varargs - 1; i >= 0; --i)
            regs[va_base + i] = std::move(regs[new_base + fp.n_fixed + i]);
    }
    Frame fr;
    fr.return_ip = return_ip;
    fr.reg_base = new_base;
    fr.varargs_base = va_base;
    fr.n_varargs = n_varargs;
    fr.is_ctor = is_ctor;
    fr.return_dest = return_dest;
    fr.upvals = std::move(fuv);
    call_stack.push_back(std::move(fr));
    return fp.addr;
}

// ── runGoto: dispatch loop, stops when call_stack.size() <= stop_depth ────────
void VM::runGoto(size_t stop_depth) {
// ── Computed-goto dispatch (GCC / Clang) ─────────────────────────────────────
// Table in the exact order of enum Op (chunk.h).
// Each handler ends with NEXT() → direct jump to the next handler.
#define NEXT()                                                                                                         \
    do {                                                                                                               \
        Instr _ni = ch->code[ip++];                                                                                    \
        A = iA(_ni);                                                                                                   \
        B = iB(_ni);                                                                                                   \
        C = iC(_ni);                                                                                                   \
        Bx = iBx(_ni);                                                                                                 \
        goto* dt[iOP(_ni)];                                                                                            \
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
        &&op_HALT,
    };

    uint8_t A, B, C;
    uint16_t Bx;
    int base = call_stack.back().reg_base;
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
            throw std::runtime_error("line " + std::to_string(errLine()) + ": undefined: " + ch->identifiers[Bx]);
        regs[base + A] = globals[Bx];
        NEXT();

    op_STORE_GLOBAL:
        globals[Bx] = regs[base + A];
        globals_init[Bx] = true;
        NEXT();

    op_ADD: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (bv.isInteger() && cv.isInteger()) { // chemin chaud : entier + entier
            regs[base + A] = Value(bv.asInt() + cv.asInt());
            NEXT();
        }
        if (bv.isString() || cv.isString()) {
            {
                // Copier les opérandes AVANT valueToString : si l'un est une instance
                // avec __str, invokeStr réalloue regs → les références bv/cv pendraient.
                // Bloc interne : Value (destructeur non trivial) hors portée avant NEXT().
                Value b2 = bv;
                Value c2 = cv;
                regs[base + A] = Value(valueToString(b2) + valueToString(c2));
            }
            NEXT();
        }
        if (isInstance(bv)) {
            if (uint32_t addr = tryMetaBinary(MK().add_, base + A, bv, cv)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        regs[base + A] = Value(asDouble(bv) + asDouble(cv));
        NEXT();
    }

    op_SUB: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (bv.isInteger() && cv.isInteger()) { // chemin chaud : entier - entier
            regs[base + A] = Value(bv.asInt() - cv.asInt());
            NEXT();
        }
        if (isInstance(bv)) {
            if (uint32_t addr = tryMetaBinary(MK().sub_, base + A, bv, cv)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        regs[base + A] = Value(asDouble(bv) - asDouble(cv));
        NEXT();
    }

    op_MUL: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (bv.isInteger() && cv.isInteger()) { // chemin chaud : entier * entier
            regs[base + A] = Value(bv.asInt() * cv.asInt());
            NEXT();
        }
        if (isInstance(bv)) {
            if (uint32_t addr = tryMetaBinary(MK().mul_, base + A, bv, cv)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        regs[base + A] = Value(asDouble(bv) * asDouble(cv));
        NEXT();
    }

    op_DIV: {
        if (isInstance(regs[base + B])) {
            if (uint32_t addr = tryMetaBinary(MK().div_, base + A, regs[base + B], regs[base + C])) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        double dv = asDouble(regs[base + C]);
        if (dv == 0.0)
            throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: division by zero");
        regs[base + A] = Value(asDouble(regs[base + B]) / dv);
        NEXT();
    }

    op_MOD: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (bv.isInteger() && cv.isInteger()) { // chemin chaud : entier % entier
            if (cv.asInt() == 0)
                throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: modulo by zero");
            regs[base + A] = Value(bv.asInt() % cv.asInt());
            NEXT();
        }
        if (isInstance(bv)) {
            if (uint32_t addr = tryMetaBinary(MK().mod_, base + A, bv, cv)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        double dv = asDouble(cv);
        if (dv == 0.0)
            throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: modulo by zero");
        regs[base + A] = Value(std::fmod(asDouble(bv), dv));
        NEXT();
    }

    op_IDIV: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (bv.isInteger() && cv.isInteger()) {
            if (cv.asInt() == 0)
                throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: division by zero");
            int64_t q = bv.asInt() / cv.asInt();
            // floor division: adjust if signs differ and there is a remainder
            if ((bv.asInt() ^ cv.asInt()) < 0 && q * cv.asInt() != bv.asInt())
                q--;
            regs[base + A] = Value(q);
        } else {
            double dv = asDouble(cv);
            if (dv == 0.0)
                throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: division by zero");
            regs[base + A] = Value(std::floor(asDouble(bv) / dv));
        }
        NEXT();
    }

    op_POW: {
        {
            const Value& bv = regs[base + B]; // lu avant l'écriture de R[A] → réf sûre
            const Value& cv = regs[base + C];
            if (bv.isInteger() && cv.isInteger() && cv.asInt() >= 0) {
                int64_t b = bv.asInt(), e = cv.asInt(), r = 1;
                while (e > 0) {
                    if (e & 1)
                        r *= b;
                    b *= b;
                    e >>= 1;
                }
                regs[base + A] = Value(r);
            } else {
                regs[base + A] = Value(std::pow(asDouble(bv), asDouble(cv)));
            }
        }
        NEXT();
    }
    op_NEGATE: {
        if (isInstance(regs[base + B])) {
            if (uint32_t addr = tryMetaUnary(MK().neg_, base + A, regs[base + B])) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        const Value& bv = regs[base + B];
        regs[base + A] = bv.isInteger() ? Value(-bv.asInt()) : Value(-asDouble(bv));
        NEXT();
    }

    op_NOT:
        regs[base + A] = Value((int64_t)(isFalsy(regs[base + B]) ? 1 : 0));
        NEXT();

    op_AND:
        regs[base + A] = Value((int64_t)(!isFalsy(regs[base + B]) && !isFalsy(regs[base + C]) ? 1 : 0));
        NEXT();

    op_OR:
        regs[base + A] = Value((int64_t)(!isFalsy(regs[base + B]) || !isFalsy(regs[base + C]) ? 1 : 0));
        NEXT();

    op_EQ: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (bv.isInteger() && cv.isInteger()) { // chemin chaud : entier == entier
            regs[base + A] = Value((int64_t)(bv.asInt() == cv.asInt() ? 1 : 0));
            NEXT();
        }
        if (isInstance(bv)) {
            if (uint32_t addr = tryMetaBinary(MK().eq_, base + A, bv, cv)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        regs[base + A] = Value((int64_t)(valuesEqual(bv, cv) ? 1 : 0));
        NEXT();
    }

    op_NEQ: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        // a <> b via __eq puis négation (sinon == et <> seraient vrais en même temps).
        if (isInstance(bv)) {
            if (uint32_t addr = tryMetaBinary(MK().eq_, base + A, bv, cv, /*negate=*/true)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        regs[base + A] = Value((int64_t)(valuesEqual(bv, cv) ? 0 : 1));
        NEXT();
    }

    op_GT: {
        // GT(a,b) == LT(b,a): check __lt on rhs
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (bv.isInteger() && cv.isInteger()) { // chemin chaud : entier > entier
            regs[base + A] = Value((int64_t)(bv.asInt() > cv.asInt()));
            NEXT();
        }
        if (isInstance(cv)) { // instance à droite : a > b == b < a → b.__lt(a)
            if (uint32_t addr = tryMetaBinary(MK().lt_, base + A, cv, bv)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        } else if (isInstance(bv)) { // instance à gauche : a > b == not(a <= b) → not a.__le(b)
            if (uint32_t addr = tryMetaBinary(MK().le_, base + A, bv, cv, /*negate=*/true)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        if (bv.isString() && cv.isString()) { // ordre lexicographique
            regs[base + A] = Value((int64_t)(bv.asString() > cv.asString()));
            NEXT();
        }
        regs[base + A] = Value((int64_t)(asDouble(bv) > asDouble(cv)));
        NEXT();
    }

    op_LT: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (bv.isInteger() && cv.isInteger()) { // chemin chaud : entier < entier
            regs[base + A] = Value((int64_t)(bv.asInt() < cv.asInt()));
            NEXT();
        }
        if (isInstance(bv)) { // instance à gauche : a < b → a.__lt(b)
            if (uint32_t addr = tryMetaBinary(MK().lt_, base + A, bv, cv)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        } else if (isInstance(cv)) { // instance à droite : a < b == not(b <= a) → not b.__le(a)
            if (uint32_t addr = tryMetaBinary(MK().le_, base + A, cv, bv, /*negate=*/true)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        if (bv.isString() && cv.isString()) { // ordre lexicographique
            regs[base + A] = Value((int64_t)(bv.asString() < cv.asString()));
            NEXT();
        }
        regs[base + A] = Value((int64_t)(asDouble(bv) < asDouble(cv)));
        NEXT();
    }

    op_GE: {
        // GE(a,b) == LE(b,a): check __le on rhs
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (bv.isInteger() && cv.isInteger()) { // chemin chaud : entier >= entier
            regs[base + A] = Value((int64_t)(bv.asInt() >= cv.asInt()));
            NEXT();
        }
        if (isInstance(cv)) { // instance à droite : a >= b == b <= a → b.__le(a)
            if (uint32_t addr = tryMetaBinary(MK().le_, base + A, cv, bv)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        } else if (isInstance(bv)) { // instance à gauche : a >= b == not(a < b) → not a.__lt(b)
            if (uint32_t addr = tryMetaBinary(MK().lt_, base + A, bv, cv, /*negate=*/true)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        if (bv.isString() && cv.isString()) { // ordre lexicographique
            regs[base + A] = Value((int64_t)(bv.asString() >= cv.asString()));
            NEXT();
        }
        regs[base + A] = Value((int64_t)(asDouble(bv) >= asDouble(cv)));
        NEXT();
    }

    op_LE: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (bv.isInteger() && cv.isInteger()) { // chemin chaud : entier <= entier
            regs[base + A] = Value((int64_t)(bv.asInt() <= cv.asInt()));
            NEXT();
        }
        if (isInstance(bv)) { // instance à gauche : a <= b → a.__le(b)
            if (uint32_t addr = tryMetaBinary(MK().le_, base + A, bv, cv)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        } else if (isInstance(cv)) { // instance à droite : a <= b == not(b < a) → not b.__lt(a)
            if (uint32_t addr = tryMetaBinary(MK().lt_, base + A, cv, bv, /*negate=*/true)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        if (bv.isString() && cv.isString()) { // ordre lexicographique
            regs[base + A] = Value((int64_t)(bv.asString() <= cv.asString()));
            NEXT();
        }
        regs[base + A] = Value((int64_t)(asDouble(bv) <= asDouble(cv)));
        NEXT();
    }

    op_JUMP:
        ip = Bx;
        NEXT();

    op_JUMP_IF_FALSE:
        if (isFalsy(regs[base + A]))
            ip = Bx;
        NEXT();

    op_CALL_FUNC: {
        ip = pushCallFrame(base + A, (uint8_t)B, C, nullptr, ip);
        base = call_stack.back().reg_base;
        NEXT();
    }

    op_RETURN: {
        {
            closeUpvals();
            bool is_ctor_ = call_stack.back().is_ctor;
            bool neg_ = call_stack.back().negate_result;
            Value ctor_val;
            if (is_ctor_)
                ctor_val = regs[base + 0]; // save self before potential overwrite
            int ret_dest = call_stack.back().return_dest;
            int n = B;
            if (n > 0 && A != 0)
                for (int i = 0; i < n; ++i)
                    regs[base + i] = std::move(regs[base + A + i]);
            uint32_t rip = call_stack.back().return_ip;
            call_stack.pop_back();
            if (is_ctor_)
                regs[base + 0] = std::move(ctor_val);
            if (ret_dest >= 0)
                regs[ret_dest] = neg_ ? Value((int64_t)(isFalsy(regs[base + 0]) ? 1 : 0)) : regs[base + 0];
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
            if (n_va > 0) {
                int count = B;
                int n = (count == 0) ? n_va : std::min(count, n_va);
                size_t needed = (size_t)(base + A + n);
                if (regs.size() < needed)
                    regs.resize(needed);
                for (int i = 0; i < n; ++i)
                    regs[base + A + i] = regs[fr.varargs_base + i];
            }
        }
        NEXT();
    }

    op_RETURN_V: {
        {
            closeUpvals();
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
            int rbase = call_stack.back().reg_base;
            call_stack.pop_back();
            if ((int)regs.size() < rbase + total)
                regs.resize(rbase + total);
            for (int i = 0; i < total; ++i)
                regs[rbase + i] = std::move(rvs[i]);
            if (is_ctor_)
                regs[rbase + 0] = std::move(ctor_val);
            if (ret_dest >= 0)
                regs[ret_dest] = neg_ ? Value((int64_t)(isFalsy(regs[rbase + 0]) ? 1 : 0)) : regs[rbase + 0];
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
                throw std::runtime_error("line " + std::to_string(errLine()) +
                                         ": unhandled exception: " + valueToString(thrown));
            Handler h = handler_stack.back();
            handler_stack.pop_back();
            unwindToHandler(h, std::move(thrown));
        }
        base = call_stack.back().reg_base;
        NEXT();
    }

    op_NEW_MAP:
        regs[base + A] = Value::makeMap();
        NEXT();

    op_GET_INDEX: {
        const Value& obj = regs[base + B];
        const Value& key = regs[base + C];
        if (obj.isMap() || obj.isClass()) {
            regs[base + A] = protoChainGet(obj, key);
        } else if (obj.isString()) {
            regs[base + A] = string_module_.mapGet(key);
        } else if (obj.isArray()) {
            if (!key.isInteger())
                throw std::runtime_error("line " + std::to_string(errLine()) +
                                         ": runtime: array index must be integer");
            regs[base + A] = obj.arrayGet(key.asInt());
        } else {
            throw std::runtime_error("line " + std::to_string(errLine()) + ": cannot index " +
                                     std::string(obj.typeName()) +
                                     (key.isString() ? " with field '" + key.asString() + "'" : ""));
        }
        NEXT();
    }

    op_SET_INDEX: {
        Value& obj = regs[base + A];
        const Value& key = regs[base + B];
        if (obj.isMap() || obj.isClass()) {
            obj.mapSet(key, regs[base + C]);
        } else if (obj.isArray()) {
            if (!key.isInteger())
                throw std::runtime_error("line " + std::to_string(errLine()) +
                                         ": runtime: array index must be integer");
            obj.arraySet(key.asInt(), regs[base + C]);
        } else {
            throw std::runtime_error("line " + std::to_string(errLine()) + ": cannot assign index on " +
                                     std::string(obj.typeName()) +
                                     (key.isString() ? " with field '" + key.asString() + "'" : ""));
        }
        NEXT();
    }

    op_MAKE_ITER:
        regs[base + A] = Value::makeIterFrom(regs[base + B]);
        NEXT();

    op_BAND: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (!bv.isInteger() || !cv.isInteger())
            throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: & requires integer operands");
        regs[base + A] = Value(bv.asInt() & cv.asInt());
        NEXT();
    }

    op_BOR: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (!bv.isInteger() || !cv.isInteger())
            throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: | requires integer operands");
        regs[base + A] = Value(bv.asInt() | cv.asInt());
        NEXT();
    }

    op_BXOR: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (!bv.isInteger() || !cv.isInteger())
            throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: ^ requires integer operands");
        regs[base + A] = Value(bv.asInt() ^ cv.asInt());
        NEXT();
    }

    op_BNOT: {
        const Value& bv = regs[base + B];
        if (!bv.isInteger())
            throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: ~ requires integer operand");
        regs[base + A] = Value(~bv.asInt());
        NEXT();
    }

    op_BLSHIFT: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (!bv.isInteger() || !cv.isInteger())
            throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: << requires integer operands");
        regs[base + A] = Value((int64_t)((uint64_t)bv.asInt() << (cv.asInt() & 63)));
        NEXT();
    }

    op_BRSHIFT: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (!bv.isInteger() || !cv.isInteger())
            throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: >> requires integer operands");
        regs[base + A] = Value(bv.asInt() >> (cv.asInt() & 63));
        NEXT();
    }

    op_NEW_ARRAY:
        regs[base + A] = Value::makeArray();
        NEXT();

    op_ARRAY_PUSH:
        regs[base + A].arrayPush(regs[base + B]);
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
        regs[base + A] = Value::makeFunc((uint8_t)Bx);
        NEXT();

    op_CALL_DYN: {
        // A=arg_base, B=func_val_reg, C=argc
        if (regs[base + B].isBuiltin()) {
            auto fn = regs[base + B].asBuiltin();
            regs[base + A] = fn(&regs[base + A], C);
            last_results_ = 1; // builtin → 1 valeur (pour SPREAD_RESULTS)
            NEXT();
        }
        if (regs[base + B].isClass()) {
            // Instanciation (args en ctor_base+0.. → arg_off = 0).
            bool done;
            uint32_t addr = instantiateClass(base + A, 0, C, regs[base + B], done);
            if (!done)
                ip = addr;
            goto call_dyn_done;
        }
        {
            // Regular function/closure call
            std::unique_ptr<std::vector<Upvalue*>> fuv;
            uint8_t fi = resolveFuncVal(regs[base + B], fuv);
            ip = pushCallFrame(base + A, fi, C, std::move(fuv), ip);
        }
    call_dyn_done:
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
        regs[base + A] = Value::makeClosure(cl.release());
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
        regs[base + A] = Value::makeClass();
        NEXT();

    op_CALL_METHOD: {
        uint32_t fp_addr = 0;
        {
            int cb = base + A;
            int argc = C;
            bool is_instance = isInstance(regs[cb]) || regs[cb].isString();
            Value fn = regs[cb + 1];
            // Membre = une CLASSE (ex. `mod.Widget()` via un import aliasé) →
            // instanciation, comme CALL_DYN. Les args sont encore en cb+2.. (pas
            // de décalage self appliqué). On les amène en cb+1.. avec l'instance
            // en cb, puis on appelle init (si présent).
            if (fn.isClass()) {
                // Instanciation via un membre-classe (ex. mod.Widget()) : args en
                // cb+2.. → arg_off = 2. Partagé avec CALL_DYN.
                bool done;
                uint32_t addr = instantiateClass(cb, 2, argc, fn, done);
                if (!done)
                    ip = addr;
                goto call_method_done;
            }
            // méthode statique : pas d'injection de self, même si appelée sur une instance
            bool fn_is_static = false;
            if (fn.isFuncVal())
                fn_is_static = ch->funcs[(uint8_t)fn.asInt()].is_static;
            else if (fn.isClosure())
                fn_is_static = ch->funcs[fn.asClosure()->func_idx].is_static;
            else if (fn.isStaticBuiltin()) // builtin déclaré static → traité comme un static Ollin
                fn_is_static = true;
            bool inject_self = is_instance && !fn_is_static;
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
            if (fn.isBuiltin()) {
                regs[cb] = fn.asBuiltin()(&regs[cb], total);
                last_results_ = 1; // builtin → 1 valeur (pour SPREAD_RESULTS)
                goto call_method_done;
            }
            {
                std::unique_ptr<std::vector<Upvalue*>> fuv;
                uint8_t fi;
                if (fn.isFuncVal())
                    fi = (uint8_t)fn.asInt();
                else if (fn.isClosure()) {
                    fi = fn.asClosure()->func_idx;
                    const auto& u = fn.asClosure()->upvals;
                    if (!u.empty())
                        fuv = std::make_unique<std::vector<Upvalue*>>(u);
                } else
                    throw std::runtime_error("line " + std::to_string(errLine()) +
                                             ": runtime: method call on non-function value");
                fp_addr = pushCallFrame(cb, fi, total, std::move(fuv), ip);
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
            int line_ = errLine();
            auto toDouble_ = [&](const Value& v) -> double {
                if (v.isInteger())
                    return (double)v.asInt();
                if (v.isFloat())
                    return v.asFloat();
                throw std::runtime_error("line " + std::to_string(line_) + ": runtime: range bound must be a number");
            };
            double start = toDouble_(regs[base + B]);
            double end = toDouble_(regs[base + B + 1]);
            double step = has_step ? toDouble_(regs[base + B + 2]) : 1.0;
            validateNumericRange(start, end, step, line_);
            Range* r = new Range{1, start, end, step, incl_right};
            regs[base + A] = Value::makeRange(r);
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
            if (!vi.isNumber() || !vl.isNumber() || !vs.isNumber())
                throw std::runtime_error("line " + std::to_string(errLine()) +
                                         ": runtime: for: bornes numériques attendues");
            if (vi.isInteger() && vl.isInteger() && vs.isInteger()) {
                int64_t i0 = vi.asInt(), lim = vl.asInt(), st = vs.asInt();
                if (st == 0)
                    throw std::runtime_error("line " + std::to_string(errLine()) +
                                             ": runtime: for: le pas ne peut pas être 0");
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
                double di = vi.asNum(), dl = vl.asNum(), ds = vs.asNum();
                validateNumericRange(di, dl, ds, errLine());
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
            if (vi.isInteger()) { // type figé par FOR_PREP
                // R[A+1] = compteur de tours restants (posé par FOR_PREP). Tant qu'il est
                // non nul : décrémenter, avancer i. Pas de garde anti-débordement : le
                // compteur garantit que i + st reste dans la plage initiale.
                uint64_t cnt = (uint64_t)vl.asInt();
                if (cnt != 0) {
                    vl = Value((int64_t)(cnt - 1));
                    vi = Value(vi.asInt() + vs.asInt());
                    cont = true;
                } else {
                    cont = false;
                }
            } else {
                double ni = vi.asNum() + vs.asNum();
                cont = (vs.asNum() > 0) ? (ni <= vl.asNum()) : (ni >= vl.asNum());
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
        closeUpvals();
        call_stack.pop_back();
        return;

    } catch (const std::runtime_error& e) {
        if (handler_stack.empty()) {
            // Erreur NON rattrapée : préfixer la ligne source courante si le message
            // n'en porte pas déjà une (les builtins lèvent sans localisation). Les
            // erreurs rattrapées par try/catch gardent leur message brut (ci-dessous).
            std::string msg = e.what();
            if (msg.compare(0, 5, "line ") != 0)
                throw std::runtime_error("line " + std::to_string(errLine()) + ": " + msg);
            throw;
        }
        Handler h = handler_stack.back();
        handler_stack.pop_back();
        unwindToHandler(h, Value(std::string(e.what())));
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
                globals[gi] = Value::makeBuiltin(b.fn);
                globals_init[gi] = true;
            }
    for (int gi = 0; gi < (int)owned_chunk.identifiers.size(); ++gi)
        for (auto& name : builtinModuleNames())
            if (owned_chunk.identifiers[gi] == name) {
                globals[gi] = makeBuiltinModule(name);
                globals_init[gi] = true;
            }
    string_module_ = makeBuiltinModule("string");
    {
        Value core = makeBuiltinModule("core");
        for (auto& [k, v] : core.asMap()->data) {
            if (!k.isString())
                continue;
            const std::string& fname = k.asString();
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
        Value win = makeBuiltinModule("window");
        if (win.isMap()) {
            Value vw = win.mapGet(Value(std::string("width")));
            Value vh = win.mapGet(Value(std::string("height")));
            if (vw.isInteger())
                win_w = vw.asInt();
            if (vh.isInteger())
                win_h = vh.asInt();
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
    growRegs(owned_chunk.top_reg_count);
    call_stack.reserve(1000);
    call_stack.push_back(Frame{});

    runGoto(0);
}
