#pragma once
#include <string>
#include <string_view>
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
    // Clé = string_view pointant dans InternedStr::str (stable, heap-alloué).
    // Zéro copie du contenu : la string n'existe qu'une seule fois dans InternedStr.
    std::unordered_map<std::string_view, InternedStr*> table_;

    InternedStr* intern(std::string s) {
        auto it = table_.find(std::string_view(s));
        if (it != table_.end()) { ++it->second->refcount; return it->second; }
        auto h = (uint32_t)std::hash<std::string>{}(s);
        auto* p = new InternedStr{1, h, std::move(s)};
        table_.emplace(std::string_view(p->str), p);  // view dans p->str, pas de copie
        return p;
    }

    void erase(InternedStr* p) {
        table_.erase(std::string_view(p->str));  // avant delete — view doit rester valide
        delete p;
    }
};

inline StringTable& string_table() { static StringTable t; return t; }

inline InternedStr* intern(std::string s) { return string_table().intern(std::move(s)); }
