#include "vm.h"
#include <iostream>
#include <vector>
#include <cstdio>
#include <cstring>
#include <stdexcept>

Value make_color_class();

// Formatting core, shared by interpolation ({expr:spec}) AND printf ({N:spec}). `spec` is a C
// conversion specification WITHOUT the '%', such as ".3f", "04x" or ">8s". We read the trailing
// conversion character to coerce the value to the right C type, since a type mismatch with
// snprintf is undefined behaviour. The flags, width and precision — the "body" — pass through
// verbatim but are validated against a strict allowlist, so neither a conversion nor a '%' can be
// injected. An empty spec means the default representation.
std::string format_one(const Value& v, const std::string& spec) {
    if (spec.empty())
        return value_to_string(v);
    char conv = spec.back();
    std::string body = spec.substr(0, spec.size() - 1);   // flags + largeur + précision
    for (char c : body)
        if (!std::strchr("-+ #0123456789.", c))
            throw std::runtime_error("format: invalid character in spec '" + spec + "'");
    auto render = [](const std::string& cfmt, auto arg) {
        int need = std::snprintf(nullptr, 0, cfmt.c_str(), arg);
        if (need < 0)
            throw std::runtime_error("format: invalid spec");
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
            throw std::runtime_error("format: unknown conversion '" + spec + "'");
    }
}

// printf does positional substitution. Each {N} or {} slot may carry a format, {N:spec} or
// {:spec}, applied through format_one — the same engine as interpolation.
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
                        throw std::runtime_error("printf: invalid index '{" + content + "}'");
                    }
                    if (idx < 1)
                        throw std::runtime_error("printf: index is 1-based, must be >= 1 (got " + idx_part + ")");
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

// __fmt(value, spec) is an INTERNAL builtin — the __ prefix keeps it out of the public API — and
// the target of the {expr:spec} interpolation desugaring. Not meant to be called directly.
static int core_fmt(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    if (argc < 2 || !args[1].is_string())
        throw std::runtime_error("__fmt: expected (value, spec)");
    std::vector<Value> vargs(args, args + argc);   // copie : formatOne peut réallouer regs (__str)
    return ctx.ret(Value(format_one(vargs[0], vargs[1].as_string())));
}

static int core_print(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    // Copy BEFORE any conversion: value_to_string may invoke __str, which runs bytecode and can
    // reallocate regs, leaving `args` — a pointer into regs — dangling for the remaining
    // arguments. Same precaution as in core_printf.
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
