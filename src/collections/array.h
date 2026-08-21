#pragma once
// Included by chunk.h after Value is defined; do not include directly.
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
        if (i >= (int64_t)items.size())
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
    Array* buf[CAP];
    int n = 0;

    Array* acquire() {
        if (n) {
            Array* a = buf[--n];
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
        // REENTRANCY: a->items.clear() releases the elements, which can re-enter the pool (an
        // array element releases and does buf[n++]) and make n GROW. So clear FIRST, then test the
        // capacity again with the up-to-date n — otherwise buf[n++] would write buf[CAP], which is
        // &n, whenever a nested release filled the pool during the clear.
        if (a->items.capacity() > POOL_MAX_CAP) {
            delete a; // gros tableau : jamais poolé
            return;
        }
        a->items.clear(); // peut ré-entrer le pool (releases imbriqués) → n peut changer
        if (n < CAP) {
            buf[n++] = a; // n RELU après clear
        } else {
            delete a; // items déjà vidés
        }
    }
};
inline ArrayPool& array_pool() {
    static ArrayPool p;
    return p;
}
