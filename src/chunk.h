#pragma once
#include <cstdint>
#include <string>
#include <utility>
#include <vector>

// Tagged union Value — 16 octets (tag + union 8 octets).
//
//   NIL     : tag == T_NIL
//   Integer : tag == T_INTEGER  → int64_t  (range ±2^63)
//   Float   : tag == T_FLOAT    → double IEEE 754
//   String  : tag == T_STRING   → std::string*  (heap, owned)
//   Map     : tag == T_MAP      → OllinMap*     (heap, ref-counted)
//   Array   : tag == T_ARRAY    → OllinArray*   (heap, ref-counted, 1-based)

struct OllinMap;
struct OllinArray;

struct Value {
    uint8_t tag;
    union {
        int64_t      ival;
        double       dval;
        std::string* sptr;
        OllinMap*    mptr;
        OllinArray*  aptr;
    };

    static constexpr uint8_t T_NIL     = 0;
    static constexpr uint8_t T_INTEGER = 1;
    static constexpr uint8_t T_FLOAT   = 2;
    static constexpr uint8_t T_STRING  = 3;
    static constexpr uint8_t T_MAP     = 4;
    static constexpr uint8_t T_ARRAY   = 5;

private:
    explicit Value(OllinMap*   p) : tag(T_MAP),   mptr(p) {}
    explicit Value(OllinArray* p) : tag(T_ARRAY), aptr(p) {}

public:
    Value()              : tag(T_NIL), ival(0) {}
    Value(double d)      : tag(T_FLOAT), dval(d) {}
    Value(int64_t v)     : tag(T_INTEGER), ival(v) {}
    Value(std::string v) : tag(T_STRING), sptr(new std::string(std::move(v))) {}

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

    int64_t asInt()            const { return ival; }
    double  asFloat()          const { return dval; }
    double  asNum()            const { return isInteger() ? (double)ival : dval; }
    const std::string& asString() const { return *sptr; }

    static Value makeMap();
    Value       mapGet(const std::string& key) const;
    void        mapSet(const std::string& key, const Value& val);
    int         mapSize()           const;
    std::string mapKeyAt(int idx)   const;
    Value       mapValAt(int idx)   const;

    static Value makeArray();
    Value  arrayGet(int64_t idx)                    const; // 1-based
    void   arraySet(int64_t idx, const Value& val);        // 1-based, grows if needed
    void   arrayPush(const Value& val);
    int    arraySize()                              const;
};

// ── OllinMap ──────────────────────────────────────────────────────────────────
struct OllinMap {
    std::vector<std::pair<std::string, Value>> entries;
    int refcount = 1;

    Value get(const std::string& k) const {
        for (const auto& e : entries)
            if (e.first == k) return e.second;
        return Value{};
    }
    void set(const std::string& k, const Value& v) {
        for (auto& e : entries)
            if (e.first == k) { e.second = v; return; }
        entries.emplace_back(k, v);
    }
};

struct MapPool {
    static constexpr int CAP = 64;
    OllinMap* buf[CAP];
    int       n = 0;

    OllinMap* acquire() {
        if (n) { OllinMap* m = buf[--n]; m->refcount = 1; return m; }
        return new OllinMap();
    }
    void release(OllinMap* m) {
        m->entries.clear();
        if (n < CAP) buf[n++] = m;
        else delete m;
    }
};
inline MapPool& map_pool() { static MapPool p; return p; }

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

// ── inline Value implementations (require complete OllinMap / OllinArray) ─────

inline Value Value::makeMap()   { return Value(map_pool().acquire()); }
inline Value Value::makeArray() { return Value(array_pool().acquire()); }

inline Value Value::mapGet(const std::string& k)                 const { return mptr->get(k); }
inline void  Value::mapSet(const std::string& k, const Value& v)       { mptr->set(k, v); }
inline int         Value::mapSize()          const { return (int)mptr->entries.size(); }
inline std::string Value::mapKeyAt(int idx)  const { return mptr->entries[idx].first; }
inline Value       Value::mapValAt(int idx)  const { return mptr->entries[idx].second; }

inline Value Value::arrayGet(int64_t idx)                  const { return aptr->get(idx); }
inline void  Value::arraySet(int64_t idx, const Value& v)        { aptr->set(idx, v); }
inline void  Value::arrayPush(const Value& v)                    { aptr->push(v); }
inline int   Value::arraySize()                            const { return (int)aptr->items.size(); }

inline Value::Value(const Value& o) : tag(o.tag), ival(0) {
    switch (tag) {
        case T_NIL:     break;
        case T_INTEGER: ival = o.ival; break;
        case T_FLOAT:   dval = o.dval; break;
        case T_STRING:  sptr = new std::string(*o.sptr); break;
        case T_MAP:     mptr = o.mptr; mptr->refcount++; break;
        case T_ARRAY:   aptr = o.aptr; aptr->refcount++; break;
    }
}
inline Value& Value::operator=(const Value& o) {
    if (this == &o) return *this;
    std::string* new_s = (o.tag == T_STRING) ? new std::string(*o.sptr) : nullptr;
    switch (tag) {
        case T_STRING: delete sptr; break;
        case T_MAP:   { OllinMap*   mp = mptr; if (--mp->refcount == 0) map_pool().release(mp);   break; }
        case T_ARRAY: { OllinArray* ap = aptr; if (--ap->refcount == 0) array_pool().release(ap); break; }
        default: break;
    }
    tag = o.tag; ival = 0;
    switch (tag) {
        case T_NIL:     break;
        case T_INTEGER: ival = o.ival; break;
        case T_FLOAT:   dval = o.dval; break;
        case T_STRING:  sptr = new_s; break;
        case T_MAP:     mptr = o.mptr; mptr->refcount++; break;
        case T_ARRAY:   aptr = o.aptr; aptr->refcount++; break;
    }
    return *this;
}
inline Value& Value::operator=(Value&& o) noexcept {
    if (this == &o) return *this;
    switch (tag) {
        case T_STRING: delete sptr; break;
        case T_MAP:   { OllinMap*   mp = mptr; if (--mp->refcount == 0) map_pool().release(mp);   break; }
        case T_ARRAY: { OllinArray* ap = aptr; if (--ap->refcount == 0) array_pool().release(ap); break; }
        default: break;
    }
    tag = o.tag; ival = o.ival; o.tag = T_NIL;
    return *this;
}
inline Value::~Value() {
    switch (tag) {
        case T_STRING: delete sptr; break;
        case T_MAP:   { OllinMap*   mp = mptr; if (--mp->refcount == 0) map_pool().release(mp);   break; }
        case T_ARRAY: { OllinArray* ap = aptr; if (--ap->refcount == 0) array_pool().release(ap); break; }
        default: break;
    }
}

inline bool isFalsy(const Value& v) {
    if (v.isNil())     return true;
    if (v.isInteger()) return v.asInt() == 0;
    if (v.isFloat())   return v.asFloat() == 0.0;
    if (v.isString())  return v.asString().empty();
    return false;  // map, array → always truthy
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
    GET_INDEX,      // ABC: R[A] = R[B][R[C]]  (map→string key, array→int 1-based)
    SET_INDEX,      // ABC: R[A][R[B]] = R[C]  (map→string key, array→int 1-based)
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
