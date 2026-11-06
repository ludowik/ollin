#pragma once
// The frame-rate readout of the engine (graphics.stats) shows the rate only when the program falls short of what the
// screen can give. Both rules live here, with no window and no clock, so that a unit test can run them.

// The refresh rates of the screens there are. The display rate is a standard one: a rate measured at 118 on a 120 Hz screen
// is 120, so that the target does not follow a program that is a little slow.
inline double display_rate_from_best(double best_fps) {
    static const double k_rates[] = {60.0, 75.0, 90.0, 100.0, 120.0, 144.0, 165.0, 240.0};
    if (best_fps <= 0.0)
        return 60.0;
    for (double r : k_rates) {
        if (r >= best_fps * 0.95)
            return r;
    }
    return best_fps;   // faster than any screen known: the measure itself
}

// Whether the rate is more than 5 % under the target.
inline bool fps_below_target(double fps, double target) {
    return fps < target * 0.95;
}

// The best rate the program held over the last seconds, which tells the refresh rate of the screen: a loop that waits for
// the screen (requestAnimationFrame) never runs faster than it, and a slow one still has its best seconds to show what
// the screen gives. The rate is that of a whole second (frames counted over time), not of one frame: a frame that comes
// early after a late one would read as a rate far above the screen's. Two windows of `k_window` seconds are kept, so
// that the best comes back down some time after a program has changed for good, and a readout does not decide before
// `k_warm_up` seconds: a program loading its resources is slow without being a slow program.
struct RateWatch {
    static constexpr double k_chunk = 1.0;
    static constexpr double k_window = 5.0;
    static constexpr double k_warm_up = 2.0;
    double current = 0.0;
    double previous = 0.0;
    double window_time = 0.0;
    double total_time = 0.0;
    double chunk_time = 0.0;
    int chunk_frames = 0;

    void reset() {
        *this = RateWatch{};
    }
    // `dt` is the duration of this frame, in seconds.
    void feed(double dt) {
        total_time += dt;
        window_time += dt;
        chunk_time += dt;
        chunk_frames++;
        if (chunk_time >= k_chunk) {
            double rate = chunk_frames / chunk_time;
            if (rate > current)
                current = rate;
            chunk_time = 0.0;
            chunk_frames = 0;
        }
        if (window_time >= k_window) {
            previous = current;
            current = 0.0;
            window_time = 0.0;
        }
    }
    double best() const {
        return current > previous ? current : previous;
    }
    bool warm() const {
        return total_time >= k_warm_up;
    }
};
