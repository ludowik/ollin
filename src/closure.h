#pragma once
#include <cstdint>
#include <vector>

// Included from the bottom of chunk.h — Value is complete here.

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
};
