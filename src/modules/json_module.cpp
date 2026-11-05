#include "module_utils.h"
#include "modules.h"
#include "utf8.h"
#include "value.h"
#include "vm.h"
#include <algorithm>
#include <cerrno>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <stdexcept>
#include <string>
#include <vector>

// The `json` module: json.parse(text) builds the values of the language from a JSON text, and
// json.stringify(value [, indent]) writes them back.
//
//   object -> map, array -> array, string -> string, true/false -> bool, null -> nil,
//   a number without fraction or exponent -> int (a double when it does not fit in 64 bits), any other -> float
//   (a text whose value is too large for a double, 1e999, is refused: the language has no value for it).
//
// A nil inside an array is written as null and read back as nil. A nil value in a map is not stored
// at all (a map has no nil), so a key read as null is simply absent.

namespace {

constexpr int k_max_depth = 200;   // deeper than any real document, shallower than the C++ stack

struct Parser {
    const std::string& s;
    size_t i = 0;
    const char* who = "json.parse";   // names the caller in the errors: data.get reads values with this parser too

    [[noreturn]] void fail(const std::string& what) const {
        throw std::runtime_error(std::string(who) + ": " + what + " at position " + std::to_string(i + 1));
    }

    void skip_space() {
        while (i < s.size() && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r'))
            i++;
    }

    bool take(const char* word) {
        size_t n = std::char_traits<char>::length(word);
        if (s.compare(i, n, word) != 0)
            return false;
        i += n;
        return true;
    }

    unsigned hex4() {
        if (i + 4 > s.size())
            fail("truncated \\u escape");
        unsigned v = 0;
        for (int k = 0; k < 4; k++) {
            char c = s[i++];
            v <<= 4;
            if (c >= '0' && c <= '9')
                v |= (unsigned)(c - '0');
            else if (c >= 'a' && c <= 'f')
                v |= (unsigned)(c - 'a' + 10);
            else if (c >= 'A' && c <= 'F')
                v |= (unsigned)(c - 'A' + 10);
            else {
                i--;
                fail("bad \\u escape");
            }
        }
        return v;
    }

    std::string string_body() {
        // s[i] is the opening quote.
        i++;
        std::string out;
        while (true) {
            if (i >= s.size())
                fail("unterminated string");
            unsigned char c = (unsigned char)s[i++];
            if (c == '"')
                return out;
            if (c < 0x20) {
                i--;
                fail("control character in string");
            }
            if (c != '\\') {
                out += (char)c;
                continue;
            }
            if (i >= s.size())
                fail("unterminated string");
            char e = s[i++];
            switch (e) {
            case '"': out += '"'; break;
            case '\\': out += '\\'; break;
            case '/': out += '/'; break;
            case 'b': out += '\b'; break;
            case 'f': out += '\f'; break;
            case 'n': out += '\n'; break;
            case 'r': out += '\r'; break;
            case 't': out += '\t'; break;
            case 'u': {
                unsigned cp = hex4();
                if (cp >= 0xD800 && cp <= 0xDBFF) {
                    // A high surrogate must be followed by a low one: together they are one code point.
                    if (!(i + 1 < s.size() && s[i] == '\\' && s[i + 1] == 'u'))
                        fail("lone surrogate");
                    i += 2;
                    unsigned lo = hex4();
                    if (lo < 0xDC00 || lo > 0xDFFF)
                        fail("lone surrogate");
                    cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                } else if (cp >= 0xDC00 && cp <= 0xDFFF) {
                    fail("lone surrogate");
                }
                utf8_encode(cp, out);
                break;
            }
            default:
                i--;
                fail("bad escape");
            }
        }
    }

    Value number() {
        size_t start = i;
        if (s[i] == '-')
            i++;
        if (i >= s.size() || !(s[i] >= '0' && s[i] <= '9'))
            fail("bad number");
        if (s[i] == '0') {
            i++;
        } else {
            while (i < s.size() && s[i] >= '0' && s[i] <= '9')
                i++;
        }
        bool integral = true;
        if (i < s.size() && s[i] == '.') {
            integral = false;
            i++;
            if (i >= s.size() || !(s[i] >= '0' && s[i] <= '9'))
                fail("bad number");
            while (i < s.size() && s[i] >= '0' && s[i] <= '9')
                i++;
        }
        if (i < s.size() && (s[i] == 'e' || s[i] == 'E')) {
            integral = false;
            i++;
            if (i < s.size() && (s[i] == '+' || s[i] == '-'))
                i++;
            if (i >= s.size() || !(s[i] >= '0' && s[i] <= '9'))
                fail("bad number");
            while (i < s.size() && s[i] >= '0' && s[i] <= '9')
                i++;
        }
        std::string text = s.substr(start, i - start);
        if (integral) {
            errno = 0;
            char* end = nullptr;
            long long v = std::strtoll(text.c_str(), &end, 10);
            if (errno == 0)
                return Value((int64_t)v);
        }
        double d = std::strtod(text.c_str(), nullptr);
        if (!std::isfinite(d))
            fail("number out of range");   // 1e999: the language has no value for it
        return Value(d);
    }

    Value value(int depth) {
        if (depth > k_max_depth)
            fail("nested too deeply");
        skip_space();
        if (i >= s.size())
            fail("unexpected end of text");
        char c = s[i];
        if (c == '{') {
            i++;
            Value m = Value::make_map();
            skip_space();
            if (i < s.size() && s[i] == '}') {
                i++;
                return m;
            }
            while (true) {
                skip_space();
                if (i >= s.size() || s[i] != '"')
                    fail("expected a string key");
                std::string key = string_body();
                skip_space();
                if (i >= s.size() || s[i] != ':')
                    fail("expected ':'");
                i++;
                Value v = value(depth + 1);
                m.map_set(Value(key), v);   // a nil removes the key: the LAST of two equal keys wins, null included
                skip_space();
                if (i < s.size() && s[i] == ',') {
                    i++;
                    continue;
                }
                if (i < s.size() && s[i] == '}') {
                    i++;
                    return m;
                }
                fail("expected ',' or '}'");
            }
        }
        if (c == '[') {
            i++;
            Value a = Value::make_array();
            skip_space();
            if (i < s.size() && s[i] == ']') {
                i++;
                return a;
            }
            while (true) {
                a.array_push(value(depth + 1));
                skip_space();
                if (i < s.size() && s[i] == ',') {
                    i++;
                    continue;
                }
                if (i < s.size() && s[i] == ']') {
                    i++;
                    return a;
                }
                fail("expected ',' or ']'");
            }
        }
        if (c == '"')
            return Value(string_body());
        if (c == '-' || (c >= '0' && c <= '9'))
            return number();
        if (take("true"))
            return Value::make_bool(true);
        if (take("false"))
            return Value::make_bool(false);
        if (take("null"))
            return Value{};
        fail(std::string("unexpected character '") + c + "'");
    }
};

Value decode_text(const std::string& text, const char* who) {
    Parser p{text, 0, who};
    Value v = p.value(0);
    p.skip_space();
    if (p.i < text.size())
        p.fail("unexpected text after the value");
    return v;
}

int json_parse(CallCtx& ctx) {
    return ctx.ret(decode_text(str_arg(ctx.args, ctx.argc, 0, "json.parse"), "json.parse"));
}

// ── stringify ────────────────────────────────────────────────────────────────────────────────────

void escape(const std::string& s, std::string& out) {
    out += '"';
    for (unsigned char c : s) {
        switch (c) {
        case '"': out += "\\\""; break;
        case '\\': out += "\\\\"; break;
        case '\b': out += "\\b"; break;
        case '\f': out += "\\f"; break;
        case '\n': out += "\\n"; break;
        case '\r': out += "\\r"; break;
        case '\t': out += "\\t"; break;
        default:
            if (c < 0x20) {
                char buf[8];
                std::snprintf(buf, sizeof buf, "\\u%04x", c);
                out += buf;
            } else {
                out += (char)c;
            }
        }
    }
    out += '"';
}

// The shortest text that reads back as the same double, so that 0.1 stays 0.1 and not 0.1000000000000000055.
std::string number_text(double d, const char* who) {
    if (!std::isfinite(d))
        throw std::runtime_error(std::string(who) + ": a number that is not finite has no JSON form");
    char buf[40];
    for (int digits = 15; digits <= 17; digits++) {
        std::snprintf(buf, sizeof buf, "%.*g", digits, d);
        if (std::strtod(buf, nullptr) == d)
            break;
    }
    std::string text = buf;
    if (text.find_first_of(".eE") == std::string::npos)
        text += ".0";   // a float stays a float when it is read back
    return text;
}

struct Writer {
    std::string out;
    int indent;   // spaces per level, 0 = compact
    const char* who = "json.stringify";   // names the caller in the errors, as for the Parser

    void newline(int depth) {
        if (indent == 0)
            return;
        out += '\n';
        out.append((size_t)(depth * indent), ' ');
    }

    void write(const Value& v, int depth) {
        if (depth > k_max_depth)
            throw std::runtime_error(std::string(who) + ": nested too deeply (or the value contains itself)");
        if (v.is_nil()) {
            out += "null";
        } else if (v.is_bool()) {
            out += v.as_bool() ? "true" : "false";
        } else if (v.is_integer()) {
            out += std::to_string(v.as_int());
        } else if (v.is_float()) {
            out += number_text(v.as_float(), who);
        } else if (v.is_string()) {
            escape(v.as_string(), out);
        } else if (v.is_array()) {
            int64_t n = v.array_size();
            if (n == 0) {
                out += "[]";
                return;
            }
            out += '[';
            for (int64_t k = 1; k <= n; k++) {
                if (k > 1)
                    out += ',';
                newline(depth + 1);
                write(v.array_get(k), depth + 1);
            }
            newline(depth);
            out += ']';
        } else if (v.tag == Value::T_MAP) {
            // The keys are sorted: a map has no order, and the same value must give the same text.
            auto fields = sorted_string_entries(v, std::string(who) + ": a map key", true);
            if (fields.empty()) {
                out += "{}";
                return;
            }
            out += '{';
            bool first = true;
            for (auto& f : fields) {
                if (!first)
                    out += ',';
                first = false;
                newline(depth + 1);
                escape(f.first, out);
                out += indent == 0 ? ":" : ": ";
                write(f.second, depth + 1);
            }
            newline(depth);
            out += '}';
        } else {
            throw std::runtime_error(std::string(who) + ": cannot write a " + v.type_name());
        }
    }
};

int json_stringify(CallCtx& ctx) {
    if (ctx.argc < 1)
        throw std::runtime_error("json.stringify: missing argument");
    int indent = 0;
    if (ctx.argc >= 2 && !ctx.args[1].is_nil()) {
        double d = num_arg(ctx.args, ctx.argc, 1, "json.stringify");
        if (d < 0 || d > 16 || d != std::floor(d))
            throw std::runtime_error("json.stringify: indent must be a whole number from 0 to 16");
        indent = (int)d;
    }
    Writer w{"", indent};
    w.write(ctx.args[0], 0);
    return ctx.ret(Value(w.out));
}

} // namespace

std::string json_encode(const Value& v, const char* who) {
    Writer w{"", 0, who};
    w.write(v, 0);
    return w.out;
}

Value json_decode(const std::string& text, const char* who) {
    return decode_text(text, who);
}

Value make_json_module() {
    return MapBuilder().fn("parse", json_parse).fn("stringify", json_stringify).done();
}
