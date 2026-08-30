#define _USE_MATH_DEFINES
#include "module_utils.h"
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <ctime>
#include <limits>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// Perlin improved noise plus fBm.
// Reference permutation table (256 values), duplicated into s_perm[512].
static const unsigned char PERLIN_REF[256] = {
    151, 160, 137, 91,  90,  15,  131, 13,  201, 95,  96,  53,  194, 233, 7,   225, 140, 36,  103, 30,  69,  142,
    8,   99,  37,  240, 21,  10,  23,  190, 6,   148, 247, 120, 234, 75,  0,   26,  197, 62,  94,  252, 219, 203,
    117, 35,  11,  32,  57,  177, 33,  88,  237, 149, 56,  87,  174, 20,  125, 136, 171, 168, 68,  175, 74,  165,
    71,  134, 139, 48,  27,  166, 77,  146, 158, 231, 83,  111, 229, 122, 60,  211, 133, 230, 220, 105, 92,  41,
    55,  46,  245, 40,  244, 102, 143, 54,  65,  25,  63,  161, 1,   216, 80,  73,  209, 76,  132, 187, 208, 89,
    18,  169, 200, 196, 135, 130, 116, 188, 159, 86,  164, 100, 109, 198, 173, 186, 3,   64,  52,  217, 226, 250,
    124, 123, 5,   202, 38,  147, 118, 126, 255, 82,  85,  212, 207, 206, 59,  227, 47,  16,  58,  17,  182, 189,
    28,  42,  223, 183, 170, 213, 119, 248, 152, 2,   44,  154, 163, 70,  221, 153, 101, 155, 167, 43,  172, 9,
    129, 22,  39,  253, 19,  98,  108, 110, 79,  113, 224, 232, 178, 185, 112, 104, 218, 246, 97,  228, 251, 34,
    242, 193, 238, 210, 144, 12,  191, 179, 162, 241, 81,  51,  145, 235, 249, 14,  239, 107, 49,  192, 214, 31,
    181, 199, 106, 157, 184, 84,  204, 176, 115, 121, 50,  45,  127, 4,   150, 254, 138, 236, 205, 93,  222, 114,
    67,  29,  24,  72,  243, 141, 128, 195, 78,  66,  215, 61,  156, 180};

static int s_perm[512];

static void noise_init_default() {
    for (int i = 0; i < 256; i++) {
        s_perm[i] = PERLIN_REF[i];
        s_perm[256 + i] = PERLIN_REF[i];
    }
}

// Reshuffles the table with a local deterministic PRNG (xorshift64), independent of rand() and
// math.seed, so noise and randomness do not influence each other.
static void noise_reseed(uint64_t seed) {
    int p[256];
    for (int i = 0; i < 256; i++)
        p[i] = i;
    uint64_t s = seed ? seed : 0x9E3779B97F4A7C15ULL;
    for (int i = 255; i > 0; i--) {
        s ^= s << 13;
        s ^= s >> 7;
        s ^= s << 17;
        int j = (int)(s % (uint64_t)(i + 1));
        int tmp = p[i];
        p[i] = p[j];
        p[j] = tmp;
    }
    for (int i = 0; i < 256; i++) {
        s_perm[i] = p[i];
        s_perm[256 + i] = p[i];
    }
}

static inline double noise_fade(double t) {
    return t * t * t * (t * (t * 6 - 15) + 10);
}

static inline double noise_lerp(double t, double a, double b) {
    return a + t * (b - a);
}

static inline double noise_grad(int hash, double x, double y, double z) {
    int h = hash & 15;
    double u = h < 8 ? x : y;
    double v = h < 4 ? y : (h == 12 || h == 14 ? x : z);
    return ((h & 1) == 0 ? u : -u) + ((h & 2) == 0 ? v : -v);
}

static double perlin3(double x, double y, double z) {
    int X = (int)std::floor(x) & 255;
    int Y = (int)std::floor(y) & 255;
    int Z = (int)std::floor(z) & 255;
    x -= std::floor(x);
    y -= std::floor(y);
    z -= std::floor(z);
    double u = noise_fade(x);
    double v = noise_fade(y);
    double w = noise_fade(z);
    int A = s_perm[X] + Y, AA = s_perm[A] + Z, AB = s_perm[A + 1] + Z;
    int B = s_perm[X + 1] + Y, BA = s_perm[B] + Z, BB = s_perm[B + 1] + Z;
    return noise_lerp(
        w,
        noise_lerp(v, noise_lerp(u, noise_grad(s_perm[AA], x, y, z), noise_grad(s_perm[BA], x - 1, y, z)),
                  noise_lerp(u, noise_grad(s_perm[AB], x, y - 1, z), noise_grad(s_perm[BB], x - 1, y - 1, z))),
        noise_lerp(v, noise_lerp(u, noise_grad(s_perm[AA + 1], x, y, z - 1), noise_grad(s_perm[BA + 1], x - 1, y, z - 1)),
                  noise_lerp(u, noise_grad(s_perm[AB + 1], x, y - 1, z - 1),
                            noise_grad(s_perm[BB + 1], x - 1, y - 1, z - 1))));
}

static const int NOISE_OCTAVES = 4;
static const double NOISE_FALLOFF = 0.5;
// PRACTICAL amplitude of the fBm average above (the measured max |average|). It depends on
// OCTAVES, FALLOFF and the dimension, and dividing by it makes the output span [0,1]. Re-measure
// if OCTAVES or FALLOFF change; the downstream [0,1] clamp remains the guard should the real
// amplitude overshoot slightly.
static const double NOISE_AMP_1D = 0.37;
static const double NOISE_AMP_2D = 0.55;
static const double NOISE_AMP_3D = 0.62;

#define MATH1(name, expr)                                                                                              \
    static int math_##name(CallCtx& ctx) {                                                                             \
        Value* args = ctx.args;                                                                                        \
        int argc = ctx.argc;                                                                                           \
        double x = num_arg(args, argc, 0, "math." #name);                                                               \
        return ctx.ret(num_value(expr));                                                                                \
    }

MATH1(abs, std::fabs(x))
MATH1(sign, x > 0.0 ? 1.0 : x < 0.0 ? -1.0 : 0.0)
MATH1(floor, std::floor(x))
MATH1(ceil, std::ceil(x))
MATH1(round, std::round(x))
MATH1(trunc, std::trunc(x))
MATH1(sqrt, std::sqrt(x))
MATH1(exp, std::exp(x))
MATH1(log, std::log(x))
MATH1(log2, std::log2(x))
MATH1(log10, std::log10(x))
MATH1(sin, std::sin(x))
MATH1(cos, std::cos(x))
MATH1(tan, std::tan(x))
MATH1(asin, std::asin(x))
MATH1(acos, std::acos(x))
MATH1(atan, std::atan(x))
MATH1(deg, x * (180.0 / M_PI))
MATH1(rad, x*(M_PI / 180.0))
MATH1(frac, x - std::floor(x))
// These two answer yes or no rather than with a number, hence a separate macro so they return a
// boolean without going through num_value.
#define MATH1_BOOL(name, expr)                                                                                         \
    static int math_##name(CallCtx& ctx) {                                                                             \
        Value* args = ctx.args;                                                                                        \
        int argc = ctx.argc;                                                                                           \
        double x = num_arg(args, argc, 0, "math." #name);                                                              \
        return ctx.ret(Value::make_bool(expr));                                                                        \
    }

MATH1_BOOL(is_nan, std::isnan(x))
MATH1_BOOL(is_inf, std::isinf(x))

static int math_map(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    double x = num_arg(args, argc, 0, "math.map");
    double in_lo = num_arg(args, argc, 1, "math.map");
    double in_hi = num_arg(args, argc, 2, "math.map");
    double out_lo = num_arg(args, argc, 3, "math.map");
    double out_hi = num_arg(args, argc, 4, "math.map");
    if (in_hi == in_lo)
        return ctx.ret(num_value(out_lo)); // a degenerate input range gives the low bound, which avoids inf and nan
    return ctx.ret(num_value(out_lo + (x - in_lo) * (out_hi - out_lo) / (in_hi - in_lo)));
}

static int math_atan2(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    double y = num_arg(args, argc, 0, "math.atan2");
    double x = num_arg(args, argc, 1, "math.atan2");
    return ctx.ret(num_value(std::atan2(y, x)));
}

static int math_pow(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    double x = num_arg(args, argc, 0, "math.pow");
    double n = num_arg(args, argc, 1, "math.pow");
    return ctx.ret(num_value(std::pow(x, n)));
}

static int math_clamp(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    double x = num_arg(args, argc, 0, "math.clamp");
    double lo = num_arg(args, argc, 1, "math.clamp");
    double hi = num_arg(args, argc, 2, "math.clamp");
    return ctx.ret(num_value(x < lo ? lo : x > hi ? hi : x));
}

static int math_seed(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    int64_t s = (int64_t)num_arg(args, argc, 0, "math.seed");
    srand((unsigned)s);
    return ctx.ret(Value());
}

static int math_logn(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    double x = num_arg(args, argc, 0, "math.logn");
    double n = num_arg(args, argc, 1, "math.logn");
    return ctx.ret(num_value(std::log(x) / std::log(n)));
}

static int math_min(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    if (argc == 0)
        throw std::runtime_error("math.min: at least one argument required");
    bool all_int = true;
    for (int i = 0; i < argc; i++)
        if (!args[i].is_integer()) {
            all_int = false;
            break;
        }
    if (all_int) {
        int64_t result = args[0].as_int();
        for (int i = 1; i < argc; i++) {
            int64_t v = args[i].as_int();
            if (v < result)
                result = v;
        }
        return ctx.ret(Value(result));
    }
    double result = num_arg(args, argc, 0, "math.min");
    for (int i = 1; i < argc; i++) {
        double v = num_arg(args, argc, i, "math.min");
        if (v < result)
            result = v;
    }
    return ctx.ret(Value(result));
}

static int math_max(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    if (argc == 0)
        throw std::runtime_error("math.max: at least one argument required");
    bool all_int = true;
    for (int i = 0; i < argc; i++)
        if (!args[i].is_integer()) {
            all_int = false;
            break;
        }
    if (all_int) {
        int64_t result = args[0].as_int();
        for (int i = 1; i < argc; i++) {
            int64_t v = args[i].as_int();
            if (v > result)
                result = v;
        }
        return ctx.ret(Value(result));
    }
    double result = num_arg(args, argc, 0, "math.max");
    for (int i = 1; i < argc; i++) {
        double v = num_arg(args, argc, i, "math.max");
        if (v > result)
            result = v;
    }
    return ctx.ret(Value(result));
}

static int math_rand(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    double r = (double)rand() / ((double)RAND_MAX + 1.0);
    if (argc == 0)
        return ctx.ret(Value(r));
    if (argc == 1)
        return ctx.ret(Value(r * num_arg(args, argc, 0, "math.rand")));
    double lo = num_arg(args, argc, 0, "math.rand");
    double hi = num_arg(args, argc, 1, "math.rand");
    return ctx.ret(Value(lo + r * (hi - lo)));
}

// Integer argument: (int64_t)num_arg is UB — and traps on WASM — when the double is NaN, infinite
// or out of int64 range. double_fits_int64 (value.h) guards the cast and yields a clear error.
static int64_t int_arg(const Value* args, int argc, int i, const char* fn) {
    double d = num_arg(args, argc, i, fn);
    if (!double_fits_int64(d))
        throw std::runtime_error(std::string(fn) + ": integer argument out of range");
    return (int64_t)d;
}

static int math_rand_int(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    if (argc == 0)
        throw std::runtime_error("math.randInt: at least one argument required");
    if (argc == 1) {
        int64_t hi = int_arg(args, argc, 0, "math.randInt");
        if (hi <= 0)
            throw std::runtime_error("math.randInt: argument must be > 0");
        return ctx.ret(Value((int64_t)(rand() % hi + 1)));
    }
    int64_t lo = int_arg(args, argc, 0, "math.randInt");
    int64_t hi = int_arg(args, argc, 1, "math.randInt");
    if (lo > hi)
        throw std::runtime_error("math.randInt: lo must be <= hi");
    return ctx.ret(Value(lo + (int64_t)(rand() % (hi - lo + 1))));
}

// Fractal Perlin noise (fBm) in 1, 2 or 3 dimensions, returning a FLOAT in [0, 1].
static int math_noise(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    if (argc < 1 || argc > 3)
        throw std::runtime_error("math.noise: expects 1, 2 or 3 arguments");
    double x = num_arg(args, argc, 0, "math.noise");
    double y = argc >= 2 ? num_arg(args, argc, 1, "math.noise") : 0.0;
    double z = argc >= 3 ? num_arg(args, argc, 2, "math.noise") : 0.0;
    double total = 0.0, amp = 0.5, freq = 1.0, max_amp = 0.0;
    for (int o = 0; o < NOISE_OCTAVES; o++) {
        total += perlin3(x * freq, y * freq, z * freq) * amp;
        max_amp += amp;
        freq *= 2.0;
        amp *= NOISE_FALLOFF;
    }
    // Improved Perlin noise does NOT span ±1, so we normalize by the practical amplitude for the
    // dimension (see NOISE_AMP_*) and clamp, which then covers [0,1].
    double amp01 = argc >= 3 ? NOISE_AMP_3D : (argc == 2 ? NOISE_AMP_2D : NOISE_AMP_1D);
    double n = (total / max_amp / amp01 + 1.0) * 0.5;
    if (n < 0.0)
        n = 0.0;
    if (n > 1.0)
        n = 1.0;
    return ctx.ret(Value(n));
}

// Reshuffles the permutation table, giving reproducible or varying noise.
static int math_noise_seed(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    int64_t s = (int64_t)num_arg(args, argc, 0, "math.noiseSeed");
    noise_reseed((uint64_t)s);
    return ctx.ret(Value());
}

Value make_math_module() {
    srand((unsigned)time(nullptr));
    noise_init_default();
    return MapBuilder()
        // constants
        .num("PI", M_PI)
        .num("TAU", 2.0 * M_PI)
        .num("E", 2.718281828459045235360)
        .num("INF", std::numeric_limits<double>::infinity())
        // arithmetic
        .fn("abs", math_abs)
        .fn("sign", math_sign)
        .fn("floor", math_floor)
        .fn("ceil", math_ceil)
        .fn("round", math_round)
        .fn("trunc", math_trunc)
        .fn("sqrt", math_sqrt)
        .fn("pow", math_pow)
        .fn("clamp", math_clamp)
        .fn("min", math_min)
        .fn("max", math_max)
        // logarithms and the exponential
        .fn("exp", math_exp)
        .fn("log", math_log)
        .fn("log2", math_log2)
        .fn("log10", math_log10)
        .fn("logn", math_logn)
        // trigonometry
        .fn("sin", math_sin)
        .fn("cos", math_cos)
        .fn("tan", math_tan)
        .fn("asin", math_asin)
        .fn("acos", math_acos)
        .fn("atan", math_atan)
        .fn("atan2", math_atan2)
        .fn("deg", math_deg)
        .fn("rad", math_rad)
        .fn("frac", math_frac)
        .fn("isNan", math_is_nan)
        .fn("isInf", math_is_inf)
        .fn("map", math_map)
        // randomness
        .fn("rand", math_rand)
        .fn("randInt", math_rand_int)
        .fn("seed", math_seed)
        // Perlin noise
        .fn("noise", math_noise)
        .fn("noiseSeed", math_noise_seed)
        .done();
}
