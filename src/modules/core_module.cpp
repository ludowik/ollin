#include "vm.h"
#include <iostream>
#include <vector>
#include <cstdio>
#include <cstring>
#include <stdexcept>

Value make_color_class();

// Cœur de formatage partagé par l'interpolation ({expr:spec}) ET printf ({N:spec}).
// `spec` = spécification de conversion C SANS le '%' (ex. ".3f", "04x", ">8s"). On
// lit le caractère de conversion final pour coercer la valeur au bon type C — un
// mismatch de type avec snprintf serait un comportement indéfini. Les flags/largeur/
// précision (le « corps ») passent verbatim mais sont validés (allowlist stricte) →
// aucune injection de conversion ni de '%'. Spec vide → représentation par défaut.
std::string format_one(const Value& v, const std::string& spec) {
    if (spec.empty())
        return value_to_string(v);
    char conv = spec.back();
    std::string body = spec.substr(0, spec.size() - 1);   // flags + largeur + précision
    for (char c : body)
        if (!std::strchr("-+ #0123456789.", c))
            throw std::runtime_error("format: caractère invalide dans la spec '" + spec + "'");
    auto render = [](const std::string& cfmt, auto arg) {
        int need = std::snprintf(nullptr, 0, cfmt.c_str(), arg);
        if (need < 0)
            throw std::runtime_error("format: spec invalide");
        std::string out((size_t)need, '\0');
        std::snprintf(out.data(), (size_t)need + 1, cfmt.c_str(), arg);
        return out;
    };
    switch (conv) {
        case 'c': {
            if (!v.is_number())
                throw std::runtime_error("format: '%" + spec + "' attend un nombre");
            return render("%" + body + "c", (int)v.as_num());
        }
        case 'd': case 'i': case 'o': case 'u': case 'x': case 'X': {
            if (!v.is_number())
                throw std::runtime_error("format: '%" + spec + "' attend un nombre");
            return render("%" + body + "ll" + conv, (long long)v.as_num());   // 'll' = int64
        }
        case 'e': case 'E': case 'f': case 'F': case 'g': case 'G': case 'a': case 'A': {
            if (!v.is_number())
                throw std::runtime_error("format: '%" + spec + "' attend un nombre");
            return render("%" + spec, (double)v.as_num());
        }
        case 's': {
            std::string s = value_to_string(v);
            return render("%" + spec, s.c_str());
        }
        default:
            throw std::runtime_error("format: conversion inconnue '" + spec + "'");
    }
}

// printf : substitution positionnelle. Chaque emplacement {N} / {} peut porter un
// format {N:spec} / {:spec}, appliqué via formatOne (même moteur que l'interpolation).
static std::string apply_format(const std::string& fmt, const std::vector<Value>& args, int offset) {
    std::string out;
    int auto_idx = 1;   // indexation 1-based (cohérent avec les arrays Ollin) : {1} = 1er argument
    for (size_t i = 0; i < fmt.size(); ++i) {
        if (fmt[i] == '{') {
            size_t j = fmt.find('}', i + 1);
            if (j != std::string::npos) {
                std::string content = fmt.substr(i + 1, j - i - 1);
                std::string idx_part = content, spec;
                size_t colon = content.find(':');
                if (colon != std::string::npos) {
                    idx_part = content.substr(0, colon);
                    spec = content.substr(colon + 1);
                }
                int idx;
                if (idx_part.empty()) {
                    idx = auto_idx++;
                } else {
                    try {
                        idx = std::stoi(idx_part);
                    } catch (...) {
                        throw std::runtime_error("printf: index invalide '{" + content + "}'");
                    }
                    if (idx < 1)
                        throw std::runtime_error("printf: index 1-based, doit être >= 1 (reçu " + idx_part + ")");
                }
                long long ai = (long long)idx - 1 + offset;   // {1} → 1er arg réel (args[offset])
                if (ai >= 0 && ai < (long long)args.size())
                    out += format_one(args[(int)ai], spec);
                i = j;
                continue;
            }
        }
        out += fmt[i];
    }
    return out;
}

// __fmt(valeur, spec) : builtin INTERNE (préfixe __ → hors API publique), cible du
// désucrage de l'interpolation {expr:spec}. Non destiné à un appel direct.
static int core_fmt(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    if (argc < 2 || !args[1].is_string())
        throw std::runtime_error("__fmt: (valeur, spec) attendu");
    std::vector<Value> vargs(args, args + argc);   // copie : formatOne peut réallouer regs (__str)
    return ctx.ret(Value(format_one(vargs[0], vargs[1].as_string())));
}

static int core_print(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    // Copie AVANT toute conversion : valueToString peut invoquer __str, qui exécute
    // du bytecode et peut réallouer regs → `args` (pointeur dans regs) deviendrait
    // pendant pour les arguments suivants. Même précaution que core_printf.
    std::vector<Value> vargs(args, args + argc);
    for (int i = 0; i < argc; ++i) {
        if (i)
            std::cout << ' ';
        std::cout << value_to_string(vargs[i]);
    }
    std::cout << '\n';
    return ctx.ret(Value{});
}

static int core_printf(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    if (argc < 1 || !args[0].is_string())
        throw std::runtime_error("printf: first arg must be string");
    std::vector<Value> vargs(args, args + argc);
    std::cout << apply_format(args[0].as_string(), vargs, 1) << '\n';
    return ctx.ret(Value{});
}

static int core_typeof(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    if (argc < 1)
        return ctx.ret(Value(std::string("nil")));
    return ctx.ret(Value(std::string(args[0].type_name())));
}

Value make_core_module() {
    Value m = Value::make_map();
    m.map_set(Value(std::string("print")), Value::make_builtin(core_print));
    m.map_set(Value(std::string("printf")), Value::make_builtin(core_printf));
    m.map_set(Value(std::string("__fmt")), Value::make_builtin(core_fmt));   // interne : désucrage {expr:spec}
    m.map_set(Value(std::string("typeof")), Value::make_builtin(core_typeof));
    m.map_set(Value(std::string("Color")), make_color_class());
    return m;
}
