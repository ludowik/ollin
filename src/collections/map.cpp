#include "value.h"

std::size_t ValueHash::operator()(const Value& v) const noexcept {
    switch (v.tag) {
    case Value::T_NIL:
        return 0;
    case Value::T_INTEGER:
        return std::hash<int64_t>{}(v.as_int());
    case Value::T_FLOAT: {
        double d = v.as_float();
        // A float holding an integral value must hash like the equal INTEGER, to stay consistent
        // with ValueEqual. double_fits_int64 guards the cast: without it a float key outside the
        // int64 range (m[1e300]) would be UB, and would trap on WASM.
        if (double_fits_int64(d)) {
            int64_t i = static_cast<int64_t>(d);
            if (static_cast<double>(i) == d)
                return std::hash<int64_t>{}(i);
        }
        return std::hash<double>{}(d);
    }
    case Value::T_STRING:
        return v.str_hash;
    case Value::T_MAP:
        return std::hash<void*>{}((void*)v.mptr);
    case Value::T_ARRAY:
        return std::hash<void*>{}((void*)v.aptr);
    case Value::T_ITERATOR:
        return std::hash<void*>{}((void*)v.iptr);
    case Value::T_FUNCTION:
        return std::hash<int64_t>{}(v.ival);
    case Value::T_BUILTIN:
        return std::hash<int64_t>{}(v.ival);
    case Value::T_BOOL:
        // The boolean is a type of its own: `true` is NOT the key `1`. The hash therefore keeps it
        // apart from the integer, unlike the INTEGER/FLOAT pair, which is deliberately merged.
        return std::hash<int64_t>{}(v.ival) ^ 0x9e3779b9u;
    case Value::T_CLOSURE:
        return std::hash<void*>{}((void*)v.cptr);
    case Value::T_CLASS:
        return std::hash<void*>{}((void*)v.mptr);
    case Value::T_RANGE:
        return std::hash<void*>{}((void*)v.rptr);
    default:
        return 0;
    }
}

bool ValueEqual::operator()(const Value& a, const Value& b) const noexcept {
    if (a.tag == b.tag) {
        switch (a.tag) {
        case Value::T_NIL:
            return true;
        case Value::T_INTEGER:
            return a.as_int() == b.as_int();
        case Value::T_FLOAT:
            return a.as_float() == b.as_float();
        case Value::T_STRING:
            return a.sptr == b.sptr;
        case Value::T_MAP:
            return a.mptr == b.mptr;
        case Value::T_ARRAY:
            return a.aptr == b.aptr;
        case Value::T_ITERATOR:
            return a.iptr == b.iptr;
        case Value::T_FUNCTION:
            return a.ival == b.ival;
        case Value::T_BUILTIN:
            return a.ival == b.ival;
        case Value::T_BOOL:
            return a.as_bool() == b.as_bool();
        case Value::T_CLOSURE:
            return a.cptr == b.cptr;
        case Value::T_CLASS:
            return a.mptr == b.mptr;
        case Value::T_RANGE:
            return a.rptr == b.rptr;
        default:
            return false;
        }
    }
    // Cross-type numeric equality: INTEGER(1) == FLOAT(1.0).
    if (a.is_number() && b.is_number())
        return a.as_num() == b.as_num();
    return false;
}

Value Map::get(const Value& k) const {
    auto it = data.find(k);
    if (it == data.end())
        return Value{};
    return it->second;
}

const Value* Map::find_ptr(const Value& k) const {
    auto it = data.find(k);
    if (it == data.end())
        return nullptr;
    return &it->second;
}

uint64_t g_map_epoch = 0;

void Map::set(const Value& k, const Value& v) {
    data.insert_or_assign(k, v);
    version = ++g_map_epoch;   // invalide les inline caches GET_INDEX visant cette map
}
