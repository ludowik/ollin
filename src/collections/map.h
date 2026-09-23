#pragma once
// Included by chunk.h after Value is defined; do not include directly.
#include "fixed_pool.h"
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
    // The map's role. It fits in the alignment hole before userdata, so sizeof(Map) is unchanged.
    // ENUM is tested ONLY on writes (SET_INDEX): an enum reads like an ordinary map — iterable,
    // len, print — but refuses every mutation.
    // MODULE marks the root object of a built-in module (math, string, graphics…), set once by
    // make_builtin_module. It is read in exactly two places: Value::type_name (typeof(math) says
    // "module", not "map") and CALL_METHOD's self-injection (see the comment there). It is NOT a
    // separate Value tag — a module is still is_map() everywhere else (proto_chain_get, the
    // ref-counted release/retain switch, SET_INDEX…), which is the whole point: a distinct TAG
    // was tried before (T_MODULE, removed 2026-07-20) and required every one of those places to
    // grow a matching branch, and still broke on a value HELD BY a module — a Color instance
    // nested in a module kept losing its own identity across three fix attempts before the tag
    // was scrapped. MODULE lives only on the module's own root Map, never propagates to whatever
    // the module contains, and so needs no such branch anywhere else.
    // ⚠ Never set on a value the enum path can also mark: a class instance's own map is PLAIN,
    // a class object itself is T_CLASS (a different tag, unaffected by kind at all).
    enum : uint8_t { PLAIN = 0, ENUM = 1, MODULE = 2 };
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
    FixedPool<Map, CAP> pool;

    Map* acquire() {
        if (Map* m = pool.take()) {
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
        if (m->data.size() > POOL_MAX_SIZE) {
            delete m; // a big map: ~Map frees the entries and the buckets, and it is never pooled
            return;
        }
        m->data.clear();  // this can re-enter the pool through nested releases (see FixedPool)
        m->version = ++g_map_epoch;  // recycling: invalidates every inline cache aimed at this Map*
        m->kind = Map::PLAIN;             // otherwise a recycled map would come back frozen (enum) or as a module
        pool.store_or_delete(m);
    }
};
// A namespace-scope inline variable, not a function-local static: the latter carries a
// thread-safe initialization guard checked on EVERY call, measured to bloat a hot accessor's
// code and slow it down when inlined into a path used regardless of whether pooling is ever
// exercised (see the same fix and its measurement on closure_pool()/upvalue_pool(), CLAUDE.md).
inline MapPool s_map_pool;
inline MapPool& map_pool() {
    return s_map_pool;
}
