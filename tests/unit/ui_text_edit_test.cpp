// UNIT test of the editing rules of a ui.textField draft (src/ui_text_edit.h): the limit counts characters, a
// character leaves whole, and a long text shows its end. Called by the main of paths_test.cpp, which sums the failures.
#include "ui_text_edit.h"

#include <cstdio>

static int s_failures = 0;

static void expect(bool ok, const char* what) {
    if (ok)
        return;
    std::printf("FAIL %s\n", what);
    s_failures++;
}

static void test_append() {
    std::string t;
    expect(text_edit_append(t, "abc", 0) && t == "abc", "no limit: everything is appended");
    expect(!text_edit_append(t, "", 0) && t == "abc", "an empty text changes nothing");

    t = "ab";
    expect(text_edit_append(t, "cdef", 4) && t == "abcd", "the limit cuts the added text");
    expect(!text_edit_append(t, "x", 4) && t == "abcd", "at the limit nothing is appended");

    t = "";
    text_edit_append(t, "éàç", 2);
    expect(t == "éà", "the limit counts characters, not bytes");
    t = "aé";
    expect(text_edit_append(t, "€€", 3) && t == "aé€", "a 3-byte character fits as one");
    t = "";
    text_edit_append(t, "a😀b", 2);
    expect(t == "a😀", "a 4-byte character fits as one");
    t = "toolong";
    expect(!text_edit_append(t, "x", 3) && t == "toolong", "a text already over the limit is kept and grows no more");
}

static void test_erase() {
    std::string t;
    expect(!text_edit_erase_last(t), "nothing to erase in an empty text");
    t = "abc";
    expect(text_edit_erase_last(t) && t == "ab", "the last ASCII character goes");
    t = "aé";
    text_edit_erase_last(t);
    expect(t == "a", "a 2-byte character goes whole");
    t = "a€";
    text_edit_erase_last(t);
    expect(t == "a", "a 3-byte character goes whole");
    t = "a😀";
    text_edit_erase_last(t);
    expect(t == "a", "a 4-byte character goes whole");
    t = "é";
    text_edit_erase_last(t);
    expect(t.empty(), "the only character goes");
}

static void test_tail() {
    auto five = [](const std::string& s) { return utf8_count(s) <= 5; };
    expect(text_edit_tail("abc", five) == "abc", "a text that fits is shown whole");
    expect(text_edit_tail("abcdefgh", five) == "defgh", "a long text shows its end");
    expect(text_edit_tail("aéçàèù", five) == "éçàèù", "characters leave whole from the front");
    auto none = [](const std::string&) { return false; };
    expect(text_edit_tail("abc", none).empty(), "nothing fits: nothing is shown");
    expect(text_edit_tail("", five).empty(), "an empty text stays empty");
    std::string long_text(5000, 'x');
    long_text += "end";
    int measures = 0;
    auto counted = [&](const std::string& s) {
        measures++;
        return utf8_count(s) <= 5;
    };
    expect(text_edit_tail(long_text, counted) == "xxend", "a very long text shows its end");
    expect(measures < 40, "and takes a few measures, not one per character");
}

int ui_text_edit_failures() {
    test_append();
    test_erase();
    test_tail();
    return s_failures;
}
