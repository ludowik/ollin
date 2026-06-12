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

    auto pop = [&]() -> double {
        if (stack.empty()) throw std::runtime_error("stack underflow");
        double v = stack.top();
        stack.pop();
        return v;
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

            case Op::ADD: { double b = pop(), a = pop(); stack.push(a + b); break; }
            case Op::SUB: { double b = pop(), a = pop(); stack.push(a - b); break; }
            case Op::MUL: { double b = pop(), a = pop(); stack.push(a * b); break; }
            case Op::DIV: {
                double b = pop(), a = pop();
                if (b == 0.0) throw std::runtime_error("division by zero");
                stack.push(a / b);
                break;
            }

            case Op::CALL: {
                uint16_t name_idx = readU16();
                uint8_t  argc     = chunk.code[ip++];
                const std::string& name = chunk.identifiers[name_idx];

                if (name == "print") {
                    std::vector<double> args(argc);
                    for (int i = argc - 1; i >= 0; --i)
                        args[i] = pop();
                    for (int i = 0; i < argc; ++i) {
                        if (i) std::cout << ' ';
                        std::cout << args[i];
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
