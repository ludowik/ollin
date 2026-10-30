#pragma once
#include <cstdint>  // uint32_t/uint64_t, required by robin_hood.h
#include "robin_hood.h"
#include <string>

// Interned string: refcount, hash and bytes live together, so retain is a single increment
// and only release — when the count reaches zero — needs a table lookup.
struct InternedStr {
    int refcount = 1;
    uint32_t hash;
    std::string str;
    InternedStr(InternedStr&&) = delete;
    InternedStr& operator=(InternedStr&&) = delete;
};

// The table holds the strings themselves, hashed by the hash they already carry: a new string is
// hashed ONCE, when it is looked up, and the insertion, the rehash and the erase reuse that value.
struct StringTable {
    struct Hash {
        size_t operator()(const InternedStr* p) const noexcept {
            return p->hash;
        }
    };
    struct Equal {
        bool operator()(const InternedStr* a, const InternedStr* b) const noexcept {
            return a == b || (a->hash == b->hash && a->str == b->str);
        }
    };
    robin_hood::unordered_flat_set<InternedStr*, Hash, Equal> table_;

    InternedStr* intern(std::string s) {
        // A probe on the stack carries the text and its hash for the lookup; on a miss the text moves
        // on into the heap string that stays.
        InternedStr probe{1, (uint32_t)std::hash<std::string>{}(s), std::move(s)};
        auto it = table_.find(&probe);
        if (it != table_.end()) {
            ++(*it)->refcount;
            return *it;
        }
        auto* p = new InternedStr{1, probe.hash, std::move(probe.str)};
        table_.insert(p);
        return p;
    }

    void erase(InternedStr* p) {
        table_.erase(p); // BEFORE the delete: the hash and the text are read from p
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
