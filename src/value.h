#pragma once
#include "string_table.h"
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

// static_cast<int64_t>(d) is only DEFINED when the integral part of d fits in an int64;
// otherwise it is UB, and traps on WASM. The trap: (double)INT64_MAX rounds up to 2^63, which
// is NOT a valid int64, hence a STRICT upper bound. INT64_MIN = -2^63 is exact, and -lo is
// 2^63. Single source of truth for num_value, ValueHash (float keys) and RangeIterator, so the
// 2^63 literal is not duplicated.
inline bool double_fits_int64(double d) {
    constexpr double lo = static_cast<double>(std::numeric_limits<int64_t>::min()); // -2^63 (exact)
    return d >= lo && d < -lo;                                                      // -lo == 2^63, exclu
}

// Tagged union, 16 bytes: tag(1) + _pad(3) + str_hash(4) + union(8).
//
//   NIL     : tag == T_NIL
//   Integer : tag == T_INTEGER  -> int64_t (range +-2^63)
//   Float   : tag == T_FLOAT    -> IEEE 754 double
//   String  : tag == T_STRING   -> InternedStr* (ref-counted, str_hash = sptr->hash)
//   Map     : tag == T_MAP      -> Map* (heap, ref-counted, Value keys)
//   Array   : tag == T_ARRAY    -> Array* (heap, ref-counted, 1-based)
//   Range   : tag == T_RANGE    -> Range* (heap, ref-counted)
//   Iterator: tag == T_ITERATOR -> Iterator* (heap, ref-counted)
//   Function: tag == T_FUNCTION -> func_idx (int64_t ival, index into chunk.funcs)

struct Map;
struct Array;
struct Range;
struct Iterator;
struct Closure;
struct Value;
class VM;
// Call context of a builtin, on the Lua model: the builtin writes its return values into the
// result slots (args[0..], the registers from call_base on) and returns how many. `result_cap`
// is the number of safe slots (the frame's reg_count minus A); every write is clamped to it,
// which makes overflowing past the frame impossible (see the register invariant).
struct CallCtx {
    VM*    vm;
    Value* args;
    int    argc;
    int    result_cap = 0;

    int ret(const Value& v);
    // Writes the i-th return value, clamped to result_cap. Follow with `return n;`.
    void set_result(int i, const Value& v);
};

struct Value {
    uint8_t tag;
    uint8_t _pad[3];   // padding explicite (anciennement implicite)
    uint32_t str_hash; // hash contenu mis en cache, valide uniquement pour T_STRING
    union {
        int64_t ival;
        double dval;
        InternedStr* sptr; // points at the interned object, its refcount handled inline
        Map* mptr;
        Array* aptr;
        Iterator* iptr;
        Closure* cptr;
        Range* rptr;
    };

    // Tag order is a PERFORMANCE INVARIANT: every NON ref-counted type first, then the
    // T_STRING pivot and all ref-counted types contiguously. `tag < T_STRING` therefore tells
    // values needing no memory management from those needing retain/release in a SINGLE test.
    // Any new ref-counted type goes AFTER the pivot, any new plain type BEFORE it.
    static constexpr uint8_t T_NIL = 0; // ── not ref-counted (POD, by value) ──
    static constexpr uint8_t T_INTEGER = 1;
    static constexpr uint8_t T_FLOAT = 2;
    static constexpr uint8_t T_FUNCTION = 3; // func_idx dans ival (pas de tas)
    static constexpr uint8_t T_BUILTIN = 4;  // pointeur de fonction natif dans ival
    static constexpr uint8_t T_BOOL = 5;     // true/false dans ival (0/1) — type ÉTANCHE, ≠ entier
    static constexpr uint8_t T_STRING = 6;   // ── the pivot: ref-counted from here on ──
    static constexpr uint8_t T_MAP = 7;
    static constexpr uint8_t T_ARRAY = 8;
    static constexpr uint8_t T_ITERATOR = 9;
    static constexpr uint8_t T_CLOSURE = 10;
    static constexpr uint8_t T_CLASS = 11;  // a class prototype, reusing Map*
    static constexpr uint8_t T_RANGE = 12;  // range [a;b] (Range*, ref-counted)

  private:
    explicit Value(Map* p) : tag(T_MAP), str_hash(0), mptr(p) {
    }
    explicit Value(Array* p) : tag(T_ARRAY), str_hash(0), aptr(p) {
    }
    explicit Value(Iterator* p) : tag(T_ITERATOR), str_hash(0), iptr(p) {
    }
    explicit Value(Closure* p) : tag(T_CLOSURE), str_hash(0), cptr(p) {
    }
    explicit Value(Range* p) : tag(T_RANGE), str_hash(0), rptr(p) {
    }
    // Builds a boolean DIRECTLY, in the initializer list rather than by assigning afterwards:
    // comparisons produce one per test, on the hottest path of the VM. The tag type keeps this
    // from colliding with Value(int64_t).
    struct BoolTag {};
    Value(BoolTag, bool b) : tag(T_BOOL), str_hash(0), ival(b ? 1 : 0) {
    }
    void release() noexcept;
    void release_cold() noexcept; // the cold path, for the ref-counted types; not inlined
    void retain() const noexcept;

  public:
    Value() : tag(T_NIL), str_hash(0), ival(0) {
    }
    Value(double d) : tag(T_FLOAT), str_hash(0), dval(d) {
    }
    Value(int64_t v) : tag(T_INTEGER), str_hash(0), ival(v) {
    }
    Value(std::string v) : tag(T_STRING), str_hash(0) {
        sptr = intern(std::move(v));
        str_hash = sptr->hash;
    }

    Value(const Value& o);
    Value(Value&& o) noexcept : tag(o.tag), str_hash(o.str_hash), ival(o.ival) {
        o.tag = T_NIL;
    }
    Value& operator=(const Value& o);
    Value& operator=(Value&& o) noexcept;
    ~Value();

    bool is_nil() const {
        return tag == T_NIL;
    }
    bool is_float() const {
        return tag == T_FLOAT;
    }
    bool is_integer() const {
        return tag == T_INTEGER;
    }
    bool is_bool() const {
        return tag == T_BOOL;
    }
    bool as_bool() const {
        return ival != 0;
    }
    bool is_number() const {
        return tag == T_INTEGER || tag == T_FLOAT;
    }
    bool is_string() const {
        return tag == T_STRING;
    }
    bool is_map() const {
        return tag == T_MAP;
    }
    bool is_array() const {
        return tag == T_ARRAY;
    }
    bool is_iterator() const {
        return tag == T_ITERATOR;
    }
    bool is_func_val() const {
        return tag == T_FUNCTION;
    }
    bool is_closure() const {
        return tag == T_CLOSURE;
    }
    bool is_builtin() const {
        return tag == T_BUILTIN;
    }
    bool is_class() const {
        return tag == T_CLASS;
    }
    bool is_range() const {
        return tag == T_RANGE;
    }
    bool is_callable() const {
        return tag == T_FUNCTION || tag == T_CLOSURE || tag == T_BUILTIN || tag == T_CLASS;
    }

    Closure* as_closure() const {
        return cptr;
    }
    Map* as_map() const {
        return mptr;
    }

    using BuiltinFn = int (*)(CallCtx&);
    BuiltinFn as_builtin() const {
        return (BuiltinFn)(intptr_t)ival;
    }

    static Value make_func(uint8_t idx) {
        Value v;
        v.tag = T_FUNCTION;
        v.ival = idx;
        return v;
    }
    static Value make_closure(Closure* p) {
        return Value(p);
    }
    // An EXPLICIT factory rather than a `Value(bool)` constructor: with `Value(int64_t)` and
    // `Value(double)` already present, such a constructor would silently turn `Value(0)` into a
    // boolean by implicit conversion.
    static Value make_bool(bool b) {
        return Value(BoolTag{}, b);
    }
    static Value make_builtin(BuiltinFn fn) {
        Value v;
        v.tag = T_BUILTIN;
        v.ival = (int64_t)(intptr_t)fn;
        return v;
    }
    // A builtin declared STATIC (a class method): CALL_METHOD does not inject self, exactly as
    // for an Ollin `static func`, so Ollin and builtin classes follow the same rules (explicit
    // arguments in R[0..], no receiver in front). The marker lives in str_hash — unused for
    // T_BUILTIN but preserved on copy, unlike _pad.
    static Value make_static_builtin(BuiltinFn fn) {
        Value v = make_builtin(fn);
        v.str_hash = 1;
        return v;
    }
    bool is_static_builtin() const {
        return tag == T_BUILTIN && str_hash != 0;
    }
    static Value make_class();
    static Value make_range(Range* r) {
        return Value(r);
    }

    int64_t as_int() const {
        return ival;
    }
    double as_float() const {
        return dval;
    }
    double as_num() const {
        return is_integer() ? (double)ival : dval;
    }
    const std::string& as_string() const {
        return sptr->str;
    }

    static Value make_map();
    Value map_get(const Value& key) const;
    void map_set(const Value& key, const Value& val);

    static Value make_array();
    Value array_get(int64_t idx) const;            // 1-based
    void array_set(int64_t idx, const Value& val); // 1-based, grows if needed
    void array_push(const Value& val);
    Value array_pop();
    void array_insert(int64_t idx, const Value& val);
    Value array_remove(int64_t idx);
    Value array_shift();
    int64_t array_size() const;
    int64_t map_size() const;

    static Value make_iter_from(const Value& src);

    const char* type_name() const {
        switch (tag) {
        case T_NIL:
            return "nil";
        case T_INTEGER:
            return "int";
        case T_FLOAT:
            return "float";
        case T_BOOL:
            return "bool";
        case T_STRING:
            return "string";
        case T_MAP:
            return "map";
        case T_ARRAY:
            return "array";
        case T_ITERATOR:
            return "iterator";
        case T_FUNCTION:
            return "function";
        case T_CLOSURE:
            return "function";
        case T_BUILTIN:
            return "function";
        case T_CLASS:
            return "class";
        case T_RANGE:
            return "range";
        default:
            return "unknown";
        }
    }
};

inline int CallCtx::ret(const Value& v) {
    if (result_cap <= 0)
        return 0;
    args[0] = v;
    return 1;
}

inline void CallCtx::set_result(int i, const Value& v) {
    if (i >= 0 && i < result_cap)
        args[i] = v;
}

#include "collections/array.h"

#include "collections/map.h"

#include "collections/iterator.h"

#include "collections/range.h"

#include "closure.h"

// Inline Value implementations: they need Map, Array and Iterator to be complete types.

inline Value Value::make_map() {
    return Value(map_pool().acquire());
}
inline Value Value::make_array() {
    return Value(array_pool().acquire());
}
inline Value Value::make_class() {
    Value v;
    v.tag = T_CLASS;
    v.mptr = map_pool().acquire();
    return v;
}

inline Value Value::map_get(const Value& k) const {
    return mptr->get(k);
}
inline void Value::map_set(const Value& k, const Value& v) {
    mptr->set(k, v);
}

inline Value Value::array_get(int64_t idx) const {
    return aptr->get(idx);
}
inline void Value::array_set(int64_t idx, const Value& v) {
    aptr->set(idx, v);
}
inline void Value::array_push(const Value& v) {
    aptr->push(v);
}
inline Value Value::array_pop() {
    return aptr->pop();
}
inline void Value::array_insert(int64_t idx, const Value& v) {
    aptr->insert_at(idx, v);
}
inline Value Value::array_remove(int64_t idx) {
    return aptr->remove_at(idx);
}
inline Value Value::array_shift() {
    return aptr->shift();
}
inline int64_t Value::array_size() const {
    return (int64_t)aptr->items.size();
}
inline int64_t Value::map_size() const {
    return (int64_t)mptr->data.size();
}

// Hot path: for nil/int/float (tag < T_STRING) there is nothing to free. That trivial test
// stays inlinable at every call site while the ref-counted switch lives in release_cold(),
// which is not inlined — this is what lets move-assign inline.
inline void Value::release() noexcept {
    if (tag < T_STRING)
        return; // POD: nothing to release, in a single inlined test
    release_cold();
}

__attribute__((noinline)) inline void Value::release_cold() noexcept {
    switch (tag) {
    case T_STRING:
        if (--sptr->refcount == 0)
            string_table().erase(sptr);
        break;
    case T_MAP:
    case T_CLASS: {
        Map* mp = mptr;
        if (--mp->refcount == 0)
            map_pool().release(mp);
        break;
    }
    case T_ARRAY: {
        Array* ap = aptr;
        if (--ap->refcount == 0)
            array_pool().release(ap);
        break;
    }
    case T_ITERATOR: {
        Iterator* ip = iptr;
        if (--ip->refcount == 0)
            ip->release();
        break;
    }
    case T_CLOSURE: {
        Closure* cp = cptr;
        if (--cp->refcount == 0)
            delete cp;
        break;
    }
    case T_RANGE: {
        Range* rp = rptr;
        if (--rp->refcount == 0)
            delete rp;
        break;
    }
    default:
        break; // defensive: only tags >= T_STRING reach here
    }
}

// Mirror of release(). The body is a single ++refcount, so it stays inlinable WITH its switch
// and needs no cold split — unlike release, whose cases are heavy. Thanks to the pivot, plain
// types (T_FUNCTION and T_BUILTIN included) leave at `tag < T_STRING`.
inline void Value::retain() const noexcept {
    if (tag < T_STRING)
        return; // POD, not counted: nothing to retain, in a single test
    switch (tag) {
    case T_STRING:
        ++sptr->refcount;
        break;
    case T_MAP:
    case T_CLASS:
        mptr->refcount++;
        break;
    case T_ARRAY:
        aptr->refcount++;
        break;
    case T_ITERATOR:
        iptr->refcount++;
        break;
    case T_CLOSURE:
        cptr->refcount++;
        break;
    case T_RANGE:
        rptr->refcount++;
        break;
    default:
        break; // defensive: only tags >= T_STRING reach here
    }
}

inline Value Value::make_iter_from(const Value& src) {
    if (src.is_map() || src.is_class())
        return Value(new MapIterator(src.mptr));
    if (src.is_array())
        return Value(array_iter_pool().acquire(src.aptr));
    if (src.is_range())
        return Value(new RangeIterator(src.rptr));
    throw std::runtime_error("runtime: for-in on non-iterable");
}

inline Value::Value(const Value& o) : tag(o.tag), str_hash(o.str_hash), ival(o.ival) {
    // Raw copy of the union (ival/dval/ptr alias the same 8 bytes); only a ref-counted type
    // (tag >= T_STRING) needs a retain.
    retain();
}
inline Value& Value::operator=(const Value& o) {
    if (this == &o)
        return *this;
    o.retain(); // retain first, which protects the case where this and o share the resource
    release();
    // Raw copy of the union (ival/dval/ptr alias the same 8 bytes).
    tag = o.tag;
    str_hash = o.str_hash;
    ival = o.ival;
    return *this;
}
inline Value& Value::operator=(Value&& o) noexcept {
    if (this == &o)
        return *this;
    release();
    tag = o.tag;
    str_hash = o.str_hash;
    ival = o.ival;
    o.tag = T_NIL;
    return *this;
}
inline Value::~Value() {
    release();
}

// Truthiness for the types whose answer needs a MEMORY ACCESS (length of a string, size of an
// array or a map). `noinline` keeps it from bloating its callers: is_falsy is inlined at some
// fifteen sites, JUMP_IF_FALSE among them — the hottest in the VM — so every test moved out of
// it lightens all that code.
//
// NO `gnu::cold` here, and this was measured: the attribute also marks the CALLERS as unlikely,
// and run_goto contains them all — the numeric loop lost 33 % (bench_loop) for an unchanged
// instruction count. An attribute declaring a cold path therefore degrades the giant function
// that hosts every hot path.
[[gnu::noinline]] inline bool is_falsy_cold(const Value& v) {
    if (v.is_float())
        return v.as_float() == 0.0;
    if (v.is_string())
        return v.as_string().empty();
    if (v.is_array())
        return v.array_size() == 0;
    if (v.is_map())
        return v.map_size() == 0; // an instance has at least one key (__class__), hence truthy
    return false;                // T_CLASS, range, closure, function → truthy
}

inline bool is_falsy(const Value& v) {
    // The rule is "empty is false": a boolean answers for itself, everything else keeps its
    // own (0, the empty string, the empty array and the empty map are false).
    // Only the three tags that answer WITHOUT touching memory stay inlined, ordered by how
    // often they occur here — the boolean first, since every comparison produces one.
    if (v.is_bool())
        return !v.as_bool();
    if (v.is_integer())
        return v.as_int() == 0;
    if (v.is_nil())
        return true;
    return is_falsy_cold(v);
}

inline Value num_value(double d) {
    // Falls back to an integer when d is an exact integer representable as int64.
    // double_fits_int64 guards the cast (UB on NaN, inf and out-of-range); the round trip
    // confirms exactness.
    if (double_fits_int64(d)) {
        int64_t i = static_cast<int64_t>(d);
        if (static_cast<double>(i) == d)
            return Value(i);
    }
    return Value(d);
}
