## The modern style of Tetris with no drawing: its colours and where everything goes. The drawing is in
## style_modern.ol; keeping this apart is what lets modern_pure_test.ol check it.

import "rules.ol"
import "places.ol"

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
            out.push(math.lerp(v, 1, k))
        end
    end
    out.push(col[4])
    return out
end

## The shadow and the light of each piece's colour, worked out once: a block asks for both every time it is drawn.
const MODERN_SHADOW = MODERN_COLORS.map(func(col)
    return modernTone(col, -0.45)
end)
const MODERN_LIGHT = MODERN_COLORS.map(func(col)
    return modernTone(col, 0.5)
end)

## A place of places.ol, in points of the screen, turned into pixels: the screen scaled by s with its top left at
## (ox, oy).
func scaled(r, s, ox, oy)
    return {x: ox + r.x * s, y: oy + r.y * s, w: r.w * s, h: r.h * s}
end

## Where things go, exactly where the original puts them: the well and the four cards, in pixels, the size of a cell `c`,
## and the top left of the 4 by 4 cells of the next piece.
func modernFrame(s, ox, oy)
    return {
        s: s, ox: ox, oy: oy, c: CELL * s,
        well: scaled(WELL, s, ox, oy),
        score: scaled(SCORE_CARD, s, ox, oy),
        level: scaled(LEVEL_CARD, s, ox, oy),
        lines: scaled(LINES_CARD, s, ox, oy),
        next: scaled(NEXT_CARD, s, ox, oy),
        gridX: ox + NEXT_GRID.x * s,
        gridY: oy + NEXT_GRID.y * s
    }
end

## Where the title and the number of a card go, as the original puts them: the title at the top, the number under it at
## the right, never on the same row. `c` is the size of a cell. The sizes are those the text may not exceed; the number
## is also kept inside the width of the card by the drawing.
func modernCardText(r, c)
    var titleSize = c * 0.75
    var valueSize = math.min(c * 1.5, r.h - c * 1.65)
    return {
        pad: c * 0.5,
        titleY: r.y + c * 0.4, titleSize: titleSize,
        valueY: r.y + r.h - c * 0.35, valueSize: valueSize
    }
end
