#include "vm.h"
#include <chrono>
#include <cmath>
#include <sstream>
#include <stdexcept>
#include <vector>

static std::string valueToString(const Value& v) {
    if (v.isNil())     return "nil";
    if (v.isString())  return v.asString();
    if (v.isMap())     return "{map}";
    if (v.isArray())   return "{array}";
    if (v.isInteger()) return std::to_string(v.asInt());
    std::ostringstream os;
    double d = v.asFloat();
    if (d == (long long)d && d >= -1e15 && d <= 1e15)
        os << (long long)d;
    else
        os << d;
    return os.str();
}

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
                if (ai >= 0 && ai < (long long)args.size()) out += valueToString(args[(int)ai]);
                i = j;
                continue;
            }
        }
        out += fmt[i];
    }
    return out;
}

void VM::execute(const Chunk& chunk) {
    ch = &chunk;
    ip = 0;
    globals.assign(chunk.identifiers.size(), Value{});
    globals_init.assign(chunk.identifiers.size(), false);
    regs.resize(chunk.top_reg_count);
    call_stack.reserve(1000);
    call_stack.push_back({0, 0, nullptr});

#ifdef __GNUC__
// ── Computed-goto dispatch ────────────────────────────────────────────────────
// Table dans l'ordre exact de l'enum Op (chunk.h).
// Chaque handler se termine par NEXT() → saut direct vers le handler suivant,
// sans retour au while ni passage par le switch central.
#define NEXT() do {                                         \
    Instr _ni = ch->code[ip++];                            \
    A  = iA(_ni); B = iB(_ni); C = iC(_ni); Bx = iBx(_ni);\
    base = call_stack.back().reg_base;                     \
    goto *dt[iOP(_ni)];                                    \
} while(0)

    static const void* const dt[] = {
        &&op_LOAD_K, &&op_LOAD_NIL, &&op_MOVE,
        &&op_LOAD_GLOBAL, &&op_STORE_GLOBAL,
        &&op_ADD, &&op_SUB, &&op_MUL, &&op_DIV, &&op_MOD,
        &&op_NEGATE, &&op_NOT, &&op_AND, &&op_OR,
        &&op_EQ, &&op_NEQ, &&op_GT, &&op_LT, &&op_GE, &&op_LE,
        &&op_JUMP, &&op_JUMP_IF_FALSE,
        &&op_CALL_FUNC, &&op_RETURN, &&op_LOAD_VARARGS, &&op_RETURN_V,
        &&op_CALL_PRINT, &&op_CALL_PRINTF, &&op_CALL_ASSERT, &&op_CALL_TIME,
        &&op_TRY, &&op_POP_TRY, &&op_THROW,
        &&op_NEW_MAP, &&op_GET_INDEX, &&op_SET_INDEX,
        &&op_FOR_MAP_STEP,
        &&op_BAND, &&op_BOR, &&op_BXOR,
        &&op_BNOT,
        &&op_BLSHIFT, &&op_BRSHIFT,
        &&op_NEW_ARRAY, &&op_ARRAY_PUSH, &&op_FOR_ITER_STEP,
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
        throw std::runtime_error("undefined: " + ch->identifiers[Bx]);
    regs[base + A] = globals[Bx];
    NEXT();

op_STORE_GLOBAL:
    globals[Bx] = regs[base + A];
    globals_init[Bx] = true;
    NEXT();

op_ADD: {
    const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
    regs[base+A] = (bv.isInteger() && cv.isInteger())
        ? Value(bv.asInt() + cv.asInt())
        : Value(asDouble(bv) + asDouble(cv));
    NEXT();
}
op_SUB: {
    const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
    regs[base+A] = (bv.isInteger() && cv.isInteger())
        ? Value(bv.asInt() - cv.asInt())
        : Value(asDouble(bv) - asDouble(cv));
    NEXT();
}
op_MUL: {
    const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
    regs[base+A] = (bv.isInteger() && cv.isInteger())
        ? Value(bv.asInt() * cv.asInt())
        : Value(asDouble(bv) * asDouble(cv));
    NEXT();
}
op_DIV: {
    double dv = asDouble(regs[base+C]);
    if (dv == 0.0) throw std::runtime_error("runtime: division by zero");
    regs[base+A] = Value(asDouble(regs[base+B]) / dv);
    NEXT();
}
op_MOD: {
    const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
    if (bv.isInteger() && cv.isInteger()) {
        if (cv.asInt() == 0) throw std::runtime_error("runtime: modulo by zero");
        regs[base+A] = Value(bv.asInt() % cv.asInt());
    } else {
        double dv = asDouble(cv);
        if (dv == 0.0) throw std::runtime_error("runtime: modulo by zero");
        regs[base+A] = Value(std::fmod(asDouble(bv), dv));
    }
    NEXT();
}
op_NEGATE: {
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

op_GT: {
    const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
    regs[base+A] = Value((int64_t)((bv.isInteger() && cv.isInteger())
        ? bv.asInt() >  cv.asInt() : asDouble(bv) >  asDouble(cv)));
    NEXT();
}
op_LT: {
    const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
    regs[base+A] = Value((int64_t)((bv.isInteger() && cv.isInteger())
        ? bv.asInt() <  cv.asInt() : asDouble(bv) <  asDouble(cv)));
    NEXT();
}
op_GE: {
    const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
    regs[base+A] = Value((int64_t)((bv.isInteger() && cv.isInteger())
        ? bv.asInt() >= cv.asInt() : asDouble(bv) >= asDouble(cv)));
    NEXT();
}
op_LE: {
    const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
    regs[base+A] = Value((int64_t)((bv.isInteger() && cv.isInteger())
        ? bv.asInt() <= cv.asInt() : asDouble(bv) <= asDouble(cv)));
    NEXT();
}
op_EQ: {
    const Value& av = regs[base+B]; const Value& bv = regs[base+C];
    bool eq;
    if (av.isNil() && bv.isNil())             eq = true;
    else if (av.isNil() || bv.isNil())         eq = false;
    else if (av.isInteger() && bv.isInteger()) eq = av.asInt() == bv.asInt();
    else if (av.isNumber()  && bv.isNumber())  eq = av.asNum() == bv.asNum();
    else if (av.isString()  && bv.isString())  eq = av.asString() == bv.asString();
    else if (av.isString()  && bv.isNumber())  eq = (isFalsy(av) ? 0.0 : 1.0) == bv.asNum();
    else if (av.isNumber()  && bv.isString())  eq = av.asNum() == (isFalsy(bv) ? 0.0 : 1.0);
    else eq = false;
    regs[base+A] = Value((int64_t)(eq ? 1 : 0));
    NEXT();
}
op_NEQ: {
    const Value& av = regs[base+B]; const Value& bv = regs[base+C];
    bool eq;
    if (av.isNil() && bv.isNil())             eq = true;
    else if (av.isNil() || bv.isNil())         eq = false;
    else if (av.isInteger() && bv.isInteger()) eq = av.asInt() == bv.asInt();
    else if (av.isNumber()  && bv.isNumber())  eq = av.asNum() == bv.asNum();
    else if (av.isString()  && bv.isString())  eq = av.asString() == bv.asString();
    else if (av.isString()  && bv.isNumber())  eq = (isFalsy(av) ? 0.0 : 1.0) == bv.asNum();
    else if (av.isNumber()  && bv.isString())  eq = av.asNum() == (isFalsy(bv) ? 0.0 : 1.0);
    else eq = false;
    regs[base+A] = Value((int64_t)(eq ? 0 : 1));
    NEXT();
}

op_JUMP:
    ip = Bx;
    NEXT();

op_JUMP_IF_FALSE:
    if (isFalsy(regs[base + A])) ip = Bx;
    NEXT();

op_CALL_FUNC: {
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

    call_stack.push_back({ip, new_base, std::move(varargs)});
    ip = fp.addr;
    NEXT();
}

op_RETURN: {
    int n = B;
    if (n > 0 && A != 0) {
        for (int i = 0; i < n; ++i)
            regs[base + i] = std::move(regs[base + A + i]);
    }
    uint32_t rip = call_stack.back().return_ip;
    call_stack.pop_back();
    ip = rip;
    NEXT();
}

op_LOAD_VARARGS: {
    auto& va = call_stack.back().varargs;
    int count = B;
    if (va) {
        int n = (count == 0) ? (int)va->size() : std::min(count, (int)va->size());
        size_t needed = (size_t)(base + A + n);
        if (regs.size() < needed) regs.resize(needed);
        for (int i = 0; i < n; ++i) regs[base + A + i] = (*va)[i];
    }
    NEXT();
}

op_RETURN_V: {
    auto& va = call_stack.back().varargs;
    int n_va       = va ? (int)va->size() : 0;
    int n_explicit = B;
    int total      = n_explicit + n_va;
    std::vector<Value> rvs(total);
    for (int i = 0; i < n_explicit; ++i) rvs[i] = std::move(regs[base + A + i]);
    if (va) for (int i = 0; i < n_va; ++i) rvs[n_explicit + i] = std::move((*va)[i]);
    uint32_t rip   = call_stack.back().return_ip;
    int      rbase = call_stack.back().reg_base;
    call_stack.pop_back();
    if ((int)regs.size() < rbase + total) regs.resize(rbase + total);
    for (int i = 0; i < total; ++i) regs[rbase + i] = std::move(rvs[i]);
    ip = rip;
    NEXT();
}

op_CALL_PRINT: {
    for (int i = 0; i < B; ++i) {
        if (i) std::cout << ' ';
        printValue(regs[base + A + i]);
    }
    std::cout << '\n';
    NEXT();
}

op_CALL_PRINTF: {
    if (B < 1 || !regs[base + A].isString())
        throw std::runtime_error("printf: first arg must be string");
    std::vector<Value> args(B);
    for (int i = 0; i < B; ++i) args[i] = regs[base + A + i];
    std::cout << applyFormat(args[0].asString(), args, 1) << '\n';
    NEXT();
}

op_CALL_ASSERT: {
    if (B == 0 || isFalsy(regs[base + A])) {
        std::string msg = (B >= 2 && regs[base + A + 1].isString())
            ? regs[base + A + 1].asString() : "assertion failed";
        throw std::runtime_error(msg);
    }
    NEXT();
}

op_CALL_TIME: {
    auto now = std::chrono::system_clock::now();
    regs[base + A] = Value(std::chrono::duration<double>(now.time_since_epoch()).count());
    NEXT();
}

op_TRY:
    handler_stack.push_back({Bx, A, base, regs.size(), call_stack.size()});
    NEXT();

op_POP_TRY:
    handler_stack.pop_back();
    NEXT();

op_THROW: {
    Value thrown = regs[base + A];
    if (handler_stack.empty())
        throw std::runtime_error("unhandled exception: " + valueToString(thrown));
    Handler h = handler_stack.back();
    handler_stack.pop_back();
    while (call_stack.size() > h.call_depth) call_stack.pop_back();
    if (regs.size() > h.regs_size) regs.resize(h.regs_size);
    regs[h.reg_base + h.catch_reg] = std::move(thrown);
    ip = h.catch_addr;
    NEXT();
}

op_NEW_MAP:
    regs[base + A] = Value::makeMap();
    NEXT();

op_GET_INDEX: {
    const Value& obj = regs[base + B];
    const Value& key = regs[base + C];
    if (obj.isMap()) {
        regs[base + A] = obj.mapGet(key);
    } else if (obj.isArray()) {
        if (!key.isInteger()) throw std::runtime_error("runtime: array index must be integer");
        regs[base + A] = obj.arrayGet(key.asInt());
    } else {
        throw std::runtime_error("runtime: [] on non-indexable");
    }
    NEXT();
}

op_SET_INDEX: {
    Value& obj = regs[base + A];
    const Value& key = regs[base + B];
    if (obj.isMap()) {
        obj.mapSet(key, regs[base + C]);
    } else if (obj.isArray()) {
        if (!key.isInteger()) throw std::runtime_error("runtime: array index must be integer");
        obj.arraySet(key.asInt(), regs[base + C]);
    } else {
        throw std::runtime_error("runtime: []= on non-indexable");
    }
    NEXT();
}

op_FOR_MAP_STEP: {
    // R[base+A+3]=obj, R[base+A+2]=iter; if done→ip=Bx else fill R[A+0]=key R[A+1]=val, iter++
    Value& obj_v = regs[base + A + 3];
    int64_t iter = regs[base + A + 2].isInteger() ? regs[base + A + 2].asInt() : 0;
    if (obj_v.isMap()) {
        int sz = obj_v.mapSize();
        if (iter >= sz) { ip = Bx; NEXT(); }
        regs[base + A + 0] = obj_v.mapKeyAt((int)iter);
        regs[base + A + 1] = obj_v.mapValAt((int)iter);
    } else if (obj_v.isArray()) {
        int sz = obj_v.arraySize();
        if (iter >= sz) { ip = Bx; NEXT(); }
        regs[base + A + 0] = Value(iter + 1);          // 1-based index as key
        regs[base + A + 1] = obj_v.arrayGet(iter + 1); // 1-based value
    } else {
        throw std::runtime_error("runtime: for-in on non-iterable");
    }
    regs[base + A + 2] = Value(iter + 1);
    NEXT();
}

op_BAND: {
    const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
    if (!bv.isInteger() || !cv.isInteger()) throw std::runtime_error("runtime: & requires integer operands");
    regs[base+A] = Value(bv.asInt() & cv.asInt());
    NEXT();
}
op_BOR: {
    const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
    if (!bv.isInteger() || !cv.isInteger()) throw std::runtime_error("runtime: | requires integer operands");
    regs[base+A] = Value(bv.asInt() | cv.asInt());
    NEXT();
}
op_BXOR: {
    const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
    if (!bv.isInteger() || !cv.isInteger()) throw std::runtime_error("runtime: ^ requires integer operands");
    regs[base+A] = Value(bv.asInt() ^ cv.asInt());
    NEXT();
}
op_BNOT: {
    const Value& bv = regs[base+B];
    if (!bv.isInteger()) throw std::runtime_error("runtime: ~ requires integer operand");
    regs[base+A] = Value(~bv.asInt());
    NEXT();
}
op_BLSHIFT: {
    const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
    if (!bv.isInteger() || !cv.isInteger()) throw std::runtime_error("runtime: << requires integer operands");
    regs[base+A] = Value((int64_t)((uint64_t)bv.asInt() << (cv.asInt() & 63)));
    NEXT();
}
op_BRSHIFT: {
    const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
    if (!bv.isInteger() || !cv.isInteger()) throw std::runtime_error("runtime: >> requires integer operands");
    regs[base+A] = Value(bv.asInt() >> (cv.asInt() & 63));
    NEXT();
}

op_NEW_ARRAY:
    regs[base + A] = Value::makeArray();
    NEXT();

op_ARRAY_PUSH:
    regs[base + A].arrayPush(regs[base + B]);
    NEXT();

op_FOR_ITER_STEP: {
    // R[base+A+2]=array, R[base+A+1]=iter; if done→ip=Bx else R[A+0]=val, iter++
    Value& arr_v = regs[base + A + 2];
    if (!arr_v.isArray()) throw std::runtime_error("runtime: for-in on non-array");
    int64_t iter = regs[base + A + 1].isInteger() ? regs[base + A + 1].asInt() : 0;
    int sz = arr_v.arraySize();
    if (iter >= sz) { ip = Bx; NEXT(); }
    regs[base + A + 0] = arr_v.arrayGet(iter + 1);  // 1-based
    regs[base + A + 1] = Value(iter + 1);
    NEXT();
}

op_HALT:
    return;

#undef NEXT

#else
// ── Fallback switch (compilateurs sans GNU extensions) ────────────────────────
    while (true) {
        Instr instr = ch->code[ip++];
        uint8_t  A  = iA(instr);
        uint8_t  B  = iB(instr);
        uint8_t  C  = iC(instr);
        uint16_t Bx = iBx(instr);
        int base = call_stack.back().reg_base;

        switch (static_cast<Op>(iOP(instr))) {
        case Op::LOAD_K:       regs[base+A] = ch->constants[Bx]; break;
        case Op::LOAD_NIL:     regs[base+A] = Value{}; break;
        case Op::MOVE:         regs[base+A] = regs[base+B]; break;
        case Op::LOAD_GLOBAL:
            if (!globals_init[Bx]) throw std::runtime_error("undefined: " + ch->identifiers[Bx]);
            regs[base+A] = globals[Bx]; break;
        case Op::STORE_GLOBAL: globals[Bx] = regs[base+A]; globals_init[Bx] = true; break;
        case Op::ADD: { const Value& bv=regs[base+B]; const Value& cv=regs[base+C];
            regs[base+A]=(bv.isInteger()&&cv.isInteger())?Value(bv.asInt()+cv.asInt()):Value(asDouble(bv)+asDouble(cv)); break; }
        case Op::SUB: { const Value& bv=regs[base+B]; const Value& cv=regs[base+C];
            regs[base+A]=(bv.isInteger()&&cv.isInteger())?Value(bv.asInt()-cv.asInt()):Value(asDouble(bv)-asDouble(cv)); break; }
        case Op::MUL: { const Value& bv=regs[base+B]; const Value& cv=regs[base+C];
            regs[base+A]=(bv.isInteger()&&cv.isInteger())?Value(bv.asInt()*cv.asInt()):Value(asDouble(bv)*asDouble(cv)); break; }
        case Op::DIV: { double dv=asDouble(regs[base+C]); if(dv==0.0)throw std::runtime_error("runtime: division by zero");
            regs[base+A]=Value(asDouble(regs[base+B])/dv); break; }
        case Op::MOD: { const Value& bv=regs[base+B]; const Value& cv=regs[base+C];
            if(bv.isInteger()&&cv.isInteger()){if(cv.asInt()==0)throw std::runtime_error("runtime: modulo by zero");
            regs[base+A]=Value(bv.asInt()%cv.asInt());}else{double dv=asDouble(cv);
            if(dv==0.0)throw std::runtime_error("runtime: modulo by zero");regs[base+A]=Value(std::fmod(asDouble(bv),dv));} break; }
        case Op::NEGATE: { const Value& bv=regs[base+B];
            regs[base+A]=bv.isInteger()?Value(-bv.asInt()):Value(-asDouble(bv)); break; }
        case Op::NOT:  regs[base+A]=Value((int64_t)(isFalsy(regs[base+B])?1:0)); break;
        case Op::AND:  regs[base+A]=Value((int64_t)(!isFalsy(regs[base+B])&&!isFalsy(regs[base+C])?1:0)); break;
        case Op::OR:   regs[base+A]=Value((int64_t)(!isFalsy(regs[base+B])||!isFalsy(regs[base+C])?1:0)); break;
        case Op::GT: { const Value& bv=regs[base+B]; const Value& cv=regs[base+C];
            regs[base+A]=Value((int64_t)((bv.isInteger()&&cv.isInteger())?bv.asInt()>cv.asInt():asDouble(bv)>asDouble(cv))); break; }
        case Op::LT: { const Value& bv=regs[base+B]; const Value& cv=regs[base+C];
            regs[base+A]=Value((int64_t)((bv.isInteger()&&cv.isInteger())?bv.asInt()<cv.asInt():asDouble(bv)<asDouble(cv))); break; }
        case Op::GE: { const Value& bv=regs[base+B]; const Value& cv=regs[base+C];
            regs[base+A]=Value((int64_t)((bv.isInteger()&&cv.isInteger())?bv.asInt()>=cv.asInt():asDouble(bv)>=asDouble(cv))); break; }
        case Op::LE: { const Value& bv=regs[base+B]; const Value& cv=regs[base+C];
            regs[base+A]=Value((int64_t)((bv.isInteger()&&cv.isInteger())?bv.asInt()<=cv.asInt():asDouble(bv)<=asDouble(cv))); break; }
        case Op::EQ: {
            const Value& av=regs[base+B]; const Value& bv=regs[base+C]; bool eq;
            if(av.isNil()&&bv.isNil())eq=true; else if(av.isNil()||bv.isNil())eq=false;
            else if(av.isInteger()&&bv.isInteger())eq=av.asInt()==bv.asInt();
            else if(av.isNumber()&&bv.isNumber())eq=av.asNum()==bv.asNum();
            else if(av.isString()&&bv.isString())eq=av.asString()==bv.asString();
            else if(av.isString()&&bv.isNumber())eq=(isFalsy(av)?0.0:1.0)==bv.asNum();
            else if(av.isNumber()&&bv.isString())eq=av.asNum()==(isFalsy(bv)?0.0:1.0);
            else eq=false; regs[base+A]=Value((int64_t)(eq?1:0)); break; }
        case Op::NEQ: {
            const Value& av=regs[base+B]; const Value& bv=regs[base+C]; bool eq;
            if(av.isNil()&&bv.isNil())eq=true; else if(av.isNil()||bv.isNil())eq=false;
            else if(av.isInteger()&&bv.isInteger())eq=av.asInt()==bv.asInt();
            else if(av.isNumber()&&bv.isNumber())eq=av.asNum()==bv.asNum();
            else if(av.isString()&&bv.isString())eq=av.asString()==bv.asString();
            else if(av.isString()&&bv.isNumber())eq=(isFalsy(av)?0.0:1.0)==bv.asNum();
            else if(av.isNumber()&&bv.isString())eq=av.asNum()==(isFalsy(bv)?0.0:1.0);
            else eq=false; regs[base+A]=Value((int64_t)(eq?0:1)); break; }
        case Op::JUMP: ip=Bx; break;
        case Op::JUMP_IF_FALSE: if(isFalsy(regs[base+A]))ip=Bx; break;
        case Op::CALL_FUNC: {
            const FuncProto& fp=ch->funcs[B]; int new_base=base+A; int argc=C;
            size_t needed=(size_t)(new_base+std::max((int)fp.reg_count,argc));
            if(regs.size()<needed)regs.resize(needed);
            if(argc<fp.n_fixed){auto& defs=ch->func_defaults[fp.defaults_idx];
            for(int i=argc;i<fp.n_fixed;++i)regs[new_base+i]=(i<(int)defs.size())?defs[i]:Value{};}
            std::unique_ptr<std::vector<Value>> varargs;
            if(fp.variadic&&argc>fp.n_fixed){varargs=std::make_unique<std::vector<Value>>();
            for(int i=fp.n_fixed;i<argc;++i)varargs->push_back(std::move(regs[new_base+i]));}
            size_t full_needed=(size_t)(new_base+fp.reg_count);
            if(regs.size()<full_needed)regs.resize(full_needed);
            call_stack.push_back({ip,new_base,std::move(varargs)}); ip=fp.addr; break; }
        case Op::RETURN: {
            int n=B; if(n>0&&A!=0)for(int i=0;i<n;++i)regs[base+i]=std::move(regs[base+A+i]);
            uint32_t rip=call_stack.back().return_ip; call_stack.pop_back(); ip=rip; break; }
        case Op::LOAD_VARARGS: {
            auto& va=call_stack.back().varargs; int count=B;
            if(va){int n=(count==0)?(int)va->size():std::min(count,(int)va->size());
            size_t needed=(size_t)(base+A+n); if(regs.size()<needed)regs.resize(needed);
            for(int i=0;i<n;++i)regs[base+A+i]=(*va)[i];} break; }
        case Op::RETURN_V: {
            auto& va=call_stack.back().varargs; int n_va=va?(int)va->size():0;
            int n_explicit=B; int total=n_explicit+n_va;
            std::vector<Value> rvs(total);
            for(int i=0;i<n_explicit;++i)rvs[i]=std::move(regs[base+A+i]);
            if(va)for(int i=0;i<n_va;++i)rvs[n_explicit+i]=std::move((*va)[i]);
            uint32_t rip=call_stack.back().return_ip; int rbase=call_stack.back().reg_base;
            call_stack.pop_back(); if((int)regs.size()<rbase+total)regs.resize(rbase+total);
            for(int i=0;i<total;++i)regs[rbase+i]=std::move(rvs[i]); ip=rip; break; }
        case Op::CALL_PRINT: {
            for(int i=0;i<B;++i){if(i)std::cout<<' ';printValue(regs[base+A+i]);}
            std::cout<<'\n'; break; }
        case Op::CALL_PRINTF: {
            if(B<1||!regs[base+A].isString())throw std::runtime_error("printf: first arg must be string");
            std::vector<Value> args(B); for(int i=0;i<B;++i)args[i]=regs[base+A+i];
            std::cout<<applyFormat(args[0].asString(),args,1)<<'\n'; break; }
        case Op::CALL_ASSERT: {
            if(B==0||isFalsy(regs[base+A])){
            std::string msg=(B>=2&&regs[base+A+1].isString())?regs[base+A+1].asString():"assertion failed";
            throw std::runtime_error(msg);} break; }
        case Op::CALL_TIME: {
            auto now=std::chrono::system_clock::now();
            regs[base+A]=Value(std::chrono::duration<double>(now.time_since_epoch()).count()); break; }
        case Op::TRY:
            handler_stack.push_back({Bx,A,base,regs.size(),call_stack.size()}); break;
        case Op::POP_TRY: handler_stack.pop_back(); break;
        case Op::THROW: {
            Value thrown=regs[base+A];
            if(handler_stack.empty())throw std::runtime_error("unhandled exception: "+valueToString(thrown));
            Handler h=handler_stack.back(); handler_stack.pop_back();
            while(call_stack.size()>h.call_depth)call_stack.pop_back();
            if(regs.size()>h.regs_size)regs.resize(h.regs_size);
            regs[h.reg_base+h.catch_reg]=std::move(thrown); ip=h.catch_addr; break; }
        case Op::FOR_MAP_STEP: {
            Value& obj_v=regs[base+A+3];
            int64_t iter=regs[base+A+2].isInteger()?regs[base+A+2].asInt():0;
            if(obj_v.isMap()){
                int sz=obj_v.mapSize(); if(iter>=sz){ip=Bx;break;}
                regs[base+A+0]=obj_v.mapKeyAt((int)iter);
                regs[base+A+1]=obj_v.mapValAt((int)iter);
            } else if(obj_v.isArray()){
                int sz=obj_v.arraySize(); if(iter>=sz){ip=Bx;break;}
                regs[base+A+0]=Value(iter+1);
                regs[base+A+1]=obj_v.arrayGet(iter+1);
            } else { throw std::runtime_error("runtime: for-in on non-iterable"); }
            regs[base+A+2]=Value(iter+1); break; }
        case Op::NEW_MAP: regs[base+A]=Value::makeMap(); break;
        case Op::GET_INDEX: {
            const Value& obj=regs[base+B]; const Value& key=regs[base+C];
            if(obj.isMap()){
                regs[base+A]=obj.mapGet(key);
            } else if(obj.isArray()){
                if(!key.isInteger())throw std::runtime_error("runtime: array index must be integer");
                regs[base+A]=obj.arrayGet(key.asInt());
            } else { throw std::runtime_error("runtime: [] on non-indexable"); }
            break; }
        case Op::SET_INDEX: {
            Value& obj=regs[base+A]; const Value& key=regs[base+B];
            if(obj.isMap()){
                obj.mapSet(key,regs[base+C]);
            } else if(obj.isArray()){
                if(!key.isInteger())throw std::runtime_error("runtime: array index must be integer");
                obj.arraySet(key.asInt(),regs[base+C]);
            } else { throw std::runtime_error("runtime: []= on non-indexable"); }
            break; }
        case Op::BAND: { const Value& bv=regs[base+B]; const Value& cv=regs[base+C];
            if(!bv.isInteger()||!cv.isInteger())throw std::runtime_error("runtime: & requires integer operands");
            regs[base+A]=Value(bv.asInt()&cv.asInt()); break; }
        case Op::BOR: { const Value& bv=regs[base+B]; const Value& cv=regs[base+C];
            if(!bv.isInteger()||!cv.isInteger())throw std::runtime_error("runtime: | requires integer operands");
            regs[base+A]=Value(bv.asInt()|cv.asInt()); break; }
        case Op::BXOR: { const Value& bv=regs[base+B]; const Value& cv=regs[base+C];
            if(!bv.isInteger()||!cv.isInteger())throw std::runtime_error("runtime: ^ requires integer operands");
            regs[base+A]=Value(bv.asInt()^cv.asInt()); break; }
        case Op::BNOT: { const Value& bv=regs[base+B];
            if(!bv.isInteger())throw std::runtime_error("runtime: ~ requires integer operand");
            regs[base+A]=Value(~bv.asInt()); break; }
        case Op::BLSHIFT: { const Value& bv=regs[base+B]; const Value& cv=regs[base+C];
            if(!bv.isInteger()||!cv.isInteger())throw std::runtime_error("runtime: << requires integer operands");
            regs[base+A]=Value((int64_t)((uint64_t)bv.asInt()<<(cv.asInt()&63))); break; }
        case Op::BRSHIFT: { const Value& bv=regs[base+B]; const Value& cv=regs[base+C];
            if(!bv.isInteger()||!cv.isInteger())throw std::runtime_error("runtime: >> requires integer operands");
            regs[base+A]=Value(bv.asInt()>>(cv.asInt()&63)); break; }
        case Op::NEW_ARRAY: regs[base+A]=Value::makeArray(); break;
        case Op::ARRAY_PUSH: regs[base+A].arrayPush(regs[base+B]); break;
        case Op::FOR_ITER_STEP: {
            Value& arr_v=regs[base+A+2];
            if(!arr_v.isArray())throw std::runtime_error("runtime: for-in on non-array");
            int64_t iter=regs[base+A+1].isInteger()?regs[base+A+1].asInt():0;
            int sz=arr_v.arraySize(); if(iter>=sz){ip=Bx;break;}
            regs[base+A+0]=arr_v.arrayGet(iter+1);
            regs[base+A+1]=Value(iter+1); break; }
        case Op::HALT: return;
        default: throw std::runtime_error("runtime: unknown opcode ("+std::to_string((int)iOP(ch->code[ip-1]))+")");
        }
    }
#endif
}
