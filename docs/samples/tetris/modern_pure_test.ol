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

func sameRect(a, b)
    return close(a.x, b.x) and close(a.y, b.y) and close(a.w, b.w) and close(a.h, b.h)
end

## The frame is the places of places.ol and nothing else: at scale 1 and the corner of the area it is them, and at any
## other scale and corner it is the same places scaled and moved, whole cells and all.
var one = modernFrame(1, 0, 0)
assert(one.c == CELL and one.s == 1)
assert(sameRect(one.well, WELL) and sameRect(one.score, SCORE_CARD) and sameRect(one.level, LEVEL_CARD))
assert(sameRect(one.lines, LINES_CARD) and sameRect(one.next, NEXT_CARD))
assert(one.gridX == NEXT_GRID.x and one.gridY == NEXT_GRID.y)
for scale in [0.5, 1, 2, 3.75, 6] do
    for corner in [[0, 0], [10, 20], [37, 0]] do
        var f = modernFrame(scale, corner[1], corner[2])
        var tag = "scale {scale} at {corner[1]}, {corner[2]}"
        assert(close(f.c, CELL * scale), tag)
        assert(close(f.well.x, corner[1] + WELL.x * scale) and close(f.well.y, corner[2] + WELL.y * scale), tag)
        assert(close(f.well.w, COLS * f.c) and close(f.well.h, ROWS * f.c), "{tag}: the well is {COLS} by {ROWS} cells")
        assert(close(f.next.x, corner[1] + NEXT_CARD.x * scale) and close(f.next.h, NEXT_CARD.h * scale), tag)
        assert(close(f.gridX, corner[1] + NEXT_GRID.x * scale) and close(f.gridY, corner[2] + NEXT_GRID.y * scale), tag)
        assert(close(f.score.h, SCORE_CARD.h * scale) and close(f.lines.y, corner[2] + LINES_CARD.y * scale), tag)
    end
end

print("tetris modern pure ok")
