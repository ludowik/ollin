#pragma once

// Free-list bookkeeping shared by every fixed-capacity object pool (Map, Array, ArrayIterator,
// Closure, Upvalue): a fixed buf[CAP] of pointers plus a count, so a short-lived object no longer
// pays a malloc/free pair on the hot allocate/release path. A concrete pool composes this — it
// keeps its own acquire()/release() (the reset logic differs per type, and ArrayIteratorPool and
// ClosurePool even take construction arguments, and Map/Array/ArrayIterator additionally bail out
// of pooling a large instance) — only the slot bookkeeping itself is written once.
//
// REENTRANCY (the invariant every concrete release() must honour): whatever type-specific reset
// runs before store_or_delete (clearing a container, releasing captured upvalues…) can itself
// release another object of the SAME pool, growing n as a side effect — a map holding another map,
// a closure whose upvalue closes over another closure. store_or_delete must therefore be called
// LAST, after that reset, so it reads n fresh; calling it before the reset let a nested release
// overflow buf[CAP] (= &n) once, corrupting the free list — see MapPool's history.
template <class T, int CAP>
struct FixedPool {
    T* buf[CAP];
    int n = 0;

    // The pooled instance to reuse, or nullptr when the pool is empty (the caller then makes a
    // fresh one).
    T* take() {
        return n ? buf[--n] : nullptr;
    }
    // Give p back to the pool if there is room, otherwise free it. Call this LAST in release() —
    // see REENTRANCY above.
    void store_or_delete(T* p) {
        if (n < CAP)
            buf[n++] = p;
        else
            delete p;
    }
};
