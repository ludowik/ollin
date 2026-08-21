#pragma once
#include <cstdint>
#include <vector>

// Included from the bottom of chunk.h, where Value is a complete type.

struct Upvalue {
    int refcount = 1;
    bool closed = false;
    int frame_base = 0;
    int reg_idx = 0;
    Value val; // holds value after close
};

struct Closure {
    int refcount = 1;
    uint8_t func_idx;
    std::vector<Upvalue*> upvals;

    explicit Closure(uint8_t fi) : func_idx(fi) {
    }
    ~Closure() {
        for (auto* u : upvals)
            if (--u->refcount == 0)
                delete u;
    }
    // Owns ref-counted Upvalue*, hence non-copyable: a copy would share the pointers without
    // retaining them and the second destructor would double-free. Always handled through
    // Closure* (new / refcount), never by value.
    Closure(const Closure&) = delete;
    Closure& operator=(const Closure&) = delete;
};
