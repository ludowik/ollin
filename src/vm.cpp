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

// ── invokeStr : mini-loop to call __str without recursion ─────────────────────
std::string VM::invokeStr(const Value& obj) {
    Value cls = obj.mapGet(MK().class_);
    if (cls.isNil()) return "{map}";
    Value str_fn = protoChainGet(cls, MK().str_);
    if (str_fn.isNil() || !str_fn.isCallable()) {
        Value nm = cls.mapGet(MK().name_);
        return nm.isString() ? "{" + nm.asString() + "}" : "{object}";
    }
    uint8_t fi;
    std::vector<Upvalue*> frame_upvals;
    if (str_fn.isFuncVal()) {
        fi = (uint8_t)str_fn.asInt();
    } else if (str_fn.isClosure()) {
        fi = str_fn.asClosure()->func_idx;
        frame_upvals = str_fn.asClosure()->upvals;
    } else {
        Value nm = cls.mapGet(MK().name_);
        return nm.isString() ? "{" + nm.asString() + "}" : "{object}";
    }
    const FuncProto& fp = ch->funcs[fi];
    int call_base = (int)regs.size();
    size_t needed = (size_t)(call_base + std::max((int)fp.reg_count, 1));
    regs.resize(needed);
    regs[call_base] = obj;
    uint32_t saved_ip = ip;
    call_stack.push_back({0, call_base, {}, std::move(frame_upvals), {}, {}});
    ip = fp.addr;
    runSwitch(call_stack.size() - 1);
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
static std::string valueToString(const Value& v) {
    if (v.isNil())      return "nil";
    if (v.isString())   return v.asString();
    if (v.isClass())    return "{class}";
    if (v.isMap()) {
        if (s_current_vm) {
            Value cls = v.mapGet(MK().class_);
            if (!cls.isNil()) return s_current_vm->invokeStr(v);
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

// ── applyFormat ───────────────────────────────────────────────────────────────
static std::string applyFormat(const std::string& fmt, const std::vector<Value>& args, int offset) {
    std::string out;
    int auto_idx = 0;
    for (size_t i = 0; i < fmt.size(); ++i) {
        if (fmt[i] == '{') {
            size_t j = fmt.find('}', i + 1);
            if (j != std::string::npos) {
                std::string spec = fmt.substr(i + 1, j - i - 1);
                int idx;
                if (spec.empty()) {
                    idx = auto_idx++;
                } else {
                    try { idx = std::stoi(spec); }
                    catch (...) {
                        throw std::runtime_error("printf: invalid index '{" + spec + "}'");
                    }
                }
                long long ai = (long long)idx + offset;
                if (ai >= 0 && ai < (long long)args.size())
                    out += valueToString(args[(int)ai]);
                i = j;
                continue;
            }
        }
        out += fmt[i];
    }
    return out;
}

// ── Builtins ──────────────────────────────────────────────────────────────────

void printOneValue(const Value& v) {
    if (v.isNil())       std::cout << "nil";
    else if (v.isString()) std::cout << v.asString();
    else if (v.isClass()) std::cout << "{class}";
    else if (v.isMap()) {
        if (s_current_vm) {
            Value cls = v.mapGet(MK().class_);
            if (!cls.isNil()) { std::cout << s_current_vm->invokeStr(v); return; }
        }
        std::cout << "{map}";
    } else if (v.isArray())  std::cout << "{array}";
    else if (v.isFuncVal() || v.isClosure() || v.isBuiltin())
        std::cout << "{function}";
    else if (v.isInteger())  std::cout << v.asInt();
    else {
        double d = v.asFloat();
        if (d == (long long)d && d >= -1e15 && d <= 1e15) std::cout << (long long)d;
        else                                               std::cout << d;
    }
}

static Value builtin_print(Value* args, int argc) {
    for (int i = 0; i < argc; ++i) {
        if (i) std::cout << ' ';
        printOneValue(args[i]);
    }
    std::cout << '\n';
    return Value{};
}

static Value builtin_printf(Value* args, int argc) {
    if (argc < 1 || !args[0].isString())
        throw std::runtime_error("printf: first arg must be string");
    std::vector<Value> vargs(args, args + argc);
    std::cout << applyFormat(args[0].asString(), vargs, 1) << '\n';
    return Value{};
}

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
    { "print",  builtin_print  },
    { "printf", builtin_printf },
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
    std::vector<Upvalue*> fuv;
    if (fn.isFuncVal())      fi = (uint8_t)fn.asInt();
    else { fi = fn.asClosure()->func_idx; fuv = fn.asClosure()->upvals; }
    const FuncProto& fp = ch->funcs[fi];
    int nb = (int)regs.size();
    regs.resize(nb + std::max((int)fp.reg_count, 2));
    regs[nb]     = std::move(lhs);
    regs[nb + 1] = std::move(rhs);
    call_stack.push_back({ip, nb, {}, std::move(fuv), {}, {}, dest});
    return fp.addr;
}

uint32_t VM::tryMetaUnary(const Value& name, int dest, Value lhs) {
    Value fn = protoChainGet(lhs.mapGet(MK().class_), name);
    if (!fn.isCallable()) return 0;
    uint8_t fi;
    std::vector<Upvalue*> fuv;
    if (fn.isFuncVal())      fi = (uint8_t)fn.asInt();
    else { fi = fn.asClosure()->func_idx; fuv = fn.asClosure()->upvals; }
    const FuncProto& fp = ch->funcs[fi];
    int nb = (int)regs.size();
    regs.resize(nb + std::max((int)fp.reg_count, 1));
    regs[nb] = std::move(lhs);
    call_stack.push_back({ip, nb, {}, std::move(fuv), {}, {}, dest});
    return fp.addr;
}

// ── closeUpvals : close and free all open upvalues of the top frame ──────────
void VM::closeUpvals() {
    for (auto* uv : call_stack.back().open_upvals) {
        if (!uv->closed) {
            uv->val    = regs[uv->frame_base + uv->reg_idx];
            uv->closed = true;
        }
        if (--uv->refcount == 0) delete uv;
    }
}

// ── Helper: resolve function value → func_idx + upvals ───────────────────────
static uint8_t resolveFuncVal(const Value& fv, std::vector<Upvalue*>& out_upvals) {
    if (fv.isFuncVal())  return (uint8_t)fv.asInt();
    if (fv.isClosure()) {
        out_upvals = fv.asClosure()->upvals;
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

// ── VM::errLine / VM::current / VM::callValue / VM::runSwitch ────────────────

int VM::errLine() const {
    uint32_t idx = ip > 0 ? ip - 1 : 0;
    return (idx < (uint32_t)ch->lines.size()) ? ch->lines[idx] : 0;
}

VM* VM::current() { return s_current_vm; }

Value VM::callValue(const Value& fn) {
    if (fn.isBuiltin())
        return fn.asBuiltin()(nullptr, 0);
    uint8_t fi;
    std::vector<Upvalue*> frame_upvals;
    if (fn.isFuncVal()) {
        fi = (uint8_t)fn.asInt();
    } else if (fn.isClosure()) {
        fi = fn.asClosure()->func_idx;
        frame_upvals = fn.asClosure()->upvals;
    } else {
        throw std::runtime_error("callValue: not callable");
    }
    const FuncProto& fp = ch->funcs[fi];
    int call_base = (int)regs.size();
    regs.resize(call_base + std::max((int)fp.reg_count, 1));
    uint32_t saved_ip = ip;
    call_stack.push_back({saved_ip, call_base, {}, std::move(frame_upvals), {}, {}});
    ip = fp.addr;
    runSwitch(call_stack.size() - 1);
    Value result = (int)regs.size() > call_base ? regs[call_base] : Value{};
    regs.resize(call_base);
    ip = saved_ip;
    return result;
}

void VM::runSwitch(size_t stop_depth) {
    while (call_stack.size() > stop_depth) {
        Instr    instr = ch->code[ip++];
        uint8_t  A     = iA(instr),  B = iB(instr), C = iC(instr);
        uint16_t Bx    = iBx(instr);
        int      base  = call_stack.back().reg_base;

        switch (static_cast<Op>(iOP(instr))) {

        case Op::LOAD_K:
            regs[base+A] = ch->constants[Bx];
            break;
        case Op::LOAD_NIL:
            regs[base+A] = Value{};
            break;
        case Op::MOVE:
            regs[base+A] = regs[base+B];
            break;
        case Op::LOAD_GLOBAL:
            if (!globals_init[Bx])
                throw std::runtime_error("line " + std::to_string(errLine()) + ": undefined: " + ch->identifiers[Bx]);
            regs[base+A] = globals[Bx];
            break;
        case Op::STORE_GLOBAL:
            globals[Bx] = regs[base+A];
            globals_init[Bx] = true;
            break;

        case Op::ADD: {
            if (regs[base+B].isString() || regs[base+C].isString()) {
                regs[base+A] = Value(valueToString(regs[base+B]) + valueToString(regs[base+C]));
                break;
            }
            if (isInstance(regs[base+B])) {
                if (uint32_t addr = tryMetaBinary(MK().add_, base+A, regs[base+B], regs[base+C]))
                    { ip = addr; break; }
            }
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            regs[base+A] = (bv.isInteger() && cv.isInteger())
                ? Value(bv.asInt() + cv.asInt())
                : Value(asDouble(bv) + asDouble(cv));
            break;
        }
        case Op::SUB: {
            if (isInstance(regs[base+B])) {
                if (uint32_t addr = tryMetaBinary(MK().sub_, base+A, regs[base+B], regs[base+C]))
                    { ip = addr; break; }
            }
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            regs[base+A] = (bv.isInteger() && cv.isInteger())
                ? Value(bv.asInt() - cv.asInt())
                : Value(asDouble(bv) - asDouble(cv));
            break;
        }
        case Op::MUL: {
            if (isInstance(regs[base+B])) {
                if (uint32_t addr = tryMetaBinary(MK().mul_, base+A, regs[base+B], regs[base+C]))
                    { ip = addr; break; }
            }
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            regs[base+A] = (bv.isInteger() && cv.isInteger())
                ? Value(bv.asInt() * cv.asInt())
                : Value(asDouble(bv) * asDouble(cv));
            break;
        }
        case Op::DIV: {
            if (isInstance(regs[base+B])) {
                if (uint32_t addr = tryMetaBinary(MK().div_, base+A, regs[base+B], regs[base+C]))
                    { ip = addr; break; }
            }
            double dv = asDouble(regs[base+C]);
            if (dv == 0.0) throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: division by zero");
            regs[base+A] = Value(asDouble(regs[base+B]) / dv);
            break;
        }
        case Op::MOD: {
            if (isInstance(regs[base+B])) {
                if (uint32_t addr = tryMetaBinary(MK().mod_, base+A, regs[base+B], regs[base+C]))
                    { ip = addr; break; }
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
            break;
        }
        case Op::NEGATE: {
            if (isInstance(regs[base+B])) {
                if (uint32_t addr = tryMetaUnary(MK().neg_, base+A, regs[base+B]))
                    { ip = addr; break; }
            }
            const Value& bv = regs[base+B];
            regs[base+A] = bv.isInteger() ? Value(-bv.asInt()) : Value(-asDouble(bv));
            break;
        }
        case Op::NOT:
            regs[base+A] = Value((int64_t)(isFalsy(regs[base+B]) ? 1 : 0));
            break;
        case Op::AND:
            regs[base+A] = Value((int64_t)(!isFalsy(regs[base+B]) && !isFalsy(regs[base+C]) ? 1 : 0));
            break;
        case Op::OR:
            regs[base+A] = Value((int64_t)(!isFalsy(regs[base+B]) || !isFalsy(regs[base+C]) ? 1 : 0));
            break;

        case Op::EQ: {
            if (isInstance(regs[base+B])) {
                if (uint32_t addr = tryMetaBinary(MK().eq_, base+A, regs[base+B], regs[base+C]))
                    { ip = addr; break; }
            }
            regs[base+A] = Value((int64_t)(valuesEqual(regs[base+B], regs[base+C]) ? 1 : 0));
            break;
        }
        case Op::NEQ:
            regs[base+A] = Value((int64_t)(valuesEqual(regs[base+B], regs[base+C]) ? 0 : 1));
            break;
        case Op::GT: {
            if (isInstance(regs[base+C])) {
                if (uint32_t addr = tryMetaBinary(MK().lt_, base+A, regs[base+C], regs[base+B]))
                    { ip = addr; break; }
            }
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            regs[base+A] = Value((int64_t)((bv.isInteger() && cv.isInteger())
                ? bv.asInt()  > cv.asInt()
                : asDouble(bv) > asDouble(cv)));
            break;
        }
        case Op::LT: {
            if (isInstance(regs[base+B])) {
                if (uint32_t addr = tryMetaBinary(MK().lt_, base+A, regs[base+B], regs[base+C]))
                    { ip = addr; break; }
            }
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            regs[base+A] = Value((int64_t)((bv.isInteger() && cv.isInteger())
                ? bv.asInt()  < cv.asInt()
                : asDouble(bv) < asDouble(cv)));
            break;
        }
        case Op::GE: {
            if (isInstance(regs[base+C])) {
                if (uint32_t addr = tryMetaBinary(MK().le_, base+A, regs[base+C], regs[base+B]))
                    { ip = addr; break; }
            }
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            regs[base+A] = Value((int64_t)((bv.isInteger() && cv.isInteger())
                ? bv.asInt()  >= cv.asInt()
                : asDouble(bv) >= asDouble(cv)));
            break;
        }
        case Op::LE: {
            if (isInstance(regs[base+B])) {
                if (uint32_t addr = tryMetaBinary(MK().le_, base+A, regs[base+B], regs[base+C]))
                    { ip = addr; break; }
            }
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            regs[base+A] = Value((int64_t)((bv.isInteger() && cv.isInteger())
                ? bv.asInt()  <= cv.asInt()
                : asDouble(bv) <= asDouble(cv)));
            break;
        }

        case Op::JUMP:
            ip = Bx;
            break;
        case Op::JUMP_IF_FALSE:
            if (isFalsy(regs[base+A])) ip = Bx;
            break;

        case Op::CALL_FUNC: {
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
            std::unique_ptr<std::vector<Value>> varargs;
            if (fp.variadic && argc > fp.n_fixed) {
                varargs = std::make_unique<std::vector<Value>>();
                for (int i = fp.n_fixed; i < argc; ++i)
                    varargs->push_back(std::move(regs[new_base + i]));
            }
            size_t full_needed = (size_t)(new_base + fp.reg_count);
            if (regs.size() < full_needed) regs.resize(full_needed);
            call_stack.push_back({ip, new_base, std::move(varargs), {}, {}});
            ip = fp.addr;
            break;
        }
        case Op::RETURN: {
            closeUpvals();
            Value ctor   = std::move(call_stack.back().ctor_result);
            int ret_dest = call_stack.back().return_dest;
            int n = B;
            if (n > 0 && A != 0)
                for (int i = 0; i < n; ++i)
                    regs[base + i] = std::move(regs[base + A + i]);
            uint32_t rip = call_stack.back().return_ip;
            call_stack.pop_back();
            if (!ctor.isNil())  regs[base + 0] = std::move(ctor);
            if (ret_dest >= 0)  regs[ret_dest] = regs[base + 0];
            ip = rip;
            break;
        }
        case Op::LOAD_VARARGS: {
            auto& va = call_stack.back().varargs;
            if (va) {
                int count = B;
                int n = (count == 0) ? (int)va->size() : std::min(count, (int)va->size());
                size_t needed = (size_t)(base + A + n);
                if (regs.size() < needed) regs.resize(needed);
                for (int i = 0; i < n; ++i) regs[base + A + i] = (*va)[i];
            }
            break;
        }
        case Op::RETURN_V: {
            closeUpvals();
            auto& va   = call_stack.back().varargs;
            int n_va   = va ? (int)va->size() : 0;
            int n_expl = B;
            int total  = n_expl + n_va;
            std::vector<Value> rvs(total);
            for (int i = 0; i < n_expl; ++i) rvs[i] = std::move(regs[base + A + i]);
            if (va) for (int i = 0; i < n_va; ++i) rvs[n_expl + i] = std::move((*va)[i]);
            uint32_t rip = call_stack.back().return_ip;
            int rbase    = call_stack.back().reg_base;
            call_stack.pop_back();
            if ((int)regs.size() < rbase + total) regs.resize(rbase + total);
            for (int i = 0; i < total; ++i) regs[rbase + i] = std::move(rvs[i]);
            ip = rip;
            break;
        }
        case Op::TRY:
            handler_stack.push_back({Bx, A, base, regs.size(), call_stack.size()});
            break;
        case Op::POP_TRY:
            handler_stack.pop_back();
            break;
        case Op::THROW: {
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
            break;
        }

        case Op::NEW_MAP:
            regs[base+A] = Value::makeMap();
            break;
        case Op::GET_INDEX: {
            const Value& obj = regs[base+B]; const Value& key = regs[base+C];
            if (obj.isMap() || obj.isClass()) {
                regs[base+A] = protoChainGet(obj, key);
            } else if (obj.isArray()) {
                if (!key.isInteger()) throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: array index must be integer");
                regs[base+A] = obj.arrayGet(key.asInt());
            } else {
                throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: [] on non-indexable");
            }
            break;
        }
        case Op::SET_INDEX: {
            Value& obj = regs[base+A]; const Value& key = regs[base+B];
            if (obj.isMap() || obj.isClass()) {
                obj.mapSet(key, regs[base+C]);
            } else if (obj.isArray()) {
                if (!key.isInteger()) throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: array index must be integer");
                obj.arraySet(key.asInt(), regs[base+C]);
            } else {
                throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: []= on non-indexable");
            }
            break;
        }
        case Op::MAKE_ITER:
            regs[base+A] = Value::makeIterFrom(regs[base+B]);
            break;

        case Op::BAND: {
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            if (!bv.isInteger() || !cv.isInteger())
                throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: & requires integer operands");
            regs[base+A] = Value(bv.asInt() & cv.asInt());
            break;
        }
        case Op::BOR: {
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            if (!bv.isInteger() || !cv.isInteger())
                throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: | requires integer operands");
            regs[base+A] = Value(bv.asInt() | cv.asInt());
            break;
        }
        case Op::BXOR: {
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            if (!bv.isInteger() || !cv.isInteger())
                throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: ^ requires integer operands");
            regs[base+A] = Value(bv.asInt() ^ cv.asInt());
            break;
        }
        case Op::BNOT: {
            const Value& bv = regs[base+B];
            if (!bv.isInteger())
                throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: ~ requires integer operand");
            regs[base+A] = Value(~bv.asInt());
            break;
        }
        case Op::BLSHIFT: {
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            if (!bv.isInteger() || !cv.isInteger())
                throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: << requires integer operands");
            regs[base+A] = Value((int64_t)((uint64_t)bv.asInt() << (cv.asInt() & 63)));
            break;
        }
        case Op::BRSHIFT: {
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            if (!bv.isInteger() || !cv.isInteger())
                throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: >> requires integer operands");
            regs[base+A] = Value(bv.asInt() >> (cv.asInt() & 63));
            break;
        }

        case Op::NEW_ARRAY:
            regs[base+A] = Value::makeArray();
            break;
        case Op::ARRAY_PUSH:
            regs[base+A].arrayPush(regs[base+B]);
            break;
        case Op::FOR_ITER_NEXT: {
            Value key, val;
            if (!regs[base+A].iptr->next(key, val)) {
                ip = Bx;
            } else {
                regs[base+A+1] = std::move(key);
                regs[base+A+2] = std::move(val);
            }
            break;
        }
        case Op::FOR_ITER_NEXT1: {
            Value key, val;
            if (!regs[base+A].iptr->next(key, val)) {
                ip = Bx;
            } else {
                regs[base+A+1] = regs[base+A].iptr->primary_is_val()
                                  ? std::move(val) : std::move(key);
            }
            break;
        }
        case Op::LOAD_FUNC:
            regs[base+A] = Value::makeFunc((uint8_t)Bx);
            break;

        case Op::CALL_DYN: {
            if (regs[base+B].isBuiltin()) {
                regs[base+A] = regs[base+B].asBuiltin()(&regs[base+A], C);
                break;
            }
            if (regs[base+B].isClass()) {
                Value cls  = regs[base+B];
                Value inst = Value::makeMap();
                inst.mapSet(MK().class_, cls);
                int new_base = base + A;
                int argc = C;
                Value init_fn = protoChainGet(cls, MK().init_);
                if (!init_fn.isCallable()) { regs[new_base] = std::move(inst); break; }
                std::vector<Upvalue*> fuv;
                uint8_t fi = resolveFuncVal(init_fn, fuv);
                const FuncProto& fp = ch->funcs[fi];
                int total = argc + 1;
                size_t needed = (size_t)(new_base + std::max((int)fp.reg_count, total));
                if (regs.size() < needed) regs.resize(needed);
                for (int i = argc - 1; i >= 0; --i)
                    regs[new_base + 1 + i] = std::move(regs[new_base + i]);
                regs[new_base + 0] = inst;
                if (total < fp.n_fixed) {
                    auto& defs = ch->func_defaults[fp.defaults_idx];
                    for (int i = total; i < fp.n_fixed; ++i)
                        regs[new_base + i] = (i < (int)defs.size()) ? defs[i] : Value{};
                }
                size_t full_needed = (size_t)(new_base + fp.reg_count);
                if (regs.size() < full_needed) regs.resize(full_needed);
                call_stack.push_back({ip, new_base, {}, std::move(fuv), {}, inst});
                ip = fp.addr;
                break;
            }
            {
                int new_base = base + A;
                int argc = C;
                std::vector<Upvalue*> fuv;
                uint8_t fi = resolveFuncVal(regs[base + B], fuv);
                const FuncProto& fp = ch->funcs[fi];
                size_t needed = (size_t)(new_base + std::max((int)fp.reg_count, argc));
                if (regs.size() < needed) regs.resize(needed);
                if (argc < fp.n_fixed) {
                    auto& defs = ch->func_defaults[fp.defaults_idx];
                    for (int i = argc; i < fp.n_fixed; ++i)
                        regs[new_base + i] = (i < (int)defs.size()) ? defs[i] : Value{};
                }
                std::unique_ptr<std::vector<Value>> varargs;
                if (fp.variadic && argc > fp.n_fixed) {
                    varargs = std::make_unique<std::vector<Value>>();
                    for (int i = fp.n_fixed; i < argc; ++i)
                        varargs->push_back(std::move(regs[new_base + i]));
                }
                size_t full_needed = (size_t)(new_base + fp.reg_count);
                if (regs.size() < full_needed) regs.resize(full_needed);
                call_stack.push_back({ip, new_base, std::move(varargs), std::move(fuv), {}, {}});
                ip = fp.addr;
            }
            break;
        }

        case Op::MAKE_CLOSURE: {
            uint8_t fi = (uint8_t)Bx;
            auto* cl = new Closure(fi);
            for (auto& desc : ch->funcs[fi].upvals) {
                Upvalue* uv = nullptr;
                if (desc.is_local) {
                    for (auto* ou : call_stack.back().open_upvals)
                        if (!ou->closed && ou->frame_base == base && ou->reg_idx == desc.idx)
                            { uv = ou; break; }
                    if (!uv) {
                        uv = new Upvalue;
                        uv->frame_base = base;
                        uv->reg_idx    = desc.idx;
                        call_stack.back().open_upvals.push_back(uv);
                    }
                    uv->refcount++;
                } else {
                    uv = call_stack.back().upvals[desc.idx];
                    uv->refcount++;
                }
                cl->upvals.push_back(uv);
            }
            regs[base+A] = Value::makeClosure(cl);
            break;
        }
        case Op::GET_UPVAL: {
            Upvalue* uv = call_stack.back().upvals[B];
            regs[base+A] = uv->closed ? uv->val : regs[uv->frame_base + uv->reg_idx];
            break;
        }
        case Op::SET_UPVAL: {
            Upvalue* uv = call_stack.back().upvals[B];
            if (uv->closed) uv->val = regs[base+A];
            else            regs[uv->frame_base + uv->reg_idx] = regs[base+A];
            break;
        }
        case Op::NEW_CLASS:
            regs[base+A] = Value::makeClass();
            break;
        case Op::CALL_METHOD: {
            int cb   = base + A;
            int argc = C;
            bool is_instance = isInstance(regs[cb]);
            Value fn = regs[cb + 1];
            int total;
            if (is_instance) {
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
                break;
            }
            std::vector<Upvalue*> fuv;
            uint8_t fi;
            if (fn.isFuncVal())       fi = (uint8_t)fn.asInt();
            else if (fn.isClosure())  { fi = fn.asClosure()->func_idx; fuv = fn.asClosure()->upvals; }
            else throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: method call on non-function value");
            const FuncProto& fp = ch->funcs[fi];
            size_t needed = (size_t)(cb + std::max((int)fp.reg_count, total));
            if (regs.size() < needed) regs.resize(needed);
            if (total < fp.n_fixed) {
                auto& defs = ch->func_defaults[fp.defaults_idx];
                for (int i = total; i < fp.n_fixed; ++i)
                    regs[cb + i] = (i < (int)defs.size()) ? defs[i] : Value{};
            }
            size_t full_needed = (size_t)(cb + fp.reg_count);
            if (regs.size() < full_needed) regs.resize(full_needed);
            call_stack.push_back({ip, cb, {}, std::move(fuv), {}, {}});
            ip = fp.addr;
            break;
        }
        case Op::MAKE_RANGE: {
            bool has_step    = (C >> 1) & 1;
            bool incl_right2 = C & 1;
            int line_s = errLine();
            auto toDouble_s = [&](const Value& v) -> double {
                if (v.isInteger()) return (double)v.asInt();
                if (v.isFloat())   return v.asFloat();
                throw std::runtime_error("line " + std::to_string(line_s) + ": runtime: range bound must be a number");
            };
            double start2 = toDouble_s(regs[base + B]);
            double end2   = toDouble_s(regs[base + B + 1]);
            double step2  = has_step ? toDouble_s(regs[base + B + 2]) : 1.0;
            if (step2 == 0.0) throw std::runtime_error("line " + std::to_string(line_s) + ": runtime: range step cannot be zero");
            Range* r2 = new Range{1, start2, end2, step2, incl_right2};
            regs[base + A] = Value::makeRange(r2);
            break;
        }
        case Op::HALT:
            return;
        default:
            throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: unknown opcode (" +
                std::to_string((int)iOP(ch->code[ip-1])) + ")");
        }
    }
}

// ── execute ───────────────────────────────────────────────────────────────────
void VM::execute(const Chunk& chunk) {
    ch = &chunk;
    ip = 0;
    s_current_vm = this;
    globals.assign(chunk.identifiers.size(), Value{});
    globals_init.assign(chunk.identifiers.size(), false);
    for (int gi = 0; gi < (int)chunk.identifiers.size(); ++gi)
        for (auto& b : k_builtins)
            if (chunk.identifiers[gi] == b.name) {
                globals[gi]      = Value::makeBuiltin(b.fn);
                globals_init[gi] = true;
            }
    for (int gi = 0; gi < (int)chunk.identifiers.size(); ++gi)
        for (auto& name : builtinModuleNames())
            if (chunk.identifiers[gi] == name) {
                globals[gi]      = makeBuiltinModule(name);
                globals_init[gi] = true;
            }
    regs.resize(chunk.top_reg_count);
    call_stack.reserve(1000);
    call_stack.push_back({0, 0, {}, {}, {}});

    auto errLine = [&]() -> int {
        uint32_t idx = ip > 0 ? ip - 1 : 0;
        return (idx < (uint32_t)ch->lines.size()) ? ch->lines[idx] : 0;
    };

#ifdef __GNUC__
// ── Computed-goto dispatch ────────────────────────────────────────────────────
// Table in the exact order of enum Op (chunk.h).
// Each handler ends with NEXT() → direct jump to the next handler.
#define NEXT() do {                                          \
    Instr _ni = ch->code[ip++];                             \
    A  = iA(_ni); B = iB(_ni); C = iC(_ni); Bx = iBx(_ni); \
    base = call_stack.back().reg_base;                      \
    goto *dt[iOP(_ni)];                                     \
} while(0)

    static const void* const dt[] = {
        &&op_LOAD_K, &&op_LOAD_NIL, &&op_MOVE,
        &&op_LOAD_GLOBAL, &&op_STORE_GLOBAL,
        &&op_ADD, &&op_SUB, &&op_MUL, &&op_DIV, &&op_MOD,
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

    uint8_t A, B, C; uint16_t Bx; int base;
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
        regs[base+A] = Value(valueToString(regs[base+B]) + valueToString(regs[base+C]));
        NEXT();
    }
    if (isInstance(regs[base+B])) {
        if (uint32_t addr = tryMetaBinary(MK().add_, base+A, regs[base+B], regs[base+C]))
            { ip = addr; NEXT(); }
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
            { ip = addr; NEXT(); }
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
            { ip = addr; NEXT(); }
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
            { ip = addr; NEXT(); }
    }
    double dv = asDouble(regs[base+C]);
    if (dv == 0.0) throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: division by zero");
    regs[base+A] = Value(asDouble(regs[base+B]) / dv);
    NEXT();
}

op_MOD: {
    if (isInstance(regs[base+B])) {
        if (uint32_t addr = tryMetaBinary(MK().mod_, base+A, regs[base+B], regs[base+C]))
            { ip = addr; NEXT(); }
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

op_NEGATE: {
    if (isInstance(regs[base+B])) {
        if (uint32_t addr = tryMetaUnary(MK().neg_, base+A, regs[base+B]))
            { ip = addr; NEXT(); }
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
            { ip = addr; NEXT(); }
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
            { ip = addr; NEXT(); }
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
            { ip = addr; NEXT(); }
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
            { ip = addr; NEXT(); }
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
            { ip = addr; NEXT(); }
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
        std::unique_ptr<std::vector<Value>> varargs;
        if (fp.variadic && argc > fp.n_fixed) {
            varargs = std::make_unique<std::vector<Value>>();
            for (int i = fp.n_fixed; i < argc; ++i)
                varargs->push_back(std::move(regs[new_base + i]));
        }
        size_t full_needed = (size_t)(new_base + fp.reg_count);
        if (regs.size() < full_needed) regs.resize(full_needed);
        call_stack.push_back({ip, new_base, std::move(varargs), {}, {}});
        fp_addr = fp.addr;
    }
    ip = fp_addr;
    NEXT();
}

op_RETURN: {
    {
        closeUpvals();
        Value ctor   = std::move(call_stack.back().ctor_result);
        int ret_dest = call_stack.back().return_dest;
        int n = B;
        if (n > 0 && A != 0)
            for (int i = 0; i < n; ++i)
                regs[base + i] = std::move(regs[base + A + i]);
        uint32_t rip = call_stack.back().return_ip;
        call_stack.pop_back();
        if (!ctor.isNil())  regs[base + 0] = std::move(ctor);
        if (ret_dest >= 0)  regs[ret_dest] = regs[base + 0];
        ip = rip;
    }
    NEXT();
}

op_LOAD_VARARGS: {
    auto& va = call_stack.back().varargs;
    if (va) {
        int count = B;
        int n = (count == 0) ? (int)va->size() : std::min(count, (int)va->size());
        size_t needed = (size_t)(base + A + n);
        if (regs.size() < needed) regs.resize(needed);
        for (int i = 0; i < n; ++i) regs[base + A + i] = (*va)[i];
    }
    NEXT();
}

op_RETURN_V: {
    {
        closeUpvals();
        auto& va   = call_stack.back().varargs;
        int n_va   = va ? (int)va->size() : 0;
        int n_expl = B;
        int total  = n_expl + n_va;
        std::vector<Value> rvs(total);
        for (int i = 0; i < n_expl; ++i) rvs[i] = std::move(regs[base + A + i]);
        if (va) for (int i = 0; i < n_va; ++i) rvs[n_expl + i] = std::move((*va)[i]);
        uint32_t rip   = call_stack.back().return_ip;
        int      rbase = call_stack.back().reg_base;
        call_stack.pop_back();
        if ((int)regs.size() < rbase + total) regs.resize(rbase + total);
        for (int i = 0; i < total; ++i) regs[rbase + i] = std::move(rvs[i]);
        ip = rip;
    }
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
    } else if (obj.isArray()) {
        if (!key.isInteger()) throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: array index must be integer");
        regs[base + A] = obj.arrayGet(key.asInt());
    } else {
        throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: [] on non-indexable");
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
        throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: []= on non-indexable");
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

op_FOR_ITER_NEXT: {
    {
        Value key, val;
        if (!regs[base + A].iptr->next(key, val)) {
            ip = Bx;
        } else {
            regs[base + A + 1] = std::move(key);
            regs[base + A + 2] = std::move(val);
        }
    }
    NEXT();
}

op_FOR_ITER_NEXT1: {
    {
        Value key, val;
        if (!regs[base + A].iptr->next(key, val)) {
            ip = Bx;
        } else {
            regs[base + A + 1] = regs[base + A].iptr->primary_is_val()
                                  ? std::move(val) : std::move(key);
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
            std::vector<Upvalue*> fuv;
            uint8_t fi = resolveFuncVal(init_fn, fuv);
            const FuncProto& fp = ch->funcs[fi];
            int total = argc + 1;
            size_t needed = (size_t)(ctor_base + std::max((int)fp.reg_count, total));
            if (regs.size() < needed) regs.resize(needed);
            for (int i = argc - 1; i >= 0; --i)
                regs[ctor_base + 1 + i] = std::move(regs[ctor_base + i]);
            regs[ctor_base + 0] = inst;
            if (total < fp.n_fixed) {
                auto& defs = ch->func_defaults[fp.defaults_idx];
                for (int i = total; i < fp.n_fixed; ++i)
                    regs[ctor_base + i] = (i < (int)defs.size()) ? defs[i] : Value{};
            }
            size_t full_needed = (size_t)(ctor_base + fp.reg_count);
            if (regs.size() < full_needed) regs.resize(full_needed);
            ctor_addr = fp.addr;
            call_stack.push_back({ip, ctor_base, {}, std::move(fuv), {}, inst});
            do_call = true;
        }
        if (do_call) { ip = ctor_addr; NEXT(); }
    }
    {
        // Regular function/closure call
        uint32_t fp_addr;
        {
            int new_base = base + A;
            int argc = C;
            std::vector<Upvalue*> fuv;
            uint8_t fi = resolveFuncVal(regs[base + B], fuv);
            const FuncProto& fp = ch->funcs[fi];
            size_t needed = (size_t)(new_base + std::max((int)fp.reg_count, argc));
            if (regs.size() < needed) regs.resize(needed);
            if (argc < fp.n_fixed) {
                auto& defs = ch->func_defaults[fp.defaults_idx];
                for (int i = argc; i < fp.n_fixed; ++i)
                    regs[new_base + i] = (i < (int)defs.size()) ? defs[i] : Value{};
            }
            std::unique_ptr<std::vector<Value>> varargs;
            if (fp.variadic && argc > fp.n_fixed) {
                varargs = std::make_unique<std::vector<Value>>();
                for (int i = fp.n_fixed; i < argc; ++i)
                    varargs->push_back(std::move(regs[new_base + i]));
            }
            size_t full_needed = (size_t)(new_base + fp.reg_count);
            if (regs.size() < full_needed) regs.resize(full_needed);
            call_stack.push_back({ip, new_base, std::move(varargs), std::move(fuv), {}, {}});
            fp_addr = fp.addr;
        }
        ip = fp_addr;
    }
    call_dyn_done:
    NEXT();
}

op_MAKE_CLOSURE: {
    uint8_t fi = (uint8_t)Bx;
    auto* cl = new Closure(fi);
    for (auto& desc : ch->funcs[fi].upvals) {
        Upvalue* uv;
        if (desc.is_local) {
            uv = nullptr;
            for (auto* ou : call_stack.back().open_upvals) {
                if (!ou->closed && ou->frame_base == base && ou->reg_idx == desc.idx)
                    { uv = ou; break; }
            }
            if (!uv) {
                uv = new Upvalue;
                uv->frame_base = base;
                uv->reg_idx    = desc.idx;
                call_stack.back().open_upvals.push_back(uv);
            }
            uv->refcount++;
        } else {
            uv = call_stack.back().upvals[desc.idx];
            uv->refcount++;
        }
        cl->upvals.push_back(uv);
    }
    regs[base + A] = Value::makeClosure(cl);
    NEXT();
}

op_GET_UPVAL: {
    Upvalue* uv = call_stack.back().upvals[B];
    regs[base + A] = uv->closed ? uv->val : regs[uv->frame_base + uv->reg_idx];
    NEXT();
}

op_SET_UPVAL: {
    Upvalue* uv = call_stack.back().upvals[B];
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
        bool is_instance = isInstance(regs[cb]);
        Value fn = regs[cb + 1];
        int total;
        if (is_instance) {
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
            std::vector<Upvalue*> fuv;
            uint8_t fi;
            if (fn.isFuncVal())      fi = (uint8_t)fn.asInt();
            else if (fn.isClosure()) { fi = fn.asClosure()->func_idx; fuv = fn.asClosure()->upvals; }
            else throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: method call on non-function value");
            const FuncProto& fp = ch->funcs[fi];
            size_t needed = (size_t)(cb + std::max((int)fp.reg_count, total));
            if (regs.size() < needed) regs.resize(needed);
            if (total < fp.n_fixed) {
                auto& defs = ch->func_defaults[fp.defaults_idx];
                for (int i = total; i < fp.n_fixed; ++i)
                    regs[cb + i] = (i < (int)defs.size()) ? defs[i] : Value{};
            }
            size_t full_needed = (size_t)(cb + fp.reg_count);
            if (regs.size() < full_needed) regs.resize(full_needed);
            call_stack.push_back({ip, cb, {}, std::move(fuv), {}, {}});
            fp_addr = fp.addr;
        }
    }
    ip = fp_addr;
    call_method_done:
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
    return;

#undef NEXT

#else
    runSwitch(0);
/*
// ── Fallback switch (compilers without GNU extensions) ────────────────────────
    while (true) {
        Instr    instr = ch->code[ip++];
        uint8_t  A     = iA(instr),  B = iB(instr), C = iC(instr);
        uint16_t Bx    = iBx(instr);
        int      base  = call_stack.back().reg_base;

        switch (static_cast<Op>(iOP(instr))) {

        case Op::LOAD_K:
            regs[base+A] = ch->constants[Bx];
            break;
        case Op::LOAD_NIL:
            regs[base+A] = Value{};
            break;
        case Op::MOVE:
            regs[base+A] = regs[base+B];
            break;
        case Op::LOAD_GLOBAL:
            if (!globals_init[Bx])
                throw std::runtime_error("line " + std::to_string(errLine()) + ": undefined: " + ch->identifiers[Bx]);
            regs[base+A] = globals[Bx];
            break;
        case Op::STORE_GLOBAL:
            globals[Bx] = regs[base+A];
            globals_init[Bx] = true;
            break;

        case Op::ADD: {
            if (regs[base+B].isString() || regs[base+C].isString()) {
                regs[base+A] = Value(valueToString(regs[base+B]) + valueToString(regs[base+C]));
                break;
            }
            if (isInstance(regs[base+B])) {
                if (uint32_t addr = tryMetaBinary(MK().add_, base+A, regs[base+B], regs[base+C]))
                    { ip = addr; break; }
            }
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            regs[base+A] = (bv.isInteger() && cv.isInteger())
                ? Value(bv.asInt() + cv.asInt())
                : Value(asDouble(bv) + asDouble(cv));
            break;
        }
        case Op::SUB: {
            if (isInstance(regs[base+B])) {
                if (uint32_t addr = tryMetaBinary(MK().sub_, base+A, regs[base+B], regs[base+C]))
                    { ip = addr; break; }
            }
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            regs[base+A] = (bv.isInteger() && cv.isInteger())
                ? Value(bv.asInt() - cv.asInt())
                : Value(asDouble(bv) - asDouble(cv));
            break;
        }
        case Op::MUL: {
            if (isInstance(regs[base+B])) {
                if (uint32_t addr = tryMetaBinary(MK().mul_, base+A, regs[base+B], regs[base+C]))
                    { ip = addr; break; }
            }
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            regs[base+A] = (bv.isInteger() && cv.isInteger())
                ? Value(bv.asInt() * cv.asInt())
                : Value(asDouble(bv) * asDouble(cv));
            break;
        }
        case Op::DIV: {
            if (isInstance(regs[base+B])) {
                if (uint32_t addr = tryMetaBinary(MK().div_, base+A, regs[base+B], regs[base+C]))
                    { ip = addr; break; }
            }
            double dv = asDouble(regs[base+C]);
            if (dv == 0.0) throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: division by zero");
            regs[base+A] = Value(asDouble(regs[base+B]) / dv);
            break;
        }
        case Op::MOD: {
            if (isInstance(regs[base+B])) {
                if (uint32_t addr = tryMetaBinary(MK().mod_, base+A, regs[base+B], regs[base+C]))
                    { ip = addr; break; }
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
            break;
        }
        case Op::NEGATE: {
            if (isInstance(regs[base+B])) {
                if (uint32_t addr = tryMetaUnary(MK().neg_, base+A, regs[base+B]))
                    { ip = addr; break; }
            }
            const Value& bv = regs[base+B];
            regs[base+A] = bv.isInteger() ? Value(-bv.asInt()) : Value(-asDouble(bv));
            break;
        }
        case Op::NOT:
            regs[base+A] = Value((int64_t)(isFalsy(regs[base+B]) ? 1 : 0));
            break;
        case Op::AND:
            regs[base+A] = Value((int64_t)(!isFalsy(regs[base+B]) && !isFalsy(regs[base+C]) ? 1 : 0));
            break;
        case Op::OR:
            regs[base+A] = Value((int64_t)(!isFalsy(regs[base+B]) || !isFalsy(regs[base+C]) ? 1 : 0));
            break;

        case Op::EQ: {
            if (isInstance(regs[base+B])) {
                if (uint32_t addr = tryMetaBinary(MK().eq_, base+A, regs[base+B], regs[base+C]))
                    { ip = addr; break; }
            }
            regs[base+A] = Value((int64_t)(valuesEqual(regs[base+B], regs[base+C]) ? 1 : 0));
            break;
        }
        case Op::NEQ:
            regs[base+A] = Value((int64_t)(valuesEqual(regs[base+B], regs[base+C]) ? 0 : 1));
            break;
        case Op::GT: {
            if (isInstance(regs[base+C])) {
                if (uint32_t addr = tryMetaBinary(MK().lt_, base+A, regs[base+C], regs[base+B]))
                    { ip = addr; break; }
            }
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            regs[base+A] = Value((int64_t)((bv.isInteger() && cv.isInteger())
                ? bv.asInt()  > cv.asInt()
                : asDouble(bv) > asDouble(cv)));
            break;
        }
        case Op::LT: {
            if (isInstance(regs[base+B])) {
                if (uint32_t addr = tryMetaBinary(MK().lt_, base+A, regs[base+B], regs[base+C]))
                    { ip = addr; break; }
            }
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            regs[base+A] = Value((int64_t)((bv.isInteger() && cv.isInteger())
                ? bv.asInt()  < cv.asInt()
                : asDouble(bv) < asDouble(cv)));
            break;
        }
        case Op::GE: {
            if (isInstance(regs[base+C])) {
                if (uint32_t addr = tryMetaBinary(MK().le_, base+A, regs[base+C], regs[base+B]))
                    { ip = addr; break; }
            }
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            regs[base+A] = Value((int64_t)((bv.isInteger() && cv.isInteger())
                ? bv.asInt()  >= cv.asInt()
                : asDouble(bv) >= asDouble(cv)));
            break;
        }
        case Op::LE: {
            if (isInstance(regs[base+B])) {
                if (uint32_t addr = tryMetaBinary(MK().le_, base+A, regs[base+B], regs[base+C]))
                    { ip = addr; break; }
            }
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            regs[base+A] = Value((int64_t)((bv.isInteger() && cv.isInteger())
                ? bv.asInt()  <= cv.asInt()
                : asDouble(bv) <= asDouble(cv)));
            break;
        }

        case Op::JUMP:
            ip = Bx;
            break;
        case Op::JUMP_IF_FALSE:
            if (isFalsy(regs[base+A])) ip = Bx;
            break;

        case Op::CALL_FUNC: {
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
            std::unique_ptr<std::vector<Value>> varargs;
            if (fp.variadic && argc > fp.n_fixed) {
                varargs = std::make_unique<std::vector<Value>>();
                for (int i = fp.n_fixed; i < argc; ++i)
                    varargs->push_back(std::move(regs[new_base + i]));
            }
            size_t full_needed = (size_t)(new_base + fp.reg_count);
            if (regs.size() < full_needed) regs.resize(full_needed);
            call_stack.push_back({ip, new_base, std::move(varargs), {}, {}});
            ip = fp.addr;
            break;
        }
        case Op::RETURN: {
            closeUpvals();
            Value ctor   = std::move(call_stack.back().ctor_result);
            int ret_dest = call_stack.back().return_dest;
            int n = B;
            if (n > 0 && A != 0)
                for (int i = 0; i < n; ++i)
                    regs[base + i] = std::move(regs[base + A + i]);
            uint32_t rip = call_stack.back().return_ip;
            call_stack.pop_back();
            if (!ctor.isNil())  regs[base + 0] = std::move(ctor);
            if (ret_dest >= 0)  regs[ret_dest] = regs[base + 0];
            ip = rip;
            break;
        }
        case Op::LOAD_VARARGS: {
            auto& va = call_stack.back().varargs;
            if (va) {
                int count = B;
                int n = (count == 0) ? (int)va->size() : std::min(count, (int)va->size());
                size_t needed = (size_t)(base + A + n);
                if (regs.size() < needed) regs.resize(needed);
                for (int i = 0; i < n; ++i) regs[base + A + i] = (*va)[i];
            }
            break;
        }
        case Op::RETURN_V: {
            closeUpvals();
            auto& va   = call_stack.back().varargs;
            int n_va   = va ? (int)va->size() : 0;
            int n_expl = B;
            int total  = n_expl + n_va;
            std::vector<Value> rvs(total);
            for (int i = 0; i < n_expl; ++i) rvs[i] = std::move(regs[base + A + i]);
            if (va) for (int i = 0; i < n_va; ++i) rvs[n_expl + i] = std::move((*va)[i]);
            uint32_t rip = call_stack.back().return_ip;
            int rbase    = call_stack.back().reg_base;
            call_stack.pop_back();
            if ((int)regs.size() < rbase + total) regs.resize(rbase + total);
            for (int i = 0; i < total; ++i) regs[rbase + i] = std::move(rvs[i]);
            ip = rip;
            break;
        }
        case Op::TRY:
            handler_stack.push_back({Bx, A, base, regs.size(), call_stack.size()});
            break;
        case Op::POP_TRY:
            handler_stack.pop_back();
            break;
        case Op::THROW: {
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
            break;
        }

        case Op::NEW_MAP:
            regs[base+A] = Value::makeMap();
            break;
        case Op::GET_INDEX: {
            const Value& obj = regs[base+B]; const Value& key = regs[base+C];
            if (obj.isMap() || obj.isClass()) {
                regs[base+A] = protoChainGet(obj, key);
            } else if (obj.isArray()) {
                if (!key.isInteger()) throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: array index must be integer");
                regs[base+A] = obj.arrayGet(key.asInt());
            } else {
                throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: [] on non-indexable");
            }
            break;
        }
        case Op::SET_INDEX: {
            Value& obj = regs[base+A]; const Value& key = regs[base+B];
            if (obj.isMap() || obj.isClass()) {
                obj.mapSet(key, regs[base+C]);
            } else if (obj.isArray()) {
                if (!key.isInteger()) throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: array index must be integer");
                obj.arraySet(key.asInt(), regs[base+C]);
            } else {
                throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: []= on non-indexable");
            }
            break;
        }
        case Op::MAKE_ITER:
            regs[base+A] = Value::makeIterFrom(regs[base+B]);
            break;

        case Op::BAND: {
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            if (!bv.isInteger() || !cv.isInteger())
                throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: & requires integer operands");
            regs[base+A] = Value(bv.asInt() & cv.asInt());
            break;
        }
        case Op::BOR: {
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            if (!bv.isInteger() || !cv.isInteger())
                throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: | requires integer operands");
            regs[base+A] = Value(bv.asInt() | cv.asInt());
            break;
        }
        case Op::BXOR: {
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            if (!bv.isInteger() || !cv.isInteger())
                throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: ^ requires integer operands");
            regs[base+A] = Value(bv.asInt() ^ cv.asInt());
            break;
        }
        case Op::BNOT: {
            const Value& bv = regs[base+B];
            if (!bv.isInteger())
                throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: ~ requires integer operand");
            regs[base+A] = Value(~bv.asInt());
            break;
        }
        case Op::BLSHIFT: {
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            if (!bv.isInteger() || !cv.isInteger())
                throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: << requires integer operands");
            regs[base+A] = Value((int64_t)((uint64_t)bv.asInt() << (cv.asInt() & 63)));
            break;
        }
        case Op::BRSHIFT: {
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            if (!bv.isInteger() || !cv.isInteger())
                throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: >> requires integer operands");
            regs[base+A] = Value(bv.asInt() >> (cv.asInt() & 63));
            break;
        }

        case Op::NEW_ARRAY:
            regs[base+A] = Value::makeArray();
            break;
        case Op::ARRAY_PUSH:
            regs[base+A].arrayPush(regs[base+B]);
            break;
        case Op::FOR_ITER_NEXT: {
            Value key, val;
            if (!regs[base+A].iptr->next(key, val)) {
                ip = Bx;
            } else {
                regs[base+A+1] = std::move(key);
                regs[base+A+2] = std::move(val);
            }
            break;
        }
        case Op::FOR_ITER_NEXT1: {
            Value key, val;
            if (!regs[base+A].iptr->next(key, val)) {
                ip = Bx;
            } else {
                regs[base+A+1] = regs[base+A].iptr->primary_is_val()
                                  ? std::move(val) : std::move(key);
            }
            break;
        }
        case Op::LOAD_FUNC:
            regs[base+A] = Value::makeFunc((uint8_t)Bx);
            break;

        case Op::CALL_DYN: {
            if (regs[base+B].isBuiltin()) {
                regs[base+A] = regs[base+B].asBuiltin()(&regs[base+A], C);
                break;
            }
            if (regs[base+B].isClass()) {
                Value cls  = regs[base+B];
                Value inst = Value::makeMap();
                inst.mapSet(MK().class_, cls);
                int new_base = base + A;
                int argc = C;
                Value init_fn = protoChainGet(cls, MK().init_);
                if (!init_fn.isCallable()) { regs[new_base] = std::move(inst); break; }
                std::vector<Upvalue*> fuv;
                uint8_t fi = resolveFuncVal(init_fn, fuv);
                const FuncProto& fp = ch->funcs[fi];
                int total = argc + 1;
                size_t needed = (size_t)(new_base + std::max((int)fp.reg_count, total));
                if (regs.size() < needed) regs.resize(needed);
                for (int i = argc - 1; i >= 0; --i)
                    regs[new_base + 1 + i] = std::move(regs[new_base + i]);
                regs[new_base + 0] = inst;
                if (total < fp.n_fixed) {
                    auto& defs = ch->func_defaults[fp.defaults_idx];
                    for (int i = total; i < fp.n_fixed; ++i)
                        regs[new_base + i] = (i < (int)defs.size()) ? defs[i] : Value{};
                }
                size_t full_needed = (size_t)(new_base + fp.reg_count);
                if (regs.size() < full_needed) regs.resize(full_needed);
                call_stack.push_back({ip, new_base, {}, std::move(fuv), {}, inst});
                ip = fp.addr;
                break;
            }
            {
                int new_base = base + A;
                int argc = C;
                std::vector<Upvalue*> fuv;
                uint8_t fi = resolveFuncVal(regs[base + B], fuv);
                const FuncProto& fp = ch->funcs[fi];
                size_t needed = (size_t)(new_base + std::max((int)fp.reg_count, argc));
                if (regs.size() < needed) regs.resize(needed);
                if (argc < fp.n_fixed) {
                    auto& defs = ch->func_defaults[fp.defaults_idx];
                    for (int i = argc; i < fp.n_fixed; ++i)
                        regs[new_base + i] = (i < (int)defs.size()) ? defs[i] : Value{};
                }
                std::unique_ptr<std::vector<Value>> varargs;
                if (fp.variadic && argc > fp.n_fixed) {
                    varargs = std::make_unique<std::vector<Value>>();
                    for (int i = fp.n_fixed; i < argc; ++i)
                        varargs->push_back(std::move(regs[new_base + i]));
                }
                size_t full_needed = (size_t)(new_base + fp.reg_count);
                if (regs.size() < full_needed) regs.resize(full_needed);
                call_stack.push_back({ip, new_base, std::move(varargs), std::move(fuv), {}, {}});
                ip = fp.addr;
            }
            break;
        }

        case Op::MAKE_CLOSURE: {
            uint8_t fi = (uint8_t)Bx;
            auto* cl = new Closure(fi);
            for (auto& desc : ch->funcs[fi].upvals) {
                Upvalue* uv = nullptr;
                if (desc.is_local) {
                    for (auto* ou : call_stack.back().open_upvals)
                        if (!ou->closed && ou->frame_base == base && ou->reg_idx == desc.idx)
                            { uv = ou; break; }
                    if (!uv) {
                        uv = new Upvalue;
                        uv->frame_base = base;
                        uv->reg_idx    = desc.idx;
                        call_stack.back().open_upvals.push_back(uv);
                    }
                    uv->refcount++;
                } else {
                    uv = call_stack.back().upvals[desc.idx];
                    uv->refcount++;
                }
                cl->upvals.push_back(uv);
            }
            regs[base+A] = Value::makeClosure(cl);
            break;
        }
        case Op::GET_UPVAL: {
            Upvalue* uv = call_stack.back().upvals[B];
            regs[base+A] = uv->closed ? uv->val : regs[uv->frame_base + uv->reg_idx];
            break;
        }
        case Op::SET_UPVAL: {
            Upvalue* uv = call_stack.back().upvals[B];
            if (uv->closed) uv->val = regs[base+A];
            else            regs[uv->frame_base + uv->reg_idx] = regs[base+A];
            break;
        }
        case Op::NEW_CLASS:
            regs[base+A] = Value::makeClass();
            break;
        case Op::CALL_METHOD: {
            int cb   = base + A;
            int argc = C;
            bool is_instance = isInstance(regs[cb]);
            Value fn = regs[cb + 1];
            int total;
            if (is_instance) {
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
                break;
            }
            std::vector<Upvalue*> fuv;
            uint8_t fi;
            if (fn.isFuncVal())       fi = (uint8_t)fn.asInt();
            else if (fn.isClosure())  { fi = fn.asClosure()->func_idx; fuv = fn.asClosure()->upvals; }
            else throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: method call on non-function value");
            const FuncProto& fp = ch->funcs[fi];
            size_t needed = (size_t)(cb + std::max((int)fp.reg_count, total));
            if (regs.size() < needed) regs.resize(needed);
            if (total < fp.n_fixed) {
                auto& defs = ch->func_defaults[fp.defaults_idx];
                for (int i = total; i < fp.n_fixed; ++i)
                    regs[cb + i] = (i < (int)defs.size()) ? defs[i] : Value{};
            }
            size_t full_needed = (size_t)(cb + fp.reg_count);
            if (regs.size() < full_needed) regs.resize(full_needed);
            call_stack.push_back({ip, cb, {}, std::move(fuv), {}, {}});
            ip = fp.addr;
            break;
        }
        case Op::MAKE_RANGE: {
            bool has_step   = (C >> 1) & 1;
            bool incl_right2 = C & 1;
            int line_s = errLine();
            auto toDouble_s = [&](const Value& v) -> double {
                if (v.isInteger()) return (double)v.asInt();
                if (v.isFloat())   return v.asFloat();
                throw std::runtime_error("line " + std::to_string(line_s) + ": runtime: range bound must be a number");
            };
            double start2 = toDouble_s(regs[base + B]);
            double end2   = toDouble_s(regs[base + B + 1]);
            double step2  = has_step ? toDouble_s(regs[base + B + 2]) : 1.0;
            if (step2 == 0.0) throw std::runtime_error("line " + std::to_string(line_s) + ": runtime: range step cannot be zero");
            Range* r2 = new Range{1, start2, end2, step2, incl_right2};
            regs[base + A] = Value::makeRange(r2);
            break;
        }
        case Op::HALT:
            return;
        default:
            throw std::runtime_error("line " + std::to_string(errLine()) + ": runtime: unknown opcode (" +
                std::to_string((int)iOP(ch->code[ip-1])) + ")");
        }
    }
*/
#endif
}
