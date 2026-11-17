// UNIT test of the generator (src/rng.h): the published splitmix64 sequence, which is what makes a seed give the same
// numbers on every platform, and the bounds and the fairness of the draws. Called by the main of paths_test.cpp, which sums the failures.
#include "rng.h"
#include "check.h"

#include <cstdio>

static void test_sequence() {
    Rng rng(0);
    expect(rng.next() == 0xE220A8397B1DCDAFULL, "the first value of splitmix64 from seed 0");
    expect(rng.next() == 0x6E789E6AA1B965F4ULL, "the second value");
    expect(rng.next() == 0x06C45D188009454FULL, "the third value");
    Rng a(42);
    Rng b(42);
    expect(a.next() == b.next() && a.next() == b.next(), "the same seed gives the same sequence");
    b.seed(43);
    expect(a.next() != b.next(), "another seed gives another one");
}

static void test_shuffle() {
    int a[8] = {0, 1, 2, 3, 4, 5, 6, 7};
    Rng(1).shuffle(a, a + 8);
    const int expected[8] = {0, 3, 7, 1, 2, 6, 5, 4};   // the same draws as an independent Fisher-Yates from seed 1
    bool same = true;
    for (int i = 0; i < 8; i++)
        same = same && a[i] == expected[i];
    expect(same, "shuffle gives the Fisher-Yates order of splitmix64 from seed 1");
    int one[1] = {5};
    Rng rng(9);
    uint64_t before = rng.state;
    rng.shuffle(one, one + 1);
    rng.shuffle(one, one);
    expect(one[0] == 5 && rng.state == before, "an empty range or a single element draws nothing");
}

static void test_unit() {
    Rng rng(7);
    bool inside = true;
    for (int i = 0; i < 100000; i++) {
        double u = rng.unit();
        inside = inside && u >= 0.0 && u < 1.0;
    }
    expect(inside, "unit() stays in [0, 1)");
}

static void test_below() {
    Rng rng(1);
    bool inside = true;
    for (int i = 0; i < 1000; i++)
        inside = inside && rng.below(3) < 3;
    expect(inside, "below(3) stays in [0, 3)");
    expect(rng.below(1) == 0, "below(1) is 0");
    // A bound above 2^63 throws away about half of the draws: the rejection loop must still end inside the range.
    Rng wide_bound(3);
    uint64_t bound = (1ULL << 63) + 12345;
    bool rejected_inside = true;
    for (int i = 0; i < 1000; i++)
        rejected_inside = rejected_inside && wide_bound.below(bound) < bound;
    expect(rejected_inside, "below(2^63 + k) stays in range through the rejection path");
}

static void test_between() {
    Rng rng(5);
    bool inside = true;
    for (int i = 0; i < 10000; i++) {
        int64_t v = rng.between(-3, 4);
        inside = inside && v >= -3 && v <= 4;
    }
    expect(inside, "between(-3, 4) stays in range");
    expect(rng.between(9, 9) == 9, "between(n, n) is n");
    expect(Rng(5).between(INT64_MIN, INT64_MAX) == (int64_t)Rng(5).next(), "the whole range of int64 is one raw draw");
}

// The product of two 64-bit numbers on a target without 128-bit integers must be the one the wide form gives.
static void test_mul() {
    Rng rng(11);
    const uint64_t edges[] = {0, 1, 2, 0xFFFFFFFFULL, 0x100000000ULL, 0x7FFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL};
    bool same = true;
    for (uint64_t a : edges)
        for (uint64_t b : edges) {
            uint64_t h1, l1, h2, l2;
            rng_mul_portable(a, b, h1, l1);
            rng_mul_wide(a, b, h2, l2);
            same = same && h1 == h2 && l1 == l2;
        }
    for (int i = 0; i < 10000; i++) {
        uint64_t a = rng.next(), b = rng.next(), h1, l1, h2, l2;
        rng_mul_portable(a, b, h1, l1);
        rng_mul_wide(a, b, h2, l2);
        same = same && h1 == h2 && l1 == l2;
    }
    expect(same, "the portable 64x64 product equals the wide one");
}

int rng_failures() {
    test_sequence();
    test_shuffle();
    test_unit();
    test_below();
    test_between();
    test_mul();
    return s_failures;
}
