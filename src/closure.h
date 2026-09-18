#pragma once
#include "opcode.h" // FuncIdx: a closure names its function exactly as CALL_FUNC does
#include <cstdint>
#include <memory>
#include <vector>

// Included from the bottom of chunk.h, where Value is a complete type.

struct Upvalue {
    int refcount = 1;
    bool closed = false;
    int frame_base = 0;
    int reg_idx = 0;
    Value val; // holds value after close
};

// Same shape as MapPool/ArrayPool (collections/map.h): a small fixed-capacity free list, so a
// closure created and dropped in a tight loop no longer pays a malloc/free pair per upvalue.
// REENTRANCY, same rule as those pools: releasing `val` can itself release a Closure whose
// upvalues come back through THIS pool (a closed-over variable holding another closure), so `n`
// is read again AFTER that release, never cached before it.
struct UpvaluePool {
    static constexpr int CAP = 64;
    Upvalue* buf[CAP];
    int n = 0;

    Upvalue* acquire() {
        if (n) {
            Upvalue* u = buf[--n];
            u->refcount = 1;
            u->closed = false;
            u->frame_base = 0;
            u->reg_idx = 0;
            return u; // val already cleared by release()
        }
        return new Upvalue();
    }
    void release(Upvalue* u) {
        u->val = Value(); // let go of whatever it held; see the reentrancy note above
        if (n < CAP) {
            buf[n++] = u;
        } else {
            delete u;
        }
    }
};
inline UpvaluePool& upvalue_pool() {
    static UpvaluePool p;
    return p;
}

struct Closure {
    int refcount = 1;
    FuncIdx func_idx;
    std::vector<Upvalue*> upvals;

    explicit Closure(FuncIdx fi) : func_idx(fi) {
    }
    ~Closure() {
        release_upvals();
    }
    // Owns ref-counted Upvalue*, hence non-copyable: a copy would share the pointers without
    // retaining them and the second release would double-free. Always handled through
    // Closure* (pool-acquired or new, refcount), never by value.
    Closure(const Closure&) = delete;
    Closure& operator=(const Closure&) = delete;

    // Decrements each captured upvalue's refcount, returning the ones that reach zero to
    // UpvaluePool, then empties the vector (capacity kept, as Map keeps its buckets — a closure
    // recycled by ClosurePool needs the same slots again more often than not). Shared by the
    // destructor (a Closure not recycled, or one whose pool was full) and by
    // ClosurePool::release, where the Closure object itself survives.
    void release_upvals() {
        for (auto* u : upvals)
            if (--u->refcount == 0)
                upvalue_pool().release(u);
        upvals.clear();
    }
};

// Same free-list shape as UpvaluePool, for the same reason: MAKE_CLOSURE runs once per closure
// created, and a tight loop returning one (a factory function, say) was a malloc and a free for
// what is otherwise a handful of pointer writes. `upvals` holds only pointers, never the
// captured data itself, so — unlike a Map's buckets — there is no scenario where recycling a
// Closure pins down a large buffer; no size cutoff is needed here.
struct ClosurePool {
    static constexpr int CAP = 64;
    Closure* buf[CAP];
    int n = 0;

    Closure* acquire(FuncIdx fi) {
        if (n) {
            Closure* c = buf[--n];
            c->refcount = 1;
            c->func_idx = fi;
            return c; // upvals already emptied by release()
        }
        return new Closure(fi);
    }
    void release(Closure* c) {
        // REENTRANCY: release_upvals() can re-enter this pool (an upvalue's closed value may
        // itself be a Closure whose refcount just hit zero), so `n` is read fresh AFTER it.
        c->release_upvals();
        if (n < CAP) {
            buf[n++] = c;
        } else {
            delete c;
        }
    }
};
inline ClosurePool& closure_pool() {
    static ClosurePool p;
    return p;
}

// Pairs with std::unique_ptr for exception safety at the one construction site (MAKE_CLOSURE):
// if capturing an upvalue throws partway through, the partially-built Closure is returned to the
// pool — its already-retained upvalues correctly released by release_upvals() — instead of
// leaking or being freed outright.
struct ClosurePoolDeleter {
    void operator()(Closure* c) const {
        closure_pool().release(c);
    }
};
using ClosureGuard = std::unique_ptr<Closure, ClosurePoolDeleter>;
