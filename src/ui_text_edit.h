#pragma once
#include "utf8.h"
#include <cstddef>
#include <string>

// The editing rules of a ui.textField draft, kept apart from the module so that a unit test can run them without a
// screen. Lengths are in CHARACTERS (codepoints), never bytes: "é" is one character of a 12-character limit.

// Appends `added` to `text`, stopping at `max_chars` characters (0 = no limit). Returns whether anything was appended.
inline bool text_edit_append(std::string& text, const std::string& added, size_t max_chars) {
    size_t room = (size_t)-1;
    if (max_chars > 0) {
        size_t have = utf8_count(text);
        room = have >= max_chars ? 0 : max_chars - have;
    }
    size_t bytes = utf8_byte_offset(added, room);
    text.append(added, 0, bytes);
    return bytes > 0;
}

// Removes the last character. Returns whether there was one.
inline bool text_edit_erase_last(std::string& text) {
    if (text.empty())
        return false;
    text.resize(utf8_byte_offset(text, utf8_count(text) - 1));
    return true;
}

// The end of `text` that `fits` accepts: characters leave from the FRONT until the rest fits, so the cursor stays
// visible in a field narrower than its text. `fits` is a predicate on a string (the module measures with the font) and
// must be monotone — a shorter tail never fits less — which is what lets a bisection find the first tail that fits in
// log(n) measures instead of one per character.
template <typename Fits>
inline std::string text_edit_tail(const std::string& text, Fits fits) {
    size_t low = 0;
    size_t high = utf8_count(text);
    while (low < high) {
        size_t middle = low + (high - low) / 2;
        if (fits(text.substr(utf8_byte_offset(text, middle))))
            high = middle;
        else
            low = middle + 1;
    }
    return text.substr(utf8_byte_offset(text, low));
}
