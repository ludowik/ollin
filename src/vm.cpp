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
    stack.reserve(1024);
    call_stack.reserve(1000);
    locals_pool.reserve(1000);

    // Le bytecode émis par le compilateur termine toujours par HALT et ses
    // opérandes sont correctement dimensionnés : on saute les bounds-checks
    // dans la boucle chaude.
    while (true) {
        Op op = static_cast<Op>(ch->code[ip]);
        ip++;
        switch (op) {
            case Op::LOAD_CONST: {
                uint16_t idx = readU16();
                stack.push_back(ch->constants[idx]);
                break;
            }

            case Op::LOAD_VAR: {
                uint16_t idx = readU16();
                if (!vars_init[idx])
                    throw std::runtime_error("runtime: undefined variable '" + ch->identifiers[idx] + "'");
                stack.push_back(vars[idx]);
                break;
            }

            case Op::STORE_VAR: {
                uint16_t idx = readU16();
                vars[idx] = pop();
                vars_init[idx] = true;
                break;
            }

            case Op::ADD: { auto b = pop(), a = pop(); stack.push_back(asDouble(a) + asDouble(b)); break; }
            case Op::SUB: { auto b = pop(), a = pop(); stack.push_back(asDouble(a) - asDouble(b)); break; }
            case Op::MUL: { auto b = pop(), a = pop(); stack.push_back(asDouble(a) * asDouble(b)); break; }
            case Op::DIV: {
                auto b = pop(), a = pop();
                double bd = asDouble(b);
                if (bd == 0.0) throw std::runtime_error("runtime: division by zero");
                stack.push_back(asDouble(a) / bd);
                break;
            }

            case Op::GT: { auto b = pop(), a = pop(); stack.push_back(asDouble(a) >  asDouble(b) ? 1.0 : 0.0); break; }
            case Op::LT: { auto b = pop(), a = pop(); stack.push_back(asDouble(a) <  asDouble(b) ? 1.0 : 0.0); break; }
            case Op::GE:  { auto b = pop(), a = pop(); stack.push_back(asDouble(a) >= asDouble(b) ? 1.0 : 0.0); break; }
            case Op::LE:  { auto b = pop(), a = pop(); stack.push_back(asDouble(a) <= asDouble(b) ? 1.0 : 0.0); break; }
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
                stack.push_back(eq ? 0.0 : 1.0); // NEQ = inverse de EQ
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
                stack.push_back(eq ? 1.0 : 0.0);
                break;
            }
            case Op::MOD: {
                auto b = pop(), a = pop();
                double bd = asDouble(b);
                if (bd == 0.0) throw std::runtime_error("runtime: modulo by zero");
                stack.push_back(std::fmod(asDouble(a), bd));
                break;
            }
            case Op::NEGATE: { auto a = pop(); stack.push_back(-asDouble(a)); break; }
            case Op::NOT_OP: { auto a = pop(); stack.push_back(isFalsy(a) ? 1.0 : 0.0); break; }
            case Op::OR_OP:  { auto b = pop(), a = pop(); stack.push_back(!isFalsy(a) || !isFalsy(b) ? 1.0 : 0.0); break; }
            case Op::AND_OP: { auto b = pop(), a = pop(); stack.push_back(!isFalsy(a) && !isFalsy(b) ? 1.0 : 0.0); break; }

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
                    stack.push_back(t);
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
                stack.resize(h.stack_size);
                stack.push_back(std::move(thrown));
                ip = h.catch_addr;
                break;
            }

            case Op::LOAD_LOCAL: {
                uint16_t idx = readU16();
                Frame& f = call_stack.back();
                if (idx >= (uint16_t)f.locals_count || !(f.init_mask >> idx & 1ULL))
                    throw std::runtime_error("runtime: variable locale non initialisée");
                stack.push_back(locals_pool[f.locals_base + idx]);
                break;
            }

            case Op::STORE_LOCAL: {
                uint16_t idx = readU16();
                Frame& f = call_stack.back();
                int needed = f.locals_base + idx + 1;
                if ((int)locals_pool.size() < needed) {
                    locals_pool.resize(needed);
                    f.locals_count = idx + 1;
                } else if (idx >= (uint16_t)f.locals_count) {
                    f.locals_count = idx + 1;
                }
                locals_pool[f.locals_base + idx] = pop();
                if (idx < 64) f.init_mask |= (1ULL << idx);
                break;
            }

            case Op::CALL_FUNC: {
                uint16_t addr         = readU16();
                uint8_t  n_fixed      = readU8();
                uint8_t  argc         = readU8();
                bool     variadic     = readU8() != 0;
                uint16_t defaults_idx = readU16();

                if (!variadic && argc > n_fixed)
                    throw std::runtime_error("runtime: trop d'arguments");
                if (call_stack.size() >= 1000)
                    throw std::runtime_error("runtime: stack overflow (profondeur max 1000)");

                // Args sont en tête de stack : stack[sbase .. sbase+argc)
                int sbase = (int)stack.size() - argc;
                int n_from_stack = (int)argc < n_fixed ? (int)argc : n_fixed;

                Frame frame;
                frame.return_ip    = ip;
                frame.stack_base   = sbase;
                frame.n_fixed      = n_fixed;
                frame.locals_base  = (int)locals_pool.size();
                frame.locals_count = n_fixed;
                frame.init_mask    = 0;

                // push_back des args directement (évite default-construct + assign)
                uint64_t mask = 0;
                for (int i = 0; i < n_from_stack; ++i) {
                    locals_pool.push_back(std::move(stack[sbase + i]));
                    mask |= (1ULL << i);
                }
                frame.init_mask = mask;

                // Collect varargs before shrinking the operand stack
                if (variadic && (int)argc > n_fixed) {
                    frame.varargs = std::make_unique<std::vector<Value>>();
                    for (int i = n_fixed; i < (int)argc; ++i)
                        frame.varargs->push_back(std::move(stack[sbase + i]));
                }
                // Supprime tous les args de la stack d'opérandes
                stack.resize(sbase);

                // Params manquants → defaults ou nil
                if (n_from_stack < n_fixed) {
                    if (defaults_idx >= ch->func_defaults.size())
                        throw std::runtime_error("runtime: defaults_idx hors bornes");
                    auto& defs = ch->func_defaults[defaults_idx];
                    for (int i = n_from_stack; i < n_fixed; ++i) {
                        locals_pool.push_back(i < (int)defs.size() ? defs[i] : Value{});
                        frame.init_mask |= (1ULL << i);
                    }
                }
                call_stack.push_back(std::move(frame));
                ip = addr;
                break;
            }

            case Op::RETURN_N: {
                uint8_t n  = readU8();
                int rip    = call_stack.back().return_ip;
                int sbase  = call_stack.back().stack_base;
                int lbase  = call_stack.back().locals_base;
                call_stack.pop_back();
                locals_pool.resize(lbase);
                if (n == 0) {
                    stack.resize(sbase);
                } else if (n == 1) {
                    // fast path : pas d'allocation temporaire
                    Value v = std::move(stack.back()); stack.pop_back();
                    stack.resize(sbase);
                    stack.push_back(std::move(v));
                } else {
                    std::vector<Value> rv(n);
                    for (int i = n - 1; i >= 0; --i) rv[i] = pop();
                    stack.resize(sbase);
                    for (auto& v : rv) stack.push_back(std::move(v));
                }
                ret_count = n;
                ip = rip;
                break;
            }

            case Op::RETURN_V: {
                uint8_t n_explicit = readU8();
                auto&   va         = call_stack.back().varargs;
                int     n_varargs  = va ? (int)va->size() : 0;
                int     total      = n_explicit + n_varargs;
                std::vector<Value> retvals(total);
                for (int i = total - 1; i >= 0; --i) retvals[i] = pop();
                int  rip   = call_stack.back().return_ip;
                int  sbase = call_stack.back().stack_base;
                int  lbase = call_stack.back().locals_base;
                call_stack.pop_back();
                locals_pool.resize(lbase);
                stack.resize(sbase);
                for (auto& v : retvals) stack.push_back(std::move(v));
                ret_count = total;
                ip = rip;
                break;
            }

            case Op::LOAD_VARARGS: {
                if (call_stack.empty()) throw std::runtime_error("runtime: LOAD_VARARGS hors fonction");
                auto& va = call_stack.back().varargs;
                if (va) for (auto& v : *va) stack.push_back(v);
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
                throw std::runtime_error("runtime: opcode inconnu (" + std::to_string(static_cast<int>(op)) + ")");
        }
    }
}
