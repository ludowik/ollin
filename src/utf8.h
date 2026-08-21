#pragma once
#include <cstddef>
#include <cstdint>
#include <string>

// Shared UTF-8 helpers (string_module: char/substr; vm: len).
// Malformed sequences are tolerated: an invalid lead byte or a truncated codepoint counts as
// one 1-byte codepoint, so decoding never reads out of bounds.

// Byte length (1..4) of the codepoint starting at s[i], bounded by the end of s and by the
// presence of valid continuation bytes (10xxxxxx).
inline size_t utf8_step(const std::string& s, size_t i) {
    unsigned char c = (unsigned char)s[i];
    size_t len = c >= 0xF0 ? 4 : c >= 0xE0 ? 3 : c >= 0xC0 ? 2 : 1;
    size_t adv = 1;
    for (size_t k = 1; k < len && i + k < s.size(); k++) {
        if (((unsigned char)s[i + k] & 0xC0) != 0x80)
            break; // pas un octet de continuation → codepoint tronqué
        adv++;
    }
    return adv;
}

inline size_t utf8_count(const std::string& s) {
    size_t i = 0, cp = 0;
    while (i < s.size()) {
        i += utf8_step(s, i);
        cp++;
    }
    return cp;
}

// Byte offset of the codepoint at index cpIndex (0-based); returns s.size() when cpIndex is
// past the last codepoint.
inline size_t utf8_byte_offset(const std::string& s, size_t cp_index) {
    size_t i = 0, cp = 0;
    while (i < s.size() && cp < cp_index) {
        i += utf8_step(s, i);
        cp++;
    }
    return i;
}

// A malformed sequence (truncated, or an invalid lead byte) yields the raw byte with
// *nbytes = 1, matching utf8Step. Never reads past the end of s.
inline uint32_t utf8_decode(const std::string& s, size_t i, size_t* nbytes) {
    unsigned char c = (unsigned char)s[i];
    size_t lead_len = c >= 0xF0 ? 4 : c >= 0xE0 ? 3 : c >= 0xC0 ? 2 : 1;
    size_t actual = utf8_step(s, i);
    if (actual != lead_len) { // malformé → octet brut
        *nbytes = actual;
        return c;
    }
    *nbytes = lead_len;
    if (lead_len == 1)
        return c;
    uint32_t cp = lead_len == 2 ? (c & 0x1Fu) : lead_len == 3 ? (c & 0x0Fu) : (c & 0x07u);
    for (size_t k = 1; k < lead_len; k++)
        cp = (cp << 6) | ((unsigned char)s[i + k] & 0x3Fu);
    return cp;
}

inline void utf8_encode(uint32_t cp, std::string& out) {
    if (cp < 0x80) {
        out += (char)cp;
    } else if (cp < 0x800) {
        out += (char)(0xC0 | (cp >> 6));
        out += (char)(0x80 | (cp & 0x3F));
    } else if (cp < 0x10000) {
        out += (char)(0xE0 | (cp >> 12));
        out += (char)(0x80 | ((cp >> 6) & 0x3F));
        out += (char)(0x80 | (cp & 0x3F));
    } else {
        out += (char)(0xF0 | (cp >> 18));
        out += (char)(0x80 | ((cp >> 12) & 0x3F));
        out += (char)(0x80 | ((cp >> 6) & 0x3F));
        out += (char)(0x80 | (cp & 0x3F));
    }
}
