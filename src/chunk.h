#pragma once
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

// NaN-boxing : Value = 8 octets (un uint64_t).
//
// IEEE 754 quiet NaN : exposant=0x7FF + bit 51 (quiet) = 0x7FF8_0000_0000_0000
// On réserve deux masques au-dessus de ce seuil pour nos types non-numériques :
//
//   Nombre   : tout double dont (bits & QNAN) != QNAN  (double normal ou NaN "nu")
//   Nil      : NIL_BITS  = 0x7FFF_0000_0000_0001       (valeur sentinelle unique)
//   String   : STAG      = 0xFFFF_0000_0000_0000 | ptr48
//              (bit 63=1 garantit qu'aucun double positif ne collide)
//
// Les pointeurs heap macOS/Linux tiennent en 48 bits → ptr & PMSK est réversible.

struct Value {
    uint64_t bits;

private:
    static constexpr uint64_t QNAN = 0x7FF8000000000000ULL;
    static constexpr uint64_t NIL  = 0x7FFF000000000001ULL;
    static constexpr uint64_t STAG = 0xFFFF000000000000ULL;
    static constexpr uint64_t PMSK = 0x0000FFFFFFFFFFFFULL;

    std::string* strPtr() const { return reinterpret_cast<std::string*>(bits & PMSK); }
    static uint64_t mkStr(std::string* p) { return STAG | (reinterpret_cast<uint64_t>(p) & PMSK); }

public:
    Value()             : bits(NIL) {}
    Value(double d)     { std::memcpy(&bits, &d, 8); }
    Value(std::string v): bits(mkStr(new std::string(std::move(v)))) {}

    Value(const Value& o) : bits(o.bits) {
        if (isString()) bits = mkStr(new std::string(asString()));
    }
    Value(Value&& o) noexcept : bits(o.bits) { o.bits = NIL; }
    Value& operator=(const Value& o) {
        if (this == &o) return *this;
        // Allouer d'abord pour être exception-safe (pas de delete avant succès)
        std::string* new_ptr = o.isString() ? new std::string(o.asString()) : nullptr;
        if (isString()) delete strPtr();
        bits = new_ptr ? mkStr(new_ptr) : o.bits;
        return *this;
    }
    Value& operator=(Value&& o) noexcept {
        if (this == &o) return *this;
        if (isString()) delete strPtr();
        bits = o.bits; o.bits = NIL;
        return *this;
    }
    ~Value() { if (isString()) delete strPtr(); }

    bool isNil()    const { return bits == NIL; }
    bool isNumber() const { return (bits & QNAN) != QNAN; }
    bool isString() const { return (bits & STAG) == STAG; }

    double asNum()                const { double d; std::memcpy(&d, &bits, 8); return d; }
    const std::string& asString() const { return *strPtr(); }
};

inline bool isFalsy(const Value& v) {
    if (v.isNil())    return true;
    if (v.isNumber()) return v.asNum() == 0.0;
    if (v.isString()) return v.asString().empty();
    return true;
}

enum class Op : uint8_t {
    LOAD_CONST,      // uint16 index → constants
    LOAD_VAR,        // uint16 index → identifiers
    STORE_VAR,       // uint16 index → identifiers
    ADD, SUB, MUL, DIV, MOD,
    NEGATE, NOT_OP,
    OR_OP, AND_OP,
    GT, LT, GE, LE, NEQ,  // pop b,a → push résultat (1.0 ou 0.0)
    EQ,              // pop b,a → push a==b (1.0 ou 0.0)
    JUMP,            // uint16 addr absolu
    JUMP_IF_FALSE,   // uint16 addr absolu ; pop cond
    CALL,            // uint16 name_index, uint8 argc
    TRY,             // uint16 catch_addr  — empile un handler
    POP_TRY,         // dépile le handler  (try body terminé sans throw)
    THROW,           // pop value → saute vers le handler courant
    LOAD_LOCAL,      // uint16 idx → frame.locals
    STORE_LOCAL,     // uint16 idx → frame.locals
    CALL_FUNC,       // uint16 addr, uint8 n_fixed, uint8 argc, uint8 variadic
    RETURN_N,        // uint8 n — retourne n valeurs explicites
    RETURN_V,        // uint8 n — n valeurs explicites + varargs
    LOAD_VARARGS,    // push tous les varargs du frame courant
    DISCARD_RETURNS, // pop ret_count valeurs
    POP,             // dépile et jette la valeur du sommet
    HALT
};

struct Chunk {
    std::vector<uint8_t>   code;
    std::vector<Value>     constants;
    std::vector<std::string> identifiers;
    std::vector<std::vector<Value>> func_defaults; // valeurs par défaut par fonction

    uint16_t addConstant(Value v);
    uint16_t addIdentifier(const std::string& name);
    uint16_t addFuncDefaults(std::vector<Value> defs);

    void   emit(Op op);
    void   emitU16(Op op, uint16_t arg);
    void   emitU8(Op op, uint8_t arg);
    void   emitCall(uint16_t name_idx, uint8_t argc);
    void   emitCallFunc(uint16_t addr, uint8_t n_fixed, uint8_t argc, bool variadic, uint16_t defaults_idx);
    size_t emitJump(Op op);
    void   patchJump(size_t pos, uint16_t target);
    size_t currentPos() const { return code.size(); }
};
