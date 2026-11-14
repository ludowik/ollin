## The texts of the Sudoku sample: both languages must speak about everything, since a key missing from one of them
## would show up in the game as nothing at all, and the first language is the one the game starts in.

import "board.ol"
import "solver.ol"
import "texts.ol"
import "../lib/i18n_testlib.ol"

checkLanguages()
assert(i18n.languages[1] == "fr", "French is the default language")

var rules = {box: 3, size: 9, hints: 3}
var hint = {row: 2, col: 5, digit: 7, unit: "x"}
checkHelp(rules, ["{rules.box}x{rules.box}", "{rules.hints}"])
for code in LANGUAGES do
    var table = TEXTS[code]
    ## the texts that take figures say them
    var naked = table.hintNaked(hint)
    assert(naked.find("{hint.row}") <> nil and naked.find("{hint.col}") <> nil and naked.find("{hint.digit}") <> nil, "{code}: the naked-single hint lost a figure")
    assert(table.hintHidden(hint).find("{hint.digit}") <> nil and table.hintHidden(hint).find(hint.unit) <> nil, "{code}: the hidden-single hint lost its unit or its digit")
    assert(table.hintPlain(hint).find("{hint.digit}") <> nil)
    for key in ["unitRow", "unitColumn", "unitBox"] do
        assert(table[key](4).find("4") <> nil, "{code}: {key} lost its number")
    end
end

## The words of a hint leave the hint as the screen reads it: its unit stays a number.
for code in LANGUAGES do
    setLanguage(code)
    var hidden = {kind: "hidden", cell: boardIdx(2, 5), digit: 7, unit: 11}
    var said = hintText(hidden)
    assert(hidden.unit == 11 and typeof(hidden.unit) == "int", "{code}: hintText changed the unit of the hint")
    assert(said.find(tr("unitColumn")(2)) <> nil and said.find("7") <> nil, "{code}: the hidden-single words lost the unit or the digit: {said}")
    var naked = hintText({kind: "naked", cell: boardIdx(2, 5), digit: 7})
    assert(naked.find("2") <> nil and naked.find("5") <> nil and naked.find("7") <> nil, "{code}: the naked-single words lost a figure")
    assert(hintText({kind: "mistake", cell: 1, digit: 1}) == tr("hintMistake"))
end

assert(setLanguage("fr") and tr("newGame") == "Nouvelle partie")
setLanguage("en")
assert(tr("newGame") == "New game", "switching to English")
print("sudoku texts ok")
