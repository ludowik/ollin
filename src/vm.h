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

    struct Frame {
        int    return_ip;
        size_t stack_base;
        int    n_fixed;
        std::vector<Value> locals;
        std::vector<bool>  locals_init;
        std::vector<Value> varargs;
    };

    const Chunk* ch = nullptr;
    int          ip = 0;

    std::stack<Value, std::vector<Value>> stack;
    std::vector<Value>   vars;
    std::vector<bool>    vars_init;
    std::vector<Handler> handler_stack;
    std::vector<Frame>   call_stack;
    int                  ret_count = 0;

    // Lecture sans vérification — sûre uniquement après checkBounds(n)
    [[gnu::always_inline]] inline uint8_t  readU8()  { return ch->code[ip++]; }
    [[gnu::always_inline]] inline uint16_t readU16() {
        uint16_t v = (static_cast<uint16_t>(ch->code[ip]) << 8) | ch->code[ip + 1];
        ip += 2;
        return v;
    }

    // Vérifie qu'il reste au moins n octets à partir de ip
    [[gnu::always_inline]] inline void checkBounds(int n) {
        if (ip + n > (int)ch->code.size())
            throw std::runtime_error("runtime: bytecode tronqué");
    }

    [[gnu::always_inline]] inline Value pop() {
        if (stack.empty()) throw std::runtime_error("runtime: stack underflow");
        Value v = std::move(stack.top());
        stack.pop();
        return v;
    }

    [[gnu::always_inline]] inline double asDouble(const Value& v) {
        if (v.isNumber()) return v.asNum();
        if (v.isNil()) throw std::runtime_error("runtime: expected number, got nil");
        throw std::runtime_error("runtime: expected number, got string");
    }

    [[gnu::always_inline]] inline void printValue(const Value& v) {
        if (v.isNil())         std::cout << "nil";
        else if (v.isString()) std::cout << v.asString();
        else                   std::cout << v.asNum();
    }
};
