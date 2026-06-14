#pragma once
#include "chunk.h"
#include <iostream>
#include <memory>
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
        int      return_ip;
        int      stack_base;
        int      n_fixed;
        int      locals_base;    // offset into VM::locals_pool
        int      locals_count;   // slots currently in use
        uint64_t init_mask = 0;  // bit i = locals_pool[locals_base+i] initialised
        // null pour les fonctions non-variadiques (évite 24 octets de vector vide)
        std::unique_ptr<std::vector<Value>> varargs;
    };

    const Chunk* ch = nullptr;
    int          ip = 0;

    std::vector<Value>   stack;        // opérande stack (vector → reserve possible)
    std::vector<Value>   vars;
    std::vector<bool>    vars_init;
    std::vector<Handler> handler_stack;
    std::vector<Frame>   call_stack;
    std::vector<Value>   locals_pool;  // pool plat partagé par tous les frames
    int                  ret_count = 0;

    [[gnu::always_inline]] inline uint8_t  readU8()  { return ch->code[ip++]; }
    [[gnu::always_inline]] inline uint16_t readU16() {
        uint16_t v = (static_cast<uint16_t>(ch->code[ip]) << 8) | ch->code[ip + 1];
        ip += 2;
        return v;
    }

    // pop() sans check : le bytecode produit par le compilateur ne peut pas underflow
    [[gnu::always_inline]] inline Value pop() {
        Value v = std::move(stack.back());
        stack.pop_back();
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
