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

## Where things go in an area of w by h points: the size of a cell `c` (a whole number of points), the corner of the well,
## and the four cards {x, y, w, h} of the score, the level, the lines and the next piece. In a wide area the cards stand
## in a column at the right of the well; in a tall one they make a strip above it.
func modernFrame(w, h)
    var wide = w >= h * 0.95
    var f = {w: w, h: h, wide: wide}
    var c
    if wide then
        c = math.max(1, math.floor(h * 0.94 / ROWS))   ## the height limits: a wide area is at least 0.95 of a square
        var panelW = math.floor(c * 5.6)
        var gap = math.floor(c * 0.9)
        f.c = c
        f.wellX = math.floor((w - (COLS * c + gap + panelW)) / 2)
        f.wellY = math.floor((h - ROWS * c) / 2)
        var x = f.wellX + COLS * c + gap
        var cardH = math.floor(c * 2.5)
        var step = math.floor(c * 3)
        f.score = {x: x, y: f.wellY, w: panelW, h: cardH}
        f.level = {x: x, y: f.wellY + step, w: panelW, h: cardH}
        f.lines = {x: x, y: f.wellY + 2 * step, w: panelW, h: cardH}
        f.next = {x: x, y: f.wellY + 3 * step, w: panelW, h: math.floor(c * 5)}
    else
        var strip = math.floor(h * 0.11)
        c = math.max(1, math.floor(math.min(w * 0.94 / COLS, (h * 0.97 - strip) / (ROWS + 0.4))))
        f.c = c
        f.wellX = math.floor((w - COLS * c) / 2)
        f.wellY = h - ROWS * c - math.floor(h * 0.015)
        var y = f.wellY - strip - math.floor(c * 0.4)
        var gap = math.floor(c * 0.3)
        var room = COLS * c - 3 * gap
        var wScore = math.floor(room * 0.34)
        var wSmall = math.floor(room * 0.17)
        var wNext = room - wScore - 2 * wSmall
        f.score = {x: f.wellX, y: y, w: wScore, h: strip}
        f.level = {x: f.score.x + wScore + gap, y: y, w: wSmall, h: strip}
        f.lines = {x: f.level.x + wSmall + gap, y: y, w: wSmall, h: strip}
        f.next = {x: f.lines.x + wSmall + gap, y: y, w: wNext, h: strip}
    end
    return f
end
