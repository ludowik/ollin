// The counter and the check shared by the unit tests: each test file includes it, so each has its own copy of the
// counter (internal linkage), which its xxx_failures() hands to the main of paths_test.cpp to sum.
#pragma once
#include <cstdio>

static int s_failures = 0;

static void expect(bool ok, const char* what) {
    if (ok)
        return;
    std::printf("FAIL %s\n", what);
    s_failures++;
}
