## The size of the field and of what is in it, in the pixels of the arcade game's own screen (224 x 256, the cabinet's monitor
## standing on its side) — graphics.viewport does the rest. The frog hops on a grid of 16 pixel cells, and a ROW of the
## field is one cell high: row 0 is the strip where it starts, rows 1 to 5 the road, row 6 the median strip, rows 7 to 11 the
## river and row 12 the homes. The lanes are the eleven rows from 1 to 11, which the arcade numbers from the top: lane 0 is the
## top row of the river and lane 10 the bottom row of the road.

const FIELD_W = 224
const FIELD_H = 256
const PAD_H   = 96             ## the strip under the field that holds the buttons, drawn in the same viewport
const VIEW_H  = FIELD_H + PAD_H
const CELL    = 16
const STRIP   = 256            ## a lane is a strip of 32 tiles that wraps, wider than the 28 that show
const TILE    = 8

## The buttons, in the pixels of the viewport: the four ways on the left as a cross, pause and sound on the right.
const BTN = 28
const PAD_CX = 62
const PAD_CY = FIELD_H + PAD_H / 2
const BUTTONS = [
    {name: "up",    x: PAD_CX - BTN / 2,       y: PAD_CY - BTN * 3 / 2, w: BTN, h: BTN},
    {name: "down",  x: PAD_CX - BTN / 2,       y: PAD_CY + BTN / 2,     w: BTN, h: BTN},
    {name: "left",  x: PAD_CX - BTN * 3 / 2,   y: PAD_CY - BTN / 2,     w: BTN, h: BTN},
    {name: "right", x: PAD_CX + BTN / 2,       y: PAD_CY - BTN / 2,     w: BTN, h: BTN},
    {name: "pause", x: 140,                    y: PAD_CY - BTN - 2,     w: 72,  h: BTN},
    {name: "sound", x: 140,                    y: PAD_CY + 2,           w: 72,  h: BTN}
]

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
