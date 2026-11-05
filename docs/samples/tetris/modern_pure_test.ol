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
end

## As in the original, whatever the shape: the cards in one column at the right of the well and level with its top,
## the next piece at the bottom of the well, and the column's width and cell kept by the area.
for size in [[800, 600], [390, 700], [700, 700], [320, 288], [1920, 1080], [360, 780], [100, 1000], [1000, 100], [40, 40]] do
    var f = modernFrame(size[1], size[2])
    var well = {x: f.wellX, y: f.wellY, w: COLS * f.c, h: ROWS * f.c}
    assert(f.score.y == well.y and f.score.x >= well.x + well.w, "{size[1]}x{size[2]}: the score is not at the top right")
    assert(f.level.x == f.score.x and f.lines.x == f.score.x and f.next.x == f.score.x)
    assert(f.level.w == f.score.w and f.lines.w == f.score.w and f.next.w == f.score.w)
    assert(f.score.y < f.level.y and f.level.y < f.lines.y and f.lines.y < f.next.y, "{size[1]}x{size[2]}: the order of the cards")
    assert(f.next.y + f.next.h == well.y + well.h, "{size[1]}x{size[2]}: the next piece is not level with the bottom of the well")
    assert(math.abs(f.wellY - (size[2] - well.h - f.wellY)) <= 1 or f.c == 1, "{size[1]}x{size[2]}: the well is not centred up and down")
    assert(math.abs(f.wellX - (size[1] - (f.next.x + f.next.w) )) <= 1 or f.c == 1, "{size[1]}x{size[2]}: the well and the column are not centred across")
    assert(f.c * 16.5 <= size[1] * 0.96 + 1 or f.c == 1, "{size[1]}x{size[2]}: the well and the column are wider than the area")
end

## The cell is as large as the area allows: the height of a wide area, the width of a tall one.
assert(modernFrame(1920, 1080).c == 56)
assert(modernFrame(390, 700).c == math.floor(390 * 0.96 / 16.5))
assert(modernFrame(390, 700).c < math.floor(700 * 0.94 / ROWS))
assert(modernFrame(390, 900).c == modernFrame(390, 700).c, "a taller area does not make the well wider")

print("tetris modern pure ok")
