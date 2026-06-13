#include "vm.h"
#include <chrono>
#include <cmath>
#include <sstream>
#include <stdexcept>
#include <vector>

// Taille des opérandes (octets hors opcode) par opcode, indexé par octet brut.
// 0 pour les opcodes sans opérande et pour les valeurs inconnues (≥33).
// Ordre : doit rester synchronisé avec enum class Op dans chunk.h.
static constexpr uint8_t s_operand_sizes[256] = {
    2, 2, 2,          // LOAD_CONST, LOAD_VAR, STORE_VAR
    0, 0, 0, 0, 0,    // ADD, SUB, MUL, DIV, MOD
    0, 0,             // NEGATE, NOT_OP
    0, 0,             // OR_OP, AND_OP
    0, 0, 0, 0, 0, 0, // GT, LT, GE, LE, NEQ, EQ
    2, 2,             // JUMP, JUMP_IF_FALSE
    3,                // CALL  (u16 name + u8 argc)
    2,                // TRY   (u16 catch_addr)
    0, 0,             // POP_TRY, THROW
    2, 2,             // LOAD_LOCAL, STORE_LOCAL
    7,                // CALL_FUNC (u16+u8+u8+u8+u16)
    1, 1,             // RETURN_N, RETURN_V
    0, 0, 0, 0,       // LOAD_VARARGS, DISCARD_RETURNS, POP, HALT
    // [33..255] → 0 par zero-initialisation
};

static std::string valueToString(const Value& v) {
    if (v.isNil())    return "nil";
    if (v.isString()) return v.asString();
    std::ostringstream os; os << v.asNum(); return os.str();
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
                        throw std::runtime_error("printf: index invalide '{" + spec + "}'");
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

// ── boucle d'exécution ────────────────────────────────────────────────────────

void VM::execute(const Chunk& chunk) {
    ch = &chunk;
    ip = 0;
    vars.assign(chunk.identifiers.size(), 0.0);
    vars_init.assign(chunk.identifiers.size(), false);

    while (true) {
        if (ip >= (int)ch->code.size())
            throw std::runtime_error("runtime: bytecode tronqué");
        uint8_t raw = ch->code[ip];
        if (ip + 1 + s_operand_sizes[raw] > (int)ch->code.size())
            throw std::runtime_error("runtime: instruction tronquée");
        Op op = static_cast<Op>(raw);
        ip++;
        switch (op) {
            case Op::LOAD_CONST: {
                uint16_t idx = readU16();
                if (idx >= ch->constants.size())
                    throw std::runtime_error("runtime: constant index out of bounds");
                stack.push(ch->constants[idx]);
                break;
            }

            case Op::LOAD_VAR: {
                uint16_t idx = readU16();
                if (idx >= ch->identifiers.size() || idx >= vars.size())
                    throw std::runtime_error("runtime: variable index out of bounds");
                if (!vars_init[idx])
                    throw std::runtime_error("runtime: undefined variable '" + ch->identifiers[idx] + "'");
                stack.push(vars[idx]);
                break;
            }

            case Op::STORE_VAR: {
                uint16_t idx = readU16();
                if (idx >= vars.size())
                    throw std::runtime_error("runtime: variable index out of bounds");
                vars[idx] = pop();
                vars_init[idx] = true;
                break;
            }

            case Op::ADD: { auto b = pop(), a = pop(); stack.push(asDouble(a) + asDouble(b)); break; }
            case Op::SUB: { auto b = pop(), a = pop(); stack.push(asDouble(a) - asDouble(b)); break; }
            case Op::MUL: { auto b = pop(), a = pop(); stack.push(asDouble(a) * asDouble(b)); break; }
            case Op::DIV: {
                auto b = pop(), a = pop();
                double bd = asDouble(b);
                if (bd == 0.0) throw std::runtime_error("runtime: division by zero");
                stack.push(asDouble(a) / bd);
                break;
            }

            case Op::GT: { auto b = pop(), a = pop(); stack.push(asDouble(a) >  asDouble(b) ? 1.0 : 0.0); break; }
            case Op::LT: { auto b = pop(), a = pop(); stack.push(asDouble(a) <  asDouble(b) ? 1.0 : 0.0); break; }
            case Op::GE:  { auto b = pop(), a = pop(); stack.push(asDouble(a) >= asDouble(b) ? 1.0 : 0.0); break; }
            case Op::LE:  { auto b = pop(), a = pop(); stack.push(asDouble(a) <= asDouble(b) ? 1.0 : 0.0); break; }
            case Op::NEQ: {
                auto b = pop(), a = pop();
                bool eq;
                if (a.isNil() && b.isNil())           eq = true;
                else if (a.isNil() || b.isNil())       eq = false;
                else if (a.isNumber() && b.isNumber()) eq = (a.asNum() == b.asNum());
                else if (a.isString() && b.isString()) eq = (a.asString() == b.asString());
                else if (a.isString() && b.isNumber()) eq = (isFalsy(a) ? 0.0 : 1.0) == b.asNum();
                else if (a.isNumber() && b.isString()) eq = a.asNum() == (isFalsy(b) ? 0.0 : 1.0);
                else eq = false;
                stack.push(eq ? 0.0 : 1.0); // NEQ = inverse de EQ
                break;
            }
            case Op::EQ: {
                auto b = pop(), a = pop();
                bool eq;
                if (a.isNil() && b.isNil())           eq = true;
                else if (a.isNil() || b.isNil())       eq = false;
                else if (a.isNumber() && b.isNumber()) eq = (a.asNum() == b.asNum());
                else if (a.isString() && b.isString()) eq = (a.asString() == b.asString());
                // string == number : comparer la valeur de vérité de la chaîne
                else if (a.isString() && b.isNumber()) eq = (isFalsy(a) ? 0.0 : 1.0) == b.asNum();
                else if (a.isNumber() && b.isString()) eq = a.asNum() == (isFalsy(b) ? 0.0 : 1.0);
                else eq = false;
                stack.push(eq ? 1.0 : 0.0);
                break;
            }
            case Op::MOD: {
                auto b = pop(), a = pop();
                double bd = asDouble(b);
                if (bd == 0.0) throw std::runtime_error("runtime: modulo by zero");
                stack.push(std::fmod(asDouble(a), bd));
                break;
            }
            case Op::NEGATE: { auto a = pop(); stack.push(-asDouble(a)); break; }
            case Op::NOT_OP: { auto a = pop(); stack.push(isFalsy(a) ? 1.0 : 0.0); break; }
            case Op::OR_OP:  { auto b = pop(), a = pop(); stack.push(!isFalsy(a) || !isFalsy(b) ? 1.0 : 0.0); break; }
            case Op::AND_OP: { auto b = pop(), a = pop(); stack.push(!isFalsy(a) && !isFalsy(b) ? 1.0 : 0.0); break; }

            case Op::JUMP:
                ip = readU16();
                break;

            case Op::JUMP_IF_FALSE: {
                uint16_t target = readU16();
                if (isFalsy(pop())) ip = target;
                break;
            }

            case Op::CALL: {
                uint16_t name_idx = readU16();
                uint8_t  argc     = readU8();
                const std::string& name = ch->identifiers[name_idx];

                if (name == "assert") {
                    std::vector<Value> args(argc);
                    for (int i = argc - 1; i >= 0; --i) args[i] = pop();
                    if (isFalsy(args[0])) {
                        std::string msg = (argc >= 2 && args[1].isString())
                            ? args[1].asString() : "assertion failed";
                        throw std::runtime_error(msg);
                    }
                } else if (name == "time") {
                    auto now = std::chrono::system_clock::now();
                    double t = std::chrono::duration<double>(now.time_since_epoch()).count();
                    stack.push(t);
                } else if (name == "print") {
                    std::vector<Value> args(argc);
                    for (int i = argc - 1; i >= 0; --i) args[i] = pop();
                    for (int i = 0; i < argc; ++i) {
                        if (i) std::cout << ' ';
                        printValue(args[i]);
                    }
                    std::cout << '\n';
                } else if (name == "printf") {
                    std::vector<Value> args(argc);
                    for (int i = argc - 1; i >= 0; --i) args[i] = pop();
                    if (argc < 1 || !args[0].isString())
                        throw std::runtime_error("printf: premier argument doit être une chaîne");
                    std::cout << applyFormat(args[0].asString(), args, 1) << '\n';
                } else {
                    throw std::runtime_error("unknown function: " + name);
                }
                break;
            }

            case Op::TRY: {
                uint16_t catch_addr = readU16();
                handler_stack.push_back({catch_addr, stack.size()});
                break;
            }

            case Op::POP_TRY:
                if (handler_stack.empty())
                    throw std::runtime_error("runtime: POP_TRY sans TRY correspondant");
                handler_stack.pop_back();
                break;

            case Op::THROW: {
                Value thrown = pop();
                if (handler_stack.empty()) {
                    std::string msg = valueToString(thrown);
                    throw std::runtime_error("unhandled exception: " + msg);
                }
                Handler h = handler_stack.back();
                handler_stack.pop_back();
                while (stack.size() > h.stack_size) stack.pop();
                stack.push(std::move(thrown));
                ip = h.catch_addr;
                break;
            }

            case Op::LOAD_LOCAL: {
                uint16_t idx = readU16();
                if (call_stack.empty()) throw std::runtime_error("runtime: LOAD_LOCAL hors fonction");
                Frame& f = call_stack.back();
                if (idx >= f.locals.size() || !f.locals_init[idx])
                    throw std::runtime_error("runtime: variable locale non initialisée");
                stack.push(f.locals[idx]);
                break;
            }

            case Op::STORE_LOCAL: {
                uint16_t idx = readU16();
                if (call_stack.empty()) throw std::runtime_error("runtime: STORE_LOCAL hors fonction");
                Frame& f = call_stack.back();
                if (idx >= f.locals.size()) {
                    f.locals.resize(idx + 1);
                    f.locals_init.resize(idx + 1, false);
                }
                f.locals[idx] = pop();
                f.locals_init[idx] = true;
                break;
            }

            case Op::CALL_FUNC: {
                uint16_t addr         = readU16();
                uint8_t  n_fixed      = readU8();
                uint8_t  argc         = readU8();
                bool     variadic     = readU8() != 0;
                uint16_t defaults_idx = readU16();

                std::vector<Value> args(argc);
                for (int i = argc - 1; i >= 0; --i) args[i] = pop();

                if (!variadic && argc > n_fixed)
                    throw std::runtime_error("runtime: trop d'arguments");

                Frame frame;
                frame.return_ip  = ip;
                frame.stack_base = stack.size();
                frame.n_fixed    = n_fixed;
                frame.locals.resize(n_fixed);
                frame.locals_init.resize(n_fixed, false);
                int n_init = (int)argc < n_fixed ? (int)argc : n_fixed;
                for (int i = 0; i < n_init; ++i) {
                    frame.locals[i]      = args[i];
                    frame.locals_init[i] = true;
                }
                // Params manquants → valeur par défaut ou nil
                if ((int)argc < n_fixed) {
                    if (defaults_idx >= ch->func_defaults.size())
                        throw std::runtime_error("runtime: defaults_idx hors bornes");
                    auto& defs = ch->func_defaults[defaults_idx];
                    for (int i = n_init; i < n_fixed; ++i) {
                        frame.locals[i]      = (i < (int)defs.size()) ? defs[i] : Value{};
                        frame.locals_init[i] = true;
                    }
                }
                if (variadic) {
                    for (int i = n_fixed; i < (int)argc; ++i)
                        frame.varargs.push_back(std::move(args[i]));
                }
                if (call_stack.size() >= 1000)
                    throw std::runtime_error("runtime: stack overflow (profondeur max 1000)");
                call_stack.push_back(std::move(frame));
                ip = addr;
                break;
            }

            case Op::RETURN_N: {
                uint8_t n = readU8();
                std::vector<Value> retvals(n);
                for (int i = n - 1; i >= 0; --i) retvals[i] = pop();
                int    rip  = call_stack.back().return_ip;
                size_t base = call_stack.back().stack_base;
                call_stack.pop_back();
                while (stack.size() > base) stack.pop();
                for (auto& v : retvals) stack.push(std::move(v));
                ret_count = n;
                ip = rip;
                break;
            }

            case Op::RETURN_V: {
                uint8_t n_explicit = readU8();
                int     n_varargs  = (int)call_stack.back().varargs.size();
                int     total      = n_explicit + n_varargs;
                std::vector<Value> retvals(total);
                for (int i = total - 1; i >= 0; --i) retvals[i] = pop();
                int    rip  = call_stack.back().return_ip;
                size_t base = call_stack.back().stack_base;
                call_stack.pop_back();
                while (stack.size() > base) stack.pop();
                for (auto& v : retvals) stack.push(std::move(v));
                ret_count = total;
                ip = rip;
                break;
            }

            case Op::LOAD_VARARGS: {
                if (call_stack.empty()) throw std::runtime_error("runtime: LOAD_VARARGS hors fonction");
                for (auto& v : call_stack.back().varargs)
                    stack.push(v);
                break;
            }

            case Op::DISCARD_RETURNS: {
                for (int i = 0; i < ret_count; ++i) pop();
                ret_count = 0;
                break;
            }

            case Op::POP:
                pop();
                break;

            case Op::HALT:
                return;

            default:
                throw std::runtime_error("runtime: opcode inconnu (" + std::to_string(raw) + ")");
        }
    }
}
