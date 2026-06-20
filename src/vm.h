#pragma once
#include "chunk.h"
#include <iostream>
#include <memory>
#include <stdexcept>
#include <unordered_map>
#include <vector>

std::string valueToString(const Value& v);

class VM {
public:
    void execute(Chunk chunk);
    std::string invokeStr(Value v);
    static VM* current();                   // returns s_current_vm
    Value callValue(const Value& fn);       // calls an Ollin function from C++
    Value getGlobal(const std::string& name) const; // returns nil if not found

private:
    int  errLine() const;                   // extracted from the lambda in execute()
    void runSwitch(size_t stop_depth);      // complete reusable switch dispatch
    struct Handler {
        uint32_t catch_addr;
        uint8_t  catch_reg;
        int      reg_base;
        size_t   regs_size;
        size_t   call_depth;
    };

    struct Frame {
        uint32_t    return_ip;
        int         reg_base;
        std::unique_ptr<std::vector<Value>> varargs;
        std::vector<Upvalue*> upvals;
        std::vector<Upvalue*> open_upvals;
        Value       ctor_result{};  // non-nil = frame is a constructor; RETURN overrides R[0] with instance
        int         return_dest = -1; // >= 0: RETURN stores R[0] into regs[return_dest] (metamethod result)
    };

    Chunk                owned_chunk;
    const Chunk*         ch = nullptr;
    Value                string_module_;
    uint32_t             ip = 0;
    std::vector<Value>   globals;
    std::vector<bool>    globals_init;
    std::vector<Value>   regs;
    std::vector<Frame>   call_stack;
    std::vector<Handler> handler_stack;

    static Value protoChainGet(const Value& obj, const Value& key);

    static bool isInstance(const Value& v);

    uint32_t tryMetaBinary(const Value& name, int dest, Value lhs, Value rhs);
    uint32_t tryMetaUnary (const Value& name, int dest, Value lhs);
    void     closeUpvals  ();   // closes & frees all open upvalues of the top frame
    void     growRegs(size_t needed); // croît par doublement, max 4096, jamais rétrécit

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
