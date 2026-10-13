#pragma once
#include <cmath>
#include <stdexcept>
#include <string>

// The easing curves of the `tween` module: pure functions of a progress in [0;1], with no Value and no
// VM, so nothing here depends on the module's state.

namespace easing {

// They all take and return a progress normalized to [0;1]. The exposed names live in string
// literals, hence camelCase like the rest of the Ollin API.

inline double ease_linear(double t) {
    return t;
}

inline double ease_in_quad(double t) {
    return t * t;
}

inline double ease_out_quad(double t) {
    return t * (2.0 - t);
}

inline double ease_in_out_quad(double t) {
    return t < 0.5 ? 2.0 * t * t : 1.0 - 2.0 * (1.0 - t) * (1.0 - t);
}

inline double ease_in_cubic(double t) {
    return t * t * t;
}

inline double ease_out_cubic(double t) {
    double u = 1.0 - t;
    return 1.0 - u * u * u;
}

inline double ease_in_out_cubic(double t) {
    if (t < 0.5)
        return 4.0 * t * t * t;
    double u = 1.0 - t;
    return 1.0 - 4.0 * u * u * u;
}

inline double ease_in_sine(double t) {
    return 1.0 - std::cos(t * 1.5707963267948966);
}

inline double ease_out_sine(double t) {
    return std::sin(t * 1.5707963267948966);
}

inline double ease_in_out_sine(double t) {
    return 0.5 * (1.0 - std::cos(t * 3.141592653589793));
}

inline double ease_in_expo(double t) {
    return t <= 0.0 ? 0.0 : std::pow(2.0, 10.0 * t - 10.0);
}

inline double ease_out_expo(double t) {
    return t >= 1.0 ? 1.0 : 1.0 - std::pow(2.0, -10.0 * t);
}

inline double ease_in_out_expo(double t) {
    if (t <= 0.0)
        return 0.0;
    if (t >= 1.0)
        return 1.0;
    if (t < 0.5)
        return 0.5 * std::pow(2.0, 20.0 * t - 10.0);
    return 1.0 - 0.5 * std::pow(2.0, 10.0 - 20.0 * t);
}

// The overshoot of `back` comes from the 1.70158 constant of Penner's model.
inline double ease_in_back(double t) {
    return t * t * (2.70158 * t - 1.70158);
}

inline double ease_out_back(double t) {
    double u = t - 1.0;
    return 1.0 + u * u * (2.70158 * u + 1.70158);
}

inline double ease_in_out_back(double t) {
    const double c = 1.70158 * 1.525;
    if (t < 0.5)
        return 0.5 * (4.0 * t * t * ((c + 1.0) * 2.0 * t - c));
    double u = 2.0 * t - 2.0;
    return 0.5 * (u * u * ((c + 1.0) * u + c) + 2.0);
}

inline double ease_out_elastic(double t) {
    if (t <= 0.0)
        return 0.0;
    if (t >= 1.0)
        return 1.0;
    return std::pow(2.0, -10.0 * t) * std::sin((10.0 * t - 0.75) * 2.0943951023931953) + 1.0;
}

inline double ease_out_bounce(double t) {
    const double n = 7.5625;
    const double d = 2.75;
    if (t < 1.0 / d)
        return n * t * t;
    if (t < 2.0 / d) {
        double u = t - 1.5 / d;
        return n * u * u + 0.75;
    }
    if (t < 2.5 / d) {
        double u = t - 2.25 / d;
        return n * u * u + 0.9375;
    }
    double u = t - 2.625 / d;
    return n * u * u + 0.984375;
}

struct CurveEntry {
    const char* name;
    double (*fn)(double);
};

inline constexpr CurveEntry k_curves[] = {
    {"linear", ease_linear},
    {"easeInQuad", ease_in_quad},
    {"easeOutQuad", ease_out_quad},
    {"easeInOutQuad", ease_in_out_quad},
    {"easeInCubic", ease_in_cubic},
    {"easeOutCubic", ease_out_cubic},
    {"easeInOutCubic", ease_in_out_cubic},
    {"easeInSine", ease_in_sine},
    {"easeOutSine", ease_out_sine},
    {"easeInOutSine", ease_in_out_sine},
    {"easeInExpo", ease_in_expo},
    {"easeOutExpo", ease_out_expo},
    {"easeInOutExpo", ease_in_out_expo},
    {"easeInBack", ease_in_back},
    {"easeOutBack", ease_out_back},
    {"easeInOutBack", ease_in_out_back},
    {"easeOutElastic", ease_out_elastic},
    {"easeOutBounce", ease_out_bounce},
};

inline constexpr int k_curve_default = 3;   // easeInOutQuad

inline std::string curve_names() {
    std::string s;
    for (const auto& c : k_curves) {
        if (!s.empty())
            s += ", ";
        s += c.name;
    }
    return s;
}

inline int curve_index(const std::string& name, const char* fn) {
    for (int i = 0; i < (int)(sizeof(k_curves) / sizeof(k_curves[0])); i++) {
        if (name == k_curves[i].name)
            return i;
    }
    throw std::runtime_error(std::string(fn) + ": unknown curve '" + name + "' — available: " + curve_names());
}

}   // namespace easing
