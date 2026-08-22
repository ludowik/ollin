#pragma once
// Included by chunk.h after Value is defined; do not include directly.
#include "robin_hood.h"

struct ValueHash {
    std::size_t operator()(const Value& v) const noexcept;
};

struct ValueEqual {
    bool operator()(const Value& a, const Value& b) const noexcept;
};

// Monotonic global epoch: every map mutation gets a unique version. The GET_INDEX inline cache
// (vm.cpp) relies on it — a (Map*, version) pair identifies one state of one map, and stays
// unambiguous when an address is reused by the pool.
extern uint64_t g_map_epoch;

struct Map {
    robin_hood::unordered_map<Value, Value, ValueHash, ValueEqual> data;
    int refcount = 1;
    // The map's role, tested ONLY on writes (SET_INDEX): an enum reads like an ordinary map —
    // iterable, len, print — but refuses every mutation. It fits in the alignment hole before
    // userdata, so sizeof(Map) is unchanged.
    enum : uint8_t { PLAIN = 0, ENUM = 1 };
    uint8_t kind = PLAIN;
    void* userdata = nullptr;
    uint64_t version = 0;   // = ++g_map_epoch on every mutation; 0 means never mutated

    Value get(const Value& k) const;
    // Location of the value, or nullptr when absent. This is what lets the GET_INDEX inline
    // cache keep a NON-owning reference: the map itself keeps the value alive as long as its
    // version does not change. Only dereference after validating (Map*, version).
    const Value* find_ptr(const Value& k) const;
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
            return m;   // kind and version were already reset by release()
        }
        return new Map();
    }
    // clear() does not free robin_hood's buckets, so only small maps are pooled: a large
    // transient map would otherwise stay pinned in this static pool and its memory never
    // returned. Same reasoning as ArrayPool and ArrayIteratorPool.
    static constexpr size_t POOL_MAX_SIZE = 1024;
    void release(Map* m) {
        // REENTRANCY: m->data.clear() releases the entries, which can re-enter the pool (a map
        // entry releases and does buf[n++]) and make n GROW. So clear FIRST, then test the
        // capacity again with the up-to-date n — otherwise buf[n++] would write buf[CAP], which
        // is &n, whenever a nested release filled the pool during the clear. That one-byte
        // overflow used to corrupt n.
        if (m->data.size() > POOL_MAX_SIZE) {
            delete m; // a big map: ~Map frees the entries and the buckets, and it is never pooled
            return;
        }
        m->data.clear();  // this can re-enter the pool through nested releases, so n may change
        m->version = ++g_map_epoch;  // recyclage : invalide tout inline cache pointant sur ce Map*
        m->kind = Map::PLAIN;             // otherwise a recycled map would come back frozen, as an enum
        if (n < CAP) {
            buf[n++] = m; // n is READ AGAIN after the clear
        } else {
            delete m; // the data is already emptied
        }
    }
};
inline MapPool& map_pool() {
    static MapPool p;
    return p;
}
