#pragma once
#include <cstdint>
#include <string>
#include <vector>

enum class Op : uint8_t {
    LOAD_CONST,      // uint16 index → constants
    LOAD_VAR,        // uint16 index → identifiers
    STORE_VAR,       // uint16 index → identifiers
    ADD, SUB, MUL, DIV,
    GT, LT,          // pop b,a → push a>b (1.0 ou 0.0)
    JUMP,            // uint16 addr absolu
    JUMP_IF_FALSE,   // uint16 addr absolu ; pop cond
    CALL,            // uint16 name_index, uint8 argc
    HALT
};

struct Chunk {
    std::vector<uint8_t>   code;
    std::vector<double>    constants;
    std::vector<std::string> identifiers;

    uint16_t addConstant(double v);
    uint16_t addIdentifier(const std::string& name);

    void   emit(Op op);
    void   emitU16(Op op, uint16_t arg);
    void   emitCall(uint16_t name_idx, uint8_t argc);
    size_t emitJump(Op op);                        // émet un jump avec placeholder, retourne la position
    void   patchJump(size_t pos, uint16_t target); // corrige le placeholder
    size_t currentPos() const { return code.size(); }
};
