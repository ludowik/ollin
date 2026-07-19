#include "module_utils.h"
#include "utf8.h"
#include <climits>
#include <cmath>
#include <unordered_set>

// (int)d est un COMPORTEMENT INDÉFINI (et trappe sur WASM) si d est NaN/inf ou
// hors plage int. On borne le double AVANT le cast ; les contrôles de bornes des
// appelants transforment ensuite un index hors limites en "".
static int toIntSafe(double d) {
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
static void appendUpper(uint32_t cp, std::string& out) {
    if (cp < 0x80)
        out += (char)((cp >= 'a' && cp <= 'z') ? cp - 32 : cp);
    else if (cp == 0xDF) // ß → SS
        out += "SS";
    else if (cp >= 0xE0 && cp <= 0xFE && cp != 0xF7) // à..þ (sauf ÷) → À..Þ
        utf8Encode(cp - 0x20, out);
    else if (cp == 0xFF) // ÿ → Ÿ (U+0178)
        utf8Encode(0x178, out);
    else
        utf8Encode(cp, out);
}

static void appendLower(uint32_t cp, std::string& out) {
    if (cp < 0x80)
        out += (char)((cp >= 'A' && cp <= 'Z') ? cp + 32 : cp);
    else if (cp >= 0xC0 && cp <= 0xDE && cp != 0xD7) // À..Þ (sauf ×) → à..þ
        utf8Encode(cp + 0x20, out);
    else if (cp == 0x178) // Ÿ → ÿ
        utf8Encode(0xFF, out);
    else
        utf8Encode(cp, out);
}

static Value str_upper(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    const std::string& s = strArg(args, argc, 0, "string.upper");
    std::string out;
    for (size_t i = 0; i < s.size();) {
        size_t nb;
        appendUpper(utf8Decode(s, i, &nb), out);
        i += nb;
    }
    return Value(std::move(out));
}

static Value str_lower(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    const std::string& s = strArg(args, argc, 0, "string.lower");
    std::string out;
    for (size_t i = 0; i < s.size();) {
        size_t nb;
        appendLower(utf8Decode(s, i, &nb), out);
        i += nb;
    }
    return Value(std::move(out));
}

// Rogne les codepoints présents dans `chars` (par codepoint, pas par octet) aux
// extrémités choisies (left/right).
static std::string trimCp(const std::string& s, const std::string& chars, bool left, bool right) {
    std::unordered_set<uint32_t> set;
    for (size_t i = 0; i < chars.size();) {
        size_t nb;
        set.insert(utf8Decode(chars, i, &nb));
        i += nb;
    }
    size_t b = 0, e = s.size();
    if (left) {
        while (b < s.size()) {
            size_t nb;
            uint32_t cp = utf8Decode(s, b, &nb);
            if (!set.count(cp))
                break;
            b += nb;
        }
    }
    if (right) {
        size_t j = b, keep = b;
        while (j < s.size()) {
            size_t nb;
            uint32_t cp = utf8Decode(s, j, &nb);
            j += nb;
            if (!set.count(cp))
                keep = j; // fin (exclusive) après le dernier codepoint conservé
        }
        e = keep;
    }
    return (b >= e) ? std::string("") : s.substr(b, e - b);
}

static Value str_trim(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    const std::string& s = strArg(args, argc, 0, "string.trim");
    std::string chars = (argc >= 2) ? std::string(strArg(args, argc, 1, "string.trim")) : " ";
    return Value(trimCp(s, chars, true, true));
}

static Value str_ltrim(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    const std::string& s = strArg(args, argc, 0, "string.ltrim");
    std::string chars = (argc >= 2) ? std::string(strArg(args, argc, 1, "string.ltrim")) : " ";
    return Value(trimCp(s, chars, true, false));
}

static Value str_rtrim(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    const std::string& s = strArg(args, argc, 0, "string.rtrim");
    std::string chars = (argc >= 2) ? std::string(strArg(args, argc, 1, "string.rtrim")) : " ";
    return Value(trimCp(s, chars, false, true));
}

// string.char(s, i) : i-ème CARACTÈRE (codepoint UTF-8), 1-based ; renvoyé sous
// forme de string ; "" si hors limites. (Index par codepoint, pas par octet.)
static Value str_char(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    const std::string& s = strArg(args, argc, 0, "string.char");
    int i = toIntSafe(numArg(args, argc, 1, "string.char"));
    size_t cnt = utf8Count(s);
    if (i < 1 || (size_t)i > cnt)
        return Value(std::string(""));
    size_t b0 = utf8ByteOffset(s, (size_t)i - 1);
    size_t b1 = utf8ByteOffset(s, (size_t)i);
    return Value(s.substr(b0, b1 - b0));
}

// string.substr(s, start[, length]) : sous-chaîne à partir du caractère start
// (1-based), de length CARACTÈRES (jusqu'à la fin si omis) ; bornes ajustées, ""
// si hors plage. (Comptage par codepoint UTF-8, pas par octet.)
static Value str_substr(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    const std::string& s = strArg(args, argc, 0, "string.substr");
    size_t cnt = utf8Count(s);
    int start = toIntSafe(numArg(args, argc, 1, "string.substr"));
    int len = (argc >= 3) ? toIntSafe(numArg(args, argc, 2, "string.substr")) : (int)cnt;
    if (start < 1)
        start = 1;
    if (len <= 0 || (size_t)start > cnt)
        return Value(std::string(""));
    size_t startCp = (size_t)start - 1;
    size_t endCp = startCp + (size_t)len; // borné à cnt ci-dessous
    if (endCp > cnt)
        endCp = cnt;
    size_t b0 = utf8ByteOffset(s, startCp);
    size_t b1 = utf8ByteOffset(s, endCp);
    return Value(s.substr(b0, b1 - b0));
}

// string.len(s) : nombre de CARACTÈRES (codepoints UTF-8) de la chaîne. Contrairement
// au builtin global len (polymorphe : array/map/string/range), celui-ci n'accepte
// QU'une string — un autre type lève une erreur (via strArg).
static Value str_len(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    const std::string& s = strArg(args, argc, 0, "string.len");
    return Value((int64_t)utf8Count(s));
}

Value makeStringModule() {
    Value m = Value::makeMap();
    m.mapSet(Value(std::string("len")), Value::makeBuiltin(str_len));
    m.mapSet(Value(std::string("upper")), Value::makeBuiltin(str_upper));
    m.mapSet(Value(std::string("lower")), Value::makeBuiltin(str_lower));
    m.mapSet(Value(std::string("trim")), Value::makeBuiltin(str_trim));
    m.mapSet(Value(std::string("ltrim")), Value::makeBuiltin(str_ltrim));
    m.mapSet(Value(std::string("rtrim")), Value::makeBuiltin(str_rtrim));
    m.mapSet(Value(std::string("char")), Value::makeBuiltin(str_char));
    m.mapSet(Value(std::string("substr")), Value::makeBuiltin(str_substr));
    return m;
}