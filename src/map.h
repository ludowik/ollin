#pragma once
// Inclus par chunk.h après la définition de Value — ne pas inclure directement.
#include <unordered_map>

struct ValueHash {
    std::size_t operator()(const Value& v) const noexcept;
};

struct ValueEqual {
    bool operator()(const Value& a, const Value& b) const noexcept;
};

struct Map {
    std::unordered_map<Value, Value, ValueHash, ValueEqual> data;
    int refcount = 1;

    Value get(const Value& k) const;
    void  set(const Value& k, const Value& v);
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
        m->data.clear();
        if (n < CAP) buf[n++] = m;
        else delete m;
    }
};
inline MapPool& map_pool() { static MapPool p; return p; }
