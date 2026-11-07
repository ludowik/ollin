## The search panel of the weather example (docs/samples/weather/keypad.ol): what its keys type, and that for any size
## of area every key is inside it, is not under another, and is the one found at its own centre. How weather.ol draws
## the panel needs the screen, and is looked at there.

import "keypad.ol"

## ── What a key types ──────────────────────────────────────────────────────────────────────────────

assert(appendChar("", "a") == "a" and appendChar("Par", "i") == "Pari", "a letter is added")
assert(appendChar("", " ") == "", "a name does not start with a space")
assert(appendChar("Saint ", " ") == "Saint ", "a space is not added twice running")
assert(appendChar("Saint", " ") == "Saint ", "a space comes after a letter")
assert(appendChar("Aix-en-Provence", "-") == "Aix-en-Provence-" and appendChar("L", "'") == "L'", "the hyphen and the apostrophe")
assert(appendChar("São Tomé", "é") == "São Tomé" + "é", "an accent is one character")
var longest = string.repeat("a", MAX_NAME)
assert(appendChar(longest, "b") == longest, "a name stops at its longest")
assert(appendChar(string.repeat("a", MAX_NAME - 1), "b") == string.repeat("a", MAX_NAME - 1) + "b", "the last place is taken")

assert(eraseLast("abc") == "ab" and eraseLast("a") == "" and eraseLast("") == "", "the last character goes")
assert(eraseLast("café") == "caf" and eraseLast("Saint ") == "Saint", "by character, not by byte")

for key in ["a", "m", "z", "0", "5", "9"] do
    assert(isNameKey(key), "{key} is a name key")
end
for key in ["space", "return", "left", "A", "é", "-", ""] do
    assert(not isNameKey(key), "{key} is no name key")
end

## ── The keys of the panel, whatever the size ──────────────────────────────────────────────────────

func characterKeys(panel)
    var found = []
    for k in panel.keys do
        if k.kind == "char" then
            found.push(k.text)
        end
    end
    return found
end

func checkPanel(w, h)
    var panel = panelLayout(w, h)
    var where = "{w}x{h}"
    assert(#panel.keys == #KEY_ROWS * KEY_COLUMNS + #KEY_CONTROLS, "every key is laid out at {where}")
    assert(panel.top > 0 and panel.top < h, "the panel is on the area at {where}")
    for i = 1, #panel.keys do
        var k = panel.keys[i]
        assert(k.x >= 0 and k.x + k.w <= w and k.y >= panel.top and k.y + k.h <= h + 0.001, "{k.label} is inside the area at {where}")
        assert(k.w > 0 and k.h > 0, "{k.label} has a size at {where}")
        var found = keyAt(panel, k.x + k.w / 2, k.y + k.h / 2)
        assert(found <> nil and found.label == k.label, "the centre of {k.label} is {k.label} at {where}")
        for j = i + 1, #panel.keys do
            var o = panel.keys[j]
            var apart = k.x + k.w <= o.x or o.x + o.w <= k.x or k.y + k.h <= o.y or o.y + o.h <= k.y
            assert(apart, "{k.label} and {o.label} overlap at {where}")
        end
    end
    assert(panel.fieldY + panel.kh <= panel.keys[1].y, "the name sits above the first row at {where}")
    assert(keyAt(panel, w / 2, panel.top - 1) == nil, "nothing is above the panel at {where}")
end

for size in [[1100, 652], [390, 732], [320, 480], [800, 360], [2400, 1200], [600, 600]] do
    checkPanel(size[1], size[2])
end

## ── What can be typed ─────────────────────────────────────────────────────────────────────────────

var panel = panelLayout(390, 732)
var typed = characterKeys(panel)
for c = 0, 25 do
    var letter = string.char("abcdefghijklmnopqrstuvwxyz", c + 1)
    assert(typed.contains(letter), "{letter} is on the panel")
end
for digit in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"] do
    assert(typed.contains(digit), "{digit} is on the panel")
end
for special in ["-", "'", " ", "é", "è", "ê", "à", "ç", "ô", "î", "ï", "ü", "œ"] do
    assert(typed.contains(special), "{special} is on the panel")
end
var seen = {}
for t in typed do
    assert(seen[t] == nil, "{t} is on the panel twice")
    seen[t] = true
end

var kinds = {}
for k in panel.keys do
    kinds[k.kind] = true
end
assert(kinds["back"] == true and kinds["go"] == true, "the panel can erase and can search")
