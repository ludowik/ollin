#pragma once
#include <string>
#include <unordered_map>

// Table d'internement des chaînes avec comptage de références.
// Chaque chaîne unique est stockée une fois ; les pointeurs vers les clés
// sont stables (garantie C++17 unordered_map — pas d'invalidation sur insert).
//
// by_ptr_ fournit un accès O(1) depuis un pointeur vers le {refcount, hash}
// de l'entrée, évitant un lookup par contenu (O(n)) à chaque retain/release.
struct StringTable {
    struct Entry {
        int    refcount;
        size_t hash;  // hash contenu, calculé une seule fois à l'internement
    };

    std::unordered_map<std::string, Entry>          content_;  // déduplication
    std::unordered_map<const std::string*, Entry*>  by_ptr_;   // accès O(1) par pointeur

    const std::string* intern(std::string s) {
        size_t h = std::hash<std::string>{}(s);
        auto [it, inserted] = content_.emplace(std::move(s), Entry{0, h});
        it->second.refcount++;
        if (inserted) by_ptr_[&it->first] = &it->second;
        return &it->first;
    }

    void retain(const std::string* p) {
        by_ptr_.at(p)->refcount++;
    }

    void release(const std::string* p) {
        auto bit = by_ptr_.find(p);
        if (bit == by_ptr_.end()) return;
        if (--bit->second->refcount == 0) {
            by_ptr_.erase(bit);
            content_.erase(*p);
        }
    }

    size_t hashOf(const std::string* p) const {
        auto it = by_ptr_.find(p);
        return it != by_ptr_.end() ? it->second->hash : 0;
    }
};

inline StringTable& string_table() {
    static StringTable t;
    return t;
}

inline const std::string* intern(std::string s) { return string_table().intern(std::move(s)); }
