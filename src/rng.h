#pragma once
// The engine's random generator: splitmix64, in integers only, so a seed gives the SAME sequence on every platform. The C
// library's rand() is not used anywhere: its range is 32767 on Windows, which left whole parts of a big array or of a wide
// randInt out of reach, and its sequence differs from one platform to the next.
//
// A generator is an INSTANCE that owns its state: the engine's own is g_engine_rng (main thread), the Perlin table is
// shuffled by a local one, every sound voice has its own, which is what keeps the audio thread free of shared state, and
// a script makes its own with the Random class (modules/random_module.cpp).
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <utility>

// The two halves of a * b. A 128-bit integer is a GCC/Clang extension that 32-bit targets (armeabi-v7a, i686) do not
// have: there the product is put together from four 32-bit ones. Both forms are kept apart so that the unit test can
// hold the portable one against the wide one.
inline void rng_mul_portable(uint64_t a, uint64_t b, uint64_t& hi, uint64_t& lo) {
    const uint64_t mask = 0xFFFFFFFFULL;
    uint64_t a0 = a & mask, a1 = a >> 32, b0 = b & mask, b1 = b >> 32;
    uint64_t p00 = a0 * b0, p01 = a0 * b1, p10 = a1 * b0, p11 = a1 * b1;
    uint64_t mid = (p00 >> 32) + (p01 & mask) + (p10 & mask);
    hi = p11 + (p01 >> 32) + (p10 >> 32) + (mid >> 32);
    lo = (mid << 32) | (p00 & mask);
}

inline void rng_mul_wide(uint64_t a, uint64_t b, uint64_t& hi, uint64_t& lo) {
#ifdef __SIZEOF_INT128__
    unsigned __int128 m = (unsigned __int128)a * b;
    hi = (uint64_t)(m >> 64);
    lo = (uint64_t)m;
#else
    rng_mul_portable(a, b, hi, lo);
#endif
}

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
        uint64_t high, low;
        rng_mul_wide(next(), n, high, low);
        if (low < n) {
            uint64_t threshold = (0 - n) % n;   // 2^64 mod n
            while (low < threshold)
                rng_mul_wide(next(), n, high, low);
        }
        return high;
    }

    // Fisher-Yates over [first, last): every ordering is equally likely, `below` being unbiased, which `rand() % n`
    // would not be. For a given seed this is the one shuffle of the engine: the Perlin table and array.shuffle.
    template <class RandomIt>
    void shuffle(RandomIt first, RandomIt last) {
        for (size_t i = (size_t)(last - first); i > 1; i--)
            std::swap(first[i - 1], first[(size_t)below(i)]);
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
    return Rng((uint64_t)std::chrono::system_clock::now().time_since_epoch().count()).next();
}

// The generator of math.rand, math.randInt, Color.random. A namespace-scope inline variable, and not a
// function-local static: no guard to check at each call (cf. the pools, CLAUDE.md).
inline Rng g_engine_rng{rng_clock_seed()};
