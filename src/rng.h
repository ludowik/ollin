#pragma once
// The engine's random generator: splitmix64, in integers only, so a seed gives the SAME sequence on every platform. The C
// library's rand() is not used anywhere: its range is 32767 on Windows, which left whole parts of a big array or of a wide
// randInt out of reach, and its sequence differs from one platform to the next.
//
// A generator is an INSTANCE that owns its state: the engine's own is g_engine_rng (main thread), the Perlin table is
// shuffled by a local one, and every sound voice has its own, which is what keeps the audio thread free of shared state.
#include <chrono>
#include <cstdint>

struct Rng {
    uint64_t state;

    explicit Rng(uint64_t seed)
        : state(seed) {
    }

    void seed(uint64_t s) {
        state = s;
    }

    uint64_t next() {
        uint64_t z = (state += 0x9E3779B97F4A7C15ULL);
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
        return z ^ (z >> 31);
    }

    // In [0, 1), with all the 53 bits of a double.
    double unit() {
        return (double)(next() >> 11) * (1.0 / 9007199254740992.0);
    }

    // In [-1, 1): a noise sample.
    double signed_unit() {
        return unit() * 2.0 - 1.0;
    }

    // In [0, n), n > 0, with no bias (Lemire): the high half of next() * n is the answer, and the draws that would
    // favour the small values are thrown away. The division that gives the threshold is only reached when the low half
    // is below n, which happens with probability n / 2^64 : the usual draw costs a multiplication and no division.
    uint64_t below(uint64_t n) {
        unsigned __int128 m = (unsigned __int128)next() * n;
        uint64_t low = (uint64_t)m;
        if (low < n) {
            uint64_t threshold = (0 - n) % n;   // 2^64 mod n
            while (low < threshold) {
                m = (unsigned __int128)next() * n;
                low = (uint64_t)m;
            }
        }
        return (uint64_t)(m >> 64);
    }

    // In [lo, hi], lo <= hi, the whole range of int64 included.
    int64_t between(int64_t lo, int64_t hi) {
        uint64_t span = (uint64_t)hi - (uint64_t)lo + 1;
        if (span == 0)
            return (int64_t)next();
        return (int64_t)((uint64_t)lo + below(span));
    }
};

// A seed taken from the clock, to the nanosecond: two programs started in the same second do not share a sequence.
inline uint64_t rng_clock_seed() {
    uint64_t wall = (uint64_t)std::chrono::system_clock::now().time_since_epoch().count();
    uint64_t steady = (uint64_t)std::chrono::steady_clock::now().time_since_epoch().count();
    return Rng(wall ^ (steady << 1)).next();
}

// The generator of math.rand, math.randInt, colors.random. A namespace-scope inline variable, and not a
// function-local static: no guard to check at each call (cf. the pools, CLAUDE.md).
inline Rng g_engine_rng{rng_clock_seed()};
