#include "chunk.h"

std::size_t ValueHash::operator()(const Value& v) const noexcept {
    switch (v.tag) {
        case Value::T_NIL:     return 0;
        case Value::T_INTEGER: return std::hash<int64_t>{}(v.asInt());
        case Value::T_FLOAT: {
            double d = v.asFloat();
            auto   i = static_cast<int64_t>(d);
            if (static_cast<double>(i) == d) return std::hash<int64_t>{}(i);
            return std::hash<double>{}(d);
        }
        case Value::T_STRING:  return std::hash<std::string>{}(v.asString());
        case Value::T_MAP:     return std::hash<void*>{}((void*)v.mptr);
        case Value::T_ARRAY:   return std::hash<void*>{}((void*)v.aptr);
        default:               return 0;
    }
}

bool ValueEqual::operator()(const Value& a, const Value& b) const noexcept {
    if (a.tag == b.tag) {
        switch (a.tag) {
            case Value::T_NIL:     return true;
            case Value::T_INTEGER: return a.asInt()    == b.asInt();
            case Value::T_FLOAT:   return a.asFloat()  == b.asFloat();
            case Value::T_STRING:  return a.asString() == b.asString();
            case Value::T_MAP:     return a.mptr == b.mptr;
            case Value::T_ARRAY:   return a.aptr == b.aptr;
            default:               return false;
        }
    }
    // Cross-type numérique : INTEGER(1) == FLOAT(1.0)
    if (a.isNumber() && b.isNumber()) return a.asNum() == b.asNum();
    return false;
}

Value Map::get(const Value& k) const {
    auto it = index.find(k);
    if (it == index.end()) return Value{};
    return entries[it->second].second;
}

void Map::set(const Value& k, const Value& v) {
    auto it = index.find(k);
    if (it != index.end()) {
        entries[it->second].second = v;
    } else {
        index.emplace(k, entries.size());
        entries.emplace_back(k, v);
    }
}
