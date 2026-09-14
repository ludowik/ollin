#pragma once
#include <cassert>
#include <cstdint>

// Fixed-size instruction format, in THREE forms.
// Format ABC:  [OP][A][B][C]   3-address ops
// Format ABx:  [OP][A][ Bx ]   register + index or address, Bx spanning B and C
// Format Bx:   [OP][0][ Bx ]   unconditional jump
//
// The widths below are the ONE place that says how wide a field is: the packing, the accessors,
// the bounds and their error messages are all derived from them. No emitter carries a width of
// its own, so making an operand wider is a change to these lines alone — and the static_assert
// refuses a set that does not fill the word.

using Instr = uint32_t;

constexpr unsigned k_op_bits = 8;
constexpr unsigned k_field_bits = 8;             // A, B and C
constexpr unsigned k_bx_bits = 2 * k_field_bits; // Bx spans B and C
static_assert(k_op_bits + 3 * k_field_bits == 8 * sizeof(Instr), "the three fields must fill the word");

// The type of a field READ from an instruction. Named per role, so that widening a role is one
// line here rather than a hunt through the engine for the sites that happen to hold it.
using OpByte = uint8_t; // the opcode itself, and the underlying type of enum class Op
using Field = uint8_t;  // a register index, a small count, a mode
using Wide = uint16_t;  // Bx: a constant, an identifier, a function, a code address
static_assert(8 * sizeof(OpByte) >= k_op_bits, "OpByte must hold an opcode");
static_assert(8 * sizeof(Field) >= k_field_bits, "Field must hold a field");
static_assert(8 * sizeof(Wide) >= k_bx_bits, "Wide must hold a Bx");

// The four ROLES an operand plays, named so that a declaration says what it holds rather than how
// wide it is today. Widening a role is then a single line, and every site that carries it follows.
using RegIdx = Field;  // a register of the current frame
using FuncIdx = Field; // a function of the chunk, as CALL_FUNC names it
using PoolIdx = Wide;  // an index into a chunk pool: constants, identifiers, defaults, tables
using CodeAddr = Wide; // an instruction address, which is what a jump carries

constexpr uint64_t k_op_max = (uint64_t(1) << k_op_bits) - 1;
constexpr uint64_t k_field_max = (uint64_t(1) << k_field_bits) - 1;
constexpr uint64_t k_bx_max = (uint64_t(1) << k_bx_bits) - 1;

// The engine's five ceilings, each the largest value the field that carries it can hold. Spelled
// here so that the guard and its error message read the same number, and so that a program
// meeting one of them is refused rather than silently truncated. Every guard has the same shape,
// `count >= ceiling`, so that the message names exactly what is allowed.
constexpr uint64_t k_max_reg = k_field_max;   // registers per frame (A, B, C name one)
constexpr uint64_t k_max_upval = k_field_max; // upvalues captured by one function (GET_UPVAL)
constexpr uint64_t k_max_pool = k_bx_max;     // constants, identifiers, switch tables, defaults
// The callee of a CALL_FUNC is named in ONE field, not in a Bx — hence the tightest ceiling of
// the set, and the only one that is a property of a single opcode rather than of the format.
constexpr uint64_t k_max_func = k_field_max;
constexpr uint64_t k_max_code = k_bx_max; // instructions in a program (a jump target is Bx)

enum class Op : OpByte {
    LOAD_K,       // ABx: R[A] = K[Bx]
    LOAD_NIL,     // A:   R[A] = nil
    MOVE,         // AB:  R[A] = R[B]
    LOAD_GLOBAL,  // ABx: R[A] = G[Bx]
    STORE_GLOBAL, // ABx: G[Bx] = R[A]
    ADD,
    SUB,
    MUL,
    DIV,
    MOD,
    IDIV,
    POW, // ABC: R[A] = R[B] op R[C]
    NEGATE,
    NOT, // AB:  R[A] = op R[B]
    AND,
    OR, // ABC: logical and/or → 0 or 1
    EQ,
    NEQ,
    GT,
    LT,
    GE,
    LE,            // ABC: R[A] = R[B] cmp R[C] → 0 or 1
    JUMP,          // Bx: ip = Bx
    JUMP_IF_FALSE, // ABx: if falsy(R[A]) ip = Bx
    CALL_FUNC,     // ABC: A=base_reg, B=func_idx, C=argc
    RETURN,        // AB: copy R[A..A+B-1] → R[0..B-1], pop frame
    LOAD_VARARGS,  // AB: R[A..A+B-1] = varargs
    RETURN_V,      // AB: return B explicit + varargs
    TRY,           // ABx: push handler{catch_addr=Bx, catch_reg=A}
    POP_TRY,
    THROW,     // A: throw R[A]
    NEW_MAP,   // A: R[A] = {}
    GET_INDEX, // ABC: R[A] = R[B][R[C]]  (map→Value key, array→int 1-based)
    SET_INDEX, // ABC: R[A][R[B]] = R[C]  (map→Value key, array→int 1-based)
    MAKE_ITER, // AB: R[A] = iterator(R[B])  (Map ou Array)
    BAND,
    BOR,
    BXOR,
    BNOT,
    BLSHIFT,
    BRSHIFT,        // bitwise (integers)
    NEW_ARRAY,      // A: R[A] = []
    ARRAY_PUSH,     // AB: R[A].push(R[B])
    FOR_ITER_NEXT,  // ABx: R[A]=iter; next gives R[A+1]=key, R[A+2]=val; exhausted jumps to Bx
    FOR_ITER_NEXT1, // ABx: R[A]=iter; next gives R[A+1]=primary (key or value); exhausted jumps to Bx
    LOAD_FUNC,      // ABx: R[A] = func_value(Bx)
    CALL_DYN,       // ABC: A=arg_base, B=func_val_reg, C=argc
    MAKE_CLOSURE,   // ABx: A=dest, Bx=func_idx → create closure, capture upvals from current frame
    GET_UPVAL,      // AB:  A=dest, B=upval_idx → R[A] = upval[B]
    SET_UPVAL,      // AB:  A=src,  B=upval_idx → upval[B] = R[A]
    NEW_CLASS,      // A:   R[A] = T_CLASS (a fresh, empty prototype map)
    CALL_METHOD,    // ABC: A=call_base, C=argc  R[A]=self R[A+1]=method R[A+2..]=args
                    // B = the tail's MODE: 0 none, 1 `...` (frame varargs), 2 a call (last_results_)
    MAKE_RANGE,     // ABC: A=dest, B=first_reg (start=R[B],end=R[B+1],step=R[B+2] if has_step), C=flags
                    // (bit0 = incl_right, bit1 = has_step)
    FOR_PREP, // ABx: a numeric for — R[A]=i, R[A+1]=limit, R[A+2]=step. It validates, normalises int/float, does
              // i-=step, then ip=Bx (towards FOR_LOOP)
    FOR_LOOP, // ABx: i+=step; within the limit (inclusive) → R[A]=i, ip=Bx (body); otherwise falls through (exit)
    SPREAD_RESULTS,     // AB: multi-return destructuring — sets R[A+last_results..A+B-1] to nil
    CALL_VA,            // ABC: A=arg_base, B=func_val_reg, C=n_fixed; argc = C + last_results_ (the last
                        // argument is a multi-value call, already materialized after the fixed ones)
    CALL_VARARGS,       // ABC: A=arg_base(the fixed ones), B=func_val_reg, C=n_fixed; the last argument is `...`.
                        // Gathers the fixed arguments and the current frame's varargs into a FRESH area
                        // (above the caller's varargs, so nothing is overwritten), calls, and returns
                        // the results at A, the callee frame's result_base.
    ARRAY_PUSH_SPREAD,  // AB: pushes last_results_ values R[B..] into the array R[A] (a spread call)
    ARRAY_PUSH_VARARGS, // A: pushes ALL of the current frame's varargs into the array R[A] ([..., ...])
    MOVE_RESULTS,       // AB: copies last_results_ values from R[B..] to R[A..], recomposing a nested spread
    RETURN_SPREAD, // AB: returns B explicit values plus last_results_ (the last being a call), contiguous at R[A..]
    SEAL_ENUM,     // A: the map in R[A] becomes an enum, and every indexed write is refused
    CLOSE_UPVALS,  // A: closes the open upvalues whose register is >= A, at the end of a scope
    LEN,           // AB: R[A] = length of R[B] — the '#' operator
    SWITCH,        // ABx: jumps through switch_tables[Bx], indexed by the integer in R[A]
    HALT,
};

// The C field of MAKE_RANGE, a bit per fact. Named on BOTH sides: the compiler composed the
// number and the VM took it apart, each with its own literals and a comment for agreement.
constexpr uint64_t k_range_incl_right = 1;
constexpr uint64_t k_range_has_step = 2;

inline Field i_a(Instr i) noexcept {
    return (i >> (2 * k_field_bits)) & k_field_max;
}
inline Field i_b(Instr i) noexcept {
    return (i >> k_field_bits) & k_field_max;
}
inline Field i_c(Instr i) noexcept {
    return i & k_field_max;
}
inline Wide i_bx(Instr i) noexcept {
    return i & k_bx_max;
}
inline OpByte i_op(Instr i) noexcept {
    return (i >> (3 * k_field_bits)) & k_op_max;
}

// The emitters take VALUES, not fields: an operand computed as an int no longer needs a cast at
// every call site, and a cast is exactly what used to truncate an index in silence. The assert
// is the backstop — the real guards are the named ceilings above, checked where the index is
// handed out (Chunk::add_*, the compiler's register count).
inline Instr make_abc(Op op, uint64_t a, uint64_t b, uint64_t c) noexcept {
    assert(a <= k_field_max && b <= k_field_max && c <= k_field_max);
    return ((Instr)op << (3 * k_field_bits)) | ((Instr)a << (2 * k_field_bits)) | ((Instr)b << k_field_bits) | (Instr)c;
}
inline Instr make_abx(Op op, uint64_t a, uint64_t bx) noexcept {
    assert(a <= k_field_max && bx <= k_bx_max);
    return ((Instr)op << (3 * k_field_bits)) | ((Instr)a << (2 * k_field_bits)) | (Instr)bx;
}
inline Instr make_bx(Op op, uint64_t bx) noexcept {
    assert(bx <= k_bx_max);
    return ((Instr)op << (3 * k_field_bits)) | (Instr)bx;
}
