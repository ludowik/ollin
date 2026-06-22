#pragma once
#include <string>
#include <unordered_map>

// Objet d'internement : refcount + hash + contenu au même endroit.
// retain = ++p->refcount (zéro lookup)
// release = if (--p->refcount == 0) string_table().erase(p) (lookup seulement à la mort)
struct InternedStr {
    int         refcount = 1;
    uint32_t    hash;
    std::string str;
};

struct StringTable {
    std::unordered_map<std::string, InternedStr*> table_;

    InternedStr* intern(std::string s) {
        auto it = table_.find(s);
        if (it != table_.end()) { ++it->second->refcount; return it->second; }
        auto h = (uint32_t)std::hash<std::string>{}(s);
        auto* p = new InternedStr{1, h, std::move(s)};
        table_[p->str] = p;
        return p;
    }

    void erase(InternedStr* p) {
        table_.erase(p->str);
        delete p;
    }
};

inline StringTable& string_table() { static StringTable t; return t; }

inline InternedStr* intern(std::string s) { return string_table().intern(std::move(s)); }
