## The size of the field and of what is in it, in the pixels of the arcade game's own screen (224 x 256, the cabinet's monitor
## standing on its side) — graphics.viewport does the rest. The frog hops on a grid of 16 pixel cells, and a ROW of the
## field is one cell high: row 0 is the strip where it starts, rows 1 to 5 the road, row 6 the median strip, rows 7 to 11 the
## river and row 12 the homes. The lanes are the eleven rows from 1 to 11, which the arcade numbers from the top: lane 0 is the
## top row of the river and lane 10 the bottom row of the road.

const FIELD_W = 224
const FIELD_H = 256
const CELL    = 16
const STRIP   = 256            ## a lane is a strip of 32 tiles that wraps, wider than the 28 that show
const TILE    = 8

## Under the field the viewport holds a strip for the buttons. Its height follows the shape of the area the program is shown in, so
## that a tall phone screen is filled — the field stays at the top and the buttons grow — within these bounds.
const PAD_MIN = 96
const PAD_MAX = 200

## The height of the viewport for an area of w x h pixels: as tall as the area's shape asks, so that nothing is left over.
func viewHeight(w, h)
    return math.floor(math.clamp(FIELD_W * h / w, FIELD_H + PAD_MIN, FIELD_H + PAD_MAX))
end

## The buttons in a viewport of FIELD_W x viewH pixels: the four ways on the right as a cross, under the right thumb, and pause
## and sound on the left. They grow with the strip, from 28 to 44 pixels.
func padButtons(viewH)
    var pad = viewH - FIELD_H
    var btn = math.floor(math.clamp(pad / 3.6, 28, 44))
    var cx = FIELD_W - 8 - btn * 3 / 2
    var cy = FIELD_H + pad / 2
    var wide = math.min(72, cx - btn * 3 / 2 - 16)
    return [
        {name: "up",    x: cx - btn / 2,     y: cy - btn * 3 / 2, w: btn, h: btn},
        {name: "down",  x: cx - btn / 2,     y: cy + btn / 2,     w: btn, h: btn},
        {name: "left",  x: cx - btn * 3 / 2, y: cy - btn / 2,     w: btn, h: btn},
        {name: "right", x: cx + btn / 2,     y: cy - btn / 2,     w: btn, h: btn},
        {name: "pause", x: 8,                y: cy - btn - 2,     w: wide, h: btn},
        {name: "sound", x: 8,                y: cy + 2,           w: wide, h: btn}
    ]
end

const ROW_START  = 0
const ROW_MEDIAN = 6
const ROW_HOMES  = 12
const ROW_TOP_Y  = 32          ## the y of the row of the homes; the rows below it follow every 16 pixels

## Where the frog stands when it starts a life, and the left edge of the cells it can reach: x = 8 + 16 * column.
const COLUMN_X0  = 8
const START_X    = 104

## The five homes, 48 pixels apart; a frog that arrives within HOME_REACH pixels of one is in it.
const HOMES      = 5
const HOME_X0    = 8
const HOME_STEP  = 48
const HOME_REACH = 7.0

func rowY(row)
    return ROW_TOP_Y + (ROW_HOMES - row) * CELL
end

## The left edge of the h-th home, from 1 to HOMES.
func homeX(h)
    return HOME_X0 + (h - 1) * HOME_STEP
end
