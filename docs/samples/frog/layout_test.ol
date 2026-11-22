## The layout of Frog's screen (docs/samples/frog/layout.ol): how tall the viewport is, and where the buttons are in it.

import "layout.ol"
import "../lib/area.ol"

assert(viewHeight(390, 732) == 420 and viewHeight(800, 400) == FIELD_H + PAD_MIN and viewHeight(224, 5000) == FIELD_H + PAD_MAX, "the viewport is as tall as the area's shape asks, within bounds")
for view = FIELD_H + PAD_MIN, FIELD_H + PAD_MAX, 26 do
    var list = padButtons(view)
    for b in list do
        assert(rectAt(list, b.x + b.w / 2, b.y + b.h / 2).name == b.name, "view {view}: the middle of the {b.name} button is on it")
        assert(b.y >= FIELD_H and b.y + b.h <= view and b.x >= 0 and b.x + b.w <= FIELD_W, "view {view}: the {b.name} button is in the strip under the field")
    end
    for a = 1, #list do
        for c = a + 1, #list do
            var p = list[a]
            var q = list[c]
            assert(p.x + p.w <= q.x or q.x + q.w <= p.x or p.y + p.h <= q.y or q.y + q.h <= p.y, "view {view}: {p.name} and {q.name} do not overlap")
        end
    end
    assert(rectAt(list, 10, 10) == nil, "the field is no button")
end
assert(padButtons(FIELD_H + PAD_MAX)[1].w > padButtons(FIELD_H + PAD_MIN)[1].w, "the buttons grow with the strip")
print("frog layout ok")
