#include "module_utils.h"
#include "utf8.h"
#include <climits>
#include <cmath>
#include <unordered_set>

// (int)d is UNDEFINED BEHAVIOUR — and traps on WASM — when d is NaN, infinite, or out of int
// range. The double is clamped BEFORE the cast, and the callers' bound checks then turn an
// out-of-range index into "".
static int to_int_safe(double d) {
    if (std::isnan(d))
        return 0;
    if (d < (double)INT_MIN)
        return INT_MIN;
    if (d > (double)INT_MAX)
        return INT_MAX;
    return (int)d;
}

// Case mapping per codepoint, covering ASCII and Latin-1 Supplement (accented Latin letters).
// Beyond that — Latin Extended, Greek, Cyrillic — codepoints are left unchanged: full Unicode
// casing would need data tables out of proportion with this language.
static void append_upper(uint32_t cp, std::string& out) {
    if (cp < 0x80)
        out += (char)((cp >= 'a' && cp <= 'z') ? cp - 32 : cp);
    else if (cp == 0xDF) // ß → SS
        out += "SS";
    else if (cp >= 0xE0 && cp <= 0xFE && cp != 0xF7) // à..þ, excluding ÷, maps to À..Þ
        utf8_encode(cp - 0x20, out);
    else if (cp == 0xFF) // ÿ → Ÿ (U+0178)
        utf8_encode(0x178, out);
    else
        utf8_encode(cp, out);
}

static void append_lower(uint32_t cp, std::string& out) {
    if (cp < 0x80)
        out += (char)((cp >= 'A' && cp <= 'Z') ? cp + 32 : cp);
    else if (cp >= 0xC0 && cp <= 0xDE && cp != 0xD7) // À..Þ, excluding ×, maps to à..þ
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

// Trims the codepoints listed in `chars` — by codepoint, not by byte — from the chosen ends.
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
                keep = j; // the exclusive end, past the last codepoint kept
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

// string.char(s, i): the i-th CHARACTER (UTF-8 codepoint), 1-based, returned as a string, or ""
// when out of range. The index counts codepoints, not bytes.
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

// string.substr(s, start[, length]): the substring from character `start` (1-based) spanning
// `length` CHARACTERS, to the end when omitted. Bounds are clamped, and "" is returned when out
// of range. Counting is by UTF-8 codepoint, not by byte.
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
    size_t end_cp = start_cp + (size_t)len; // clamped to cnt below
    if (end_cp > cnt)
        end_cp = cnt;
    size_t b0 = utf8_byte_offset(s, start_cp);
    size_t b1 = utf8_byte_offset(s, end_cp);
    return ctx.ret(Value(s.substr(b0, b1 - b0)));
}

// string.len(s): the number of CHARACTERS (UTF-8 codepoints). Unlike the global len builtin,
// which is polymorphic over arrays, maps, strings and ranges, this one accepts ONLY a string and
// throws on any other type, through str_arg.
static int str_len(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    const std::string& s = str_arg(args, argc, 0, "string.len");
    return ctx.ret(Value((int64_t)utf8_count(s)));
}

Value make_string_module() {
    return MapBuilder()
        .fn("len", str_len)
        .fn("upper", str_upper)
        .fn("lower", str_lower)
        .fn("trim", str_trim)
        .fn("ltrim", str_ltrim)
        .fn("rtrim", str_rtrim)
        .fn("char", str_char)
        .fn("substr", str_substr)
        .done();
}
