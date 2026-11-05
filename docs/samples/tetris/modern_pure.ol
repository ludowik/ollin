## The modern style of Tetris with no drawing: its colours and where everything goes in an area of any size. The
## drawing is in style_modern.ol; keeping this apart is what lets modern_pure_test.ol check that the well, the panels
## and the next piece always fit in the area, however narrow or tall it is.

import "rules.ol"

## The colour of each piece, by the number the well stores it with (I, O, T, S, Z, J, L): cyan, yellow, purple, green,
## red, blue and orange, as in the guideline of the modern games.
const MODERN_COLORS = [
    [0.00, 0.78, 0.90, 1],
    [0.96, 0.80, 0.10, 1],
    [0.66, 0.32, 0.86, 1],
    [0.28, 0.80, 0.36, 1],
    [0.92, 0.26, 0.28, 1],
    [0.26, 0.42, 0.96, 1],
    [0.96, 0.56, 0.16, 1]
]

## A colour made darker (k from -1 to 0, -1 being black) or lighter (k from 0 to 1, 1 being white), its alpha kept.
func modernTone(col, k)
    var out = []
    for i = 1, 3 do
        var v = col[i]
        if k < 0 then
            out.push(v * (1 + k))
        else
            out.push(v + (1 - v) * k)
        end
    end
    out.push(col[4])
    return out
end

## Where things go in an area of w by h points, as in the original: the well at the left and a column of cards at its
## right, the score, the level and the lines from the top and the next piece at the bottom, level with the bottom of
## the well. The result is the size of a cell `c` (a whole number of points), the corner of the well, and the four cards
## {x, y, w, h}. The well and the column together are 16.5 cells wide, which limits a tall area; the height of the
## well limits a wide one.
func modernFrame(w, h)
    var c = math.max(1, math.floor(math.min(h * 0.94 / ROWS, w * 0.96 / 16.5)))
    var panelW = math.floor(c * 5.6)
    var gap = math.floor(c * 0.9)
    var f = {w: w, h: h, c: c}
    f.wellX = math.floor((w - (COLS * c + gap + panelW)) / 2)
    f.wellY = math.floor((h - ROWS * c) / 2)
    var x = f.wellX + COLS * c + gap
    var cardH = math.floor(c * 2.5)
    var step = math.floor(c * 3)
    var nextH = math.floor(c * 5)
    f.score = {x: x, y: f.wellY, w: panelW, h: cardH}
    f.level = {x: x, y: f.wellY + step, w: panelW, h: cardH}
    f.lines = {x: x, y: f.wellY + 2 * step, w: panelW, h: cardH}
    f.next = {x: x, y: f.wellY + ROWS * c - nextH, w: panelW, h: nextH}
    return f
end
