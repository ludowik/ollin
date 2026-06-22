#include "vm.h"
#include "modules.h"
#include <chrono>
#include <cmath>
#include <sstream>
#include <stdexcept>
#include <vector>

static VM* s_current_vm = nullptr;

// ── Interned meta-key constants (initialized once, reused across all calls) ───
struct MetaKeys {
    Value class_, parent_, str_, name_, init_;
    Value add_, sub_, mul_, div_, mod_, neg_, eq_, lt_, le_;
    MetaKeys()
        : class_(std::string("__class__")), parent_(std::string("__parent__"))
        , str_(std::string("__str")),       name_(std::string("__name__"))
        , init_(std::string("init"))
        , add_(std::string("__add")),  sub_(std::string("__sub"))
        , mul_(std::string("__mul")),  div_(std::string("__div"))
        , mod_(std::string("__mod")),  neg_(std::string("__neg"))
        , eq_(std::string("__eq")),    lt_(std::string("__lt"))
        , le_(std::string("__le"))
    {}
};
static MetaKeys& MK() { static MetaKeys mk; return mk; }

bool VM::isInstance(const Value& v) {
    return (v.isMap() || v.isClass()) && !v.mapGet(MK().class_).isNil();
}

// ── protoChainGet ─────────────────────────────────────────────────────────────
Value VM::protoChainGet(const Value& obj, const Value& key) {
    if (obj.isMap() || obj.isClass()) {
        Value v = obj.mapGet(key);
        if (!v.isNil()) return v;
        if (obj.isMap()) {
            Value cls = obj.mapGet(MK().class_);
            if (!cls.isNil()) return protoChainGet(cls, key);
        } else {
            Value par = obj.mapGet(MK().parent_);
            if (!par.isNil()) return protoChainGet(par, key);
        }
    }
    return Value{};
}

// ── growRegs : croît par doublement, max 4096, size reste exacte ─────────────
void VM::growRegs(size_t needed) {
    if (regs.size() >= needed) return;
    if (needed > 4096)
        throw std::runtime_error("runtime: stack overflow (max 4096 registers)");
    size_t cap = regs.capacity() < 32 ? 32 : regs.capacity();
    while (cap < needed) cap *= 2;
    regs.reserve(cap < 4096 ? cap : 4096);
    regs.resize(needed);
}

// ── invokeStr : mini-loop to call __str without recursion ─────────────────────
std::string VM::invokeStr(Value obj) {   // by value: regs.resize() ne invalide pas obj
    Value cls = obj.mapGet(MK().class_);
    if (cls.isNil()) return "{map}";
    Value str_fn = protoChainGet(cls, MK().str_);
    if (str_fn.isNil() || !str_fn.isCallable()) {
        Value nm = cls.mapGet(MK().name_);
        return nm.isString() ? "{" + nm.asString() + "}" : "{object}";
    }
    uint8_t fi;
    std::unique_ptr<std::vector<Upvalue*>> frame_upvals;
    if (str_fn.isFuncVal()) {
        fi = (uint8_t)str_fn.asInt();
    } else if (str_fn.isClosure()) {
        fi = str_fn.asClosure()->func_idx;
        const auto& uvs = str_fn.asClosure()->upvals;
        if (!uvs.empty()) frame_upvals = std::make_unique<std::vector<Upvalue*>>(uvs);
    } else if (str_fn.isBuiltin()) {
        Value self = obj;
        Value result = str_fn.asBuiltin()(&self, 1);
        return result.isString() ? result.asString() : "{object}";
    } else {
        Value nm = cls.mapGet(MK().name_);
        return nm.isString() ? "{" + nm.asString() + "}" : "{object}";
    }
    const FuncProto& fp = ch->funcs[fi];
    int call_base = (int)regs.size();
    growRegs((size_t)(call_base + std::max((int)fp.reg_count, 1)));
    regs[call_base] = obj;
    uint32_t saved_ip = ip;
    {
        Frame fr;
        fr.return_ip = 0;
        fr.reg_base  = call_base;
        fr.upvals    = std::move(frame_upvals);
        call_stack.push_back(std::move(fr));
    }
    ip = fp.addr;
    runGoto(call_stack.size() - 1);
    std::string result;
    if ((int)regs.size() > call_base) {
        const Value& rv = regs[call_base];
        if (rv.isString()) {
            result = rv.asString();
        } else {
            std::ostringstream os;
            if (rv.isNil())          os << "nil";
            else if (rv.isInteger()) os << rv.asInt();
            else if (rv.isFloat()) {
                double d = rv.asFloat();
                if (d == (long long)d && d >= -1e15 && d <= 1e15) os << (long long)d;
                else os << d;
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
    if (v.isNil())      return "nil";
    if (v.isString())   return v.asString();
    if (v.isClass())    return "{class}";
    if (v.isMap()) {
        VM* vm = VM::current();
        if (vm) {
            Value cls = v.mapGet(MK().class_);
            if (!cls.isNil()) return vm->invokeStr(v);
        }
        return "{map}";
    }
    if (v.isArray())    return "{array}";
    if (v.isIterator()) return "{iterator}";
    if (v.isRange())    return "{range}";
    if (v.isFuncVal() || v.isClosure() || v.isBuiltin()) return "{function}";
    if (v.isInteger())  return std::to_string(v.asInt());
    std::ostringstream os;
    double d = v.asFloat();
    if (d == (long long)d && d >= -1e15 && d <= 1e15) os << (long long)d;
    else                                               os << d;
    return os.str();
}

// ── Builtins ──────────────────────────────────────────────────────────────────

static Value builtin_assert(Value* args, int argc) {
    if (argc == 0 || isFalsy(args[0])) {
        std::string msg = (argc >= 2 && args[1].isString())
                          ? args[1].asString() : "assertion failed";
        throw std::runtime_error(msg);
    }
    return Value{};
}

static Value builtin_time(Value* args, int argc) {
    (void)args; (void)argc;
    auto now = std::chrono::system_clock::now();
    return Value(std::chrono::duration<double>(now.time_since_epoch()).count());
}

static const struct { const char* name; Value::BuiltinFn fn; } k_builtins[] = {
    { "assert", builtin_assert },
    { "time",   builtin_time   },
};

// ── Meta-method dispatch helpers ──────────────────────────────────────────────
// Both helpers push a call frame and return fp.addr (non-zero) on success.
// The caller sets ip = addr, then dispatches (NEXT() or continue in switch).

uint32_t VM::tryMetaBinary(const Value& name, int dest, Value lhs, Value rhs) {
    Value fn = protoChainGet(lhs.mapGet(MK().class_), name);
    if (!fn.isCallable()) return 0;
    uint8_t fi;
    std::unique_ptr<std::vector<Upvalue*>> fuv;
    if (fn.isFuncVal()) fi = (uint8_t)fn.asInt();
    else { fi = fn.asClosure()->func_idx; const auto& u = fn.asClosure()->upvals; if (!u.empty()) fuv = std::make_unique<std::vector<Upvalue*>>(u); }
    const FuncProto& fp = ch->funcs[fi];
    int nb = (int)regs.size();
    growRegs((size_t)(nb + std::max((int)fp.reg_count, 2)));
    regs[nb]     = std::move(lhs);
    regs[nb + 1] = std::move(rhs);
    {
        Frame fr;
        fr.return_ip  = ip;
        fr.reg_base   = nb;
        fr.return_dest = dest;
        fr.upvals     = std::move(fuv);
        call_stack.push_back(std::move(fr));
    }
    return fp.addr;
}

uint32_t VM::tryMetaUnary(const Value& name, int dest, Value lhs) {
    Value fn = protoChainGet(lhs.mapGet(MK().class_), name);
    if (!fn.isCallable()) return 0;
    uint8_t fi;
    std::unique_ptr<std::vector<Upvalue*>> fuv;
    if (fn.isFuncVal()) fi = (uint8_t)fn.asInt();
    else { fi = fn.asClosure()->func_idx; const auto& u = fn.asClosure()->upvals; if (!u.empty()) fuv = std::make_unique<std::vector<Upvalue*>>(u); }
    const FuncProto& fp = ch->funcs[fi];
    int nb = (int)regs.size();
    growRegs((size_t)(nb + std::max((int)fp.reg_count, 1)));
    regs[nb] = std::move(lhs);
    {
        Frame fr;
        fr.return_ip   = ip;
        fr.reg_base    = nb;
        fr.return_dest = dest;
        fr.upvals      = std::move(fuv);
        call_stack.push_back(std::move(fr));
    }
    return fp.addr;
}

// ── closeUpvals : close and free all open upvalues of the top frame ──────────
void VM::closeUpvals() {
    auto& ouv = call_stack.back().open_upvals;
    if (!ouv) return;
    for (auto* uv : *ouv) {
        if (!uv->closed) {
            uv->val    = regs[uv->frame_base + uv->reg_idx];
            uv->closed = true;
        }
        if (--uv->refcount == 0) delete uv;
    }
}

// ── Helper: resolve function value → func_idx + upvals ───────────────────────
static uint8_t resolveFuncVal(const Value& fv, std::unique_ptr<std::vector<Upvalue*>>& out_upvals) {
    if (fv.isFuncVal()) return (uint8_t)fv.asInt();
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
    if (av.isNil() && bv.isNil())              return true;
    if (av.isNil() || bv.isNil())              return false;
    if (av.isInteger() && bv.isInteger())      return av.asInt()  == bv.asInt();
    if (av.isNumber()  && bv.isNumber())       return av.asNum()  == bv.asNum();
    if (av.isString()  && bv.isString())       return av.asString() == bv.asString();
    if (av.isString()  && bv.isNumber())       return (isFalsy(av) ? 0.0 : 1.0) == bv.asNum();
    if (av.isNumber()  && bv.isString())       return av.asNum() == (isFalsy(bv) ? 0.0 : 1.0);
    return (av.isMap()   && bv.isMap()   && av.mptr == bv.mptr) ||
           (av.isClass() && bv.isClass() && av.mptr == bv.mptr);
}

// ── VM::errLine / VM::current / VM::callValue ────────────────────────────────

int VM::errLine() const {
    uint32_t idx = ip > 0 ? ip - 1 : 0;
    return (idx < (uint32_t)ch->lines.size()) ? ch->lines[idx] : 0;
}

VM* VM::current() { return s_current_vm; }

Value VM::getGlobal(const std::string& name) const {
    if (!ch) return Value{};
    for (int i = 0; i < (int)ch->identifiers.size(); ++i)
        if (ch->identifiers[i] == name && globals_init[i])
            return globals[i];
    return Value{};
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
        if (!uvs.empty()) frame_upvals = std::make_unique<std::vector<Upvalue*>>(uvs);
    } else {
        throw std::runtime_error("callValue: not callable");
    }
    const FuncProto& fp = ch->funcs[fi];
    int call_base = (int)regs.size();
    growRegs((size_t)(call_base + std::max((int)fp.reg_count, 1)));
    uint32_t saved_ip = ip;
    {
        Frame fr;
        fr.return_ip = saved_ip;
        fr.reg_base  = call_base;
        fr.upvals    = std::move(frame_upvals);
        call_stack.push_back(std::move(fr));
    }
    ip = fp.addr;
    runGoto(call_stack.size() - 1);
    Value result = (int)regs.size() > call_base ? regs[call_base] : Value{};
    regs.resize(call_base);
    ip = saved_ip;
    return result;
}


// ── runGoto: dispatch loop, stops when call_stack.size() <= stop_depth ────────
void VM::runGoto(size_t stop_depth) {
// ── Computed-goto dispatch (GCC / Clang) ─────────────────────────────────────
// Table in the exact order of enum Op (chunk.h).
// Each handler ends with NEXT() → direct jump to the next handler.
#define NEXT() do {                                          \
    Instr _ni = ch->code[ip++];                             \
    A  = iA(_ni); B = iB(_ni); C = iC(_ni); Bx = iBx(_ni); \
    goto *dt[iOP(_ni)];                                     \
} while(0)

    static const void* const dt[] = {
        &&op_LOAD_K, &&op_LOAD_NIL, &&op_MOVE,
        &&op_LOAD_GLOBAL, &&op_STORE_GLOBAL,
        &&op_ADD, &&op_SUB, &&op_MUL, &&op_DIV, &&op_MOD, &&op_IDIV, &&op_POW,
        &&op_NEGATE, &&op_NOT, &&op_AND, &&op_OR,
        &&op_EQ, &&op_NEQ, &&op_GT, &&op_LT, &&op_GE, &&op_LE,
        &&op_JUMP, &&op_JUMP_IF_FALSE,
        &&op_CALL_FUNC, &&op_RETURN, &&op_LOAD_VARARGS, &&op_RETURN_V,
        &&op_TRY, &&op_POP_TRY, &&op_THROW,
        &&op_NEW_MAP, &&op_GET_INDEX, &&op_SET_INDEX,
        &&op_MAKE_ITER,
        &&op_BAND, &&op_BOR, &&op_BXOR,
        &&op_BNOT,
        &&op_BLSHIFT, &&op_BRSHIFT,
        &&op_NEW_ARRAY, &&op_ARRAY_PUSH, &&op_FOR_ITER_NEXT, &&op_FOR_ITER_NEXT1,
        &&op_LOAD_FUNC, &&op_CALL_DYN,
        &&op_MAKE_CLOSURE, &&op_GET_UPVAL, &&op_SET_UPVAL,
        &&op_NEW_CLASS, &&op_CALL_METHOD,
        &&op_MAKE_RANGE,
        &&op_HALT,
    };

    uint8_t A, B, C; uint16_t Bx; int base = call_stack.back().reg_base;
dispatch_loop:
    try {
    NEXT();

op_LOAD_K:
    regs[base + A] = ch->constants[Bx];
    NEXT();

op_LOAD_NIL:
    regs[base + A] = Value{};
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
    if (regs[base+B].isString() || regs[base+C].isString()) {
        { Value bv_ = regs[base+B], cv_ = regs[base+C];
          regs[base+A] = Value(valueToString(bv_) + valueToString(cv_)); }
        NEXT();
    }
    if (isInstance(regs[base+B])) {
        if (uint32_t addr = tryMetaBinary(MK().add_, base+A, regs[base+B], regs[base+C]))
            { ip = addr; base = call_stack.back().reg_base; NEXT(); }
    }
    const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
    regs[base+A] = (bv.isInteger() && cv.isInteger())
        ? Value(bv.asInt() + cv.asInt())
        : Value(asDouble(bv) + asDouble(cv));
    NEXT();
}

op_SUB: {
    if (isInstance(regs[base+B])) {
        if (uint32_t addr = tryMetaBinary(MK().sub_, base+A, regs[base+B], regs[base+C]))
            { ip = addr; base = call_stack.back().reg_base; NEXT(); }
    }
    const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
    regs[base+A] = (bv.isInteger() && cv.isInteger())
        ? Value(bv.asInt() - cv.asInt())
        : Value(asDouble(bv) - asDouble(cv));
    NEXT();
}

op_MUL: {
    if (isInstance(regs[base+B])) {
        if (uint32_t addr = tryMetaBinary(MK().mul_, base+A, regs[base+B], regs[base+C]))
            { ip = addr; base = call_stack.back().reg_base; NEXT(); }
    }
    const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
    regs[base+A] = (bv.isInteger() && cv.isInteger())
        ? Value(bv.asInt() * cv.asInt())
        : Value(asDouble(bv) * asDouble(cv));
    NEXT();
}

op_DIV: {
    if (isInstance(regs[base+B])) {
        if (uint32_t addr = tryMetaBinary(MK().div_, base+A, regs[base+B], regs[base+C]))
            { ip = addr; base = call_stack.back().reg_base; NEXT(); }
    }
    double dv = asDouble(regs[base+C]);
    if (dv == 0.0) throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: division by zero");
    regs[base+A] = Value(asDouble(regs[base+B]) / dv);
    NEXT();
}

op_MOD: {
    if (isInstance(regs[base+B])) {
        if (uint32_t addr = tryMetaBinary(MK().mod_, base+A, regs[base+B], regs[base+C]))
            { ip = addr; base = call_stack.back().reg_base; NEXT(); }
    }
    const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
    if (bv.isInteger() && cv.isInteger()) {
        if (cv.asInt() == 0) throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: modulo by zero");
        regs[base+A] = Value(bv.asInt() % cv.asInt());
    } else {
        double dv = asDouble(cv);
        if (dv == 0.0) throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: modulo by zero");
        regs[base+A] = Value(std::fmod(asDouble(bv), dv));
    }
    NEXT();
}

op_IDIV: {
    const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
    if (bv.isInteger() && cv.isInteger()) {
        if (cv.asInt() == 0) throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: division by zero");
        int64_t q = bv.asInt() / cv.asInt();
        // floor division: adjust if signs differ and there is a remainder
        if ((bv.asInt() ^ cv.asInt()) < 0 && q * cv.asInt() != bv.asInt()) q--;
        regs[base+A] = Value(q);
    } else {
        double dv = asDouble(cv);
        if (dv == 0.0) throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: division by zero");
        regs[base+A] = Value(std::floor(asDouble(bv) / dv));
    }
    NEXT();
}


op_POW: {
    {
        Value bv = regs[base+B]; Value cv = regs[base+C];
        if (bv.isInteger() && cv.isInteger() && cv.asInt() >= 0) {
            int64_t b = bv.asInt(), e = cv.asInt(), r = 1;
            while (e > 0) { if (e & 1) r *= b; b *= b; e >>= 1; }
            regs[base+A] = Value(r);
        } else {
            regs[base+A] = Value(std::pow(asDouble(bv), asDouble(cv)));
        }
    }
    NEXT();
}
op_NEGATE: {
    if (isInstance(regs[base+B])) {
        if (uint32_t addr = tryMetaUnary(MK().neg_, base+A, regs[base+B]))
            { ip = addr; base = call_stack.back().reg_base; NEXT(); }
    }
    const Value& bv = regs[base+B];
    regs[base+A] = bv.isInteger() ? Value(-bv.asInt()) : Value(-asDouble(bv));
    NEXT();
}

op_NOT:
    regs[base+A] = Value((int64_t)(isFalsy(regs[base+B]) ? 1 : 0));
    NEXT();

op_AND:
    regs[base+A] = Value((int64_t)(!isFalsy(regs[base+B]) && !isFalsy(regs[base+C]) ? 1 : 0));
    NEXT();

op_OR:
    regs[base+A] = Value((int64_t)(!isFalsy(regs[base+B]) || !isFalsy(regs[base+C]) ? 1 : 0));
    NEXT();

op_EQ: {
    if (isInstance(regs[base+B])) {
        if (uint32_t addr = tryMetaBinary(MK().eq_, base+A, regs[base+B], regs[base+C]))
            { ip = addr; base = call_stack.back().reg_base; NEXT(); }
    }
    regs[base+A] = Value((int64_t)(valuesEqual(regs[base+B], regs[base+C]) ? 1 : 0));
    NEXT();
}

op_NEQ: {
    // NEQ has no meta-method: __eq result can't be trivially inverted after return
    regs[base+A] = Value((int64_t)(valuesEqual(regs[base+B], regs[base+C]) ? 0 : 1));
    NEXT();
}

op_GT: {
    // GT(a,b) == LT(b,a): check __lt on rhs
    if (isInstance(regs[base+C])) {
        if (uint32_t addr = tryMetaBinary(MK().lt_, base+A, regs[base+C], regs[base+B]))
            { ip = addr; base = call_stack.back().reg_base; NEXT(); }
    }
    const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
    regs[base+A] = Value((int64_t)((bv.isInteger() && cv.isInteger())
        ? bv.asInt()  > cv.asInt()
        : asDouble(bv) > asDouble(cv)));
    NEXT();
}

op_LT: {
    if (isInstance(regs[base+B])) {
        if (uint32_t addr = tryMetaBinary(MK().lt_, base+A, regs[base+B], regs[base+C]))
            { ip = addr; base = call_stack.back().reg_base; NEXT(); }
    }
    const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
    regs[base+A] = Value((int64_t)((bv.isInteger() && cv.isInteger())
        ? bv.asInt()  < cv.asInt()
        : asDouble(bv) < asDouble(cv)));
    NEXT();
}

op_GE: {
    // GE(a,b) == LE(b,a): check __le on rhs
    if (isInstance(regs[base+C])) {
        if (uint32_t addr = tryMetaBinary(MK().le_, base+A, regs[base+C], regs[base+B]))
            { ip = addr; base = call_stack.back().reg_base; NEXT(); }
    }
    const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
    regs[base+A] = Value((int64_t)((bv.isInteger() && cv.isInteger())
        ? bv.asInt()  >= cv.asInt()
        : asDouble(bv) >= asDouble(cv)));
    NEXT();
}

op_LE: {
    if (isInstance(regs[base+B])) {
        if (uint32_t addr = tryMetaBinary(MK().le_, base+A, regs[base+B], regs[base+C]))
            { ip = addr; base = call_stack.back().reg_base; NEXT(); }
    }
    const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
    regs[base+A] = Value((int64_t)((bv.isInteger() && cv.isInteger())
        ? bv.asInt()  <= cv.asInt()
        : asDouble(bv) <= asDouble(cv)));
    NEXT();
}

op_JUMP:
    ip = Bx;
    NEXT();

op_JUMP_IF_FALSE:
    if (isFalsy(regs[base + A])) ip = Bx;
    NEXT();

op_CALL_FUNC: {
    uint32_t fp_addr;
    {
        const FuncProto& fp = ch->funcs[B];
        int new_base = base + A;
        int argc = C;
        size_t needed = (size_t)(new_base + std::max((int)fp.reg_count, argc));
        if (regs.size() < needed) regs.resize(needed);
        if (argc < fp.n_fixed) {
            auto& defs = ch->func_defaults[fp.defaults_idx];
            for (int i = argc; i < fp.n_fixed; ++i)
                regs[new_base + i] = (i < (int)defs.size()) ? defs[i] : Value{};
        }
        int n_extra = 0;
        int va_base = new_base + fp.reg_count;
        if (fp.variadic && argc > fp.n_fixed) {
            n_extra = argc - fp.n_fixed;
            growRegs((size_t)(va_base + n_extra));
            // Backward copy: va_base may overlap source range when reg_count > n_fixed
            for (int i = n_extra - 1; i >= 0; --i)
                regs[va_base + i] = std::move(regs[new_base + fp.n_fixed + i]);
        }
        size_t full_needed = (size_t)(new_base + fp.reg_count);
        if (regs.size() < full_needed) regs.resize(full_needed);
        Frame fr;
        fr.return_ip   = ip;
        fr.reg_base    = new_base;
        fr.varargs_base = va_base;
        fr.n_varargs   = n_extra;
        call_stack.push_back(std::move(fr));
        fp_addr = fp.addr;
    }
    ip = fp_addr;
    base = call_stack.back().reg_base;
    NEXT();
}

op_RETURN: {
    {
        closeUpvals();
        bool is_ctor_ = call_stack.back().is_ctor;
        Value ctor_val;
        if (is_ctor_) ctor_val = regs[base + 0];  // save self before potential overwrite
        int ret_dest = call_stack.back().return_dest;
        int n = B;
        if (n > 0 && A != 0)
            for (int i = 0; i < n; ++i)
                regs[base + i] = std::move(regs[base + A + i]);
        uint32_t rip = call_stack.back().return_ip;
        call_stack.pop_back();
        if (is_ctor_)      regs[base + 0] = std::move(ctor_val);
        if (ret_dest >= 0) regs[ret_dest] = regs[base + 0];
        ip = rip;
    }
    if (call_stack.size() <= stop_depth) return;
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
            if (regs.size() < needed) regs.resize(needed);
            for (int i = 0; i < n; ++i) regs[base + A + i] = regs[fr.varargs_base + i];
        }
    }
    NEXT();
}

op_RETURN_V: {
    {
        closeUpvals();
        int n_va   = call_stack.back().n_varargs;
        int va_src = call_stack.back().varargs_base;
        int n_expl = B;
        int total  = n_expl + n_va;
        std::vector<Value> rvs(total);
        for (int i = 0; i < n_expl; ++i) rvs[i] = std::move(regs[base + A + i]);
        for (int i = 0; i < n_va;   ++i) rvs[n_expl + i] = std::move(regs[va_src + i]);
        uint32_t rip   = call_stack.back().return_ip;
        int      rbase = call_stack.back().reg_base;
        call_stack.pop_back();
        if ((int)regs.size() < rbase + total) regs.resize(rbase + total);
        for (int i = 0; i < total; ++i) regs[rbase + i] = std::move(rvs[i]);
        ip = rip;
    }
    if (call_stack.size() <= stop_depth) return;
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
            throw std::runtime_error("line " + std::to_string(errLine()) + ": unhandled exception: " + valueToString(thrown));
        Handler h = handler_stack.back();
        handler_stack.pop_back();
        while (call_stack.size() > h.call_depth) {
            closeUpvals();
            call_stack.pop_back();
        }
        if (regs.size() > h.regs_size) regs.resize(h.regs_size);
        regs[h.reg_base + h.catch_reg] = std::move(thrown);
        ip = h.catch_addr;
        base = call_stack.back().reg_base;
    }
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
        if (!key.isInteger()) throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: array index must be integer");
        regs[base + A] = obj.arrayGet(key.asInt());
    } else {
        throw std::runtime_error("line " + std::to_string(errLine()) + ": cannot index " + std::string(obj.typeName()) + (key.isString() ? " with field '" + key.asString() + "'" : ""));
    }
    NEXT();
}

op_SET_INDEX: {
    Value& obj       = regs[base + A];
    const Value& key = regs[base + B];
    if (obj.isMap() || obj.isClass()) {
        obj.mapSet(key, regs[base + C]);
    } else if (obj.isArray()) {
        if (!key.isInteger()) throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: array index must be integer");
        obj.arraySet(key.asInt(), regs[base + C]);
    } else {
        throw std::runtime_error("line " + std::to_string(errLine()) + ": cannot assign index on " + std::string(obj.typeName()) + (key.isString() ? " with field '" + key.asString() + "'" : ""));
    }
    NEXT();
}

op_MAKE_ITER:
    regs[base + A] = Value::makeIterFrom(regs[base + B]);
    NEXT();

op_BAND: {
    const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
    if (!bv.isInteger() || !cv.isInteger())
        throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: & requires integer operands");
    regs[base+A] = Value(bv.asInt() & cv.asInt());
    NEXT();
}

op_BOR: {
    const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
    if (!bv.isInteger() || !cv.isInteger())
        throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: | requires integer operands");
    regs[base+A] = Value(bv.asInt() | cv.asInt());
    NEXT();
}

op_BXOR: {
    const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
    if (!bv.isInteger() || !cv.isInteger())
        throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: ^ requires integer operands");
    regs[base+A] = Value(bv.asInt() ^ cv.asInt());
    NEXT();
}

op_BNOT: {
    const Value& bv = regs[base+B];
    if (!bv.isInteger())
        throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: ~ requires integer operand");
    regs[base+A] = Value(~bv.asInt());
    NEXT();
}

op_BLSHIFT: {
    const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
    if (!bv.isInteger() || !cv.isInteger())
        throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: << requires integer operands");
    regs[base+A] = Value((int64_t)((uint64_t)bv.asInt() << (cv.asInt() & 63)));
    NEXT();
}

op_BRSHIFT: {
    const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
    if (!bv.isInteger() || !cv.isInteger())
        throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: >> requires integer operands");
    regs[base+A] = Value(bv.asInt() >> (cv.asInt() & 63));
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
        Value primary;
        if (!regs[base + A].iptr->next_primary(primary)) {
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
        NEXT();
    }
    if (regs[base + B].isClass()) {
        // Instantiation
        uint32_t ctor_addr = 0;
        bool do_call = false;
        {
            int ctor_base = base + A;
            int argc = C;
            Value cls  = regs[base + B];
            Value inst = Value::makeMap();
            inst.mapSet(MK().class_, cls);
            Value init_fn = protoChainGet(cls, MK().init_);
            if (!init_fn.isCallable()) {
                regs[ctor_base] = std::move(inst);
                goto call_dyn_done;
            }
            if (init_fn.isBuiltin()) {
                std::vector<Value> bargs(argc + 1);
                bargs[0] = inst;
                for (int i = 0; i < argc; ++i) bargs[1+i] = regs[ctor_base+i];
                init_fn.asBuiltin()(bargs.data(), argc + 1);
                regs[ctor_base] = std::move(inst);
                goto call_dyn_done;
            }
            std::unique_ptr<std::vector<Upvalue*>> fuv;
            uint8_t fi = resolveFuncVal(init_fn, fuv);
            const FuncProto& fp = ch->funcs[fi];
            int total = argc + 1;
            size_t needed = (size_t)(ctor_base + std::max((int)fp.reg_count, total));
            growRegs(needed);
            for (int i = argc - 1; i >= 0; --i)
                regs[ctor_base + 1 + i] = std::move(regs[ctor_base + i]);
            regs[ctor_base + 0] = inst;
            if (total < fp.n_fixed) {
                auto& defs = ch->func_defaults[fp.defaults_idx];
                for (int i = total; i < fp.n_fixed; ++i)
                    regs[ctor_base + i] = (i < (int)defs.size()) ? defs[i] : Value{};
            }
            size_t full_needed = (size_t)(ctor_base + fp.reg_count);
            growRegs(full_needed);
            ctor_addr = fp.addr;
            {
                Frame fr;
                fr.return_ip = ip;
                fr.reg_base  = ctor_base;
                fr.is_ctor   = true;
                fr.upvals    = std::move(fuv);
                call_stack.push_back(std::move(fr));
            }
            do_call = true;
        }
        if (do_call) { ip = ctor_addr; base = call_stack.back().reg_base; NEXT(); }
    }
    {
        // Regular function/closure call
        uint32_t fp_addr;
        {
            int new_base = base + A;
            int argc = C;
            std::unique_ptr<std::vector<Upvalue*>> fuv;
            uint8_t fi = resolveFuncVal(regs[base + B], fuv);
            const FuncProto& fp = ch->funcs[fi];
            size_t needed = (size_t)(new_base + std::max((int)fp.reg_count, argc));
            growRegs(needed);
            if (argc < fp.n_fixed) {
                auto& defs = ch->func_defaults[fp.defaults_idx];
                for (int i = argc; i < fp.n_fixed; ++i)
                    regs[new_base + i] = (i < (int)defs.size()) ? defs[i] : Value{};
            }
            int n_extra2 = 0;
            int va_base2 = new_base + fp.reg_count;
            if (fp.variadic && argc > fp.n_fixed) {
                n_extra2 = argc - fp.n_fixed;
                growRegs((size_t)(va_base2 + n_extra2));
                for (int i = n_extra2 - 1; i >= 0; --i)
                    regs[va_base2 + i] = std::move(regs[new_base + fp.n_fixed + i]);
            }
            size_t full_needed = (size_t)(new_base + fp.reg_count);
            growRegs(full_needed);
            {
                Frame fr;
                fr.return_ip    = ip;
                fr.reg_base     = new_base;
                fr.varargs_base = va_base2;
                fr.n_varargs    = n_extra2;
                fr.upvals       = std::move(fuv);
                call_stack.push_back(std::move(fr));
            }
            fp_addr = fp.addr;
        }
        ip = fp_addr;
    }
    call_dyn_done:
    base = call_stack.back().reg_base;
    NEXT();
}

op_MAKE_CLOSURE: {
    uint8_t fi = (uint8_t)Bx;
    auto* cl = new Closure(fi);
    for (auto& desc : ch->funcs[fi].upvals) {
        Upvalue* uv;
        if (desc.is_local) {
            uv = nullptr;
            auto& frame_ouv = call_stack.back().open_upvals;
            if (frame_ouv) {
                for (auto* ou : *frame_ouv) {
                    if (!ou->closed && ou->frame_base == base && ou->reg_idx == desc.idx)
                        { uv = ou; break; }
                }
            }
            if (!uv) {
                uv = new Upvalue;
                uv->frame_base = base;
                uv->reg_idx    = desc.idx;
                if (!frame_ouv) frame_ouv = std::make_unique<std::vector<Upvalue*>>();
                frame_ouv->push_back(uv);
            }
            uv->refcount++;
        } else {
            uv = (*call_stack.back().upvals)[desc.idx];
            uv->refcount++;
        }
        cl->upvals.push_back(uv);
    }
    regs[base + A] = Value::makeClosure(cl);
    NEXT();
}

op_GET_UPVAL: {
    Upvalue* uv = (*call_stack.back().upvals)[B];
    regs[base + A] = uv->closed ? uv->val : regs[uv->frame_base + uv->reg_idx];
    NEXT();
}

op_SET_UPVAL: {
    Upvalue* uv = (*call_stack.back().upvals)[B];
    if (uv->closed) uv->val = regs[base + A];
    else            regs[uv->frame_base + uv->reg_idx] = regs[base + A];
    NEXT();
}

op_NEW_CLASS:
    regs[base + A] = Value::makeClass();
    NEXT();

op_CALL_METHOD: {
    uint32_t fp_addr = 0;
    {
        int cb   = base + A;
        int argc = C;
        bool is_instance = isInstance(regs[cb]) || regs[cb].isString();
        Value fn = regs[cb + 1];
        // méthode statique : pas d'injection de self, même si appelée sur une instance
        bool fn_is_static = false;
        if (fn.isFuncVal())  fn_is_static = ch->funcs[(uint8_t)fn.asInt()].is_static;
        else if (fn.isClosure()) fn_is_static = ch->funcs[fn.asClosure()->func_idx].is_static;
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
            goto call_method_done;
        }
        {
            std::unique_ptr<std::vector<Upvalue*>> fuv;
            uint8_t fi;
            if (fn.isFuncVal()) fi = (uint8_t)fn.asInt();
            else if (fn.isClosure()) { fi = fn.asClosure()->func_idx; const auto& u = fn.asClosure()->upvals; if (!u.empty()) fuv = std::make_unique<std::vector<Upvalue*>>(u); }
            else throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: method call on non-function value");
            const FuncProto& fp = ch->funcs[fi];
            size_t needed = (size_t)(cb + std::max((int)fp.reg_count, total));
            growRegs(needed);
            if (total < fp.n_fixed) {
                auto& defs = ch->func_defaults[fp.defaults_idx];
                for (int i = total; i < fp.n_fixed; ++i)
                    regs[cb + i] = (i < (int)defs.size()) ? defs[i] : Value{};
            }
            int n_extra3 = 0;
            int va_base3 = cb + fp.reg_count;
            if (fp.variadic && total > fp.n_fixed) {
                n_extra3 = total - fp.n_fixed;
                growRegs((size_t)(va_base3 + n_extra3));
                for (int i = n_extra3 - 1; i >= 0; --i)
                    regs[va_base3 + i] = std::move(regs[cb + fp.n_fixed + i]);
            }
            size_t full_needed = (size_t)(cb + fp.reg_count);
            growRegs(full_needed);
            {
                Frame fr;
                fr.return_ip    = ip;
                fr.reg_base     = cb;
                fr.varargs_base = va_base3;
                fr.n_varargs    = n_extra3;
                fr.upvals       = std::move(fuv);
                call_stack.push_back(std::move(fr));
            }
            fp_addr = fp.addr;
        }
    }
    ip = fp_addr;
    call_method_done:
    base = call_stack.back().reg_base;
    NEXT();
}

op_MAKE_RANGE: {
    {
        bool has_step  = (C >> 1) & 1;
        bool incl_right = C & 1;
        int line_ = errLine();
        auto toDouble_ = [&](const Value& v) -> double {
            if (v.isInteger()) return (double)v.asInt();
            if (v.isFloat())   return v.asFloat();
            throw std::runtime_error("line " + std::to_string(line_) + ": runtime: range bound must be a number");
        };
        double start = toDouble_(regs[base + B]);
        double end   = toDouble_(regs[base + B + 1]);
        double step  = has_step ? toDouble_(regs[base + B + 2]) : 1.0;
        if (step == 0.0) throw std::runtime_error("line " + std::to_string(line_) + ": runtime: range step cannot be zero");
        Range* r = new Range{1, start, end, step, incl_right};
        regs[base + A] = Value::makeRange(r);
    }
    NEXT();
}

op_HALT:
    closeUpvals();
    call_stack.pop_back();
    return;

    } catch (const std::runtime_error& e) {
        if (handler_stack.empty()) throw;
        Handler h = handler_stack.back(); handler_stack.pop_back();
        while (call_stack.size() > h.call_depth) { closeUpvals(); call_stack.pop_back(); }
        if (regs.size() > h.regs_size) regs.resize(h.regs_size);
        regs[h.reg_base + h.catch_reg] = Value(std::string(e.what()));
        ip = h.catch_addr;
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
                globals[gi]      = Value::makeBuiltin(b.fn);
                globals_init[gi] = true;
            }
    for (int gi = 0; gi < (int)owned_chunk.identifiers.size(); ++gi)
        for (auto& name : builtinModuleNames())
            if (owned_chunk.identifiers[gi] == name) {
                globals[gi]      = makeBuiltinModule(name);
                globals_init[gi] = true;
            }
    string_module_ = makeBuiltinModule("string");
    {
        Value core = makeBuiltinModule("core");
        for (auto& [k, v] : core.asMap()->data) {
            if (!k.isString()) continue;
            const std::string& fname = k.asString();
            for (int gi = 0; gi < (int)owned_chunk.identifiers.size(); ++gi)
                if (owned_chunk.identifiers[gi] == fname) {
                    globals[gi]      = v;
                    globals_init[gi] = true;
                }
        }
    }
    growRegs(owned_chunk.top_reg_count);
    call_stack.reserve(1000);
    call_stack.push_back(Frame{});


    runGoto(0);
}
