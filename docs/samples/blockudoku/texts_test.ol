## The texts of the Blockudoku sample: both languages must speak about everything, since a key missing from one
## of them would show up in the game as nothing at all, and the first language is the one the game starts in.

import "texts.ol"
import "../lib/i18n_testlib.ol"

checkLanguages()
assert(i18n.languages[1] == "fr", "French is the default language")

var rules = {box: 3, cell: 1, zone: 90, streak: 50}
checkHelp(rules, ["{rules.box}x{rules.box}", "{rules.zone}", "{rules.streak}"])

assert(setLanguage("fr") and tr("newGame") == "Nouvelle partie")
setLanguage("en")
assert(tr("newGame") == "New game", "switching to English")
print("blockudoku texts ok")
