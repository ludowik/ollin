#pragma once
#include <cstdint>  // uint32_t/uint64_t requis par robin_hood.h
#include "robin_hood.h"
#include <string>
#include <string_view>

// Interned string: refcount, hash and bytes live together, so retain is a single increment
// and only release — when the count reaches zero — needs a table lookup.
struct InternedStr {
    int refcount = 1;
    uint32_t hash;
    std::string str;
    InternedStr(InternedStr&&) = delete;
    InternedStr& operator=(InternedStr&&) = delete;
};

struct StringTable {
    // The key is a string_view into InternedStr::str (heap-allocated, hence stable), so the
    // bytes exist exactly once.
    robin_hood::unordered_map<std::string_view, InternedStr*> table_;

    InternedStr* intern(std::string s) {
        auto it = table_.find(std::string_view(s));
        if (it != table_.end()) {
            ++it->second->refcount;
            return it->second;
        }
        auto h = (uint32_t)std::hash<std::string>{}(s);
        auto* p = new InternedStr{1, h, std::move(s)};
        table_.emplace(std::string_view(p->str), p); // a view into p->str, with no copy
        return p;
    }

    void erase(InternedStr* p) {
        table_.erase(std::string_view(p->str)); // avant delete — view doit rester valide
        delete p;
    }
};

inline StringTable& string_table() {
    static StringTable t;
    return t;
}

inline InternedStr* intern(std::string s) {
    return string_table().intern(std::move(s));
}
