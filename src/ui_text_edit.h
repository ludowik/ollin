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
// visible in a field narrower than its text. `fits` is a predicate on a string (the module measures with the font).
template <typename Fits>
inline std::string text_edit_tail(const std::string& text, Fits fits) {
    size_t start = 0;
    while (start < text.size()) {
        std::string tail = text.substr(start);
        if (fits(tail))
            return tail;
        start += utf8_step(text, start);
    }
    return std::string();
}
