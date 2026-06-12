#include "vm.h"
#include <chrono>
#include <iostream>
#include <stdexcept>
#include <vector>

void VM::execute(const Chunk& chunk) {
    int ip = 0;

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
        if (auto* d = std::get_if<double>(&v)) return *d;
        throw std::runtime_error("runtime: expected number, got string");
    };

    auto printValue = [](const Value& v) {
        std::visit([](auto&& x) { std::cout << x; }, v);
    };

    while (true) {
        Op op = static_cast<Op>(chunk.code[ip++]);
        switch (op) {
            case Op::LOAD_CONST:
                stack.push(chunk.constants[readU16()]);
                break;

            case Op::LOAD_VAR: {
                const std::string& name = chunk.identifiers[readU16()];
                auto it = vars.find(name);
                if (it == vars.end())
                    throw std::runtime_error("runtime: undefined variable '" + name + "'");
                stack.push(it->second);
                break;
            }

            case Op::STORE_VAR: {
                const std::string& name = chunk.identifiers[readU16()];
                vars[name] = pop();
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
                    std::string msg = std::visit([](auto&& v) -> std::string {
                        if constexpr (std::is_same_v<std::decay_t<decltype(v)>, std::string>)
                            return v;
                        else
                            return std::to_string(v);
                    }, thrown);
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
