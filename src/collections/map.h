#pragma once
// Inclus par chunk.h après la définition de Value — ne pas inclure directement.
#include "robin_hood.h"

struct ValueHash {
    std::size_t operator()(const Value& v) const noexcept;
};

struct ValueEqual {
    bool operator()(const Value& a, const Value& b) const noexcept;
};

struct Map {
    robin_hood::unordered_map<Value, Value, ValueHash, ValueEqual> data;
    int refcount = 1;
    void* userdata = nullptr;

    Value get(const Value& k) const;
    void set(const Value& k, const Value& v);
};

struct MapPool {
    static constexpr int CAP = 64;
    Map* buf[CAP];
    int n = 0;

    Map* acquire() {
        if (n) {
            Map* m = buf[--n];
            m->refcount = 1;
            m->userdata = nullptr;
            return m;
        }
        return new Map();
    }
    // clear() ne libère pas les buckets de robin_hood → ne pooler que les petites
    // maps, sinon une map transitoire volumineuse resterait épinglée dans ce pool
    // static (mémoire jamais rendue). Cf. ArrayPool / ArrayIteratorPool.
    static constexpr size_t POOL_MAX_SIZE = 1024;
    void release(Map* m) {
        if (n < CAP && m->data.size() <= POOL_MAX_SIZE) {
            m->data.clear();
            buf[n++] = m;
        } else {
            delete m;
        }
    }
};
inline MapPool& map_pool() {
    static MapPool p;
    return p;
}
