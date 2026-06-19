#pragma once
// Inclus par chunk.h après Map et Array — ne pas inclure directement.
#include <vector>
#include <utility>

struct Iterator {
    int refcount = 1;
    virtual bool next(Value& key, Value& val) = 0;
    virtual bool next_primary(Value& out) = 0;   // FOR_ITER_NEXT1: retourne seulement la valeur primaire
    virtual bool primary_is_val() const = 0;     // true=val (array/range), false=key (map)
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
    bool next_primary(Value& out) override {
        if (pos >= snapshot.size()) return false;
        out = snapshot[pos].first;
        ++pos;
        return true;
    }
    bool primary_is_val() const override { return false; }  // 1 var → key
};

struct ArrayIterator : Iterator {
    std::vector<Value> items;  // snapshot au moment du for-in (cohérent avec MapIterator)
    int pos = 0;
    explicit ArrayIterator(Array* a) : items(a->items) {}
    bool next(Value& key, Value& val) override {
        if (pos >= (int)items.size()) return false;
        key = Value((int64_t)(pos + 1));
        val = items[pos];
        ++pos;
        return true;
    }
    bool next_primary(Value& out) override {
        if (pos >= (int)items.size()) return false;
        out = items[pos];
        ++pos;
        return true;
    }
    bool primary_is_val() const override { return true; }
};
