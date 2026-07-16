#pragma once
// Inclus par chunk.h après Map et Array — ne pas inclure directement.
#include <cstdint> // uint8_t (underlying type de Iterator::Kind)
#include <utility>
#include <vector>

struct Iterator {
    // Tag concret : permet à la VM (FOR_ITER_NEXT1) de dévirtualiser le cas range —
    // appel direct inlinable au lieu d'un appel virtuel par élément — sans dupliquer
    // la logique d'avancement (advance() reste l'unique implémentation).
    enum Kind : uint8_t { KIND_MAP, KIND_ARRAY, KIND_RANGE };
    Kind kind;
    int refcount = 1;
    explicit Iterator(Kind k) : kind(k) {
    }
    virtual bool next(Value& key, Value& val) = 0;
    virtual bool next_primary(Value& out) = 0; // FOR_ITER_NEXT1: retourne seulement la valeur primaire
    virtual bool primary_is_val() const = 0;   // true=val (array/range), false=key (map)
    virtual void release() {
        delete this;
    } // peut être overridé pour pool
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
    std::vector<Value> items; // snapshot au moment du for-in (cohérent avec MapIterator)
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
    void release() override; // retourne au pool (défini après ArrayIteratorPool)
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
    // Comme ArrayPool : le snapshot `items` peut être volumineux et clear() ne
    // libère pas la capacité → ne pooler que les petits, détruire les gros.
    static constexpr size_t POOL_MAX_CAP = 4096;
    void release(ArrayIterator* it) {
        // RÉ-ENTRANCE : it->items.clear() libère les valeurs du snapshot, ce qui peut
        // ré-entrer les pools (une valeur map/array → release → buf[n++]) et faire
        // croître n ici. On vide AVANT, puis on (re)teste la capacité — sinon buf[n++]
        // déborderait sur &n. (Cf. MapPool / ArrayPool.)
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
