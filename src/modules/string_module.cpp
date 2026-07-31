#include "module_utils.h"
#include "utf8.h"
#include <climits>
#include <cmath>
#include <unordered_set>

// (int)d est un COMPORTEMENT INDÉFINI (et trappe sur WASM) si d est NaN/inf ou
// hors plage int. On borne le double AVANT le cast ; les contrôles de bornes des
// appelants transforment ensuite un index hors limites en "".
static int to_int_safe(double d) {
    if (std::isnan(d))
        return 0;
    if (d < (double)INT_MIN)
        return INT_MIN;
    if (d > (double)INT_MAX)
        return INT_MAX;
    return (int)d;
}

// Casse par codepoint : ASCII + Latin-1 Supplement (lettres latines accentuées).
// Au-delà (Latin étendu, grec, cyrillique…) : inchangé — la casse Unicode complète
// nécessiterait des tables de données disproportionnées pour ce langage.
static void append_upper(uint32_t cp, std::string& out) {
    if (cp < 0x80)
        out += (char)((cp >= 'a' && cp <= 'z') ? cp - 32 : cp);
    else if (cp == 0xDF) // ß → SS
        out += "SS";
    else if (cp >= 0xE0 && cp <= 0xFE && cp != 0xF7) // à..þ (sauf ÷) → À..Þ
        utf8_encode(cp - 0x20, out);
    else if (cp == 0xFF) // ÿ → Ÿ (U+0178)
        utf8_encode(0x178, out);
    else
        utf8_encode(cp, out);
}

static void append_lower(uint32_t cp, std::string& out) {
    if (cp < 0x80)
        out += (char)((cp >= 'A' && cp <= 'Z') ? cp + 32 : cp);
    else if (cp >= 0xC0 && cp <= 0xDE && cp != 0xD7) // À..Þ (sauf ×) → à..þ
        utf8_encode(cp + 0x20, out);
    else if (cp == 0x178) // Ÿ → ÿ
        utf8_encode(0xFF, out);
    else
        utf8_encode(cp, out);
}

static int str_upper(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    const std::string& s = str_arg(args, argc, 0, "string.upper");
    std::string out;
    for (size_t i = 0; i < s.size();) {
        size_t nb;
        append_upper(utf8_decode(s, i, &nb), out);
        i += nb;
    }
    return ctx.ret(Value(std::move(out)));
}

static int str_lower(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    const std::string& s = str_arg(args, argc, 0, "string.lower");
    std::string out;
    for (size_t i = 0; i < s.size();) {
        size_t nb;
        append_lower(utf8_decode(s, i, &nb), out);
        i += nb;
    }
    return ctx.ret(Value(std::move(out)));
}

// Rogne les codepoints présents dans `chars` (par codepoint, pas par octet) aux
// extrémités choisies (left/right).
static std::string trim_cp(const std::string& s, const std::string& chars, bool left, bool right) {
    std::unordered_set<uint32_t> set;
    for (size_t i = 0; i < chars.size();) {
        size_t nb;
        set.insert(utf8_decode(chars, i, &nb));
        i += nb;
    }
    size_t b = 0, e = s.size();
    if (left) {
        while (b < s.size()) {
            size_t nb;
            uint32_t cp = utf8_decode(s, b, &nb);
            if (!set.count(cp))
                break;
            b += nb;
        }
    }
    if (right) {
        size_t j = b, keep = b;
        while (j < s.size()) {
            size_t nb;
            uint32_t cp = utf8_decode(s, j, &nb);
            j += nb;
            if (!set.count(cp))
                keep = j; // fin (exclusive) après le dernier codepoint conservé
        }
        e = keep;
    }
    return (b >= e) ? std::string("") : s.substr(b, e - b);
}

static int str_trim(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    const std::string& s = str_arg(args, argc, 0, "string.trim");
    std::string chars = (argc >= 2) ? std::string(str_arg(args, argc, 1, "string.trim")) : " ";
    return ctx.ret(Value(trim_cp(s, chars, true, true)));
}

static int str_ltrim(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    const std::string& s = str_arg(args, argc, 0, "string.ltrim");
    std::string chars = (argc >= 2) ? std::string(str_arg(args, argc, 1, "string.ltrim")) : " ";
    return ctx.ret(Value(trim_cp(s, chars, true, false)));
}

static int str_rtrim(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    const std::string& s = str_arg(args, argc, 0, "string.rtrim");
    std::string chars = (argc >= 2) ? std::string(str_arg(args, argc, 1, "string.rtrim")) : " ";
    return ctx.ret(Value(trim_cp(s, chars, false, true)));
}

// string.char(s, i) : i-ème CARACTÈRE (codepoint UTF-8), 1-based ; renvoyé sous
// forme de string ; "" si hors limites. (Index par codepoint, pas par octet.)
static int str_char(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    const std::string& s = str_arg(args, argc, 0, "string.char");
    int i = to_int_safe(num_arg(args, argc, 1, "string.char"));
    size_t cnt = utf8_count(s);
    if (i < 1 || (size_t)i > cnt)
        return ctx.ret(Value(std::string("")));
    size_t b0 = utf8_byte_offset(s, (size_t)i - 1);
    size_t b1 = utf8_byte_offset(s, (size_t)i);
    return ctx.ret(Value(s.substr(b0, b1 - b0)));
}

// string.substr(s, start[, length]) : sous-chaîne à partir du caractère start
// (1-based), de length CARACTÈRES (jusqu'à la fin si omis) ; bornes ajustées, ""
// si hors plage. (Comptage par codepoint UTF-8, pas par octet.)
static int str_substr(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    const std::string& s = str_arg(args, argc, 0, "string.substr");
    size_t cnt = utf8_count(s);
    int start = to_int_safe(num_arg(args, argc, 1, "string.substr"));
    int len = (argc >= 3) ? to_int_safe(num_arg(args, argc, 2, "string.substr")) : (int)cnt;
    if (start < 1)
        start = 1;
    if (len <= 0 || (size_t)start > cnt)
        return ctx.ret(Value(std::string("")));
    size_t start_cp = (size_t)start - 1;
    size_t end_cp = start_cp + (size_t)len; // borné à cnt ci-dessous
    if (end_cp > cnt)
        end_cp = cnt;
    size_t b0 = utf8_byte_offset(s, start_cp);
    size_t b1 = utf8_byte_offset(s, end_cp);
    return ctx.ret(Value(s.substr(b0, b1 - b0)));
}

// string.len(s) : nombre de CARACTÈRES (codepoints UTF-8) de la chaîne. Contrairement
// au builtin global len (polymorphe : array/map/string/range), celui-ci n'accepte
// QU'une string — un autre type lève une erreur (via strArg).
static int str_len(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    const std::string& s = str_arg(args, argc, 0, "string.len");
    return ctx.ret(Value((int64_t)utf8_count(s)));
}

Value make_string_module() {
    Value m = Value::make_map();
    m.map_set(Value(std::string("len")), Value::make_builtin(str_len));
    m.map_set(Value(std::string("upper")), Value::make_builtin(str_upper));
    m.map_set(Value(std::string("lower")), Value::make_builtin(str_lower));
    m.map_set(Value(std::string("trim")), Value::make_builtin(str_trim));
    m.map_set(Value(std::string("ltrim")), Value::make_builtin(str_ltrim));
    m.map_set(Value(std::string("rtrim")), Value::make_builtin(str_rtrim));
    m.map_set(Value(std::string("char")), Value::make_builtin(str_char));
    m.map_set(Value(std::string("substr")), Value::make_builtin(str_substr));
    return m;
}