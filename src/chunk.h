#pragma once
#include <cstdint>
#include <string>
#include <utility>
#include <vector>
#include "string_table.h"

// Tagged union Value — 16 octets (tag + union 8 octets).
//
//   NIL     : tag == T_NIL
//   Integer : tag == T_INTEGER  → int64_t  (range ±2^63)
//   Float   : tag == T_FLOAT    → double IEEE 754
//   String  : tag == T_STRING   → const std::string*  (internée, non-owning)
//   Map     : tag == T_MAP      → Map*     (heap, ref-counted, clés Value)
//   Array   : tag == T_ARRAY    → OllinArray*   (heap, ref-counted, 1-based)

struct Map;
struct OllinArray;

struct Value {
    uint8_t tag;
    union {
        int64_t            ival;
        double             dval;
        const std::string* sptr;  // pointe vers la string_table (non-owning)
        Map*               mptr;
        OllinArray*        aptr;
    };

    static constexpr uint8_t T_NIL     = 0;
    static constexpr uint8_t T_INTEGER = 1;
    static constexpr uint8_t T_FLOAT   = 2;
    static constexpr uint8_t T_STRING  = 3;
    static constexpr uint8_t T_MAP     = 4;
    static constexpr uint8_t T_ARRAY   = 5;

private:
    explicit Value(Map*        p) : tag(T_MAP),   mptr(p) {}
    explicit Value(OllinArray* p) : tag(T_ARRAY), aptr(p) {}

public:
    Value()              : tag(T_NIL), ival(0) {}
    Value(double d)      : tag(T_FLOAT), dval(d) {}
    Value(int64_t v)     : tag(T_INTEGER), ival(v) {}
    Value(std::string v) : tag(T_STRING), sptr(intern(std::move(v))) {}

    Value(const Value& o);
    Value(Value&& o) noexcept : tag(o.tag), ival(o.ival) { o.tag = T_NIL; }
    Value& operator=(const Value& o);
    Value& operator=(Value&& o) noexcept;
    ~Value();

    bool isNil()     const { return tag == T_NIL; }
    bool isFloat()   const { return tag == T_FLOAT; }
    bool isInteger() const { return tag == T_INTEGER; }
    bool isNumber()  const { return tag == T_INTEGER || tag == T_FLOAT; }
    bool isString()  const { return tag == T_STRING; }
    bool isMap()     const { return tag == T_MAP; }
    bool isArray()   const { return tag == T_ARRAY; }

    int64_t asInt()               const { return ival; }
    double  asFloat()             const { return dval; }
    double  asNum()               const { return isInteger() ? (double)ival : dval; }
    const std::string& asString() const { return *sptr; }

    static Value makeMap();
    Value        mapGet(const Value& key)              const;
    void         mapSet(const Value& key, const Value& val);
    int          mapSize()           const;
    const Value& mapKeyAt(int idx)   const;
    Value        mapValAt(int idx)   const;

    static Value makeArray();
    Value  arrayGet(int64_t idx)                    const; // 1-based
    void   arraySet(int64_t idx, const Value& val);        // 1-based, grows if needed
    void   arrayPush(const Value& val);
    int    arraySize()                              const;
};

// ── OllinArray ────────────────────────────────────────────────────────────────
struct OllinArray {
    std::vector<Value> items;
    int refcount = 1;

    Value get(int64_t idx) const {          // 1-based externally
        int64_t i = idx - 1;
        if (i < 0 || i >= (int64_t)items.size()) return Value{};
        return items[(size_t)i];
    }
    void set(int64_t idx, const Value& v) { // 1-based externally, grows if needed
        int64_t i = idx - 1;
        if (i < 0) return;
        if (i >= (int64_t)items.size()) items.resize((size_t)(i + 1));
        items[(size_t)i] = v;
    }
    void push(const Value& v) { items.push_back(v); }
};

struct ArrayPool {
    static constexpr int CAP = 64;
    OllinArray* buf[CAP];
    int         n = 0;

    OllinArray* acquire() {
        if (n) { OllinArray* a = buf[--n]; a->refcount = 1; return a; }
        return new OllinArray();
    }
    void release(OllinArray* a) {
        a->items.clear();
        if (n < CAP) buf[n++] = a;
        else delete a;
    }
};
inline ArrayPool& array_pool() { static ArrayPool p; return p; }

// ── Map (LinkedHashMap, clés Value) — définition complète ────────────────────
#include "map.h"

// ── inline Value implementations (nécessitent Map et OllinArray complets) ────

inline Value Value::makeMap()   { return Value(map_pool().acquire()); }
inline Value Value::makeArray() { return Value(array_pool().acquire()); }

inline Value        Value::mapGet(const Value& k)                  const { return mptr->get(k); }
inline void         Value::mapSet(const Value& k, const Value& v)        { mptr->set(k, v); }
inline int          Value::mapSize()          const { return mptr->size(); }
inline const Value& Value::mapKeyAt(int idx)  const { return mptr->keyAt(idx); }
inline Value        Value::mapValAt(int idx)  const { return mptr->valAt(idx); }

inline Value Value::arrayGet(int64_t idx)                  const { return aptr->get(idx); }
inline void  Value::arraySet(int64_t idx, const Value& v)        { aptr->set(idx, v); }
inline void  Value::arrayPush(const Value& v)                    { aptr->push(v); }
inline int   Value::arraySize()                            const { return (int)aptr->items.size(); }

inline Value::Value(const Value& o) : tag(o.tag), ival(0) {
    switch (tag) {
        case T_NIL:     break;
        case T_INTEGER: ival = o.ival; break;
        case T_FLOAT:   dval = o.dval; break;
        case T_STRING:  sptr = o.sptr; string_table().retain(sptr); break;
        case T_MAP:     mptr = o.mptr; mptr->refcount++; break;
        case T_ARRAY:   aptr = o.aptr; aptr->refcount++; break;
    }
}
inline Value& Value::operator=(const Value& o) {
    if (this == &o) return *this;
    // Retain d'abord (protège si this et o partagent la même ressource)
    switch (o.tag) {
        case T_STRING: string_table().retain(o.sptr); break;
        case T_MAP:    o.mptr->refcount++;             break;
        case T_ARRAY:  o.aptr->refcount++;             break;
        default: break;
    }
    // Release de l'ancienne valeur
    switch (tag) {
        case T_STRING: string_table().release(sptr); break;
        case T_MAP:   { Map*        mp = mptr; if (--mp->refcount == 0) map_pool().release(mp);   break; }
        case T_ARRAY: { OllinArray* ap = aptr; if (--ap->refcount == 0) array_pool().release(ap); break; }
        default: break;
    }
    tag = o.tag; ival = 0;
    switch (tag) {
        case T_NIL:     break;
        case T_INTEGER: ival = o.ival; break;
        case T_FLOAT:   dval = o.dval; break;
        case T_STRING:  sptr = o.sptr; break;
        case T_MAP:     mptr = o.mptr; break;
        case T_ARRAY:   aptr = o.aptr; break;
    }
    return *this;
}
inline Value& Value::operator=(Value&& o) noexcept {
    if (this == &o) return *this;
    // Release de l'ancienne valeur (on prend possession de la référence de o)
    switch (tag) {
        case T_STRING: string_table().release(sptr); break;
        case T_MAP:   { Map*        mp = mptr; if (--mp->refcount == 0) map_pool().release(mp);   break; }
        case T_ARRAY: { OllinArray* ap = aptr; if (--ap->refcount == 0) array_pool().release(ap); break; }
        default: break;
    }
    tag = o.tag; ival = o.ival; o.tag = T_NIL;
    return *this;
}
inline Value::~Value() {
    switch (tag) {
        case T_STRING: string_table().release(sptr); break;
        case T_MAP:   { Map*        mp = mptr; if (--mp->refcount == 0) map_pool().release(mp);   break; }
        case T_ARRAY: { OllinArray* ap = aptr; if (--ap->refcount == 0) array_pool().release(ap); break; }
        default: break;
    }
}

inline bool isFalsy(const Value& v) {
    if (v.isNil())     return true;
    if (v.isInteger()) return v.asInt() == 0;
    if (v.isFloat())   return v.asFloat() == 0.0;
    if (v.isString())  return v.asString().empty();
    return false;  // map, array → toujours truthy
}

inline Value numValue(double d) {
    auto i = static_cast<int64_t>(d);
    if (static_cast<double>(i) == d) return Value(i);
    return Value(d);
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
    AND, OR,                    // ABC: logical and/or → 0 or 1
    EQ, NEQ, GT, LT, GE, LE,   // ABC: R[A] = R[B] cmp R[C] → 0 or 1
    JUMP,           // Bx: ip = Bx
    JUMP_IF_FALSE,  // ABx: if falsy(R[A]) ip = Bx
    CALL_FUNC,      // ABC: A=base_reg, B=func_idx, C=argc
    RETURN,         // AB: copy R[A..A+B-1] → R[0..B-1], pop frame
    LOAD_VARARGS,   // AB: R[A..A+B-1] = varargs
    RETURN_V,       // AB: return B explicit + varargs
    CALL_PRINT,     // AB: print B args from R[A]
    CALL_PRINTF,    // AB: printf B args from R[A]
    CALL_ASSERT,    // AB: assert B args from R[A]
    CALL_TIME,      // A: R[A] = time()
    TRY,            // ABx: push handler{catch_addr=Bx, catch_reg=A}
    POP_TRY,
    THROW,          // A: throw R[A]
    NEW_MAP,        // A: R[A] = {}
    GET_INDEX,      // ABC: R[A] = R[B][R[C]]  (map→Value key, array→int 1-based)
    SET_INDEX,      // ABC: R[A][R[B]] = R[C]  (map→Value key, array→int 1-based)
    FOR_MAP_STEP,   // ABx: block+3=obj block+2=iter; iter maps/arrays; key→A+0, val→A+1
    BAND, BOR, BXOR, BNOT, BLSHIFT, BRSHIFT,   // bitwise (integers)
    NEW_ARRAY,      // A: R[A] = []
    ARRAY_PUSH,     // AB: R[A].push(R[B])
    FOR_ITER_STEP,  // ABx: block+2=array block+1=iter; val→A+0; exits to Bx when done
    HALT,
};

struct FuncProto {
    uint32_t addr;
    uint8_t  n_fixed;
    bool     variadic;
    uint16_t defaults_idx;
    uint8_t  reg_count;
};

struct Chunk {
    std::vector<Instr>       code;
    std::vector<Value>       constants;
    std::vector<std::string> identifiers;
    std::vector<std::vector<Value>> func_defaults;
    std::vector<FuncProto>   funcs;
    uint8_t                  top_reg_count = 8;

    uint16_t addConstant(Value v);
    uint16_t addIdentifier(const std::string& name);
    uint16_t addFuncDefaults(std::vector<Value> defs);
    uint8_t  addFunc(FuncProto fp);

    void   emit(Instr i);
    size_t emitJump(Op op, uint8_t a = 0);
    void   patchJump(size_t pos, uint16_t target);
    size_t currentPos() const { return code.size(); }
};
