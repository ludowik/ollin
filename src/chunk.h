#pragma once
#include "value.h"
#include "opcode.h"
#include <string>
#include <unordered_map>
#include <vector>

struct UpvalDesc {
    bool    is_local;  // true = capture local reg from enclosing frame; false = pass through upval
    uint8_t idx;       // register index (is_local) or upvalue index of enclosing closure
};

struct FuncProto {
    uint32_t addr;
    uint8_t  n_fixed;
    bool     variadic;
    bool     is_static = false;
    uint16_t defaults_idx;
    uint8_t  reg_count;
    std::vector<UpvalDesc> upvals;
};

struct Chunk {
    std::vector<Instr>       code;
    std::vector<int>         lines;    // parallel to code[] — source line per instruction
    std::vector<Value>       constants;
    std::vector<std::string> identifiers;
    std::unordered_map<std::string, uint16_t> identifier_map_;
    std::vector<std::vector<Value>> func_defaults;
    std::vector<FuncProto>   funcs;
    uint8_t                  top_reg_count = 8;
    int                      current_line_ = 0;

    void   setLine(int l) { current_line_ = l; }

    uint16_t addConstant(Value v);
    uint16_t addIdentifier(const std::string& name);
    uint16_t addFuncDefaults(std::vector<Value> defs);
    uint8_t  addFunc(FuncProto fp);

    void   emit(Instr i);
    size_t emitJump(Op op, uint8_t a = 0);
    void   patchJump(size_t pos, uint16_t target);
    size_t currentPos() const { return code.size(); }
};
