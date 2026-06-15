#pragma once
// Inclus par chunk.h après Map et Array — ne pas inclure directement.
#include <vector>
#include <utility>

struct Iterator {
    int refcount = 1;
    virtual bool next(Value& key, Value& val) = 0;
    virtual ~Iterator() = default;
};

struct MapIterator : Iterator {
    std::vector<std::pair<Value, Value>> snapshot;
    size_t pos = 0;
    explicit MapIterator(Map* m) {
        snapshot.reserve(m->data.size());
        for (auto& [k, v] : m->data) snapshot.emplace_back(k, v);
    }
    bool next(Value& key, Value& val) override {
        if (pos >= snapshot.size()) return false;
        key = snapshot[pos].first;
        val = snapshot[pos].second;
        ++pos;
        return true;
    }
};

struct ArrayIterator : Iterator {
    Array* arr;
    int pos = 0;
    explicit ArrayIterator(Array* a) : arr(a) { arr->refcount++; }
    ~ArrayIterator() override {
        if (--arr->refcount == 0) array_pool().release(arr);
    }
    bool next(Value& key, Value& val) override {
        if (pos >= (int)arr->items.size()) return false;
        key = Value((int64_t)(pos + 1));
        val = arr->items[pos];
        ++pos;
        return true;
    }
};
