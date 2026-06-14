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

    while (true) {
        Instr instr = ch->code[ip++];
        Op    op    = static_cast<Op>(iOP(instr));
        uint8_t  A  = iA(instr);
        uint8_t  B  = iB(instr);
        uint8_t  C  = iC(instr);
        uint16_t Bx = iBx(instr);
        int base = call_stack.back().reg_base;

        switch (op) {
        case Op::LOAD_K:
            regs[base + A] = ch->constants[Bx];
            break;

        case Op::LOAD_NIL:
            regs[base + A] = Value{};
            break;

        case Op::MOVE:
            regs[base + A] = regs[base + B];
            break;

        case Op::LOAD_GLOBAL:
            if (!globals_init[Bx])
                throw std::runtime_error("undefined: " + ch->identifiers[Bx]);
            regs[base + A] = globals[Bx];
            break;

        case Op::STORE_GLOBAL:
            globals[Bx] = regs[base + A];
            globals_init[Bx] = true;
            break;

        case Op::ADD: {
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            regs[base+A] = (bv.isInteger() && cv.isInteger())
                ? Value(bv.asInt() + cv.asInt())
                : Value(asDouble(bv) + asDouble(cv));
            break;
        }
        case Op::SUB: {
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            regs[base+A] = (bv.isInteger() && cv.isInteger())
                ? Value(bv.asInt() - cv.asInt())
                : Value(asDouble(bv) - asDouble(cv));
            break;
        }
        case Op::MUL: {
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            regs[base+A] = (bv.isInteger() && cv.isInteger())
                ? Value(bv.asInt() * cv.asInt())
                : Value(asDouble(bv) * asDouble(cv));
            break;
        }
        case Op::DIV: {
            double bv = asDouble(regs[base+C]);
            if (bv == 0.0) throw std::runtime_error("runtime: division by zero");
            regs[base+A] = Value(asDouble(regs[base+B]) / bv);
            break;
        }
        case Op::MOD: {
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            if (bv.isInteger() && cv.isInteger()) {
                if (cv.asInt() == 0) throw std::runtime_error("runtime: modulo by zero");
                regs[base+A] = Value(bv.asInt() % cv.asInt());
            } else {
                double dv = asDouble(cv);
                if (dv == 0.0) throw std::runtime_error("runtime: modulo by zero");
                regs[base+A] = Value(std::fmod(asDouble(bv), dv));
            }
            break;
        }
        case Op::NEGATE: {
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

        case Op::GT: {
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            regs[base+A] = Value((int64_t)((bv.isInteger() && cv.isInteger())
                ? bv.asInt() >  cv.asInt() : asDouble(bv) >  asDouble(cv)));
            break;
        }
        case Op::LT: {
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            regs[base+A] = Value((int64_t)((bv.isInteger() && cv.isInteger())
                ? bv.asInt() <  cv.asInt() : asDouble(bv) <  asDouble(cv)));
            break;
        }
        case Op::GE: {
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            regs[base+A] = Value((int64_t)((bv.isInteger() && cv.isInteger())
                ? bv.asInt() >= cv.asInt() : asDouble(bv) >= asDouble(cv)));
            break;
        }
        case Op::LE: {
            const Value& bv = regs[base+B]; const Value& cv = regs[base+C];
            regs[base+A] = Value((int64_t)((bv.isInteger() && cv.isInteger())
                ? bv.asInt() <= cv.asInt() : asDouble(bv) <= asDouble(cv)));
            break;
        }
        case Op::EQ: {
            const Value& av = regs[base+B];
            const Value& bv = regs[base+C];
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
            break;
        }
        case Op::NEQ: {
            const Value& av = regs[base+B];
            const Value& bv = regs[base+C];
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
            break;
        }

        case Op::JUMP:
            ip = Bx;
            break;

        case Op::JUMP_IF_FALSE:
            if (isFalsy(regs[base + A])) ip = Bx;
            break;

        case Op::CALL_FUNC: {
            // A=call_base, B=func_idx, C=argc
            const FuncProto& fp = ch->funcs[B];
            int new_base = base + A;
            int argc = C;

            // Grow regs if needed
            size_t needed = (size_t)(new_base + std::max((int)fp.reg_count, argc));
            if (regs.size() < needed) regs.resize(needed);

            // Fill missing args with defaults
            if (argc < fp.n_fixed) {
                auto& defs = ch->func_defaults[fp.defaults_idx];
                for (int i = argc; i < fp.n_fixed; ++i)
                    regs[new_base + i] = (i < (int)defs.size()) ? defs[i] : Value{};
            }

            // Handle varargs
            std::unique_ptr<std::vector<Value>> varargs;
            if (fp.variadic && argc > fp.n_fixed) {
                varargs = std::make_unique<std::vector<Value>>();
                for (int i = fp.n_fixed; i < argc; ++i)
                    varargs->push_back(std::move(regs[new_base + i]));
            }

            // Grow regs to full frame size
            size_t full_needed = (size_t)(new_base + fp.reg_count);
            if (regs.size() < full_needed) regs.resize(full_needed);

            call_stack.push_back({ip, new_base, std::move(varargs)});
            ip = fp.addr;
            break;
        }

        case Op::RETURN: {
            // A=first_reg, B=count
            int n = B;
            if (n > 0 && A != 0) {
                for (int i = 0; i < n; ++i)
                    regs[base + i] = std::move(regs[base + A + i]);
            }
            uint32_t rip = call_stack.back().return_ip;
            call_stack.pop_back();
            ip = rip;
            break;
        }

        case Op::RETURN_V: {
            // A=first_explicit, B=n_explicit; also append varargs
            auto& va = call_stack.back().varargs;
            int n_va       = va ? (int)va->size() : 0;
            int n_explicit = B;
            int total      = n_explicit + n_va;
            std::vector<Value> rvs(total);
            for (int i = 0; i < n_explicit; ++i) rvs[i] = std::move(regs[base + A + i]);
            if (va) for (int i = 0; i < n_va; ++i) rvs[n_explicit + i] = std::move((*va)[i]);
            uint32_t rip = call_stack.back().return_ip;
            int      rbase = call_stack.back().reg_base;
            call_stack.pop_back();
            // Grow if needed
            if ((int)regs.size() < rbase + total) regs.resize(rbase + total);
            for (int i = 0; i < total; ++i) regs[rbase + i] = std::move(rvs[i]);
            ip = rip;
            break;
        }

        case Op::LOAD_VARARGS: {
            auto& va = call_stack.back().varargs;
            int count = B;  // 0 = all
            if (va) {
                int n = (count == 0) ? (int)va->size() : std::min(count, (int)va->size());
                size_t needed = (size_t)(base + A + n);
                if (regs.size() < needed) regs.resize(needed);
                for (int i = 0; i < n; ++i) regs[base + A + i] = (*va)[i];
            }
            break;
        }

        case Op::TRY: {
            // A=catch_reg, Bx=catch_addr
            handler_stack.push_back({Bx, A, base, regs.size(), call_stack.size()});
            break;
        }

        case Op::POP_TRY:
            handler_stack.pop_back();
            break;

        case Op::THROW: {
            Value thrown = regs[base + A];
            if (handler_stack.empty())
                throw std::runtime_error("unhandled exception: " + valueToString(thrown));
            Handler h = handler_stack.back();
            handler_stack.pop_back();
            // Unwind call stack
            while (call_stack.size() > h.call_depth) call_stack.pop_back();
            // Restore regs size
            if (regs.size() > h.regs_size) regs.resize(h.regs_size);
            // Put caught value into catch_reg (relative to the frame that set up the TRY)
            regs[h.reg_base + h.catch_reg] = std::move(thrown);
            ip = h.catch_addr;
            break;
        }

        case Op::CALL_PRINT: {
            // A=first_arg, B=argc
            for (int i = 0; i < B; ++i) {
                if (i) std::cout << ' ';
                printValue(regs[base + A + i]);
            }
            std::cout << '\n';
            break;
        }

        case Op::CALL_PRINTF: {
            // A=first_arg, B=argc; args[0]=format string
            if (B < 1 || !regs[base + A].isString())
                throw std::runtime_error("printf: first arg must be string");
            std::vector<Value> args(B);
            for (int i = 0; i < B; ++i) args[i] = regs[base + A + i];
            std::cout << applyFormat(args[0].asString(), args, 1) << '\n';
            break;
        }

        case Op::CALL_ASSERT: {
            if (B == 0 || isFalsy(regs[base + A])) {
                std::string msg = (B >= 2 && regs[base + A + 1].isString())
                    ? regs[base + A + 1].asString() : "assertion failed";
                throw std::runtime_error(msg);
            }
            break;
        }

        case Op::CALL_TIME: {
            auto now = std::chrono::system_clock::now();
            regs[base + A] = Value(std::chrono::duration<double>(now.time_since_epoch()).count());
            break;
        }

        case Op::NEW_MAP:
            regs[base + A] = Value::makeMap();
            break;

        case Op::GET_INDEX: {
            const Value& map = regs[base + B];
            const Value& key = regs[base + C];
            if (!map.isMap())    throw std::runtime_error("runtime: [] on non-map");
            if (!key.isString()) throw std::runtime_error("runtime: map key must be string");
            auto& data = map.mapData();
            auto it = data.find(key.asString());
            regs[base + A] = (it != data.end()) ? it->second : Value{};
            break;
        }

        case Op::SET_INDEX: {
            // A=map_reg, B=key_reg, C=val_reg
            Value& map = regs[base + A];
            const Value& key = regs[base + B];
            if (!map.isMap())    throw std::runtime_error("runtime: []= on non-map");
            if (!key.isString()) throw std::runtime_error("runtime: map key must be string");
            map.mapData()[key.asString()] = regs[base + C];
            break;
        }

        case Op::HALT:
            return;

        default:
            throw std::runtime_error("runtime: unknown opcode (" +
                                     std::to_string((int)op) + ")");
        }
    }
}
