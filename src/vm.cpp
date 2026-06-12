#include "vm.h"
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
        if (stack.empty()) throw std::runtime_error("stack underflow");
        Value v = stack.top();
        stack.pop();
        return v;
    };

    auto asDouble = [](const Value& v) -> double {
        if (auto* d = std::get_if<double>(&v)) return *d;
        throw std::runtime_error("expected number, got string");
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
                    throw std::runtime_error("undefined variable: " + name);
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
                if (bd == 0.0) throw std::runtime_error("division by zero");
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

                if (name == "print") {
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

            case Op::HALT:
                return;
        }
    }
}
