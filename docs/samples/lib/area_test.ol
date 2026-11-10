## The rectangles of a screen (docs/samples/lib/area.ol).

import "area.ol"

var r = rectOf(10, 20, 30, 40)
assert(r.x == 10 and r.y == 20 and r.w == 30 and r.h == 40)
assert(inRect(10, 20, r) and inRect(40, 60, r) and inRect(25, 40, r), "the edges belong to the rectangle")
assert(not inRect(9, 40, r) and not inRect(41, 40, r) and not inRect(25, 19, r) and not inRect(25, 61, r))

var cache = {w: -1, h: -1}
assert(areaChanged(cache) and cache.w == W and cache.h == H, "the first look at an area is a change")
assert(not areaChanged(cache), "and the same area is none")
cache.w = W + 1
assert(areaChanged(cache) and not areaChanged(cache), "a different width is one change")
print("area ok")
