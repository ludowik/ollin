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

// ── Bruit de Perlin (improved noise, Ken Perlin) + fBm ──────────────────────
// Table de permutation de référence (256 valeurs), dupliquée en s_perm[512].
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

static void noiseInitDefault() {
    for (int i = 0; i < 256; i++) {
        s_perm[i] = PERLIN_REF[i];
        s_perm[256 + i] = PERLIN_REF[i];
    }
}

// Rebat la table via un PRNG déterministe local (xorshift64), indépendant de
// rand()/math.seed → le bruit et l'aléatoire ne s'influencent pas.
static void noiseReseed(uint64_t seed) {
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

static inline double noiseFade(double t) {
    return t * t * t * (t * (t * 6 - 15) + 10);
}

static inline double noiseLerp(double t, double a, double b) {
    return a + t * (b - a);
}

static inline double noiseGrad(int hash, double x, double y, double z) {
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
    double u = noiseFade(x);
    double v = noiseFade(y);
    double w = noiseFade(z);
    int A = s_perm[X] + Y, AA = s_perm[A] + Z, AB = s_perm[A + 1] + Z;
    int B = s_perm[X + 1] + Y, BA = s_perm[B] + Z, BB = s_perm[B + 1] + Z;
    return noiseLerp(
        w,
        noiseLerp(v, noiseLerp(u, noiseGrad(s_perm[AA], x, y, z), noiseGrad(s_perm[BA], x - 1, y, z)),
                  noiseLerp(u, noiseGrad(s_perm[AB], x, y - 1, z), noiseGrad(s_perm[BB], x - 1, y - 1, z))),
        noiseLerp(v, noiseLerp(u, noiseGrad(s_perm[AA + 1], x, y, z - 1), noiseGrad(s_perm[BA + 1], x - 1, y, z - 1)),
                  noiseLerp(u, noiseGrad(s_perm[AB + 1], x, y - 1, z - 1),
                            noiseGrad(s_perm[BB + 1], x - 1, y - 1, z - 1))));
}

static const int NOISE_OCTAVES = 4;
static const double NOISE_FALLOFF = 0.5;

#define MATH1(name, expr)                                                                                              \
    static Value math_##name(Value* args, int argc) {                                                                  \
        double x = numArg(args, argc, 0, "math." #name);                                                               \
        return numValue(expr);                                                                                         \
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
MATH1(is_nan, std::isnan(x) ? 1.0 : 0.0)
MATH1(is_inf, std::isinf(x) ? 1.0 : 0.0)

static Value math_map(Value* args, int argc) {
    double x = numArg(args, argc, 0, "math.map");
    double in_lo = numArg(args, argc, 1, "math.map");
    double in_hi = numArg(args, argc, 2, "math.map");
    double out_lo = numArg(args, argc, 3, "math.map");
    double out_hi = numArg(args, argc, 4, "math.map");
    return Value(out_lo + (x - in_lo) * (out_hi - out_lo) / (in_hi - in_lo));
}

static Value math_atan2(Value* args, int argc) {
    double y = numArg(args, argc, 0, "math.atan2");
    double x = numArg(args, argc, 1, "math.atan2");
    return Value(std::atan2(y, x));
}

static Value math_pow(Value* args, int argc) {
    double x = numArg(args, argc, 0, "math.pow");
    double n = numArg(args, argc, 1, "math.pow");
    return Value(std::pow(x, n));
}

static Value math_clamp(Value* args, int argc) {
    double x = numArg(args, argc, 0, "math.clamp");
    double lo = numArg(args, argc, 1, "math.clamp");
    double hi = numArg(args, argc, 2, "math.clamp");
    return Value(x < lo ? lo : x > hi ? hi : x);
}

static Value math_seed(Value* args, int argc) {
    int64_t s = (int64_t)numArg(args, argc, 0, "math.seed");
    srand((unsigned)s);
    return Value();
}

static Value math_logn(Value* args, int argc) {
    double x = numArg(args, argc, 0, "math.logn");
    double n = numArg(args, argc, 1, "math.logn");
    return Value(std::log(x) / std::log(n));
}

static Value math_min(Value* args, int argc) {
    if (argc == 0)
        throw std::runtime_error("math.min: at least one argument required");
    bool all_int = true;
    for (int i = 0; i < argc; i++)
        if (!args[i].isInteger()) {
            all_int = false;
            break;
        }
    if (all_int) {
        int64_t result = args[0].asInt();
        for (int i = 1; i < argc; i++) {
            int64_t v = args[i].asInt();
            if (v < result)
                result = v;
        }
        return Value(result);
    }
    double result = numArg(args, argc, 0, "math.min");
    for (int i = 1; i < argc; i++) {
        double v = numArg(args, argc, i, "math.min");
        if (v < result)
            result = v;
    }
    return Value(result);
}

static Value math_max(Value* args, int argc) {
    if (argc == 0)
        throw std::runtime_error("math.max: at least one argument required");
    bool all_int = true;
    for (int i = 0; i < argc; i++)
        if (!args[i].isInteger()) {
            all_int = false;
            break;
        }
    if (all_int) {
        int64_t result = args[0].asInt();
        for (int i = 1; i < argc; i++) {
            int64_t v = args[i].asInt();
            if (v > result)
                result = v;
        }
        return Value(result);
    }
    double result = numArg(args, argc, 0, "math.max");
    for (int i = 1; i < argc; i++) {
        double v = numArg(args, argc, i, "math.max");
        if (v > result)
            result = v;
    }
    return Value(result);
}

static Value math_rand(Value* args, int argc) {
    double r = (double)rand() / ((double)RAND_MAX + 1.0);
    if (argc == 0)
        return Value(r);
    if (argc == 1)
        return Value(r * numArg(args, argc, 0, "math.rand"));
    double lo = numArg(args, argc, 0, "math.rand");
    double hi = numArg(args, argc, 1, "math.rand");
    return Value(lo + r * (hi - lo));
}

static Value math_rand_int(Value* args, int argc) {
    if (argc == 0)
        throw std::runtime_error("math.rand_int: at least one argument required");
    if (argc == 1) {
        int64_t hi = (int64_t)numArg(args, argc, 0, "math.rand_int");
        if (hi <= 0)
            throw std::runtime_error("math.rand_int: argument must be > 0");
        return Value((int64_t)(rand() % hi + 1));
    }
    int64_t lo = (int64_t)numArg(args, argc, 0, "math.rand_int");
    int64_t hi = (int64_t)numArg(args, argc, 1, "math.rand_int");
    if (lo > hi)
        throw std::runtime_error("math.rand_int: lo must be <= hi");
    return Value(lo + (int64_t)(rand() % (hi - lo + 1)));
}

// Bruit de Perlin fractal (fBm), 1/2/3 dimensions → FLOAT dans [0, 1].
static Value math_noise(Value* args, int argc) {
    if (argc < 1 || argc > 3)
        throw std::runtime_error("math.noise: expects 1, 2 or 3 arguments");
    double x = numArg(args, argc, 0, "math.noise");
    double y = argc >= 2 ? numArg(args, argc, 1, "math.noise") : 0.0;
    double z = argc >= 3 ? numArg(args, argc, 2, "math.noise") : 0.0;
    double total = 0.0, amp = 0.5, freq = 1.0, maxAmp = 0.0;
    for (int o = 0; o < NOISE_OCTAVES; o++) {
        total += perlin3(x * freq, y * freq, z * freq) * amp;
        maxAmp += amp;
        freq *= 2.0;
        amp *= NOISE_FALLOFF;
    }
    double n = (total / maxAmp + 1.0) * 0.5;
    if (n < 0.0)
        n = 0.0;
    if (n > 1.0)
        n = 1.0;
    return Value(n);
}

// Rebat la table de permutation → bruit reproductible / variable.
static Value math_noise_seed(Value* args, int argc) {
    int64_t s = (int64_t)numArg(args, argc, 0, "math.noise_seed");
    noiseReseed((uint64_t)s);
    return Value();
}

Value makeMathModule() {
    srand((unsigned)time(nullptr));
    noiseInitDefault();
    Value m = Value::makeMap();
    // constantes
    m.mapSet(Value(std::string("PI")), Value(M_PI));
    m.mapSet(Value(std::string("TAU")), Value(2.0 * M_PI));
    m.mapSet(Value(std::string("E")), Value(2.718281828459045235360));
    m.mapSet(Value(std::string("INF")), Value(std::numeric_limits<double>::infinity()));
    // arithmétique
    m.mapSet(Value(std::string("abs")), Value::makeBuiltin(math_abs));
    m.mapSet(Value(std::string("sign")), Value::makeBuiltin(math_sign));
    m.mapSet(Value(std::string("floor")), Value::makeBuiltin(math_floor));
    m.mapSet(Value(std::string("ceil")), Value::makeBuiltin(math_ceil));
    m.mapSet(Value(std::string("round")), Value::makeBuiltin(math_round));
    m.mapSet(Value(std::string("trunc")), Value::makeBuiltin(math_trunc));
    m.mapSet(Value(std::string("sqrt")), Value::makeBuiltin(math_sqrt));
    m.mapSet(Value(std::string("pow")), Value::makeBuiltin(math_pow));
    m.mapSet(Value(std::string("clamp")), Value::makeBuiltin(math_clamp));
    m.mapSet(Value(std::string("min")), Value::makeBuiltin(math_min));
    m.mapSet(Value(std::string("max")), Value::makeBuiltin(math_max));
    // logarithmes / exponentielle
    m.mapSet(Value(std::string("exp")), Value::makeBuiltin(math_exp));
    m.mapSet(Value(std::string("log")), Value::makeBuiltin(math_log));
    m.mapSet(Value(std::string("log2")), Value::makeBuiltin(math_log2));
    m.mapSet(Value(std::string("log10")), Value::makeBuiltin(math_log10));
    m.mapSet(Value(std::string("logn")), Value::makeBuiltin(math_logn));
    // trigonométrie
    m.mapSet(Value(std::string("sin")), Value::makeBuiltin(math_sin));
    m.mapSet(Value(std::string("cos")), Value::makeBuiltin(math_cos));
    m.mapSet(Value(std::string("tan")), Value::makeBuiltin(math_tan));
    m.mapSet(Value(std::string("asin")), Value::makeBuiltin(math_asin));
    m.mapSet(Value(std::string("acos")), Value::makeBuiltin(math_acos));
    m.mapSet(Value(std::string("atan")), Value::makeBuiltin(math_atan));
    m.mapSet(Value(std::string("atan2")), Value::makeBuiltin(math_atan2));
    m.mapSet(Value(std::string("deg")), Value::makeBuiltin(math_deg));
    m.mapSet(Value(std::string("rad")), Value::makeBuiltin(math_rad));
    m.mapSet(Value(std::string("frac")), Value::makeBuiltin(math_frac));
    m.mapSet(Value(std::string("is_nan")), Value::makeBuiltin(math_is_nan));
    m.mapSet(Value(std::string("is_inf")), Value::makeBuiltin(math_is_inf));
    m.mapSet(Value(std::string("map")), Value::makeBuiltin(math_map));
    // aléatoire
    m.mapSet(Value(std::string("rand")), Value::makeBuiltin(math_rand));
    m.mapSet(Value(std::string("rand_int")), Value::makeBuiltin(math_rand_int));
    m.mapSet(Value(std::string("seed")), Value::makeBuiltin(math_seed));
    // bruit de Perlin
    m.mapSet(Value(std::string("noise")), Value::makeBuiltin(math_noise));
    m.mapSet(Value(std::string("noise_seed")), Value::makeBuiltin(math_noise_seed));
    return m;
}
