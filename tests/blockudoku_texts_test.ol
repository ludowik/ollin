## The texts of the Blockudoku sample: both languages must speak about everything, since a key missing from one
## of them would show up in the game as nothing at all, and the first language is the one the game starts in.

import "../docs/samples/blockudoku/texts.ol"

assert(LANGUAGES[1] == "fr", "French is the default language")
assert(i18n.lang == "fr", "the game starts in French")

var rules = {box: 3, cell: 1, zone: 90, streak: 50}
var reference = TEXTS[LANGUAGES[1]]
for code in LANGUAGES do
    var table = TEXTS[code]
    assert(table <> nil, "{code} is listed but has no texts")
    for key, value in reference do
        assert(table[key] <> nil, "{code} lacks the text {key}")
        assert(typeof(table[key]) == typeof(value), "{code}: {key} is not of the same kind as in {LANGUAGES[1]}")
    end
    for key, value in table do
        assert(reference[key] <> nil, "{code} has the text {key}, which {LANGUAGES[1]} lacks")
    end
    var paragraphs = table.help(rules)
    assert(len(paragraphs) == len(reference.help(rules)), "{code}: the help has another number of paragraphs")
    for text in paragraphs do
        assert(len(text) > 0, "{code}: an empty paragraph")
        assert(text.find("\{") == nil, "{code}: a placeholder was not replaced in: {text}")
    end
    var all = paragraphs.join(" ")
    assert(all.find("3x3") <> nil and all.find("90") <> nil and all.find("50") <> nil, "{code}: the help lost a figure of the rules")
end

setLanguage("en")
assert(setLanguage("xx") == false and i18n.lang == "en", "an unknown language changes nothing")
assert(setLanguage("fr") and tr("newGame") == "Nouvelle partie", "switching back to French")
setLanguage("en")
assert(tr("newGame") == "New game", "switching to English")
print("blockudoku texts ok")
