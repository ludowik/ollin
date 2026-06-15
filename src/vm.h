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
        uint32_t catch_addr;
        uint8_t  catch_reg;
        int      reg_base;
        size_t   regs_size;
        size_t   call_depth;
    };

    struct Frame {
        uint32_t return_ip;
        int      reg_base;
        std::unique_ptr<std::vector<Value>> varargs;
        std::vector<Upvalue*> upvals;       // upvalues from the closure that called us
        std::vector<Upvalue*> open_upvals;  // upvalues we opened for inner closures
    };

    const Chunk*         ch = nullptr;
    uint32_t             ip = 0;
    std::vector<Value>   globals;
    std::vector<bool>    globals_init;
    std::vector<Value>   regs;
    std::vector<Frame>   call_stack;
    std::vector<Handler> handler_stack;

    [[gnu::always_inline]] inline double asDouble(const Value& v) {
        if (v.isInteger()) return (double)v.asInt();
        if (v.isFloat())   return v.asFloat();
        if (v.isNil())     throw std::runtime_error("runtime: expected number, got nil");
        throw std::runtime_error("runtime: expected number, got string");
    }

    [[gnu::always_inline]] inline void printValue(const Value& v) {
        if (v.isNil())                      std::cout << "nil";
        else if (v.isString())              std::cout << v.asString();
        else if (v.isMap())                 std::cout << "{map}";
        else if (v.isArray())               std::cout << "{array}";
        else if (v.isCallable())            std::cout << "{function}";
        else if (v.isInteger())             std::cout << v.asInt();
        else {
            double d = v.asFloat();
            if (d == (long long)d && d >= -1e15 && d <= 1e15)
                std::cout << (long long)d;
            else
                std::cout << d;
        }
    }
};
