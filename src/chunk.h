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

// ── 32-bit fixed-size instruction format ─────────────────────────────────────
// Format ABC:  [OP:8][A:8][B:8][C:8]   — 3-address ops
// Format ABx:  [OP:8][A:8][Bx:16]      — reg + 16-bit index/addr
// Format Bx:   [OP:8][0:8][Bx:16]      — unconditional jump

using Instr = uint32_t;

inline uint8_t  iOP (Instr i) noexcept { return (i >> 24) & 0xFF; }
inline uint8_t  iA  (Instr i) noexcept { return (i >> 16) & 0xFF; }
inline uint8_t  iB  (Instr i) noexcept { return (i >>  8) & 0xFF; }
inline uint8_t  iC  (Instr i) noexcept { return  i        & 0xFF; }
inline uint16_t iBx (Instr i) noexcept { return  i        & 0xFFFF; }

inline Instr makeABC(uint8_t op, uint8_t a, uint8_t b, uint8_t c) noexcept {
    return ((uint32_t)op<<24)|((uint32_t)a<<16)|((uint32_t)b<<8)|c;
}
inline Instr makeABx(uint8_t op, uint8_t a, uint16_t bx) noexcept {
    return ((uint32_t)op<<24)|((uint32_t)a<<16)|bx;
}
inline Instr makeBx(uint8_t op, uint16_t bx) noexcept {
    return ((uint32_t)op<<24)|bx;
}

enum class Op : uint8_t {
    LOAD_K,       // ABx: R[A] = K[Bx]
    LOAD_NIL,     // A:   R[A] = nil
    MOVE,         // AB:  R[A] = R[B]
    LOAD_GLOBAL,  // ABx: R[A] = G[Bx]
    STORE_GLOBAL, // ABx: G[Bx] = R[A]
    ADD, SUB, MUL, DIV, MOD,   // ABC: R[A] = R[B] op R[C]
    NEGATE, NOT,                // AB:  R[A] = op R[B]
    AND, OR,                    // ABC: R[A] = !falsy(R[B]) && !falsy(R[C])
    EQ, NEQ, GT, LT, GE, LE,   // ABC: R[A] = R[B] cmp R[C] → 1.0 or 0.0
    JUMP,           // Bx: ip = Bx
    JUMP_IF_FALSE,  // ABx: if falsy(R[A]) ip = Bx
    CALL_FUNC,      // ABC: A=base_reg, B=func_idx (into chunk.funcs), C=argc
    RETURN,         // AB: copy R[A..A+B-1] → R[0..B-1], pop frame (B=0 means void)
    LOAD_VARARGS,   // AB: R[A..A+B-1] = varargs (B=0 means all)
    RETURN_V,       // AB: return B explicit values from R[A] then append varargs
    CALL_PRINT,     // AB: print B args from R[A]
    CALL_PRINTF,    // AB: printf B args from R[A]
    CALL_ASSERT,    // AB: assert B args from R[A]
    CALL_TIME,      // A: R[A] = time()
    TRY,            // ABx: push handler{catch_addr=Bx, catch_reg=A}
    POP_TRY,        // (no operands)
    THROW,          // A: throw R[A]
    HALT,
};

struct FuncProto {
    uint32_t addr;         // instruction index in chunk.code
    uint8_t  n_fixed;      // number of fixed parameters
    bool     variadic;
    uint16_t defaults_idx;
    uint8_t  reg_count;    // max registers the function uses (for resize)
};

struct Chunk {
    std::vector<Instr>       code;
    std::vector<Value>       constants;
    std::vector<std::string> identifiers;
    std::vector<std::vector<Value>> func_defaults;
    std::vector<FuncProto>   funcs;
    uint8_t                  top_reg_count = 8;  // for top-level code

    uint16_t addConstant(Value v);
    uint16_t addIdentifier(const std::string& name);
    uint16_t addFuncDefaults(std::vector<Value> defs);
    uint8_t  addFunc(FuncProto fp);

    void   emit(Instr i);
    size_t emitJump(Op op, uint8_t a = 0);
    void   patchJump(size_t pos, uint16_t target);
    size_t currentPos() const { return code.size(); }
};
