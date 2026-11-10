## The texts of the Blockudoku sample: both languages must speak about everything, since a key missing from one
## of them would show up in the game as nothing at all, and the first language is the one the game starts in.

import "texts.ol"
import "../lib/i18n_testlib.ol"

checkLanguages()
assert(i18n.languages[1] == "fr", "French is the default language")

var rules = {box: 3, cell: 1, zone: 90, streak: 50}
var reference = TEXTS[LANGUAGES[1]]
for code in LANGUAGES do
    var table = TEXTS[code]
    var paragraphs = table.help(rules)
    assert(len(paragraphs) == len(reference.help(rules)), "{code}: the help has another number of paragraphs")
    for text in paragraphs do
        assert(len(text) > 0, "{code}: an empty paragraph")
        assert(text.find("\{") == nil, "{code}: a placeholder was not replaced in: {text}")
    end
    var all = paragraphs.join(" ")
    assert(all.find("{rules.box}x{rules.box}") <> nil and all.find("{rules.zone}") <> nil and all.find("{rules.streak}") <> nil, "{code}: the help lost a figure of the rules")
end

assert(setLanguage("fr") and tr("newGame") == "Nouvelle partie")
setLanguage("en")
assert(tr("newGame") == "New game", "switching to English")
print("blockudoku texts ok")
