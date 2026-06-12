#include "vm.h"
#include <chrono>
#include <iostream>
#include <stdexcept>
#include <vector>

void VM::execute(const Chunk& chunk) {
    int ip = 0;
    vars.assign(chunk.identifiers.size(), 0.0);
    vars_init.assign(chunk.identifiers.size(), false);

    auto readU16 = [&]() -> uint16_t {
        uint16_t v = (static_cast<uint16_t>(chunk.code[ip]) << 8) | chunk.code[ip + 1];
        ip += 2;
        return v;
    };

    auto pop = [&]() -> Value {
        if (stack.empty()) throw std::runtime_error("runtime: stack underflow");
        Value v = stack.top();
        stack.pop();
        return v;
    };

    auto asDouble = [](const Value& v) -> double {
        if (v.isNumber()) return v.n;
        throw std::runtime_error("runtime: expected number, got string");
    };

    auto printValue = [](const Value& v) {
        if (v.isNumber()) std::cout << v.n; else std::cout << v.asString();
    };

    while (true) {
        Op op = static_cast<Op>(chunk.code[ip++]);
        switch (op) {
            case Op::LOAD_CONST:
                stack.push(chunk.constants[readU16()]);
                break;

            case Op::LOAD_VAR: {
                uint16_t idx = readU16();
                if (!vars_init[idx])
                    throw std::runtime_error("runtime: undefined variable '" + chunk.identifiers[idx] + "'");
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

            case Op::GT:  { auto b = pop(), a = pop(); stack.push(asDouble(a) > asDouble(b) ? 1.0 : 0.0); break; }
            case Op::LT:  { auto b = pop(), a = pop(); stack.push(asDouble(a) < asDouble(b) ? 1.0 : 0.0); break; }

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
                uint8_t  argc     = chunk.code[ip++];
                const std::string& name = chunk.identifiers[name_idx];

                if (name == "time") {
                    auto now = std::chrono::system_clock::now();
                    double t = std::chrono::duration<double>(now.time_since_epoch()).count();
                    stack.push(t);
                } else if (name == "print") {
                    std::vector<Value> args(argc);
                    for (int i = argc - 1; i >= 0; --i)
                        args[i] = pop();
                    for (int i = 0; i < argc; ++i) {
                        if (i) std::cout << ' ';
                        printValue(args[i]);
                    }
                    std::cout << '\n';
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
                stack.push(thrown);
                ip = h.catch_addr;
                break;
            }

            case Op::HALT:
                return;
        }
    }
}
