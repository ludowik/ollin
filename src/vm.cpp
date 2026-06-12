#include "vm.h"
#include <chrono>
#include <sstream>
#include <stdexcept>
#include <vector>

static std::string applyFormat(const std::string& fmt, const std::vector<Value>& args, int offset) {
    std::string out;
    int auto_idx = 0;
    for (size_t i = 0; i < fmt.size(); ++i) {
        if (fmt[i] == '{') {
            size_t j = fmt.find('}', i + 1);
            if (j != std::string::npos) {
                std::string spec = fmt.substr(i + 1, j - i - 1);
                int idx = spec.empty() ? auto_idx++ : std::stoi(spec);
                int ai  = idx + offset;
                if (ai < (int)args.size()) {
                    if (args[ai].isString()) out += args[ai].asString();
                    else { std::ostringstream os; os << args[ai].n; out += os.str(); }
                }
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
        Op op = static_cast<Op>(ch->code[ip++]);
        switch (op) {
            case Op::LOAD_CONST:
                stack.push(ch->constants[readU16()]);
                break;

            case Op::LOAD_VAR: {
                uint16_t idx = readU16();
                if (!vars_init[idx])
                    throw std::runtime_error("runtime: undefined variable '" + ch->identifiers[idx] + "'");
                stack.push(vars[idx]);
                break;
            }

            case Op::STORE_VAR: {
                uint16_t idx = readU16();
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

            case Op::GT: { auto b = pop(), a = pop(); stack.push(asDouble(a) > asDouble(b) ? 1.0 : 0.0); break; }
            case Op::LT: { auto b = pop(), a = pop(); stack.push(asDouble(a) < asDouble(b) ? 1.0 : 0.0); break; }
            case Op::EQ: {
                auto b = pop(), a = pop();
                bool eq;
                if (a.isNumber() && b.isNumber()) eq = (a.n == b.n);
                else if (a.isString() && b.isString()) eq = (a.asString() == b.asString());
                else eq = false;
                stack.push(eq ? 1.0 : 0.0);
                break;
            }

            case Op::JUMP:
                ip = readU16();
                break;

            case Op::JUMP_IF_FALSE: {
                uint16_t target = readU16();
                if (asDouble(pop()) == 0.0) ip = target;
                break;
            }

            case Op::CALL: {
                uint16_t name_idx = readU16();
                uint8_t  argc     = ch->code[ip++];
                const std::string& name = ch->identifiers[name_idx];

                if (name == "assert") {
                    std::vector<Value> args(argc);
                    for (int i = argc - 1; i >= 0; --i) args[i] = pop();
                    if (asDouble(args[0]) == 0.0) {
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
                handler_stack.pop_back();
                break;

            case Op::THROW: {
                Value thrown = pop();
                if (handler_stack.empty()) {
                    std::string msg = thrown.isString() ? thrown.asString() : std::to_string(thrown.n);
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
                Frame& f = call_stack.back();
                if (idx >= f.locals.size() || !f.locals_init[idx])
                    throw std::runtime_error("runtime: variable locale non initialisée");
                stack.push(f.locals[idx]);
                break;
            }

            case Op::STORE_LOCAL: {
                uint16_t idx = readU16();
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
                uint16_t addr    = readU16();
                uint8_t  n_fixed = ch->code[ip++];
                uint8_t  argc    = ch->code[ip++];
                bool     variadic = ch->code[ip++] != 0;

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
                if (variadic) {
                    for (int i = n_fixed; i < (int)argc; ++i)
                        frame.varargs.push_back(std::move(args[i]));
                }
                call_stack.push_back(std::move(frame));
                ip = addr;
                break;
            }

            case Op::RETURN_N: {
                uint8_t n = ch->code[ip++];
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
                uint8_t n_explicit = ch->code[ip++];
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
                for (auto& v : call_stack.back().varargs)
                    stack.push(v);
                break;
            }

            case Op::DISCARD_RETURNS: {
                for (int i = 0; i < ret_count; ++i) pop();
                ret_count = 0;
                break;
            }

            case Op::HALT:
                return;
        }
    }
}
