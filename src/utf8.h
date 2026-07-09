#pragma once
#include <cstddef>
#include <cstdint>
#include <string>

// Utilitaires UTF-8 partagés (string_module : char/substr ; vm : len).
// Tolérants aux séquences malformées : un octet de tête invalide ou un codepoint
// tronqué est compté comme 1 codepoint d'1 octet → jamais d'accès hors-bornes.

// Nombre d'octets du codepoint commençant à s[i] (1..4), borné par la fin de s
// et par la présence d'octets de continuation valides (10xxxxxx).
inline size_t utf8Step(const std::string& s, size_t i) {
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

// Nombre de codepoints dans s.
inline size_t utf8Count(const std::string& s) {
    size_t i = 0, cp = 0;
    while (i < s.size()) {
        i += utf8Step(s, i);
        cp++;
    }
    return cp;
}

// Offset (en octets) du début du codepoint d'index cpIndex (0-based) ; renvoie
// s.size() si cpIndex dépasse le nombre de codepoints.
inline size_t utf8ByteOffset(const std::string& s, size_t cpIndex) {
    size_t i = 0, cp = 0;
    while (i < s.size() && cp < cpIndex) {
        i += utf8Step(s, i);
        cp++;
    }
    return i;
}

// Décode le codepoint à l'octet i ; *nbytes = nb d'octets consommés. Séquence
// malformée (tronquée / octet de tête invalide) → renvoie l'octet brut, nbytes=1
// (cohérent avec utf8Step). Ne lit jamais hors de s.
inline uint32_t utf8Decode(const std::string& s, size_t i, size_t* nbytes) {
    unsigned char c = (unsigned char)s[i];
    size_t leadLen = c >= 0xF0 ? 4 : c >= 0xE0 ? 3 : c >= 0xC0 ? 2 : 1;
    size_t actual = utf8Step(s, i);
    if (actual != leadLen) { // malformé → octet brut
        *nbytes = actual;
        return c;
    }
    *nbytes = leadLen;
    if (leadLen == 1)
        return c;
    uint32_t cp = leadLen == 2 ? (c & 0x1Fu) : leadLen == 3 ? (c & 0x0Fu) : (c & 0x07u);
    for (size_t k = 1; k < leadLen; k++)
        cp = (cp << 6) | ((unsigned char)s[i + k] & 0x3Fu);
    return cp;
}

// Encode un codepoint en UTF-8 (ajouté à out).
inline void utf8Encode(uint32_t cp, std::string& out) {
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
