// UNIT test of the rules of the readout (src/frame_rate.h): which rate the screen gives, when the program falls short
// of it, the best rate over the last seconds, and when the memory has grown a lot. Called by the main of paths_test.cpp, which sums the failures.
#include "frame_rate.h"

#include <cstdio>

static int s_failures = 0;

static void expect(bool ok, const char* what) {
    if (ok)
        return;
    std::printf("FAIL %s\n", what);
    s_failures++;
}

static void test_display_rate() {
    expect(display_rate_from_best(0.0) == 60.0, "no measure yet: 60");
    expect(display_rate_from_best(59.7) == 60.0 && display_rate_from_best(62.0) == 60.0, "a screen at 60 Hz");
    expect(display_rate_from_best(45.0) == 60.0, "a slow program on a 60 Hz screen keeps the target at 60");
    expect(display_rate_from_best(118.0) == 120.0 && display_rate_from_best(121.0) == 120.0, "a screen at 120 Hz");
    expect(display_rate_from_best(142.0) == 144.0, "a screen at 144 Hz");
    expect(display_rate_from_best(90.0) == 90.0 && display_rate_from_best(75.0) == 75.0, "90 and 75 Hz screens");
    expect(display_rate_from_best(500.0) == 500.0, "faster than any screen: the measure itself");
}

static void test_below_target() {
    expect(!fps_below_target(60.0, 60.0), "on the target");
    expect(!fps_below_target(57.0, 60.0), "exactly 5 % under is not below");
    expect(fps_below_target(56.9, 60.0), "more than 5 % under");
    expect(!fps_below_target(119.0, 120.0) && fps_below_target(100.0, 120.0), "on a 120 Hz screen");
}

static void test_watch() {
    RateWatch w;
    expect(w.best() == 0.0 && !w.warm(), "a new watch knows nothing");
    for (int i = 0; i < 90; i++)
        w.feed(1.0 / 60.0);   // 1.5 s
    expect(!w.warm() && w.best() > 59.0 && w.best() < 61.0, "a screen at 60: a whole second counted, not yet warm");
    for (int i = 0; i < 60; i++)
        w.feed(1.0 / 60.0);
    expect(w.warm(), "warm after two seconds");
    // Jitter does not raise the best: frames of 10 and 23 ms alternating still give 60 over a second.
    RateWatch j;
    for (int i = 0; i < 300; i++)
        j.feed(i % 2 ? 0.010 : 0.02333);
    expect(j.best() > 59.0 && j.best() < 61.0, "alternating short and long frames still read 60");
    expect(display_rate_from_best(j.best()) == 60.0, "and the target stays 60");
    // The program slows down to 30 for good: the best comes down once the window that remembers 60 is gone.
    for (int i = 0; i < 30; i++)
        w.feed(1.0 / 30.0);   // one second
    expect(w.best() > 59.0, "a second of slowness leaves the best where it was");
    for (int i = 0; i < 30 * 12; i++)
        w.feed(1.0 / 30.0);
    expect(w.best() > 29.0 && w.best() < 31.0, "twelve seconds later it has come down to 30");
    w.reset();
    expect(w.best() == 0.0 && !w.warm(), "a reset forgets everything");
}

// Runs `seconds` of frames at 60 a second, the memory being `bytes` all along, and reads it as the engine does.
static void run_memory(MemoryWatch& w, double seconds, double bytes) {
    for (int i = 0; i < (int)(seconds * 60.0); i++) {
        if (w.sample_due(1.0 / 60.0))
            w.sample(bytes);
    }
}

static void test_memory() {
    const double mb = 1024.0 * 1024.0;
    MemoryWatch steady;
    run_memory(steady, 1.9, 10 * mb);
    expect(steady.samples.empty() && !steady.surging(), "nothing is measured before the warm-up");
    run_memory(steady, 30.0, 10 * mb);
    expect(!steady.surging(), "a memory that stays where it is shows nothing");

    // What a program loads when it starts is not a growth: it comes before the first measure.
    MemoryWatch loading;
    run_memory(loading, 1.9, 40 * mb);
    run_memory(loading, 20.0, 40 * mb);
    expect(!loading.surging(), "a load in the first two seconds is not seen");

    // 2 % a second is 22 % in ten seconds: slow growth shows nothing.
    MemoryWatch slow;
    double bytes = 10 * mb;
    run_memory(slow, 2.5, bytes);
    for (int i = 0; i < 30; i++) {
        bytes *= 1.02;
        run_memory(slow, 1.0, bytes);
    }
    expect(!slow.surging(), "22 % in ten seconds is not a lot");

    // A jump to twice the memory is seen, and stays seen while the memory stays high, long after the window moved on.
    MemoryWatch jump;
    run_memory(jump, 5.0, 10 * mb);
    expect(!jump.surging(), "before the jump");
    run_memory(jump, 1.5, 20 * mb);
    expect(jump.surging(), "twice the memory is a lot");
    run_memory(jump, 25.0, 20 * mb);
    expect(jump.surging(), "and it is still seen 25 seconds later, the memory having stayed high");
    run_memory(jump, 3.0, 10 * mb);
    expect(!jump.surging(), "the memory falls back: it ends");
    run_memory(jump, 20.0, 10 * mb);
    expect(!jump.surging(), "and stays ended");

    // A growth by steps of 6 % a second adds up to 79 % in ten seconds: seen before the end.
    MemoryWatch leak;
    bytes = 10 * mb;
    run_memory(leak, 2.5, bytes);
    bool seen = false;
    for (int i = 0; i < 12; i++) {
        bytes *= 1.06;
        run_memory(leak, 1.0, bytes);
        seen = seen || leak.surging();
    }
    expect(seen, "a leak of 6 % a second is seen within twelve seconds");
    leak.reset();
    expect(leak.samples.empty() && !leak.surging(), "a reset forgets everything");
}

int frame_rate_failures() {
    test_display_rate();
    test_below_target();
    test_watch();
    test_memory();
    return s_failures;
}
