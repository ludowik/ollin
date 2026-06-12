#pragma once
#include <cstdint>
#include <string>
#include <variant>
#include <vector>

using Value = std::variant<double, std::string>;

enum class Op : uint8_t {
    LOAD_CONST,      // uint16 index → constants
    LOAD_VAR,        // uint16 index → identifiers
    STORE_VAR,       // uint16 index → identifiers
    ADD, SUB, MUL, DIV,
    GT, LT,          // pop b,a → push a>b (1.0 ou 0.0)
    JUMP,            // uint16 addr absolu
    JUMP_IF_FALSE,   // uint16 addr absolu ; pop cond
    CALL,            // uint16 name_index, uint8 argc
    TRY,             // uint16 catch_addr  — empile un handler
    POP_TRY,         // dépile le handler  (try body terminé sans throw)
    THROW,           // pop value → saute vers le handler courant
    HALT
};

struct Chunk {
    std::vector<uint8_t>   code;
    std::vector<Value>     constants;
    std::vector<std::string> identifiers;

    uint16_t addConstant(Value v);
    uint16_t addIdentifier(const std::string& name);

    void   emit(Op op);
    void   emitU16(Op op, uint16_t arg);
    void   emitCall(uint16_t name_idx, uint8_t argc);
    size_t emitJump(Op op);
    void   patchJump(size_t pos, uint16_t target);
    size_t currentPos() const { return code.size(); }
};
