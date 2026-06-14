#pragma once
// Inclus par chunk.h après la définition de Value — ne pas inclure directement.
#include <unordered_map>
#include <utility>
#include <vector>

struct ValueHash {
    std::size_t operator()(const Value& v) const noexcept;
};

struct ValueEqual {
    bool operator()(const Value& a, const Value& b) const noexcept;
};

// LinkedHashMap : lookup O(1) + ordre d'insertion + itération indexée.
struct Map {
    std::vector<std::pair<Value, Value>>                           entries;
    std::unordered_map<Value, std::size_t, ValueHash, ValueEqual> index;
    int refcount = 1;

    Value get(const Value& k) const;
    void  set(const Value& k, const Value& v);

    int          size()       const { return (int)entries.size(); }
    const Value& keyAt(int i) const { return entries[(size_t)i].first;  }
    const Value& valAt(int i) const { return entries[(size_t)i].second; }
};

struct MapPool {
    static constexpr int CAP = 64;
    Map* buf[CAP];
    int  n = 0;

    Map* acquire() {
        if (n) { Map* m = buf[--n]; m->refcount = 1; return m; }
        return new Map();
    }
    void release(Map* m) {
        m->entries.clear();
        m->index.clear();
        if (n < CAP) buf[n++] = m;
        else delete m;
    }
};
inline MapPool& map_pool() { static MapPool p; return p; }
