#pragma once
#include <string>
#include <unordered_map>

// Table d'internement des chaînes avec comptage de références.
// Chaque chaîne unique est stockée une fois.
// Les pointeurs vers les clés sont stables (garantie C++ unordered_map).
struct StringTable {
    std::unordered_map<std::string, int> data;  // string → refcount

    const std::string* intern(std::string s) {
        auto [it, inserted] = data.emplace(std::move(s), 0);
        it->second++;
        return &it->first;
    }

    void retain(const std::string* p) {
        auto it = data.find(*p);
        if (it != data.end()) it->second++;
    }

    void release(const std::string* p) {
        auto it = data.find(*p);
        if (it != data.end() && --it->second == 0)
            data.erase(it);
    }
};

inline StringTable& string_table() {
    static StringTable t;
    return t;
}

inline const std::string* intern(std::string s) { return string_table().intern(std::move(s)); }
