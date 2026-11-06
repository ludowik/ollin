## Where the screen of the handheld and the pads of a touch screen go in an area, worked out with no drawing and no state
## but its arguments, so that the layout can be tested alone. tetris.ol keeps the result in `view.layout`, and both styles
## draw in these places; the pads answer a touch through the very same buttons they are drawn from (inButton).

import "places.ol"

## A button of the pads: the area that answers a touch, and how it is drawn (`round` is the radius of its corners, and
## `text` the letters on it).
func padButton(name, x, y, w, h, round, text)
    return {name: name, x: x, y: y, w: w, h: h, round: round, text: text}
end

## Whether the point (px, py) is on the button: inside its circle, or its rectangle.
func inButton(b, px, py)
    if b.r <> nil then
        var dx = px - b.x
        var dy = py - b.y
        return dx * dx + dy * dy <= b.r * b.r
    end
    return math.abs(px - b.x) <= b.w / 2 and math.abs(py - b.y) <= b.h / 2
end

## Where the screen and the pads go. The screen keeps the handheld's proportions; with the pads shown it takes the
## top of a tall area, or the middle of a wide one, the pads standing below it or on either side. It is the same
## whatever the style, which draws in these places. `w` and `h` are the size of the area and `pads` whether the pads are
## shown. The result holds the scale `s` of the screen and its top left `ox`, `oy`, the `buttons` and the `cross` (nil
## without pads), and the arguments it was worked out for.
func computeLayout(w, h, pads)
    var L = {s: 1, ox: 0, oy: 0, buttons: [], cross: nil, w: w, h: h, padsShown: pads}
    var portrait = h > w * 1.1
    var s
    var lx
    var ly
    var rx
    var ry
    var px
    var py
    var kx
    var ky
    var u
    if pads and portrait then
        s = math.min(w / SCREEN.w, h * 0.66 / SCREEN.h)
        L.ox = math.floor((w - SCREEN.w * s) / 2)
        L.oy = math.floor(math.max((h * 0.68 - SCREEN.h * s) / 2, 0))
        var top = L.oy + SCREEN.h * s
        var rest = h - top
        u = math.min(w * 0.065, rest * 0.11)   ## below 0.119 of the room left, where B, the cross and START would overlap
        lx, ly = w * 0.27, top + rest * 0.45
        rx, ry = w * 0.72, top + rest * 0.45
        px, py = w * 0.5, top + rest * 0.88
        kx, ky = w * 0.86, top + rest * 0.88
    elseif pads then
        s = math.min(h / SCREEN.h, w / (SCREEN.w * 1.7))
        L.ox = math.floor((w - SCREEN.w * s) / 2)
        L.oy = math.floor((h - SCREEN.h * s) / 2)
        u = math.min(L.ox * 0.11, h * 0.1)
        lx, ly = L.ox / 2, h * 0.58
        rx, ry = w - L.ox / 2, h * 0.58
        px, py = w - L.ox / 2, h * 0.16
        kx, ky = L.ox / 2, h * 0.16
    else
        s = math.min(w / SCREEN.w, h / SCREEN.h)
        L.ox = math.floor((w - SCREEN.w * s) / 2)
        L.oy = math.floor((h - SCREEN.h * s) / 2)
    end
    L.s = s
    L.buttons = []
    L.cross = nil
    if pads then
        L.cross = {x: lx, y: ly, u: u}
        L.buttons = [
            padButton("up", lx, ly - 2 * u, 2 * u, 2 * u, 0.3 * u, nil),
            padButton("left", lx - 2 * u, ly, 2 * u, 2 * u, 0.3 * u, nil),
            padButton("right", lx + 2 * u, ly, 2 * u, 2 * u, 0.3 * u, nil),
            padButton("down", lx, ly + 2 * u, 2 * u, 2 * u, 0.3 * u, nil),
            {name: "b", x: rx - 1.7 * u, y: ry + 0.9 * u, r: 1.9 * u, text: "B"},
            {name: "a", x: rx + 1.7 * u, y: ry - 0.9 * u, r: 1.9 * u, text: "A"},
            padButton("start", px, py, u * 5, u * 1.6, u * 0.8, "START"),
            padButton("style", kx, ky, u * 4, u * 1.4, u * 0.7, "STYLE")
        ]
    end
    return L
end
