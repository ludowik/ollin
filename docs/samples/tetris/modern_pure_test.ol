## The modern style of Tetris with no drawing (docs/samples/tetris/modern_pure.ol): its tones, and the frame that
## places the well and the cards in an area of any shape.

import "modern_pure.ol"

func close(a, b)
    return math.abs(a - b) < 0.0001
end

func sameColour(a, b)
    return close(a[1], b[1]) and close(a[2], b[2]) and close(a[3], b[3]) and close(a[4], b[4])
end

## Tones: 0 leaves a colour, -1 is black, 1 is white, and the alpha stays.
var red = [0.9, 0.3, 0.1, 0.5]
assert(sameColour(modernTone(red, 0), red))
assert(sameColour(modernTone(red, -1), [0, 0, 0, 0.5]))
assert(sameColour(modernTone(red, 1), [1, 1, 1, 0.5]))
assert(sameColour(modernTone(red, -0.5), [0.45, 0.15, 0.05, 0.5]))
assert(sameColour(modernTone(red, 0.5), [0.95, 0.65, 0.55, 0.5]))
assert(len(MODERN_COLORS) == KINDS)
for i = 1, KINDS do
    for j = i + 1, KINDS do
        assert(not sameColour(MODERN_COLORS[i], MODERN_COLORS[j]), "two pieces with the colour {i}")
    end
    assert(MODERN_COLORS[i][4] == 1)
end

func inside(r, w, h)
    return r.x >= 0 and r.y >= 0 and r.x + r.w <= w and r.y + r.h <= h and r.w > 0 and r.h > 0
end

func apart(a, b)
    return a.x + a.w <= b.x or b.x + b.w <= a.x or a.y + a.h <= b.y or b.y + b.h <= a.y
end

## In areas of every shape, from a watch to a wall: whole cells, the well in the area, the cards in it and apart from
## each other and from the well.
for size in [[800, 600], [390, 700], [700, 700], [320, 288], [1920, 1080], [360, 780], [100, 1000], [1000, 100], [40, 40]] do
    var w = size[1]
    var h = size[2]
    var f = modernFrame(w, h)
    assert(f.c >= 1 and f.c == math.floor(f.c), "{w}x{h}: the cell is {f.c}")
    var well = {x: f.wellX, y: f.wellY, w: COLS * f.c, h: ROWS * f.c}
    if f.c > 1 then
        assert(inside(well, w, h), "{w}x{h}: the well is out of the area")
        for card in [f.score, f.level, f.lines, f.next] do
            assert(inside(card, w, h), "{w}x{h}: a card is out of the area")
            assert(apart(card, well), "{w}x{h}: a card is on the well")
        end
        var cards = [f.score, f.level, f.lines, f.next]
        for i = 1, 4 do
            for j = i + 1, 4 do
                assert(apart(cards[i], cards[j]), "{w}x{h}: cards {i} and {j} overlap")
            end
        end
    end
    assert(f.wide == (w >= h * 0.95), "{w}x{h}")
end

## A tall area gives most of its width to the well.
var tall = modernFrame(390, 700)
assert(COLS * tall.c >= 390 * 0.8, "the well is {COLS * tall.c} points wide in 390")
var taller = modernFrame(390, 900)
assert(COLS * taller.c >= 390 * 0.8)

## The cell is as large as the area allows (here the height, 94 % of it, limits a wide area), and a tall one is the other mode.
assert(modernFrame(1920, 1080).c == 56)
assert(modernFrame(1920, 1080).wide)
assert(not modernFrame(390, 700).wide)

print("tetris modern pure ok")
