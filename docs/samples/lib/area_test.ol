## The rectangles of a screen (docs/samples/lib/area.ol).

import "area.ol"

var r = rectOf(10, 20, 30, 40)
assert(r.x == 10 and r.y == 20 and r.w == 30 and r.h == 40)
assert(inRect(10, 20, r) and inRect(40, 60, r) and inRect(25, 40, r), "the edges belong to the rectangle")
assert(not inRect(9, 40, r) and not inRect(41, 40, r) and not inRect(25, 19, r) and not inRect(25, 61, r))

var list = [{name: "a", x: 0, y: 0, w: 10, h: 10}, {name: "b", x: 20, y: 0, w: 10, h: 10}]
assert(rectAt(list, 5, 5).name == "a" and rectAt(list, 25, 5).name == "b", "the rectangle that holds the point")
assert(rectAt(list, 15, 5) == nil and rectAt([], 5, 5) == nil, "none when the point is in no rectangle")

var cache = {w: -1, h: -1}
assert(areaChanged(cache) and cache.w == W and cache.h == H, "the first look at an area is a change")
assert(not areaChanged(cache), "and the same area is none")
cache.w = W + 1
assert(areaChanged(cache) and not areaChanged(cache), "a different width is one change")
assert(fitHeight(400, 400, 800, 600, 900) == 800 and fitHeight(400, 390, 844, 600, 780) == 780 and fitHeight(400, 1000, 500, 600, 780) == 600, "as tall as the shape asks, within the bounds")
assert(fitHeight(224, 224, 300, 0, 1000) == 300 and typeof(fitHeight(400, 390, 700, 0, 1000)) == "int", "a whole number of pixels")
print("area ok")
