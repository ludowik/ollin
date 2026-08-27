#pragma once
// Included by chunk.h after Map and Array; do not include directly.
#include <cstdint> // uint8_t (the underlying type of Iterator::Kind)
#include <utility>
#include <vector>

struct Iterator {
    // Concrete tag, so the VM (FOR_ITER_NEXT1) can devirtualize the range case — an inlinable
    // direct call instead of one virtual call per element — without duplicating the stepping
    // logic: advance() remains the single implementation.
    enum Kind : uint8_t { KIND_MAP, KIND_ARRAY, KIND_RANGE };
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

struct ArrayIteratorPool {
    static constexpr int CAP = 32;
    ArrayIterator* buf[CAP];
    int n = 0;

    ArrayIterator* acquire(Array* a) {
        if (n) {
            ArrayIterator* it = buf[--n];
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
        // REENTRANCY: it->items.clear() releases the snapshot's values, which can re-enter the
        // pools (a map or array value releases and does buf[n++]) and make n grow here. Clear
        // FIRST, then test the capacity again — otherwise buf[n++] would overflow onto &n. Same
        // as MapPool and ArrayPool.
        if (it->items.capacity() > POOL_MAX_CAP) {
            delete it;
            return;
        }
        it->items.clear();
        if (n < CAP) {
            buf[n++] = it;
        } else {
            delete it;
        }
    }
};
inline ArrayIteratorPool& array_iter_pool() {
    static ArrayIteratorPool p;
    return p;
}
inline void ArrayIterator::release() {
    array_iter_pool().release(this);
}
