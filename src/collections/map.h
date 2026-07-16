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
    unsigned magic0 = 0x600DCAFEu;   // DIAG : sentinelle AVANT buf (détecte un débordement dans le pool)
    Map* buf[CAP];
    int n = 0;
    unsigned magic1 = 0x600DCAFEu;   // DIAG : sentinelle APRÈS n

    Map* acquire() {
        if (n) {
#ifdef __EMSCRIPTEN__
            // SONDE : la free-list du pool est corrompue (source du 'tag=6 ptr=0').
            // On distingue le MODE de corruption : sentinelle écrasée (débordement
            // d'un buffer voisin DANS le pool), n hors plage, ou slot nul.
            if (magic0 != 0x600DCAFEu || magic1 != 0x600DCAFEu)
                EM_ASM({ var s = "POISON pool magic clobbered m0=0x" + ($0 >>> 0).toString(16) + " m1=0x" + ($1 >>> 0).toString(16) + " n=" + $2; if (window.__ollinCrash) window.__ollinCrash.noteStderr(s); console.error(s); }, (int)magic0, (int)magic1, n);
            if (n < 0 || n > CAP)
                EM_ASM({ var s = "POISON pool n hors plage n=" + $0; if (window.__ollinCrash) window.__ollinCrash.noteStderr(s); console.error(s); }, n);
#endif
            Map* m = buf[--n];
#ifdef __EMSCRIPTEN__
            if (m == nullptr) {
                int nulls = 0;
                for (int i = 0; i < CAP; i++)
                    if (buf[i] == nullptr)
                        nulls++;
                EM_ASM({ var s = "POISON acquire NULL map: n(apres)=" + $0 + " nulls=" + $1 + "/64 m0ok=" + $2 + " m1ok=" + $3; if (window.__ollinCrash) window.__ollinCrash.noteStderr(s); console.error(s); },
                       n, nulls, magic0 == 0x600DCAFEu ? 1 : 0, magic1 == 0x600DCAFEu ? 1 : 0);
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
