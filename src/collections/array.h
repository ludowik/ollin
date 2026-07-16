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
    // clear() ne libère PAS la capacité du vector : ne pooler que les petits
    // tableaux, sinon un tableau transitoire volumineux resterait épinglé dans ce
    // pool static (mémoire jamais rendue, OOM possible sur WASM). Les gros sont
    // détruits → buffer rendu à l'allocateur.
    static constexpr size_t POOL_MAX_CAP = 4096;
    void release(Array* a) {
        // RÉ-ENTRANCE : a->items.clear() libère les éléments, ce qui peut ré-entrer le
        // pool (un élément array → release → buf[n++]) et faire CROÎTRE n. On vide donc
        // AVANT, puis on (re)teste la capacité avec le n à jour — sinon buf[n++] écrirait
        // buf[CAP] (= &n) quand un release imbriqué a rempli le pool pendant le clear.
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
