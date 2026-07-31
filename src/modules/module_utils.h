#pragma once
#include "value.h"
#include <stdexcept>

// Précondition : l'appelant DOIT avoir garanti i < argc (aucun contrôle de borne
// ici — forme rapide utilisée après une garde argc). Pour un contrôle de borne
// intégré, utiliser la surcharge (args, argc, i, fn) ci-dessous.
static inline double num_arg(const Value* args, int i, const char* fn) {
    const Value& v = args[i];
    if (v.is_integer())
        return (double)v.as_int();
    if (v.is_float())
        return v.as_float();
    throw std::runtime_error(std::string(fn) + ": argument " + std::to_string(i + 1) + " expected number, got " +
                             v.type_name());
}

static inline double num_arg(const Value* args, int argc, int i, const char* fn) {
    if (i >= argc)
        throw std::runtime_error(std::string(fn) + ": missing argument");
    return num_arg(args, i, fn);
}

static inline const std::string& str_arg(const Value* args, int argc, int i, const char* fn) {
    if (i >= argc)
        throw std::runtime_error(std::string(fn) + ": missing argument");
    if (!args[i].is_string())
        throw std::runtime_error(std::string(fn) + ": expected string");
    return args[i].as_string();
}

// Composantes couleur normalisées [0,1].
struct ColorRGBA {
    double r, g, b, a;
};

static inline double color_clamp01(double v) {
    return v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);
}

// Interprète des arguments couleur « flexibles » en composantes [0,1] — signature
// partagée par le constructeur Color et par graphics.clear/fill/stroke :
//   objet Color (instance) → ses champs r,g,b,a
//   1 nombre  n            → (n,n,n,1)   gris
//   2 nombres n,a          → (n,n,n,a)   gris + alpha
//   3 nombres r,g,b        → (r,g,b,1)
//   4 nombres r,g,b,a      → (r,g,b,a)
// Précondition : argc >= 1. Lève une erreur si la forme est invalide.
static inline ColorRGBA parse_color(const Value* args, int argc, const char* fn) {
    if (args[0].is_map() || args[0].is_class()) {
        auto field = [&](const char* k, double def) -> double {
            Value f = args[0].map_get(Value(std::string(k)));
            return f.is_number() ? color_clamp01(f.as_num()) : def;
        };
        return {field("r", 0.0), field("g", 0.0), field("b", 0.0), field("a", 1.0)};
    }
    if (!args[0].is_number())
        throw std::runtime_error(std::string(fn) + ": expected a number or a Color");
    double n0 = color_clamp01(args[0].as_num());
    if (argc == 1)
        return {n0, n0, n0, 1.0};                                  // gris
    for (int i = 1; i < argc && i < 4; i++) {
        if (!args[i].is_number())
            throw std::runtime_error(std::string(fn) + ": expected numbers");
    }
    if (argc == 2)
        return {n0, n0, n0, color_clamp01(args[1].as_num())};        // gris + alpha
    double g = color_clamp01(args[1].as_num());
    double b = color_clamp01(args[2].as_num());
    double a = argc >= 4 ? color_clamp01(args[3].as_num()) : 1.0;
    return {n0, g, b, a};                                          // r,g,b[,a]
}
