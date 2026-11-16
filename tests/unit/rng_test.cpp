// UNIT test of the generator (src/rng.h): the published splitmix64 sequence, which is what makes a seed give the same
// numbers on every platform, and the bounds and the fairness of the draws. Called by the main of paths_test.cpp, which sums the failures.
#include "rng.h"

#include <cstdio>

static int s_failures = 0;

static void expect(bool ok, const char* what) {
    if (ok)
        return;
    std::printf("FAIL %s\n", what);
    s_failures++;
}

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
    int counts[3] = {0, 0, 0};
    bool inside = true;
    for (int i = 0; i < 30000; i++) {
        uint64_t v = rng.below(3);
        inside = inside && v < 3;
        if (v < 3)
            counts[v]++;
    }
    expect(inside, "below(3) stays in [0, 3)");
    expect(counts[0] > 9500 && counts[0] < 10500 && counts[1] > 9500 && counts[1] < 10500 && counts[2] > 9500 &&
               counts[2] < 10500,
           "below(3) is fair");
    expect(rng.below(1) == 0, "below(1) is 0");
    Rng pinned(1);
    expect(pinned.below(1000) == 566 && pinned.below(1000) == 745 && pinned.below(1000) == 971,
           "below(1000) from seed 1: fixed values, the same on every platform");
    // A bound above 2^63 throws away about half of the draws: the rejection loop must still end inside the range.
    Rng wide_bound(3);
    uint64_t bound = (1ULL << 63) + 12345;
    bool rejected_inside = true;
    for (int i = 0; i < 1000; i++)
        rejected_inside = rejected_inside && wide_bound.below(bound) < bound;
    expect(rejected_inside, "below(2^63 + k) stays in range through the rejection path");
    bool wide = false;
    for (int i = 0; i < 100; i++)
        wide = wide || rng.below(1000000) > 32767;
    expect(wide, "a wide range is reached beyond 32767, which rand() on Windows never was");
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
    int64_t lo = INT64_MIN;
    int64_t hi = INT64_MAX;
    rng.between(lo, hi);
    int64_t edge = rng.between(hi - 1, hi);
    expect(edge == hi - 1 || edge == hi, "the whole range of int64 does not overflow");
}

int rng_failures() {
    test_sequence();
    test_unit();
    test_below();
    test_between();
    return s_failures;
}
