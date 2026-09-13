#pragma once
#include <cstdint>
#include <stdexcept>
#include <string>

// What a NUMBER token's lexeme is WORTH.
//
// The lexer decides what a number LOOKS like; this decides what it MEANS, and it is the only
// place that does. The parser reads a literal of the source with it, and string.number reads a
// text of the program with it, so "0xFF" or "1e3" cannot come to mean one thing in the source and
// another at run time — which is exactly what a second copy of these rules would end up doing.
//
// The lexeme is NORMALISED by the lexer: no '_', and the base prefix and the exponent letter are
// lower case, so 'X'/'O'/'B'/'E' never reach here.
struct NumLit {
    bool is_int = true;
    int64_t i = 0;
    double d = 0.0;
};

// False when the value does not fit; the caller decides what that means — the parser names the
// line of the source, string.number gives nil.
inline bool number_from_lexeme(const std::string& lex, NumLit& out) {
    try {
        // 0x / 0o / 0b: an integer in base 16/8/2 (stoull keeps the whole bit pattern, wrapping
        // int64). One conversion for the three bases, read from the prefix.
        int base = lex.size() > 2 && lex[0] == '0' ? (lex[1] == 'x'   ? 16
                                                      : lex[1] == 'o' ? 8
                                                      : lex[1] == 'b' ? 2
                                                                      : 0)
                                                   : 0;
        if (base) {
            out.is_int = true;
            out.i = static_cast<int64_t>(std::stoull(lex.c_str() + 2, nullptr, base));
            return true;
        }
        // A float on a '.' OR a scientific exponent; an integer otherwise.
        if (lex.find('.') == std::string::npos && lex.find('e') == std::string::npos) {
            out.is_int = true;
            out.i = static_cast<int64_t>(std::stoll(lex));
            return true;
        }
        out.is_int = false;
        out.d = std::stod(lex);
        return true;
    } catch (const std::out_of_range&) {
        return false;
    }
}
