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
