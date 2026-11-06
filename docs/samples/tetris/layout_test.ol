## The layout of Tetris (docs/samples/tetris/layout.ol): the screen of the handheld and the pads in areas of every shape,
## each inside the area, none on another, every pad answering a touch at its own place.

import "layout.ol"

const AREAS = [
    [390, 844], [844, 390], [800, 800], [320, 480], [1200, 700], [600, 640], [160, 144], [2000, 300],
    [360, 640], [412, 915], [375, 667], [768, 1024], [820, 1180]   ## phones and tablets: B once overlapped START on the last two
]
const NAMES = ["a", "b", "down", "left", "right", "start", "style", "up"]

## The rectangle a button covers, as {x0, y0, x1, y1}.
func boxOf(b)
    if b.r <> nil then
        return {x0: b.x - b.r, y0: b.y - b.r, x1: b.x + b.r, y1: b.y + b.r}
    end
    return {x0: b.x - b.w / 2, y0: b.y - b.h / 2, x1: b.x + b.w / 2, y1: b.y + b.h / 2}
end

func overlap(p, q)
    return p.x0 < q.x1 and q.x0 < p.x1 and p.y0 < q.y1 and q.y0 < p.y1
end

## Whether two buttons share any point, as the shapes they are: a disc is not its square.
func touching(p, q)
    if p.r <> nil and q.r <> nil then
        var dx = p.x - q.x
        var dy = p.y - q.y
        return dx * dx + dy * dy < (p.r + q.r) * (p.r + q.r)
    end
    if p.r <> nil or q.r <> nil then
        var disc = p.r <> nil and p or q
        var box = boxOf(disc == p and q or p)
        var nx = math.max(box.x0, math.min(disc.x, box.x1))
        var ny = math.max(box.y0, math.min(disc.y, box.y1))
        var dx = disc.x - nx
        var dy = disc.y - ny
        return dx * dx + dy * dy < disc.r * disc.r
    end
    return overlap(boxOf(p), boxOf(q))
end

for area in AREAS do
    var w = area[1]
    var h = area[2]
    for pads in [false, true] do
        var L = computeLayout(w, h, pads)
        var suffix = pads and " with pads" or ""
        var where = "{w}x{h}{suffix}"
        assert(L.w == w and L.h == h and L.padsShown == pads, "{where}: the arguments are kept")
        assert(L.s > 0, "{where}: no scale")
        var screen = {x0: L.ox, y0: L.oy, x1: L.ox + SCREEN.w * L.s, y1: L.oy + SCREEN.h * L.s}
        assert(screen.x0 >= 0 and screen.y0 >= 0 and screen.x1 <= w + 1 and screen.y1 <= h + 1, "{where}: the screen leaves the area")
        if not pads then
            assert(len(L.buttons) == 0 and L.cross == nil, "{where}: pads without being asked")
        else
            assert(len(L.buttons) == len(NAMES) and L.cross <> nil, "{where}: the pads are not all there")
            var seen = {}
            for b in L.buttons do
                seen[b.name] = true
                var box = boxOf(b)
                assert(box.x0 >= -0.5 and box.y0 >= -0.5 and box.x1 <= w + 0.5 and box.y1 <= h + 0.5, "{where}: {b.name} leaves the area")
                assert(not overlap(box, screen), "{where}: {b.name} is on the screen")
                assert(inButton(b, b.x, b.y), "{where}: {b.name} does not answer at its centre")
                assert(not inButton(b, b.x + w, b.y + h), "{where}: {b.name} answers far away")
            end
            for name in NAMES do
                assert(seen[name] == true, "{where}: no {name} button")
            end
            for i = 1, len(L.buttons) do
                for j = i + 1, len(L.buttons) do
                    var p = L.buttons[i]
                    var q = L.buttons[j]
                    assert(not touching(p, q), "{where}: {p.name} and {q.name} overlap")
                end
            end
        end
    end
end

## A round button answers inside its circle and not at the corner of its square; a rectangle answers up to its edge.
var round = {name: "a", x: 100, y: 100, r: 20, text: "A"}
assert(inButton(round, 100, 119) and inButton(round, 119, 100), "inside the circle")
assert(not inButton(round, 118, 118), "the corner of the square is outside the circle")
var flat = padButton("start", 50, 50, 40, 10, 5, "START")
assert(inButton(flat, 69, 54) and not inButton(flat, 71, 50) and not inButton(flat, 50, 56), "a rectangle")
assert(flat.name == "start" and flat.round == 5 and flat.text == "START")

## The same area gives the same layout, which is what lets tetris.ol work it out only when the area changes.
var first = computeLayout(390, 844, true)
var second = computeLayout(390, 844, true)
assert(first.s == second.s and first.ox == second.ox and first.oy == second.oy and len(first.buttons) == len(second.buttons))
assert(computeLayout(390, 844, true).s <> computeLayout(844, 390, true).s, "a turned area is another layout")

print("tetris layout ok")
