#pragma once
// Inclus par chunk.h après la définition de Value — ne pas inclure directement.
#include "robin_hood.h"
#ifdef __EMSCRIPTEN__
#include <emscripten.h>   // DIAG: détecteur de double-free
#endif

struct ValueHash {
    std::size_t operator()(const Value& v) const noexcept;
};

struct ValueEqual {
    bool operator()(const Value& a, const Value& b) const noexcept;
};

struct Map {
    robin_hood::unordered_map<Value, Value, ValueHash, ValueEqual> data;
    int refcount = 1;
    void* userdata = nullptr;
    bool freed = false;   // DIAG: true quand rendu au pool → détecte double-free

    Value get(const Value& k) const;
    void set(const Value& k, const Value& v);
};

struct MapPool {
    static constexpr int CAP = 64;
    Map* buf[CAP];
    int n = 0;

    Map* acquire() {
        if (n) {
            Map* m = buf[--n];
#ifdef __EMSCRIPTEN__
            // SONDE : une map recyclée DOIT être vide (data.clear() à la libération)
            // et non nulle. Sinon la free-list du pool a été corrompue (écriture
            // hors-bornes sur une map inactive pendant un run graphique) → c'est la
            // source du 'tag=6 ptr=0' relâché ensuite.
            if (m == nullptr) {
                EM_ASM({ if (window.__ollinCrash) window.__ollinCrash.noteStderr("POISON acquire: NULL map dans le pool"); console.error("POISON acquire NULL map"); });
                return new Map();
            }
            if (!m->data.empty())
                EM_ASM({ var s = "POISON acquire: map recyclee NON vide size=" + $0; if (window.__ollinCrash) window.__ollinCrash.noteStderr(s); console.error(s); }, (int)m->data.size());
#endif
            m->refcount = 1;
            m->userdata = nullptr;
            m->freed = false;
            return m;
        }
        return new Map();
    }
    // clear() ne libère pas les buckets de robin_hood → ne pooler que les petites
    // maps, sinon une map transitoire volumineuse resterait épinglée dans ce pool
    // static (mémoire jamais rendue). Cf. ArrayPool / ArrayIteratorPool.
    static constexpr size_t POOL_MAX_SIZE = 1024;
    void release(Map* m) {
#ifdef __EMSCRIPTEN__
        if (m->freed) {
            EM_ASM({ var s="POISON map double-free ptr=0x"+($0>>>0).toString(16); if(window.__ollinCrash)window.__ollinCrash.noteStderr(s); console.error(s); }, (int)(intptr_t)m);
            return;   // ne pas ré-ajouter au pool (évite d'aggraver + le log survit)
        }
        m->freed = true;
#endif
        if (n < CAP && m->data.size() <= POOL_MAX_SIZE) {
            m->data.clear();
            buf[n++] = m;
        } else {
            delete m;
        }
    }
};
inline MapPool& map_pool() {
    static MapPool p;
    return p;
}
