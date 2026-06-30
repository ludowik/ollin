#pragma once
// Inclus par chunk.h après la définition de Value — ne pas inclure directement.
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
    void release(Array* a) {
        a->items.clear();
        if (n < CAP)
            buf[n++] = a;
        else
            delete a;
    }
};
inline ArrayPool& array_pool() {
    static ArrayPool p;
    return p;
}
