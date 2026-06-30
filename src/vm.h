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
    static VM* current();                           // returns s_current_vm
    Value callValue(const Value& fn);               // calls an Ollin function from C++
    Value getGlobal(const std::string& name) const; // returns nil if not found

  private:
    int errLine() const;             // extracted from the lambda in execute()
    void runGoto(size_t stop_depth); // unified computed-goto dispatch loop
    struct Handler {
        uint32_t catch_addr;
        uint8_t catch_reg;
        int reg_base;
        size_t regs_size;
        size_t call_depth;
    };

    struct Frame {
        uint32_t return_ip = 0;
        int reg_base = 0;
        int varargs_base = 0; // = reg_base + fp.reg_count (where varargs live in regs)
        int n_varargs = 0;    // count of extra variadic args (0 if none)
        bool is_ctor = false; // true = frame is a constructor; RETURN overrides R[0] with instance
        int return_dest = -1; // >= 0: RETURN stores R[0] into regs[return_dest] (metamethod result)
        std::unique_ptr<std::vector<Upvalue*>> upvals;
        std::unique_ptr<std::vector<Upvalue*>> open_upvals;
    };

    Chunk owned_chunk;
    const Chunk* ch = nullptr;
    Value string_module_;
    uint32_t ip = 0;
    std::vector<Value> globals;
    std::vector<bool> globals_init;
    std::vector<Value> regs;
    std::vector<Frame> call_stack;
    std::vector<Handler> handler_stack;

    static Value protoChainGet(const Value& obj, const Value& key);

    static bool isInstance(const Value& v);

    uint32_t tryMetaBinary(const Value& name, int dest, Value lhs, Value rhs);
    uint32_t tryMetaUnary(const Value& name, int dest, Value lhs);
    void closeUpvals();           // closes & frees all open upvalues of the top frame
    void growRegs(size_t needed); // croît par doublement, max 4096, jamais rétrécit

    // Pousse un frame d'appel, remplit les défauts et varargs, retourne fp.addr.
    uint32_t pushCallFrame(int new_base, uint8_t fi, int argc, std::unique_ptr<std::vector<Upvalue*>> fuv,
                           uint32_t return_ip, bool is_ctor = false, int return_dest = -1);

    [[gnu::always_inline]] inline double asDouble(const Value& v) {
        if (v.isInteger())
            return (double)v.asInt();
        if (v.isFloat())
            return v.asFloat();
        if (v.isNil())
            throw std::runtime_error("runtime: expected number, got nil");
        throw std::runtime_error("runtime: expected number, got string");
    }
};
