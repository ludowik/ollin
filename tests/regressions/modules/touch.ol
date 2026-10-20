## Regression tests — The touch module (multitouch).
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/modules/touch.ol — it must finish without error.

## ── The touch module (multitouch) ──────────────────────────────────────────
## With no touch surface — which is the integration container's case — the module still exists: a
## script reading the state runs and sees nothing, instead of failing on a nil.
assert(typeof(touch) == "module")
assert(touch.count() == 0)
assert(typeof(touch.points()) == "array" and #touch.points() == 0)

## The callbacks are assigned as `mouse`'s are: the engine calls whatever exists, and the absence
## of all three is not a fault.
global tcSeen = []
func touch.began(id, x, y)
    tcSeen[#tcSeen + 1] = id
end
assert(#tcSeen == 0)

## `pinch` is derived from two contacts, so it is declared like the others and never fires with no
## touch surface. Only the FORM can be checked here: the gesture itself is measured in a browser,
## through synthetic touch events.
global tcZoom = 1.0
func touch.pinch(scale, cx, cy)
    tcZoom = tcZoom * scale
end
assert(tcZoom == 1.0)
