#pragma once
#include <cstdint>

// ── 32-bit fixed-size instruction format ─────────────────────────────────────
// Format ABC:  [OP:8][A:8][B:8][C:8]   — 3-address ops
// Format ABx:  [OP:8][A:8][Bx:16]      — reg + 16-bit index/addr
// Format Bx:   [OP:8][0:8][Bx:16]      — unconditional jump

using Instr = uint32_t;

inline uint8_t i_op(Instr i) noexcept {
    return (i >> 24) & 0xFF;
}
inline uint8_t i_a(Instr i) noexcept {
    return (i >> 16) & 0xFF;
}
inline uint8_t i_b(Instr i) noexcept {
    return (i >> 8) & 0xFF;
}
inline uint8_t i_c(Instr i) noexcept {
    return i & 0xFF;
}
inline uint16_t i_bx(Instr i) noexcept {
    return i & 0xFFFF;
}

inline Instr make_abc(uint8_t op, uint8_t a, uint8_t b, uint8_t c) noexcept {
    return ((uint32_t)op << 24) | ((uint32_t)a << 16) | ((uint32_t)b << 8) | c;
}
inline Instr make_abx(uint8_t op, uint8_t a, uint16_t bx) noexcept {
    return ((uint32_t)op << 24) | ((uint32_t)a << 16) | bx;
}
inline Instr make_bx(uint8_t op, uint16_t bx) noexcept {
    return ((uint32_t)op << 24) | bx;
}

enum class Op : uint8_t {
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
    FOR_ITER_NEXT,  // ABx: R[A]=iter; next→R[A+1]=key,R[A+2]=val; épuisé→ip=Bx
    FOR_ITER_NEXT1, // ABx: R[A]=iter; next→R[A+1]=primary(key ou val); épuisé→ip=Bx
    LOAD_FUNC,      // ABx: R[A] = func_value(Bx)
    CALL_DYN,       // ABC: A=arg_base, B=func_val_reg, C=argc
    MAKE_CLOSURE,   // ABx: A=dest, Bx=func_idx → create closure, capture upvals from current frame
    GET_UPVAL,      // AB:  A=dest, B=upval_idx → R[A] = upval[B]
    SET_UPVAL,      // AB:  A=src,  B=upval_idx → upval[B] = R[A]
    NEW_CLASS,      // A:   R[A] = T_CLASS (nouvelle map prototype vide)
    CALL_METHOD,    // ABC: A=call_base, C=argc  R[A]=self R[A+1]=method R[A+2..]=args
    MAKE_RANGE,     // ABC: A=dest, B=first_reg (start=R[B],end=R[B+1],step=R[B+2] if has_step), C=flags
                    // (bit0=incl_right,bit1=has_step)
    FOR_PREP, // ABx: for numérique — R[A]=i, R[A+1]=limite, R[A+2]=pas. valide, normalise int/float, i-=pas, ip=Bx
              // (vers FOR_LOOP)
    FOR_LOOP, // ABx: i+=pas ; si dans la limite (incl) → R[A]=i, ip=Bx (corps) ; sinon continue (sortie)
    SPREAD_RESULTS, // AB: destructuration multi-retour — met R[A+last_results..A+B-1] à nil
    CALL_VA,        // ABC: A=arg_base, B=func_val_reg, C=n_fixe ; argc = C + last_results_ (dernier
                    // argument = appel multi-valeurs, déjà matérialisé après les fixes)
    CALL_VARARGS,   // ABC: A=arg_base(fixes), B=func_val_reg, C=n_fixe ; dernier argument = `...`.
                    // Rassemble fixes + varargs du frame courant dans une zone FRAÎCHE (au-dessus
                    // des varargs de l'appelant → aucun écrasement), appelle, et renvoie les
                    // résultats à A (result_base du frame appelé).
    ARRAY_PUSH_SPREAD,  // AB: pousse last_results_ valeurs R[B..] dans le tableau R[A] (spread appel)
    ARRAY_PUSH_VARARGS, // A: pousse TOUTES les varargs du frame courant dans le tableau R[A] ([..., ...])
    MOVE_RESULTS,       // AB: copie last_results_ valeurs R[B..] → R[A..] (recompose un spread imbriqué)
    RETURN_SPREAD,      // AB: return B explicites + last_results_ (dernier = appel), contigus à R[A..]
    SEAL_ENUM,          // A: la map de R[A] devient un enum — toute écriture indexée est refusée
    HALT,
};
