## Regression tests — The ui module.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/modules/ui.ol — it must finish without error.

## ── ui.list ────────────────────────────────────────────────────────────────
## With no graphics area, the declaration validates its arguments and initialises the selection:
## that is the part tested here, the rendering and the click needing a display. An array returns a
## VALUE, a map or an enum a KEY — as `for … in` does.
enum LiDiff
    easy,
    normal,
    hard
end
var liTints = ["red", "green", "blue"]
var liSettings = {volume: 0.8, brightness: 0.5, alpha: 1}
var liC = nil
var liD = nil
var liR = nil
ui.list("Colour", liTints, ref liC)
ui.list("Difficulty", LiDiff, ref liD)
ui.list("Setting", liSettings, ref liR)
assert(liC == "red")           ## the array's first element, its VALUE
assert(liD == "easy")          ## an enum sorted by value, hence in declaration order
assert(liR == "alpha")           ## a map sorted by label, hence the first in alphabetical order

## A selection already set is honoured: the initialisation only applies to nil.
var liKept = "blue"
ui.list("Colour", liTints, ref liKept)
assert(liKept == "blue")

## ── menu.list, ui.current ──────────────────────────────────────────────────
## The declaration as a METHOD of a menu goes through its own function in the stub, with the same
## validation and the same initialisation as ui.list; ui.current() answers a handle, never nil.
var liM = nil
ui.menu("Palette").list("Colour", liTints, ref liM)
assert(liM == "red")
var liMKept = "green"
ui.menu("Palette").list("Colour", liTints, ref liMKept)
assert(liMKept == "green")
assert(ui.current() <> nil)

## ── ui.textField, menu.textField, field.edit ───────────────────────────────
## Headless, the declaration validates its arguments and initialises the variable; typing and validating need a
## display (tools/test-keyboard-browser.js drives them in the browser). A nil variable becomes "", a string is kept, the
## optional arguments come in any order, and the method of a menu goes through its own function in the stub.
var tfName = nil
var tfField = ui.textField("Name", ref tfName)
assert(tfName == "")
var tfKept = "Ada"
ui.textField("Name", ref tfKept, 12, "your name", func(t) end)
assert(tfKept == "Ada")
var tfOrder = "x"
ui.textField("Name", ref tfOrder, func(t) end, "placeholder", 3)
assert(tfOrder == "x")
var tfM = nil
ui.menu("Profile").textField("City", ref tfM, 20)
assert(tfM == "")
assert(tfField.edit() == tfField)

## A variable that holds something else than a string is refused, and is left as it was.
var tfNumber = 42
var tfRefused = false
try
    ui.textField("Name", ref tfNumber)
catch e
    tfRefused = true
end
assert(tfRefused)
assert(tfNumber == 42)
