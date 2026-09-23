#pragma once
// Included by chunk.h after Value is defined; do not include directly.
#include "fixed_pool.h"
#include <stdexcept>
#include <string>
#include <vector>

struct Array {
    std::vector<Value> items;
    int refcount = 1;

    Value get(int64_t idx) const {
        int64_t i = idx - 1;
        if (i < 0)
            throw std::runtime_error("runtime: array index must be >= 1 (got " + std::to_string(idx) + ")");
        if (i >= (int64_t)items.size())
            return Value{};
        return items[(size_t)i];
    }
    void set(int64_t idx, const Value& v) {
        int64_t i = idx - 1;
        if (i < 0)
            throw std::runtime_error("runtime: array index must be >= 1 (got " + std::to_string(idx) + ")");
        if (i >= 16'777'216)
            throw std::runtime_error("runtime: array index too large (" + std::to_string(idx) + ")");
        // Appending just past the end is how a script BUILDS an array (`arr[i] = …` in a loop),
        // and resize-then-assign touched the cell twice: a nil default-constructed, then
        // overwritten. push writes it once, on the vector's amortised path.
        // ⚠ Reordering these tests to save a comparison was TRIED and reverted, measured: hoisting
        // items.size() into a local and splitting in-bounds from growth costs +0.20% on a million
        // indexed writes. The compiler already shares the size read by the tests below.
        if (i == (int64_t)items.size()) {
            push(v);
            return;
        }
        if (i > (int64_t)items.size())
            items.resize((size_t)(i + 1));
        items[(size_t)i] = v;
    }
    void push(const Value& v) {
        items.push_back(v);
    }
    Value pop() {
        if (items.empty())
            throw std::runtime_error("runtime: pop on empty array");
        Value v = std::move(items.back());
        items.pop_back();
        return v;
    }
    Value remove_at(int64_t idx) {
        int64_t i = idx - 1;
        if (i < 0 || i >= (int64_t)items.size())
            throw std::runtime_error("runtime: array index out of bounds (got " + std::to_string(idx) + ")");
        Value v = std::move(items[(size_t)i]);
        items.erase(items.begin() + i);
        return v;
    }
    void insert_at(int64_t idx, const Value& v) {
        int64_t i = idx - 1;
        if (i < 0 || i > (int64_t)items.size())
            throw std::runtime_error("runtime: array index out of bounds (got " + std::to_string(idx) + ")");
        items.insert(items.begin() + i, v);
    }
    Value shift() {
        if (items.empty())
            throw std::runtime_error("runtime: dequeue on empty array");
        Value v = std::move(items.front());
        items.erase(items.begin());
        return v;
    }
};

struct ArrayPool {
    static constexpr int CAP = 64;
    FixedPool<Array, CAP> pool;

    Array* acquire() {
        if (Array* a = pool.take()) {
            a->refcount = 1;
            return a;
        }
        return new Array();
    }
    // clear() does NOT free the vector's capacity, so only small arrays are pooled: a large
    // transient array would stay pinned in this static pool, its memory never returned, which can
    // mean an out-of-memory on WASM. Large ones are destroyed and their buffer handed back.
    static constexpr size_t POOL_MAX_CAP = 4096;
    void release(Array* a) {
        if (a->items.capacity() > POOL_MAX_CAP) {
            delete a; // a big array is never pooled
            return;
        }
        a->items.clear(); // this can re-enter the pool through nested releases (see FixedPool)
        pool.store_or_delete(a);
    }
};
// A namespace-scope inline variable, not a function-local static: see map_pool() (map.h) for
// why — the thread-safe initialization guard of a function-local static was measured to bloat
// and slow a hot accessor even when pooling itself is never exercised.
inline ArrayPool s_array_pool;
inline ArrayPool& array_pool() {
    return s_array_pool;
}
