#pragma once
// Inclus par chunk.h après la définition de Value — ne pas inclure directement.
#include <stdexcept>
#include <string>
#include <vector>
#ifdef __EMSCRIPTEN__
#include <emscripten.h>   // DIAG: détecteur de double-free
#endif

struct Array {
    std::vector<Value> items;
    int refcount = 1;
    bool freed = false;   // DIAG: true quand rendu au pool → détecte double-free

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
            a->freed = false;
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
#ifdef __EMSCRIPTEN__
        if (a->freed) {
            EM_ASM({ var s="POISON array double-free ptr=0x"+($0>>>0).toString(16); if(window.__ollinCrash)window.__ollinCrash.noteStderr(s); console.error(s); }, (int)(intptr_t)a);
            return;   // ne pas ré-ajouter au pool (évite d'aggraver + le log survit)
        }
        a->freed = true;
#endif
        if (n < CAP && a->items.capacity() <= POOL_MAX_CAP) {
            a->items.clear();
            buf[n++] = a;
        } else {
            delete a;
        }
    }
};
inline ArrayPool& array_pool() {
    static ArrayPool p;
    return p;
}
