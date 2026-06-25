#pragma once
#include <cstdint>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>
#include "string_table.h"

// Tagged union Value — 16 octets : tag(1) + _pad(3) + str_hash(4) + union(8).
//
//   NIL     : tag == T_NIL
//   Integer : tag == T_INTEGER  → int64_t  (range ±2^63)
//   Float   : tag == T_FLOAT    → double IEEE 754
//   String  : tag == T_STRING   → InternedStr*  (ref-counted, str_hash = sptr->hash)
//   Map     : tag == T_MAP      → Map*     (heap, ref-counted, clés Value)
//   Array   : tag == T_ARRAY    → Array*   (heap, ref-counted, 1-based)
//   Range   : tag == T_RANGE    → Range*   (heap, ref-counted)
//   Iterator: tag == T_ITERATOR → Iterator* (heap, ref-counted)
//   Function: tag == T_FUNCTION → func_idx (int64_t ival, index dans chunk.funcs)

struct Map;
struct Array;
struct Range;
struct Iterator;
struct Closure;

struct Value {
    uint8_t  tag;
    uint8_t  _pad[3];    // padding explicite (anciennement implicite)
    uint32_t str_hash;   // hash contenu mis en cache, valide uniquement pour T_STRING
    union {
        int64_t            ival;
        double             dval;
        InternedStr*       sptr;  // pointe vers l'objet interné (refcount géré inline)
        Map*               mptr;
        Array*             aptr;
        Iterator*          iptr;
        Closure*           cptr;
        Range*             rptr;
    };

    static constexpr uint8_t T_NIL      = 0;
    static constexpr uint8_t T_INTEGER  = 1;
    static constexpr uint8_t T_FLOAT    = 2;
    static constexpr uint8_t T_STRING   = 3;
    static constexpr uint8_t T_MAP      = 4;
    static constexpr uint8_t T_ARRAY    = 5;
    static constexpr uint8_t T_ITERATOR = 6;
    static constexpr uint8_t T_FUNCTION = 7;
    static constexpr uint8_t T_CLOSURE  = 8;
    static constexpr uint8_t T_BUILTIN  = 9;
    static constexpr uint8_t T_CLASS    = 10;  // prototype de classe (Map* réutilisé)
    static constexpr uint8_t T_RANGE    = 11;  // range [a;b] (Range*, ref-counted)

private:
    explicit Value(Map*      p) : tag(T_MAP),      str_hash(0), mptr(p) {}
    explicit Value(Array*    p) : tag(T_ARRAY),    str_hash(0), aptr(p) {}
    explicit Value(Iterator* p) : tag(T_ITERATOR), str_hash(0), iptr(p) {}
    explicit Value(Closure*  p) : tag(T_CLOSURE),  str_hash(0), cptr(p) {}
    explicit Value(Range*    p) : tag(T_RANGE),    str_hash(0), rptr(p) {}
    void release() noexcept;

public:
    Value()              : tag(T_NIL),     str_hash(0), ival(0) {}
    Value(double d)      : tag(T_FLOAT),   str_hash(0), dval(d) {}
    Value(int64_t v)     : tag(T_INTEGER), str_hash(0), ival(v) {}
    Value(std::string v) : tag(T_STRING),  str_hash(0) {
        sptr = intern(std::move(v));
        str_hash = sptr->hash;
    }

    Value(const Value& o);
    Value(Value&& o) noexcept : tag(o.tag), str_hash(o.str_hash), ival(o.ival) { o.tag = T_NIL; }
    Value& operator=(const Value& o);
    Value& operator=(Value&& o) noexcept;
    ~Value();

    bool isNil()      const { return tag == T_NIL; }
    bool isFloat()    const { return tag == T_FLOAT; }
    bool isInteger()  const { return tag == T_INTEGER; }
    bool isNumber()   const { return tag == T_INTEGER || tag == T_FLOAT; }
    bool isString()   const { return tag == T_STRING; }
    bool isMap()      const { return tag == T_MAP; }
    bool isArray()    const { return tag == T_ARRAY; }
    bool isIterator() const { return tag == T_ITERATOR; }
    bool isFuncVal()  const { return tag == T_FUNCTION; }
    bool isClosure()  const { return tag == T_CLOSURE; }
    bool isBuiltin()  const { return tag == T_BUILTIN; }
    bool isClass()    const { return tag == T_CLASS; }
    bool isRange()    const { return tag == T_RANGE; }
    bool isCallable() const { return tag == T_FUNCTION || tag == T_CLOSURE || tag == T_BUILTIN || tag == T_CLASS; }

    Closure* asClosure() const { return cptr; }
    Map*     asMap()     const { return mptr; }

    using BuiltinFn = Value(*)(Value*, int);
    BuiltinFn asBuiltin() const { return (BuiltinFn)(intptr_t)ival; }

    static Value makeFunc(uint8_t idx) { Value v; v.tag = T_FUNCTION; v.ival = idx; return v; }
    static Value makeClosure(Closure* p) { return Value(p); }
    static Value makeBuiltin(BuiltinFn fn) { Value v; v.tag = T_BUILTIN; v.ival = (int64_t)(intptr_t)fn; return v; }
    static Value makeClass();
    static Value makeRange(Range* r) { return Value(r); }

    int64_t asInt()               const { return ival; }
    double  asFloat()             const { return dval; }
    double  asNum()               const { return isInteger() ? (double)ival : dval; }
    const std::string& asString() const { return sptr->str; }

    static Value makeMap();
    Value        mapGet(const Value& key)              const;
    void         mapSet(const Value& key, const Value& val);

    static Value makeArray();
    Value  arrayGet(int64_t idx)                    const; // 1-based
    void   arraySet(int64_t idx, const Value& val);        // 1-based, grows if needed
    void   arrayPush(const Value& val);
    int64_t arraySize()                             const;
    int64_t mapSize()                               const;

    static Value makeIterFrom(const Value& src);

    const char* typeName() const {
        switch (tag) {
            case T_NIL:      return "nil";
            case T_INTEGER:  return "int";
            case T_FLOAT:    return "float";
            case T_STRING:   return "string";
            case T_MAP:      return "map";
            case T_ARRAY:    return "array";
            case T_ITERATOR: return "iterator";
            case T_FUNCTION: return "function";
            case T_CLOSURE:  return "function";
            case T_BUILTIN:  return "function";
            case T_CLASS:    return "class";
            case T_RANGE:    return "range";
            default:         return "unknown";
        }
    }
};

// ── Array (1-based, ref-counted) — définition complète ───────────────────────
#include "collections/array.h"

// ── Map (pure hashmap, clés Value) — définition complète ─────────────────────
#include "collections/map.h"

// ── Iterator (protocole d'itération — Map, Array) ────────────────────────────
#include "collections/iterator.h"

// ── Range ([a;b] littéral, itérable) ─────────────────────────────────────────
#include "collections/range.h"

// ── Closure / Upvalue ─────────────────────────────────────────────────────────
#include "closure.h"

// ── inline Value implementations (nécessitent Map, Array, Iterator complets) ─

inline Value Value::makeMap()   { return Value(map_pool().acquire()); }
inline Value Value::makeArray() { return Value(array_pool().acquire()); }
inline Value Value::makeClass() { Value v; v.tag = T_CLASS; v.mptr = map_pool().acquire(); return v; }

inline Value Value::mapGet(const Value& k)                  const { return mptr->get(k); }
inline void  Value::mapSet(const Value& k, const Value& v)        { mptr->set(k, v); }

inline Value Value::arrayGet(int64_t idx)                  const { return aptr->get(idx); }
inline void  Value::arraySet(int64_t idx, const Value& v)        { aptr->set(idx, v); }
inline void  Value::arrayPush(const Value& v)                    { aptr->push(v); }
inline int64_t Value::arraySize()                          const { return (int64_t)aptr->items.size(); }
inline int64_t Value::mapSize()                            const { return (int64_t)mptr->data.size(); }

inline void Value::release() noexcept {
    switch (tag) {
        case T_STRING:   if (--sptr->refcount == 0) string_table().erase(sptr); break;
        case T_MAP:
        case T_CLASS:    { Map*      mp = mptr; if (--mp->refcount == 0) map_pool().release(mp);   break; }
        case T_ARRAY:    { Array*    ap = aptr; if (--ap->refcount == 0) array_pool().release(ap); break; }
        case T_ITERATOR: { Iterator* ip = iptr; if (--ip->refcount == 0) ip->release();            break; }
        case T_CLOSURE:  { Closure*  cp = cptr; if (--cp->refcount == 0) delete cp;               break; }
        case T_RANGE:    { Range*    rp = rptr; if (--rp->refcount == 0) delete rp;               break; }
        default: break;
    }
}

inline Value Value::makeIterFrom(const Value& src) {
    if (src.isMap() || src.isClass()) return Value(new MapIterator(src.mptr));
    if (src.isArray()) return Value(array_iter_pool().acquire(src.aptr));
    if (src.isRange()) return Value(new RangeIterator(src.rptr));
    throw std::runtime_error("runtime: for-in on non-iterable");
}

inline Value::Value(const Value& o) : tag(o.tag), str_hash(o.str_hash), ival(0) {
    switch (tag) {
        case T_NIL:      break;
        case T_INTEGER:  ival = o.ival; break;
        case T_FLOAT:    dval = o.dval; break;
        case T_STRING:   sptr = o.sptr; ++sptr->refcount; break;
        case T_MAP:      mptr = o.mptr; mptr->refcount++; break;
        case T_CLASS:    mptr = o.mptr; mptr->refcount++; break;
        case T_ARRAY:    aptr = o.aptr; aptr->refcount++; break;
        case T_ITERATOR: iptr = o.iptr; iptr->refcount++; break;
        case T_FUNCTION: ival = o.ival; break;
        case T_CLOSURE:  cptr = o.cptr; cptr->refcount++; break;
        case T_BUILTIN:  ival = o.ival; break;
        case T_RANGE:    rptr = o.rptr; rptr->refcount++; break;
    }
}
inline Value& Value::operator=(const Value& o) {
    if (this == &o) return *this;
    // Retain d'abord (protège si this et o partagent la même ressource)
    switch (o.tag) {
        case T_STRING:   ++o.sptr->refcount; break;
        case T_MAP:      o.mptr->refcount++;             break;
        case T_CLASS:    o.mptr->refcount++;             break;
        case T_ARRAY:    o.aptr->refcount++;             break;
        case T_ITERATOR: o.iptr->refcount++;             break;
        case T_CLOSURE:  o.cptr->refcount++;             break;
        case T_RANGE:    o.rptr->refcount++;             break;
        default: break;
    }
    release();
    tag = o.tag; str_hash = o.str_hash; ival = 0;
    switch (tag) {
        case T_NIL:      break;
        case T_INTEGER:  ival = o.ival; break;
        case T_FLOAT:    dval = o.dval; break;
        case T_STRING:   sptr = o.sptr; break;
        case T_MAP:      mptr = o.mptr; break;
        case T_CLASS:    mptr = o.mptr; break;
        case T_ARRAY:    aptr = o.aptr; break;
        case T_ITERATOR: iptr = o.iptr; break;
        case T_FUNCTION: ival = o.ival; break;
        case T_CLOSURE:  cptr = o.cptr; break;
        case T_BUILTIN:  ival = o.ival; break;
        case T_RANGE:    rptr = o.rptr; break;
    }
    return *this;
}
inline Value& Value::operator=(Value&& o) noexcept {
    if (this == &o) return *this;
    release();
    tag = o.tag; str_hash = o.str_hash; ival = o.ival; o.tag = T_NIL;
    return *this;
}
inline Value::~Value() { release(); }

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
