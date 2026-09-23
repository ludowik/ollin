#pragma once
// Included by chunk.h after Map and Array; do not include directly.
#include "../utf8.h"
#include "fixed_pool.h"
#include <cstdint> // uint8_t (the underlying type of Iterator::Kind)
#include <utility>
#include <vector>

struct Iterator {
    // Concrete tag, so the VM (FOR_ITER_NEXT1) can devirtualize the range case — an inlinable
    // direct call instead of one virtual call per element — without duplicating the stepping
    // logic: advance() remains the single implementation.
    enum Kind : uint8_t { KIND_MAP, KIND_ARRAY, KIND_RANGE, KIND_STRING };
    Kind kind;
    int refcount = 1;
    explicit Iterator(Kind k) : kind(k) {
    }
    virtual bool next(Value& key, Value& val) = 0;
    virtual bool next_primary(Value& out) = 0; // FOR_ITER_NEXT1: yields the primary value only
    virtual bool primary_is_val() const = 0;   // true=val (array/range), false=key (map)
    virtual void release() {
        delete this;
    } // can be overridden to pool the object
    virtual ~Iterator() = default;
};

struct MapIterator : Iterator {
    std::vector<std::pair<Value, Value>> snapshot;
    size_t pos = 0;
    explicit MapIterator(Map* m) : Iterator(KIND_MAP) {
        snapshot.reserve(m->data.size());
        for (auto& [k, v] : m->data)
            snapshot.emplace_back(k, v);
    }
    bool next(Value& key, Value& val) override {
        if (pos >= snapshot.size())
            return false;
        key = snapshot[pos].first;
        val = snapshot[pos].second;
        ++pos;
        return true;
    }
    bool next_primary(Value& out) override {
        if (pos >= snapshot.size())
            return false;
        out = snapshot[pos].first;
        ++pos;
        return true;
    }
    bool primary_is_val() const override {
        return false;
    } // 1 var → key
};

struct ArrayIterator : Iterator {
    std::vector<Value> items; // a snapshot taken at the for-in, consistent with MapIterator
    int64_t pos = 0;
    explicit ArrayIterator(Array* a) : Iterator(KIND_ARRAY), items(a->items) {
    }
    bool next(Value& key, Value& val) override {
        if (pos >= (int64_t)items.size())
            return false;
        key = Value(pos + 1);
        val = items[(size_t)pos];
        ++pos;
        return true;
    }
    bool next_primary(Value& out) override {
        if (pos >= (int64_t)items.size())
            return false;
        out = items[(size_t)pos];
        ++pos;
        return true;
    }
    bool primary_is_val() const override {
        return true;
    }
    void release() override; // returns to the pool; defined after ArrayIteratorPool
};

// A string yields its CHARACTERS (UTF-8 codepoints), like len, char and substr count them — with
// the same two forms as an array: one variable gives the character, two give its 1-based index
// and the character.
//
// No snapshot, unlike the map and array iterators: a string is immutable and interned, so keeping
// a retained reference is enough and nothing can change under the loop. Walking it this way is
// also what makes a traversal linear — `for i = 1, s.len() do s.char(i)` recounts the codepoints
// from the start at every turn, so it is quadratic.
struct StringIterator : Iterator {
    Value src;
    size_t byte = 0;
    int64_t idx = 0;
    explicit StringIterator(const Value& s) : Iterator(KIND_STRING), src(s) {
    }
    bool next(Value& key, Value& val) override {
        if (!step(val))
            return false;
        key = Value(idx); // idx is the index of the character step() has just yielded
        return true;
    }
    bool next_primary(Value& out) override {
        return step(out);
    }
    bool primary_is_val() const override {
        return true;
    }

  private:
    bool step(Value& out) {
        const std::string& s = src.as_string();
        if (byte >= s.size())
            return false;
        size_t n = utf8_step(s, byte);
        out = Value(s.substr(byte, n));
        byte += n;
        ++idx;
        return true;
    }
};

struct ArrayIteratorPool {
    static constexpr int CAP = 32;
    FixedPool<ArrayIterator, CAP> pool;

    ArrayIterator* acquire(Array* a) {
        if (ArrayIterator* it = pool.take()) {
            it->refcount = 1;
            it->pos = 0;
            it->items = a->items;
            return it;
        }
        return new ArrayIterator(a);
    }
    // As in ArrayPool: the `items` snapshot may be large and clear() does not free the
    // capacity, so only small ones are pooled and large ones destroyed.
    static constexpr size_t POOL_MAX_CAP = 4096;
    void release(ArrayIterator* it) {
        if (it->items.capacity() > POOL_MAX_CAP) {
            delete it;
            return;
        }
        it->items.clear(); // this can re-enter the pools through nested releases (see FixedPool)
        pool.store_or_delete(it);
    }
};
// A namespace-scope inline variable, not a function-local static: see map_pool() (map.h) for
// why — the thread-safe initialization guard of a function-local static was measured to bloat
// and slow a hot accessor even when pooling itself is never exercised.
inline ArrayIteratorPool s_array_iter_pool;
inline ArrayIteratorPool& array_iter_pool() {
    return s_array_iter_pool;
}
inline void ArrayIterator::release() {
    array_iter_pool().release(this);
}
