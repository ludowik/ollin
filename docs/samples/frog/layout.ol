## How the screen is laid out around the field: the viewport is as tall as the shape of the area asks, the field stays at the
## top and the buttons fill the strip under it.

import "field.ol"
import "../lib/area.ol"

## Under the field the viewport holds a strip for the buttons. Its height follows the shape of the area the program is shown in, so
## that a tall phone screen is filled — the field stays at the top and the buttons grow — within these bounds.
const PAD_MIN = 96
const PAD_MAX = 200

## The height of the viewport for an area of w x h pixels: as tall as the area's shape asks, so that nothing is left over.
func viewHeight(w, h)
    return fitHeight(FIELD_W, w, h, FIELD_H + PAD_MIN, FIELD_H + PAD_MAX)
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
