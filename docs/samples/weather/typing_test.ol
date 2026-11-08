## The name typed in the search of the weather example (docs/samples/weather/typing.ol): what the characters add to it, and
## that for any size of area the field and the button are inside it, apart, and the ones a finger finds at their centres.
## How weather.ol draws them needs the screen, and is looked at there.

import "typing.ol"

## ── What the characters add ───────────────────────────────────────────────────────────────────────

assert(appendChar("", "a") == "a" and appendChar("Par", "i") == "Pari", "a letter is added")
assert(appendChar("", " ") == "", "a name does not start with a space")
assert(appendChar("Saint ", " ") == "Saint ", "a space is not added twice running")
assert(appendChar("Saint", " ") == "Saint ", "a space comes after a letter")
assert(appendChar("Aix-en-Provence", "-") == "Aix-en-Provence-" and appendChar("L", "'") == "L'", "the hyphen and the apostrophe")
assert(appendChar("São Tomé", "é") == "São Tomé" + "é", "an accent is one character")
var longest = string.repeat("a", MAX_NAME)
assert(appendChar(longest, "b") == longest, "a name stops at its longest")
assert(appendChar(string.repeat("a", MAX_NAME - 1), "b") == string.repeat("a", MAX_NAME - 1) + "b", "the last place is taken")

assert(appendText("", "Saint-Étienne") == "Saint-Étienne", "a whole word in one call")
assert(appendText("Saint", "-Denis") == "Saint-Denis", "the characters join what was typed")
assert(appendText("", "  Paris") == "Paris", "a space at the start is lost, the rest stays")
assert(appendText("Le", "  Havre") == "Le Havre", "two spaces in a row are one")
assert(appendText(string.repeat("a", MAX_NAME - 2), "bcde") == string.repeat("a", MAX_NAME - 2) + "bc", "a paste stops at the longest name")

assert(eraseLast("abc") == "ab" and eraseLast("a") == "" and eraseLast("") == "", "the last character goes")
assert(eraseLast("café") == "caf" and eraseLast("Saint ") == "Saint", "by character, not by byte")

## ── The field and the button, whatever the size ───────────────────────────────────────────────────

func checkLayout(w, h)
    var s = searchLayout(w, h)
    var where = "{w}x{h}"
    for name in ["field", "go"] do
        var r = s[name]
        assert(r.w > 0 and r.h > 0, "the {name} has a size at {where}")
        assert(r.x >= 0 and r.x + r.w <= w and r.y >= 0 and r.y + r.h <= h, "the {name} is inside the area at {where}")
        assert(within(r, r.x + r.w / 2, r.y + r.h / 2), "the centre of the {name} is in the {name} at {where}")
    end
    assert(s.field.x + s.field.w <= s.go.x, "the field ends before the button at {where}")
    assert(not within(s.field, s.go.x + s.go.w / 2, s.go.y + s.go.h / 2), "the button's centre is not the field's at {where}")
    assert(s.field.h >= 40 or s.field.h >= h * 0.1, "a finger can touch the field at {where}")
    assert(s.hintY > s.field.y + s.field.h and s.hintY < h, "the hint is under the field at {where}")
end

for size in [[1100, 652], [390, 732], [320, 480], [800, 360], [2400, 1200], [600, 600], [390, 330]] do
    checkLayout(size[1], size[2])
end

var rect = {x: 10, y: 20, w: 30, h: 40}
assert(within(rect, 10, 20) and within(rect, 39, 59), "the corner and the last point are in")
assert(not within(rect, 40, 20) and not within(rect, 10, 60) and not within(rect, 9, 30), "the far edges and outside are out")
