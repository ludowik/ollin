#include "vm.h"
#include "modules/array_module.h"
#include "modules/modules.h"
#include "utf8.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <ctime>
#include <sstream>
#include <stdexcept>
#include <vector>

// mem(): heap usage, through a per-platform API.
#if defined(__EMSCRIPTEN__)
#include <malloc.h>
#elif defined(__APPLE__)
#include <malloc/malloc.h>
#elif defined(__GLIBC__)
#include <malloc.h>
#elif defined(_WIN32)
#include <psapi.h>
#include <windows.h>
#endif

static VM* s_current_vm = nullptr;

// Shared validation of the bounds of a range or numeric for, and the single source of truth
// for both iteration paths (a Range object through MAKE_RANGE, and the fast path through the
// float branch of FOR_PREP): the step must be non-zero and the bounds finite — a NaN or
// infinite bound would never satisfy the end condition and the loop would never stop. The int
// branch of FOR_PREP does not call this: integers are finite by construction, and it keeps its
// own zero-step test.
static void validate_numeric_range(double start, double end, double step, const std::string& loc) {
    if (step == 0.0)
        throw std::runtime_error(loc + ": runtime: step cannot be 0");
    if (!std::isfinite(start) || !std::isfinite(end) || !std::isfinite(step))
        throw std::runtime_error(loc + ": runtime: range bounds are not finite (NaN and infinity are refused)");
}

// Interned meta-key constants, initialized once and reused across all calls.
struct MetaKeys {
    Value class_, parent_, str_, name_, init_, len_;
    Value add_, sub_, mul_, div_, mod_, neg_, eq_, lt_, le_;
    MetaKeys()
        : class_(std::string("__class__")), parent_(std::string("__parent__")), str_(std::string("__str")),
          name_(std::string("__name__")), init_(std::string("init")), len_(std::string("len")),
          add_(std::string("__add")), sub_(std::string("__sub")), mul_(std::string("__mul")),
          div_(std::string("__div")), mod_(std::string("__mod")), neg_(std::string("__neg")), eq_(std::string("__eq")),
          lt_(std::string("__lt")), le_(std::string("__le")) {
    }
};
static MetaKeys& MK() {
    static MetaKeys mk;
    return mk;
}

bool VM::is_instance(const Value& v) {
    return (v.is_map() || v.is_class()) && !v.map_get(MK().class_).is_nil();
}

// Built-in `len` pseudo-method of maps, synthesized by GET_INDEX when the map does not define
// "len" itself. A NAMED function rather than a lambda, so that CALL_METHOD recognizes it by
// pointer and injects the map as self — maps do not inject self by default, otherwise
// math.noise(x) would receive the module.
static int builtin_map_len(CallCtx& ctx) {
    return ctx.ret(Value((int64_t)(ctx.argc > 0 ? ctx.args[0].map_size() : 0)));
}

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

// Grows by doubling, capped at 4096; size stays exact.
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

int VM::invoke_builtin(Value::BuiltinFn fn, Value* results, int argc, int cap, int regs_base) {
    CallCtx ctx{this, results, argc, cap, regs_base};
    last_results_ = fn(ctx);
    return last_results_;
}

int VM::invoke_builtin_regs(Value::BuiltinFn fn, int result_base, int argc) {
    // cap = current frame's reg_count - (result_base - reg_base) = varargs_base - result_base.
    // regs_base is passed so that the result slots are re-derived at write time: the builtin may
    // call Ollin code, which reallocates regs.
    return invoke_builtin(fn, &regs[result_base], argc, call_stack.back().varargs_base - result_base, result_base);
}

// invoke_str: a mini-loop that calls __str without recursing.
std::string VM::invoke_str(Value obj) { // by value: regs.resize() must not invalidate obj
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
        Value self = obj; // one slot is available (self); the builtin writes its result there, and it is read back
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
    regs[call_base] = obj; // self in R[0], before push_call_frame
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

std::string value_to_string(const Value& v) {
    if (v.is_nil())
        return "nil";
    // In English like the language keywords: what is printed can be pasted straight back into
    // a script.
    if (v.is_bool())
        return v.as_bool() ? "true" : "false";
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

static int builtin_assert(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    // The message is a string, and the type is checked EVEN WHEN the assertion holds: a non-string
    // there is a mistake in the test itself, and validating it only on failure would hide it until
    // the day the assertion breaks. It used to be replaced by the generic wording, which threw the
    // diagnosis away at the very moment it was needed.
    if (argc >= 2 && !args[1].is_string())
        throw std::runtime_error("assert: the message must be a string");
    if (argc == 0 || is_falsy(args[0])) {
        throw std::runtime_error(argc >= 2 ? args[1].as_string() : std::string("assertion failed"));
    }
    return ctx.ret(Value{});
}

static int builtin_time(CallCtx& ctx) {
    (void)ctx;
    auto now = std::chrono::system_clock::now();
    return ctx.ret(Value(std::chrono::duration<double>(now.time_since_epoch()).count()));
}

// CPU time consumed since startup, in seconds. Prefer it to time() for measuring a duration:
// time() reads a wall clock the system may adjust mid-run (NTP), which yields wild values.
static int builtin_cpu_time(CallCtx& ctx) {
    (void)ctx;
    return ctx.ret(Value((double)std::clock() / (double)CLOCKS_PER_SEC));
}

// Heap bytes in use, per platform: the allocator's in-use bytes (WASM, macOS, glibc) or the
// working set (Windows); 0 when unavailable.
uint64_t ollin_heap_bytes() {
    uint64_t bytes = 0;
#if defined(__EMSCRIPTEN__)
    struct mallinfo mi = mallinfo(); // uordblks (the arena) plus hblkhd (the mmapped blocks)
    bytes = (uint64_t)(unsigned)mi.uordblks + (uint64_t)(unsigned)mi.hblkhd;
#elif defined(__APPLE__)
    malloc_statistics_t s;
    malloc_zone_statistics(malloc_default_zone(), &s);
    bytes = (uint64_t)s.size_in_use;
#elif defined(__GLIBC__)
    struct mallinfo2 mi = mallinfo2();                   // glibc ≥ 2.33 : champs size_t
    bytes = (uint64_t)mi.uordblks + (uint64_t)mi.hblkhd; // the arena plus the big mmapped blocks
#elif defined(_WIN32)
    PROCESS_MEMORY_COUNTERS pmc;
    if (GetProcessMemoryInfo(GetCurrentProcess(), &pmc, sizeof(pmc)))
        bytes = (uint64_t)pmc.WorkingSetSize;
#endif
    return bytes;
}

// mem(): heap bytes currently used by the process — Ollin values, runtime and libraries.
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

// The length of a value, shared by the `len` builtin and by the LEN opcode that '#' compiles to,
// so the two can never disagree. NOT inlined: it would be pulled into run_goto, whose register
// allocation is shared by every opcode handler, and the numeric loop measured +2 instructions
// per turn for it (bench/icount.sh) — a cost paid by code that never uses '#'.
// One indexed jump instead of one comparison per arm: the compiler builds the table when every
// case value is an integer known at compile time (see Compiler::switch_table_values). Kept out of
// run_goto — its locals raised the register pressure of the single function all the handlers live
// in, which cost 600 000 instructions to the loop benchmark, a script that never runs a switch.
static __attribute__((noinline)) uint16_t switch_target_slow(const SwitchTable& t, const Value& subj) {
    if (subj.tag != Value::T_FLOAT)
        return t.other_addr; // not a number: the comparison chain, which can call an __eq
    // Equality merges INTEGER and FLOAT, so `4 / 2` — a FLOAT, division always being one — must
    // reach `case 2` exactly as the chain let it. The span is tested in doubles FIRST, which
    // makes the cast below well defined.
    double d = subj.dval;
    if (d >= (double)t.base && d <= (double)(t.base + (int64_t)t.targets.size() - 1)) {
        int64_t i = (int64_t)d;
        if ((double)i == d)
            return t.targets[(size_t)(i - t.base)];
    }
    return t.else_addr;
}

static __attribute__((noinline)) Value value_len(const Value& v) {
    if (v.is_nil())
        return Value((int64_t)0);
    if (v.is_array())
        return Value((int64_t)v.array_size());
    if (v.is_map() || v.is_class())
        return Value(v.map_size());
    if (v.is_string())
        return Value((int64_t)utf8_count(v.as_string())); // in characters (codepoints), not in bytes
    if (v.is_range())
        return Value(range_len(v.rptr));
    return Value((int64_t)1);
}

static int builtin_len(CallCtx& ctx) {
    if (ctx.argc == 0)
        throw std::runtime_error("len() requires 1 argument");
    return ctx.ret(value_len(ctx.args[0]));
}

static const struct {
    const char* name;
    Value::BuiltinFn fn;
} k_builtins[] = {
    {"assert", builtin_assert}, {"time", builtin_time}, {"cpuTime", builtin_cpu_time},
    {"mem", builtin_mem},       {"len", builtin_len},
};

// resolve_func_val: function value to func_idx (plus upvals); defined below.
static uint8_t resolve_func_val(const Value& fv, std::unique_ptr<std::vector<Upvalue*>>& out_upvals);

// Meta-method dispatch helpers.
// Both helpers push a call frame and return fp.addr (non-zero) on success.
// The caller sets ip = addr, then dispatches (NEXT() or continue in switch).

uint32_t VM::try_meta_binary(const Value& name, int dest, Value lhs, Value rhs, bool negate) {
    Value fn = proto_chain_get(lhs.map_get(MK().class_), name);
    if (!fn.is_callable())
        return 0;
    std::unique_ptr<std::vector<Upvalue*>> fuv;
    uint8_t fi = resolve_func_val(fn, fuv); // fn is callable, per the guard above
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
    uint8_t fi = resolve_func_val(fn, fuv); // fn is callable, per the guard above
    int nb = (int)regs.size();
    grow_regs((size_t)(nb + std::max((int)ch->funcs[fi].reg_count, 1)));
    regs[nb] = std::move(lhs);
    return push_call_frame(nb, fi, 1, std::move(fuv), ip, false, dest);
}

// unwind_to_handler: the unwinding shared by a script throw and a C++ runtime error.
void VM::unwind_to_handler(const Handler& h, Value thrown) {
    while (call_stack.size() > h.call_depth) {
        close_upvals();
        call_stack.pop_back();
    }
    if (regs.size() > h.regs_size)
        regs.resize(h.regs_size);
    regs[h.reg_base + h.catch_reg] = std::move(thrown);
    ip = h.catch_addr;
    // Note that the caller restores `base`, a local of the dispatch loop.
}

// instantiate_class, shared by CALL_DYN and CALL_METHOD.
uint32_t VM::instantiate_class(int base_reg, int arg_off, int argc, Value cls, bool& done) {
    done = false;
    Value inst = Value::make_map();
    inst.map_set(MK().class_, cls);
    Value init_fn = proto_chain_get(cls, MK().init_);
    if (!init_fn.is_callable()) { // no constructor, so the instance IS the result
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
        invoke_builtin(init_fn.as_builtin(), bargs.data(), argc + 1,
                       argc + 1); // the return value is ignored: the instance wins
        regs[base_reg] = std::move(inst);
        last_results_ = 1;
        done = true;
        return 0;
    }
    std::unique_ptr<std::vector<Upvalue*>> fuv;
    uint8_t fi = resolve_func_val(init_fn, fuv);
    int total = argc + 1;
    grow_regs((size_t)(base_reg + std::max((int)ch->funcs[fi].reg_count, total)));
    // Shifts the arguments to make room for self at base_reg: base_reg+arg_off+i becomes
    // base_reg+1+i. The direction of the walk depends on dest versus src, so that arguments not
    // yet moved are not overwritten.
    if (arg_off >= 1)
        for (int i = 0; i < argc; ++i)
            regs[base_reg + 1 + i] = std::move(regs[base_reg + arg_off + i]);
    else
        for (int i = argc - 1; i >= 0; --i)
            regs[base_reg + 1 + i] = std::move(regs[base_reg + arg_off + i]);
    regs[base_reg + 0] = std::move(inst);
    return push_call_frame(base_reg, fi, total, std::move(fuv), ip, /*is_ctor=*/true);
}

// Closes and releases ALL the frame's open upvalues. HOT path: called on every function
// return. Deliberately kept apart from close_upvals_above — merging the two grew this code and
// cost 5 % on bench_fib (30 M returns) for three shared lines.
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

// End of a scope INSIDE the frame (one loop iteration): only the upvalues whose register is
// >= threshold are closed, and they are REMOVED from the list, so MAKE_CLOSURE no longer
// reuses one for that register and the next turn gets a fresh variable. The others stay owned
// by the frame.
void VM::close_upvals_above(int threshold) {
    auto& ouv = call_stack.back().open_upvals;
    if (!ouv)
        return;
    size_t kept = 0;
    for (auto* uv : *ouv) {
        if (uv->reg_idx < threshold) {
            (*ouv)[kept++] = uv;
            continue;
        }
        if (!uv->closed) {
            uv->val = regs[uv->frame_base + uv->reg_idx];
            uv->closed = true;
        }
        if (--uv->refcount == 0)
            delete uv;
    }
    ouv->resize(kept);
}

// Resolves a function value to func_idx plus upvals.
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

// Equality, shared by op_EQ and op_NEQ.
static bool values_equal(const Value& av, const Value& bv) {
    if (av.is_nil() && bv.is_nil())
        return true;
    if (av.is_nil() || bv.is_nil())
        return false;
    // The boolean is a type of its own: two booleans compare with each other and `true == 1`
    // is false, hence the test on BOTH sides, which rules out comparing against a number.
    if (av.is_bool() || bv.is_bool())
        return av.is_bool() && bv.is_bool() && av.as_bool() == bv.as_bool();
    if (av.is_integer() && bv.is_integer())
        return av.as_int() == bv.as_int();
    if (av.is_number() && bv.is_number())
        return av.as_num() == bv.as_num();
    if (av.is_string() && bv.is_string())
        return av.sptr == bv.sptr;
    // Everything left has an IDENTITY, never a content: two values are equal when they denote
    // the same object. The tag test comes AFTER the numeric cases, otherwise `1 == 1.0` would
    // stop being true. Covering only maps left `a == a` FALSE for an array, a range, a closure
    // or a function — and `a <> a` true.
    if (av.tag != bv.tag)
        return false;
    switch (av.tag) {
    case Value::T_MAP:
    case Value::T_CLASS:
        return av.mptr == bv.mptr;
    case Value::T_ARRAY:
        return av.aptr == bv.aptr;
    case Value::T_RANGE:
        return av.rptr == bv.rptr;
    case Value::T_CLOSURE:
        return av.cptr == bv.cptr;
    case Value::T_ITERATOR:
        return av.iptr == bv.iptr;
    case Value::T_FUNCTION:
    case Value::T_BUILTIN:
        // The union holds the function index or the native pointer: same value, same target.
        return av.as_int() == bv.as_int();
    default:
        return false;
    }
}

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
    // `graphics` may be nil (the native stub, or a script that never mentions it) or reassigned
    // to a non-map, so the is_map() guard before map_get is mandatory.
    Value gfx = get_global("graphics");
    Value draw = get_global("draw");
    bool graphical = draw.is_callable() && gfx.is_map();

    // setup() runs once after loading, before the update/draw loop.
    Value setup = get_global("setup");
    if (setup.is_callable())
        call_value(setup);

    // IMPLICIT canvas: the mere presence of a draw() is enough to start a graphics session.
    // When NEITHER the top level NOR setup() called graphics.canvas(), we create it at W×H
    // (engine globals, pre-initialized to the window dimensions).
    // Done AFTER setup(), because setup() is a common place to call canvas() oneself: creating
    // it earlier would mean a double InitWindow, which crashes on WASM.
    if (graphical && !gfx_canvas_created_) {
        Value canvas_fn = gfx.map_get(Value(std::string("canvas")));
        if (canvas_fn.is_builtin()) {
            // Size of the render area. We do NOT read get_global("W"): when the script never
            // mentions W or H those identifiers are absent from the chunk, get_global returns
            // nil, and we would get 0. Reading the `window` module directly is reliable — it is
            // the source of the W/H globals, and on WASM it is the size measured in JS and
            // handed over through __ollinRenderW, so there is no layout race.
            int w = 0, h = 0;
            // Built afresh, and deliberately: this runs LATER, after the script has had a chance
            // to resize things, so the DOM must be read again rather than reusing what execute saw.
            Value winm = make_builtin_module("window");
            if (winm.is_map()) {
                Value vw = winm.map_get(Value(std::string("width")));
                Value vh = winm.map_get(Value(std::string("height")));
                if (vw.is_number())
                    w = (int)vw.as_num();
                if (vh.is_number())
                    h = (int)vh.as_num();
            }
            // If the size is still unusable, call canvas() with no argument and let gfx_canvas
            // apply its defaults (800×600), rather than a 0×0 canvas with no GL context, which
            // would crash.
            if (w > 0 && h > 0) {
                Value wh[2] = {Value((int64_t)w), Value((int64_t)h)};
                invoke_builtin(canvas_fn.as_builtin(), wh, 2, 2);
            } else {
                Value none[1] = {};
                invoke_builtin(canvas_fn.as_builtin(), none, 0, 1);
            }
        }
    }

    // With a draw() present, start the render loop through graphics.run(draw).
    if (graphical) {
        Value run_fn = gfx.map_get(Value(std::string("run")));
        if (run_fn.is_builtin())
            invoke_builtin(run_fn.as_builtin(), &draw, 1, 1);
    }
}

Value VM::call_value(const Value& fn, const Value* args, int argc) {
    if (fn.is_builtin()) {
        // A writable local buffer: the builtin writes its result there, since the caller's
        // arguments may be read-only. At least one slot, to receive the value.
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
    // f's return values sit in regs[call_base..], and last_results_ says how many.
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

// The single entry point for building a call frame: grow_regs to the minimum needed, fill in
// defaults for missing arguments (argc < n_fixed), then move the varargs past reg_count.
//   4. builds and pushes the Frame
//   5. returns fp.addr (the caller does ip = push_call_frame(...))
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

void VM::run_goto(size_t stop_depth) {
// Table in the exact order of enum Op (chunk.h).
// Each handler ends with NEXT() → direct jump to the next handler.
#define NEXT()                                                                                                         \
    do {                                                                                                               \
        Instr _ni = ch->code[ip++];                                                                                    \
        A = i_a(_ni);                                                                                                  \
        B = i_b(_ni);                                                                                                  \
        C = i_c(_ni);                                                                                                  \
        Bx = i_bx(_ni);                                                                                                \
        goto* dt[i_op(_ni)];                                                                                           \
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
        &&op_SEAL_ENUM,
        &&op_CLOSE_UPVALS,
        &&op_LEN,
        &&op_SWITCH,
        &&op_HALT,
    };

    uint8_t A, B, C;
    uint16_t Bx;
    int base = call_stack.back().reg_base;
    // The GET_INDEX inline cache is sized on the current code, one slot per instruction. Under
    // reentrancy (a run_goto nested through call_value) the chunk is the same, so the size
    // matches and this is a no-op.
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
        last_results_ = 1; // e.g. the nil branch of an optional call f?() (multi-return)
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
        if (bv.is_integer() && cv.is_integer()) { // the hot path: int + int
            regs[base + A] = Value(bv.as_int() + cv.as_int());
            NEXT();
        }
        if (bv.is_string() || cv.is_string()) {
            {
                // Copy the operands BEFORE value_to_string: if one is an instance with __str,
                // invoke_str reallocates regs and the bv/cv references would dangle.
                // Inner block, so the Values (non-trivial destructors) leave scope before
                // NEXT().
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
        if (bv.is_integer() && cv.is_integer()) { // the hot path: int - int
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
        if (bv.is_integer() && cv.is_integer()) { // the hot path: int * int
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
        if (bv.is_integer() && cv.is_integer()) { // the hot path: int % int
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
            const Value& bv = regs[base + B]; // read before R[A] is written, so the reference is safe
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
        regs[base + A] = Value::make_bool(is_falsy(regs[base + B]));
        NEXT();

    op_AND:
        regs[base + A] = Value::make_bool(!is_falsy(regs[base + B]) && !is_falsy(regs[base + C]));
        NEXT();

    op_OR:
        regs[base + A] = Value::make_bool(!is_falsy(regs[base + B]) || !is_falsy(regs[base + C]));
        NEXT();

    op_EQ: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (bv.is_integer() && cv.is_integer()) { // the hot path: int == int
            regs[base + A] = Value::make_bool(bv.as_int() == cv.as_int());
            NEXT();
        }
        if (is_instance(bv)) {
            if (uint32_t addr = try_meta_binary(MK().eq_, base + A, bv, cv)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        regs[base + A] = Value::make_bool(values_equal(bv, cv));
        NEXT();
    }

    op_NEQ: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        // a <> b goes through __eq then negates, otherwise == and <> could both be true.
        if (is_instance(bv)) {
            if (uint32_t addr = try_meta_binary(MK().eq_, base + A, bv, cv, /*negate=*/true)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        regs[base + A] = Value::make_bool(!values_equal(bv, cv));
        NEXT();
    }

    op_GT: {
        // GT(a,b) == LT(b,a): check __lt on rhs
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (bv.is_integer() && cv.is_integer()) { // the hot path: int > int
            regs[base + A] = Value::make_bool(bv.as_int() > cv.as_int());
            NEXT();
        }
        if (is_instance(cv)) { // the instance on the right: a > b is b < a, hence b.__lt(a)
            if (uint32_t addr = try_meta_binary(MK().lt_, base + A, cv, bv)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        } else if (is_instance(bv)) { // the instance on the left: a > b is not(a <= b), hence not a.__le(b)
            if (uint32_t addr = try_meta_binary(MK().le_, base + A, bv, cv, /*negate=*/true)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        if (bv.is_string() && cv.is_string()) { // lexicographic order
            regs[base + A] = Value::make_bool(bv.as_string() > cv.as_string());
            NEXT();
        }
        regs[base + A] = Value::make_bool(as_double(bv) > as_double(cv));
        NEXT();
    }

    op_LT: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (bv.is_integer() && cv.is_integer()) { // the hot path: int < int
            regs[base + A] = Value::make_bool(bv.as_int() < cv.as_int());
            NEXT();
        }
        if (is_instance(bv)) { // the instance on the left: a < b is a.__lt(b)
            if (uint32_t addr = try_meta_binary(MK().lt_, base + A, bv, cv)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        } else if (is_instance(cv)) { // the instance on the right: a < b is not(b <= a), hence not b.__le(a)
            if (uint32_t addr = try_meta_binary(MK().le_, base + A, cv, bv, /*negate=*/true)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        if (bv.is_string() && cv.is_string()) { // lexicographic order
            regs[base + A] = Value::make_bool(bv.as_string() < cv.as_string());
            NEXT();
        }
        regs[base + A] = Value::make_bool(as_double(bv) < as_double(cv));
        NEXT();
    }

    op_GE: {
        // GE(a,b) == LE(b,a): check __le on rhs
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (bv.is_integer() && cv.is_integer()) { // the hot path: int >= int
            regs[base + A] = Value::make_bool(bv.as_int() >= cv.as_int());
            NEXT();
        }
        if (is_instance(cv)) { // the instance on the right: a >= b is b <= a, hence b.__le(a)
            if (uint32_t addr = try_meta_binary(MK().le_, base + A, cv, bv)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        } else if (is_instance(bv)) { // the instance on the left: a >= b is not(a < b), hence not a.__lt(b)
            if (uint32_t addr = try_meta_binary(MK().lt_, base + A, bv, cv, /*negate=*/true)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        if (bv.is_string() && cv.is_string()) { // lexicographic order
            regs[base + A] = Value::make_bool(bv.as_string() >= cv.as_string());
            NEXT();
        }
        regs[base + A] = Value::make_bool(as_double(bv) >= as_double(cv));
        NEXT();
    }

    op_LE: {
        const Value& bv = regs[base + B];
        const Value& cv = regs[base + C];
        if (bv.is_integer() && cv.is_integer()) { // the hot path: int <= int
            regs[base + A] = Value::make_bool(bv.as_int() <= cv.as_int());
            NEXT();
        }
        if (is_instance(bv)) { // the instance on the left: a <= b is a.__le(b)
            if (uint32_t addr = try_meta_binary(MK().le_, base + A, bv, cv)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        } else if (is_instance(cv)) { // the instance on the right: a <= b is not(b < a), hence not b.__lt(a)
            if (uint32_t addr = try_meta_binary(MK().lt_, base + A, cv, bv, /*negate=*/true)) {
                ip = addr;
                base = call_stack.back().reg_base;
                NEXT();
            }
        }
        if (bv.is_string() && cv.is_string()) { // lexicographic order
            regs[base + A] = Value::make_bool(bv.as_string() <= cv.as_string());
            NEXT();
        }
        regs[base + A] = Value::make_bool(as_double(bv) <= as_double(cv));
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
            else if (n == 0)
                nil_result_slot(wb); // a valueless return still leaves nil where the caller reads
            uint32_t rip = call_stack.back().return_ip;
            call_stack.pop_back();
            if (is_ctor_)
                regs[wb + 0] = std::move(ctor_val);
            if (ret_dest >= 0)
                regs[ret_dest] = neg_ ? Value::make_bool(is_falsy(regs[wb + 0])) : regs[wb + 0];
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
            int count = B; // 0 = all of them; otherwise a fixed count, padded with nil
            int n = (count == 0) ? n_va : count;
            size_t needed = (size_t)(base + A + n);
            if ((int)regs.size() < (int)needed)
                regs.resize(needed);
            int va_src = fr.varargs_base;
            for (int i = 0; i < n; ++i)
                regs[base + A + i] = (i < n_va) ? regs[va_src + i] : Value{};
            last_results_ = n; // the count is published, for a spread [..., ...] and for CALL_VA
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
            if (total == 0)
                nil_result_slot(rbase);
            if (is_ctor_)
                regs[rbase + 0] = std::move(ctor_val);
            if (ret_dest >= 0)
                regs[ret_dest] = neg_ ? Value::make_bool(is_falsy(regs[rbase + 0])) : regs[rbase + 0];
            ip = rip;
            last_results_ = is_ctor_ ? 1 : total; // for SPREAD_RESULTS (a multiple return)
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
        // Capture BEFORE writing regs[base+A]: the destination may alias the key register
        // (A==C) or the object one (A==B), so reading obj or key after `regs[A] = found` would
        // read the overwritten value.
        const Map* obj_map = (obj.is_map() || obj.is_class()) ? obj.mptr : nullptr;
        const InternedStr* key_sptr = key.is_string() ? key.sptr : nullptr;
        // Inline cache (string key): a hit needs the same map or class (mptr), unmutated since
        // (version), and the same interned key (sptr). Only hits on the object's own data
        // of the object (see the fill below).
        if (obj_map && key_sptr) {
            GetIndexCache& c = gicache_[ip - 1];
            if (c.map == obj_map && c.version == obj_map->version && c.key == key_sptr) {
                {
                    // Copy BEFORE writing the register: if the destination aliases the object
                    // (A==B) and held the last reference to the map, the write would destroy
                    // it — and c.val points INSIDE that map. The temporary retains first. Block
                    // closed before NEXT(), per the computed-goto rule.
                    Value hit = *c.val;
                    regs[base + A] = std::move(hit);
                }
                NEXT();
            }
        }
        if (obj.is_map() || obj.is_class()) {
            // Own data first (T_MAP and T_CLASS share the Map layout).
            const Map* own = obj.mptr;
            // Throughout the engine `nil` means ABSENT (see proto_chain_get): an own key holding
            // nil must still defer to the prototype chain and to the `len` fallback, not shadow
            // the class method.
            const Value* slot = own->find_ptr(key);
            if (slot && !slot->is_nil()) {
                // Found directly, so validity depends ONLY on (mptr, version): cacheable even
                // on an instance, since mutating the instance bumps its version,
                // and its own data always shadows the class). No
                // is_instance here — it would cost a "__class__" lookup on every access.
                if (key_sptr) {
                    GetIndexCache& c = gicache_[ip - 1];
                    c.map = own;
                    c.version = own->version;
                    c.key = key_sptr;
                    c.val = slot;
                }
                Value hit = *slot; // read before writing the register (see the cache hit)
                regs[base + A] = std::move(hit);
            } else {
                // Absent from the own data: walk the prototype chain (__class__ / __parent__).
                // NOT cached, because mutating the CLASS does not bump the instance's version.
                // The built-in `len` is only an all-cold fallback (nothing found anywhere), which
                // keeps the strcmp off the hot path.
                Value chained = proto_chain_rest(obj, key);
                // The `len` key is compared by interned POINTER, like __class__ and __parent__,
                // rather than by content, so GET_INDEX has no strcmp left.
                if (chained.is_nil() && key_sptr == MK().len_.sptr && !is_instance(obj))
                    regs[base + A] = Value::make_builtin(builtin_map_len);
                else
                    regs[base + A] = std::move(chained);
            }
        } else if (obj.is_string()) {
            // String pseudo-methods are served by the `string` module, which never changes, so
            // every pass after the first is a cache hit.
            // (The module lives as long as the VM, so there is no aliasing risk.)
            const Value* meth = module_member(string_module_, key, key_sptr);
            regs[base + A] = meth ? *meth : Value{};
        } else if (obj.is_array()) {
            if (key_sptr) {
                // Pseudo-methods: a single lookup in the map built at startup (see
                // array_module.cpp), as for strings, and cached per site since that map is
                // immutable. A missing field is an error, not nil: an array has no free fields.
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
            throw std::runtime_error(err_line() + ": cannot index " + std::string(obj.type_name()) +
                                     (key.is_string() ? " with field '" + key.as_string() + "'" : ""));
        }
        NEXT();
    }

    op_SET_INDEX: {
        Value& obj = regs[base + A];
        const Value& key = regs[base + B];
        if (obj.is_map() || obj.is_class()) {
            if (obj.mptr->kind == Map::ENUM)
                throw std::runtime_error(err_line() + ": cannot modify an enum" +
                                         (key.is_string() ? " (field '" + key.as_string() + "')" : ""));
            obj.map_set(key, regs[base + C]);
        } else if (obj.is_array()) {
            if (!key.is_integer())
                throw std::runtime_error(err_line() + ": runtime: array index must be integer");
            obj.array_set(key.as_int(), regs[base + C]);
        } else {
            throw std::runtime_error(err_line() + ": cannot assign index on " + std::string(obj.type_name()) +
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

    op_SWITCH: {
        const SwitchTable& t = ch->switch_tables[Bx];
        const Value& subj = regs[base + A];
        if (subj.is_integer()) {
            uint64_t idx = (uint64_t)(subj.ival - t.base);
            ip = idx < t.targets.size() ? t.targets[idx] : t.else_addr;
        } else {
            ip = switch_target_slow(t, subj); // a float, or the chain for anything else
        }
        NEXT();
    }

    op_LEN: {
        regs[base + A] = value_len(regs[base + B]);
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
            // Devirtualized range case: a direct, inlinable call to advance() instead of one
            // vtable indirection per element. Other iterators keep the virtual path, and the
            // stepping logic itself is shared, not duplicated.
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
        // Like CALL_DYN but with a dynamic argc: C fixed arguments plus last_results_ values
        // from the last expanded argument (`...` or a multi-value call), already materialized
        // after the fixed ones. The callee (B) sits BELOW the argument block, so the varying
        // number of values never overwrites it.
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
        // A=fixed_base, B=func_reg, C=number of fixed arguments; the last argument is `...`,
        // the current frame's varargs. Gathers the fixed arguments and the varargs into a FRESH
        // area above the caller's varargs — which are never overwritten, so a later `...` is
        // still correct — calls, and returns the results at the static register fixed_base, the
        // callee frame's result_base.
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
            // The fresh area holds the arguments AND the results, so it is sized on both: sizing it
            // on the argument count alone gave a builtin a capacity of `total`, and `var w, h = f(...)`
            // on a two-value builtin lost the second one. The result capacity is the one the
            // non-varargs path uses, varargs_base - result_base.
            int res_cap = va_src - fixed_base;
            grow_regs((size_t)(fresh + std::max(std::max(total, res_cap), 1)));
            for (int i = 0; i < n_fixed; ++i)
                regs[fresh + i] = regs[fixed_base + i];
            for (int i = 0; i < n_va; ++i)
                regs[fresh + n_fixed + i] = regs[va_src + i];
            if (fn.is_builtin()) {
                int k = invoke_builtin(fn.as_builtin(), &regs[fresh], total, res_cap, fresh);
                for (int i = 0; i < k; ++i)
                    regs[fixed_base + i] = regs[fresh + i]; // fresh > fixed_base, so copying downwards is safe
            } else if (fn.is_class()) {
                for (int i = 0; i < total; ++i) // a rare fallback: instantiate at the static register
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
            if (A != B) // A < B, copying downwards, so a forward loop is safe
                for (int i = 0; i < n; ++i)
                    regs[base + A + i] = std::move(regs[base + B + i]);
        }
        NEXT();
    }

    op_RETURN_SPREAD: {
        // return <explicit values>, <call>: B explicit values plus last_results_ from the call,
        // all contiguous at base+A. Like RETURN_V, but with a contiguous source and no varargs.
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
            if (total == 0)
                nil_result_slot(rbase);
            if (is_ctor_)
                regs[rbase + 0] = std::move(ctor_val);
            if (ret_dest >= 0)
                regs[ret_dest] = neg_ ? Value::make_bool(is_falsy(regs[rbase + 0])) : regs[rbase + 0];
            ip = rip;
            last_results_ = is_ctor_ ? 1 : total;
        }
        if (call_stack.size() <= stop_depth)
            return;
        base = call_stack.back().reg_base;
        NEXT();
    }

    op_MAKE_CLOSURE: {
        // Inner block: the unique_ptr has a non-trivial destructor and must leave scope BEFORE
        // NEXT(), per the computed-goto rule.
        {
            uint8_t fi = (uint8_t)Bx;
            // A unique_ptr so that if capturing throws (inconsistent bytecode) the Closure is freed
            // instead of leaking.
            auto cl = std::make_unique<Closure>(fi);
            for (auto& desc : ch->funcs[fi].upvals) {
                Upvalue* uv;
                if (desc.is_local) {
                    uv = nullptr;
                    auto& frame_open = call_stack.back().open_upvals;
                    if (frame_open) {
                        for (auto* cand : *frame_open) {
                            if (!cand->closed && cand->frame_base == base && cand->reg_idx == desc.idx) {
                                uv = cand;
                                break;
                            }
                        }
                    }
                    if (!uv) {
                        uv = new Upvalue;
                        uv->frame_base = base;
                        uv->reg_idx = desc.idx;
                        if (!frame_open)
                            frame_open = std::make_unique<std::vector<Upvalue*>>();
                        frame_open->push_back(uv);
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
            // Maps do not inject self: a module such as `math` must not receive itself, so
            // math.noise(x) calls noise(x). The one exception is the built-in `len`
            // pseudo-method, recognized by pointer, which needs the map.
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
        // Numeric for: R[A]=i, R[A+1]=limit, R[A+2]=step, consecutive and inclusive on both
        // bounds. Validates and freezes the type. An empty loop jumps to ip=Bx; otherwise we
        // fall into the body, i NOT being pre-decremented, which avoids wrapping at the lower
        // bound.
        bool empty;
        {
            Value& vi = regs[base + A];
            Value& vl = regs[base + A + 1];
            Value& vs = regs[base + A + 2];
            if (!vi.is_number() || !vl.is_number() || !vs.is_number())
                throw std::runtime_error(err_line() + ": runtime: for: expected numeric bounds");
            if (vi.is_integer() && vl.is_integer() && vs.is_integer()) {
                int64_t i0 = vi.as_int(), lim = vl.as_int(), st = vs.as_int();
                if (st == 0)
                    throw std::runtime_error(err_line() + ": runtime: for: step cannot be 0");
                empty = (st > 0) ? (i0 > lim) : (i0 < lim);
                if (!empty) {
                    // Count of REMAINING turns after the first iteration, computed once in
                    // unsigned arithmetic so it is overflow-safe. FOR_LOOP then needs neither an
                    // overflow guard nor a limit comparison, and the limit in R[A+1] is replaced
                    // by this counter.
                    uint64_t ustep = (st > 0) ? (uint64_t)st : (0ull - (uint64_t)st);
                    uint64_t urange = (st > 0) ? ((uint64_t)lim - (uint64_t)i0) : ((uint64_t)i0 - (uint64_t)lim);
                    regs[base + A + 1] = Value((int64_t)(urange / ustep));
                }
            } else {
                double di = vi.as_num(), dl = vl.as_num(), ds = vs.as_num();
                validate_numeric_range(di, dl, ds, err_line());
                regs[base + A] = Value(di); // normalises everything to double
                regs[base + A + 1] = Value(dl);
                regs[base + A + 2] = Value(ds);
                empty = (ds > 0) ? (di > dl) : (di < dl);
            }
        }
        if (empty)
            ip = Bx; // an empty loop exits; otherwise we fall into the body, for the first iteration
        NEXT();
    }

    op_FOR_LOOP: {
        bool cont;
        {
            Value& vi = regs[base + A];
            Value& vl = regs[base + A + 1];
            Value& vs = regs[base + A + 2];
            if (vi.is_integer()) { // the type was frozen by FOR_PREP
                // R[A+1] holds the remaining-turn counter set by FOR_PREP. While it is non-zero,
                // decrement it and step i. No overflow guard is needed: the counter guarantees
                // that i + st stays within the initial range.
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
            ip = Bx; // into the body; otherwise we fall through to the exit
        NEXT();
    }

    op_SPREAD_RESULTS:
        // Multi-return destructuring: the previous call left last_results_ values in R[A..].
        // Set the remaining targets (A+last_results_ .. A+B-1) to nil, otherwise they would read
        // stale registers.
        for (int i = last_results_; i < B; ++i)
            regs[base + A + i] = Value{};
        NEXT();

    // Sealing an enum, emitted AFTER it is filled — the filling itself goes through SET_INDEX,
    // and may evaluate calls to produce the values.
    op_SEAL_ENUM: {
        Value& target = regs[base + A];
        if (target.is_map())
            target.mptr->kind = Map::ENUM;
        NEXT();
    }

    // End of a scope that REPEATS (one loop iteration): variables captured by a closure are
    // frozen in their upvalue, which leaves the frame's list. The next turn therefore creates a
    // fresh one, giving one variable per iteration.
    op_CLOSE_UPVALS: {
        close_upvals_above(A);
        NEXT();
    }

    op_HALT:
        close_upvals();
        call_stack.pop_back();
        return;

    } catch (const std::runtime_error& e) {
        if (handler_stack.empty()) {
            // UNCAUGHT error: prefix the current source line unless the message already carries
            // one (builtins throw without a location). Errors caught by try/catch keep their raw
            // message, below.
            std::string msg = e.what();
            // An already-located message contains ":<digits>:", the file:line: pattern.
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
        // `base` (a local) is restored here, as in op_THROW; unwind_to_handler already set ip.
        base = call_stack.back().reg_base;
        goto dispatch_loop;
    }

#undef NEXT
}

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
    // A module is built AT MOST ONCE for this program: `window`, `string` and `core` are read again
    // below, and each construction is real work — on the web, building `window` queries the DOM for
    // the layout. The cache lives for this call alone, so two runs in the same WASM instance never
    // share a module map.
    std::unordered_map<std::string, Value> built;
    auto module_of = [&built](const std::string& name) -> const Value& {
        auto it = built.find(name);
        if (it == built.end())
            it = built.emplace(name, make_builtin_module(name)).first;
        return it->second;
    };
    for (int gi = 0; gi < (int)owned_chunk.identifiers.size(); ++gi)
        for (auto& name : builtin_module_names())
            if (owned_chunk.identifiers[gi] == name) {
                globals[gi] = module_of(name);
                globals_init[gi] = true;
            }
    string_module_ = module_of("string");
    array_module_ = make_array_module();
    {
        const Value& core = module_of("core");
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
    // W and H are the render-area dimensions injected by the engine, defaulting to
    // window.width/height for the environment. They are read before the top level so that
    // graphics.canvas(W, H) works right away.
    {
        int64_t win_w = 0, win_h = 0;
        const Value& win = module_of("window");
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
            } else if (owned_chunk.identifiers[gi] == "CX") {
                globals[gi] = Value((double)win_w / 2.0);
                globals_init[gi] = true;
            } else if (owned_chunk.identifiers[gi] == "CY") {
                globals[gi] = Value((double)win_h / 2.0);
                globals_init[gi] = true;
            }
        }
    }
    grow_regs(owned_chunk.top_reg_count);
    call_stack.reserve(1000);
    Frame top;
    top.varargs_base =
        owned_chunk.top_reg_count; // the top-level frame's reg_count, so result_cap is right for the builtins
    call_stack.push_back(std::move(top));

    run_goto(0);
}
