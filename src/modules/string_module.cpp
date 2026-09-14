#include "module_utils.h"
#include "../lexer.h"
#include "../number_literal.h"
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

// string.find(s, needle [, from]): a LITERAL search — no patterns, no regular expressions.
//
// Returns TWO values, the index where the needle STARTS and the index just PAST it, both counted
// in codepoints from 1 like every other index of this module. The pair is what makes it compose
// with substr, and the reason the end is returned rather than left to the caller: adding the
// needle's length by hand is right in bytes and wrong in characters, so the one caller who forgets
// that breaks only on accented text.
//
//     var a, b = s.find(m)
//     var replaced = s.substr(1, a - 1) + other + s.substr(b)
//
// Absent: nil, a single value, so `var a, b = ...` leaves both nil and `if s.find(m) then` reads
// as it should — indices being 1-based, a match never yields 0, which is falsy in this language.
//
// Bytes are compared, not codepoints, which is exact here: a candidate is only ever tried at a
// codepoint boundary, and UTF-8 is self-synchronising, so no match can start inside a character.
static int str_find(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    const std::string& s = str_arg(args, argc, 0, "string.find");
    const std::string& needle = str_arg(args, argc, 1, "string.find");
    int from = (argc >= 3) ? to_int_safe(num_arg(args, argc, 2, "string.find")) : 1;
    if (from < 1)
        from = 1;
    size_t cnt = utf8_count(s);
    // An empty needle matches WHERE IT IS LOOKED FOR, and reports no width: (from, from) is the
    // insertion point, so the substr pair above splices `other` in without deleting anything.
    if (needle.empty()) {
        int at = ((size_t)from > cnt + 1) ? (int)cnt + 1 : from;
        ctx.set_result(0, Value((int64_t)at));
        ctx.set_result(1, Value((int64_t)at));
        return 2;
    }
    if ((size_t)from > cnt || needle.size() > s.size())
        return ctx.ret(Value{});
    size_t i = utf8_byte_offset(s, (size_t)from - 1);
    size_t cp = (size_t)from - 1;
    size_t last = s.size() - needle.size();
    while (i <= last) {
        if (s.compare(i, needle.size(), needle) == 0) {
            ctx.set_result(0, Value((int64_t)(cp + 1)));
            ctx.set_result(1, Value((int64_t)(cp + 1 + utf8_count(needle))));
            return 2;
        }
        i += utf8_step(s, i);
        cp++;
    }
    return ctx.ret(Value{});
}

// string.split(s, sep [, max]): splits on a LITERAL separator — no patterns, no regular
// expressions, like find.
//
// ALWAYS returns an array, so a text without the separator gives one element and the caller loops
// without a special case. Empty pieces are KEPT, which is what makes splitting and rejoining give
// the text back: "a,,b" is three pieces and "a," is two. Dropping them would lose an empty column
// of a data file in silence, and whoever does not want them filters them out.
//
// `max` bounds the number of pieces and the LAST one keeps the whole remainder — that is what
// reads a "key=value=with=equals" line in two. Below 1 it is clamped to 1, as find clamps `from`.
//
// An EMPTY separator is refused rather than answered with a guess: splitting "on nothing" has no
// obvious result, and the real need behind it — the characters one by one — belongs to a function
// that says so.
//
// Bytes are compared here, not codepoints: nothing is returned as an index, and UTF-8 is
// self-synchronising, so a byte match always begins on a character boundary.
static int str_split(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    const std::string& s = str_arg(args, argc, 0, "string.split");
    const std::string& sep = str_arg(args, argc, 1, "string.split");
    if (sep.empty())
        throw std::runtime_error("string.split: the separator must not be empty");
    int max_pieces = 0; // 0 = unbounded
    if (argc >= 3) {
        max_pieces = to_int_safe(num_arg(args, argc, 2, "string.split"));
        if (max_pieces < 1)
            max_pieces = 1;
    }
    Value out = Value::make_array();
    size_t start = 0;
    int done = 0;
    while (max_pieces == 0 || done + 1 < max_pieces) {
        size_t hit = s.find(sep, start);
        if (hit == std::string::npos)
            break;
        out.array_push(Value(s.substr(start, hit - start)));
        start = hit + sep.size();
        ++done;
    }
    out.array_push(Value(s.substr(start))); // the remainder, empty when the text ends on a separator
    return ctx.ret(out);
}

// string.number(s): the number a text is worth, or nil.
//
// It owns NEITHER of the two rules it needs. The LEXER reads the text — so every form the
// language itself accepts is accepted here, decimal, exponent, 0x, 0o, 0b and the '_' separator,
// and no second definition of "what a number looks like" can drift from it. number_from_lexeme
// then says what the token is worth, the same reading the parser gives a literal of the source.
// This function only checks the SHAPE of the token list and applies the sign.
//
// The sign is not part of a literal: the lexer always emits '-' as its own token, so the accepted
// shape is [+ | -] NUMBER END. Anything else is nil — "1 2" (two numbers), "42abc", "", a text the
// lexer refuses, or a value that does not fit. All or nothing: reading a prefix would let a typo
// pass for data.
//
// Whitespace around the text costs nothing to allow, the lexer skipping it already, and the
// pieces of a split(", ") carry some.
static int str_number(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    const std::string& s = str_arg(args, argc, 0, "string.number");
    std::vector<Token> toks;
    try {
        toks = Lexer(s).tokenize();
    } catch (...) { // the lexer refuses the text: not a number, not an error of the script
        return ctx.ret(Value{});
    }
    size_t i = 0;
    bool negative = false;
    if (i < toks.size() && (toks[i].type == TokenType::PLUS || toks[i].type == TokenType::MINUS)) {
        negative = toks[i].type == TokenType::MINUS;
        i++;
    }
    if (i >= toks.size() || toks[i].type != TokenType::NUMBER)
        return ctx.ret(Value{});
    const std::string& lex = toks[i].lexeme;
    if (i + 1 >= toks.size() || toks[i + 1].type != TokenType::EOF_T)
        return ctx.ret(Value{});
    NumLit n;
    if (!number_from_lexeme(lex, n))
        return ctx.ret(Value{});
    if (n.is_int)
        return ctx.ret(Value(negative ? -n.i : n.i));
    return ctx.ret(Value(negative ? -n.d : n.d));
}

// string.replace(s, needle, by [, max]): a LITERAL replacement — no patterns, like find and
// split. Returns TWO values, the text obtained and HOW MANY times it bit, so "did anything
// change" needs no second pass; whoever wants only the text writes `var s2 = ...` and the count
// is ignored without a thought.
//
// The search resumes AFTER the inserted text, never inside it: `s.replace("a", "aa")` would
// otherwise keep replacing what it had just written, forever.
//
// `max` at or below zero gives the text back unchanged with a count of 0, and is NOT clamped to 1
// the way split clamps it. The difference has a reason: zero pieces means nothing, while zero
// replacements is a perfectly clear request.
//
// An empty needle is refused, as in split — "insert between every character" would be a guess,
// and the module must answer both questions the same way. An empty `by` is allowed and deletes.
//
// Bytes are compared, exact here as in split: nothing is returned as an index, and UTF-8 is
// self-synchronising, so a byte match always begins on a character boundary.
static int str_replace(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    const std::string& s = str_arg(args, argc, 0, "string.replace");
    const std::string& needle = str_arg(args, argc, 1, "string.replace");
    const std::string& by = str_arg(args, argc, 2, "string.replace");
    if (needle.empty())
        throw std::runtime_error("string.replace: the needle must not be empty");
    int max_hits = -1; // -1 = unbounded
    if (argc >= 4) {
        max_hits = to_int_safe(num_arg(args, argc, 3, "string.replace"));
        if (max_hits < 0)
            max_hits = 0;
    }
    std::string out;
    size_t start = 0;
    int64_t hits = 0;
    while (max_hits < 0 || hits < max_hits) {
        size_t at = s.find(needle, start);
        if (at == std::string::npos)
            break;
        out.append(s, start, at - start);
        out += by;
        start = at + needle.size();
        ++hits;
    }
    out.append(s, start, std::string::npos);
    ctx.set_result(0, Value(out));
    ctx.set_result(1, Value(hits));
    return 2;
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
        .fn("find", str_find)
        .fn("split", str_split)
        .fn("number", str_number)
        .fn("replace", str_replace)
        .done();
}
