#pragma once
#include "chunk.h"
#include <iostream>
#include <stack>
#include <stdexcept>
#include <vector>

class VM {
public:
    void execute(const Chunk& chunk);

private:
    struct Handler {
        uint16_t catch_addr;
        size_t   stack_size;
    };

    const Chunk* ch = nullptr;
    int          ip = 0;

    std::stack<Value, std::vector<Value>> stack;
    std::vector<Value>   vars;
    std::vector<bool>    vars_init;
    std::vector<Handler> handler_stack;

    [[gnu::always_inline]] inline uint16_t readU16() {
        uint16_t v = (static_cast<uint16_t>(ch->code[ip]) << 8) | ch->code[ip + 1];
        ip += 2;
        return v;
    }

    [[gnu::always_inline]] inline Value pop() {
        if (stack.empty()) throw std::runtime_error("runtime: stack underflow");
        Value v = std::move(const_cast<Value&>(stack.top()));
        stack.pop();
        return v;
    }

    [[gnu::always_inline]] inline double asDouble(const Value& v) {
        if (v.isNumber()) return v.n;
        throw std::runtime_error("runtime: expected number, got string");
    }

    [[gnu::always_inline]] inline void printValue(const Value& v) {
        if (v.isNumber()) std::cout << v.n; else std::cout << v.asString();
    }
};
