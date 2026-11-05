## The MODERN style of Tetris: a dark gradient, a well with a faint grid, blocks that are rounded and lit from above in
## the colour of their piece, and cards for the score, the level, the lines and the next piece. They stand exactly
## where the original's do and are as large (places.ol), and so are the pads; the text is in the font "sans". It shows
## what the original shows, no more: no ghost piece, and the well hidden in pause. See style_gb.ol for what a style is;
## every name of this file starts with `modern`.

import "rules.ol"
import "play.ol"
import "screens.ol"
import "modern_pure.ol"
import "places.ol"
import "../lib/draw.ol"

global modernLook = {
    skyTop: [0.090, 0.100, 0.215, 1],
    skyBottom: [0.028, 0.032, 0.078, 1],
    well: [0.018, 0.022, 0.056, 1],
    card: [0.105, 0.120, 0.250, 1],
    edge: [0.45, 0.55, 1.0, 0.22],
    ink: [0.94, 0.96, 1.0, 1],
    dim: [0.62, 0.67, 0.85, 1],
    accent: [0.36, 0.64, 1.0, 1],
    accentInk: [0.03, 0.05, 0.12, 1],
    logo: [5, 7, 2, 4, 1, 3],       ## the pieces whose colours spell TETRIS: Z, L, O, S, I, T
    frame: nil                      ## the last frame worked out, see modernNow
}

const MODERN_WHITE = [1, 1, 1, 1]
const MODERN_CURTAIN = [0.17, 0.19, 0.36, 1]   ## the rows that come down on a lost game

## The frame for the screen as the layout has put it: worked out again only when that changes.
func modernNow()
    var L = view.layout
    var f = modernLook.frame
    if f == nil or f.s <> L.s or f.ox <> L.ox or f.oy <> L.oy then
        f = modernFrame(L.s, L.ox, L.oy)
        modernLook.frame = f
    end
    return f
end

## The gradient over the whole canvas: bands of one colour, from the top colour to the bottom one.
func modernBackground()
    drawGradient(modernLook.skyTop, modernLook.skyBottom, 24)
end

## A rounded rectangle with a faint edge round it.
func modernPanel(x, y, w, h, radius, fill)
    fillC(modernLook.edge)
    graphics.rect(x - 1, y - 1, w + 2, h + 2, radius + 1)
    fillC(fill)
    graphics.rect(x, y, w, h, radius)
end

## A block of side c at (x, y): its shadow, the colour of the piece, and the light from above.
func modernBlock(x, y, c, kind)
    var col = MODERN_COLORS[kind]
    var g = math.max(1, math.floor(c * 0.07))
    var radius = c * 0.18
    fillC(MODERN_SHADOW[kind])
    graphics.rect(x, y, c, c, radius)
    fillC(col)
    graphics.rect(x + g, y + g, c - 2 * g, c - 2 * g, radius * 0.8)
    fillC(MODERN_LIGHT[kind], 0.45)
    graphics.rect(x + 2 * g, y + 2 * g, c - 4 * g, math.max(1, c * 0.2), radius * 0.5)
end

## A piece in its turn, its box starting at (x, y), cells of side c.
func modernPiece(kind, turn, x, y, c)
    for cell in shapes[kind][turn] do
        modernBlock(x + cell[1] * c, y + cell[2] * c, c, kind)
    end
end

func modernWell(f)
    var c = f.c
    var x = f.well.x
    var y = f.well.y
    modernPanel(x, y, f.well.w, f.well.h, c * 0.3, modernLook.well)
    fillC(MODERN_WHITE, 0.045)
    for i = 1, COLS - 1 do
        graphics.rect(x + i * c, y, 1, ROWS * c)
    end
    for j = 1, ROWS - 1 do
        graphics.rect(x, y + j * c, COLS * c, 1)
    end
    if game.state == "paused" then
        return
    end
    var flash = clearFlashOn()
    for row = 0, ROWS - 1 do
        for col = 0, COLS - 1 do
            var v = game.well[wellIdx(col, row)]
            if v <> 0 then
                modernBlock(x + col * c, y + row * c, c, v)
                if flash and game.clearing.contains(row) then
                    fillC(MODERN_WHITE, 0.85)
                    graphics.rect(x + col * c, y + row * c, c, c, c * 0.18)
                end
            end
        end
    end
    if game.state == "play" then
        for cell in shapes[game.kind][game.turn] do
            if game.y + cell[2] >= 0 then
                modernBlock(x + (game.x + cell[1]) * c, y + (game.y + cell[2]) * c, c, game.kind)
            end
        end
    end
    if game.state == "over" and not game.won then
        for i = 0, curtainRows() - 1 do
            for col = 0, COLS - 1 do
                fillC(MODERN_CURTAIN)
                graphics.rect(x + col * c + 1, y + (ROWS - 1 - i) * c + 1, c - 2, c - 2, c * 0.18)
            end
        end
    end
end

## A card of the panel: its title, and under it a number that is kept inside the card whatever its width. `c` is the
## size of a cell, which the sizes of the card follow (modernCardText).
func modernCard(r, c, title, value)
    var t = modernCardText(r, c)
    modernPanel(r.x, r.y, r.w, r.h, c * 0.6, modernLook.card)
    drawText(title, r.x + t.pad, t.titleY, t.titleSize, "left", "top", modernLook.dim)
    if value then
        var size = fitSize(value, t.valueSize, r.w - 2 * t.pad)
        drawText(value, r.x + r.w - t.pad, t.valueY, size, "right", "bottom", modernLook.ink)
    end
end

func modernCards(f)
    modernCard(f.score, f.c, "SCORE", "{game.score}")
    modernCard(f.level, f.c, "LEVEL", "{game.level}")
    modernCard(f.lines, f.c, "LINES", "{linesShown()}")
    modernCard(f.next, f.c, "NEXT", nil)
    if game.state <> "paused" then
        modernPiece(game.next, 1, f.gridX, f.gridY, f.c)
    end
end

## The words in the well: PAUSE, and the end of a game once the curtain is down.
func modernWellText(f)
    var c = f.c
    var cx = f.well.x + f.well.w / 2
    var cy = f.well.y + f.well.h / 2
    if game.state == "paused" then
        modernPanel(cx - COLS * c * 0.4, cy - c * 1.5, COLS * c * 0.8, c * 3, c * 0.4, modernLook.card)
        drawText("PAUSE", cx, cy, c * 1.3, "center", "center", modernLook.ink)
    elseif game.state == "over" and overDone() then
        modernPanel(cx - COLS * c * 0.43, cy - c * 3.6, COLS * c * 0.86, c * 7.2, c * 0.5, modernLook.card)
        drawText(game.won and "WELL DONE" or "GAME OVER", cx, cy - c * 2.3, c * 1.1, "center", "center", modernLook.ink)
        if game.newBest then
            drawText("NEW BEST", cx, cy - c * 0.5, c * 0.9, "center", "center", modernLook.accent)
        else
            drawText("BEST  {game.best}", cx, cy - c * 0.5, c * 0.8, "center", "center", modernLook.dim)
        end
        if blinkOn() then
            drawText("PUSH START", cx, cy + c * 2.3, c * 0.8, "center", "center", modernLook.ink)
        end
    end
end

func modernGame()
    modernBackground()
    var f = modernNow()
    modernWell(f)
    modernCards(f)
    modernWellText(f)
end

## ── The screens before the game ────────────────────────────────────────────────────────────────────

## TETRIS, each letter in the colour of a piece.
func modernLogo(it, m)
    var size = it.size * m.s * 1.05
    var pitch = size * 0.86
    for i = 1, len(it.text) do
        var col = MODERN_COLORS[modernLook.logo[i]]
        drawText(it.text.char(i), m.ox + it.x * m.s + (i - 3.5) * pitch, m.oy + it.y * m.s, size, "center", "center", col)
    end
end

func modernItem(it, m)
    if it.piece then
        modernPiece(it.piece, 1, m.ox + it.x * m.s, m.oy + it.y * m.s, 8 * m.s)
    elseif it.w then
        if it.lit then
            fillC(modernLook.accent)
            graphics.rect(m.ox + it.x * m.s, m.oy + it.y * m.s, it.w * m.s, it.h * m.s, it.h * m.s * 0.22)
        else
            modernPanel(m.ox + it.x * m.s, m.oy + it.y * m.s, it.w * m.s, it.h * m.s, it.h * m.s * 0.22, modernLook.card)
        end
        drawText(it.text, m.ox + (it.x + it.w / 2) * m.s, m.oy + (it.y + it.h / 2) * m.s, it.size * m.s * 1.2,
            "center", "center", it.lit and modernLook.accentInk or modernLook.ink)
    elseif it.logo then
        modernLogo(it, m)
    else
        drawText(it.text, m.ox + it.x * m.s, m.oy + it.y * m.s, it.size * m.s * 1.2, "center", "center",
            it.dim and modernLook.dim or modernLook.ink)
    end
end

func modernItems(items)
    modernBackground()
    var m = modernNow()   ## its scale and top left: the points of the screen of 160 by 144 that places.ol speaks in, in pixels
    modernPanel(m.ox + 4 * m.s, m.oy + 4 * m.s, 152 * m.s, 136 * m.s, 6 * m.s, modernLook.well)
    for it in items do
        modernItem(it, m)
    end
end

## The pads, from the very buttons that answer a touch: dark keys, lit while a finger is on them.
func modernPads()
    for b in view.layout.buttons do
        var lit = view.pads[b.name] == true
        var fill = lit and modernLook.accent or modernLook.card
        var ink = lit and modernLook.accentInk or modernLook.ink
        if b.r then
            fillC(modernLook.edge)
            graphics.circle(b.x, b.y, b.r + 1)
            fillC(fill)
            graphics.circle(b.x, b.y, b.r)
            drawText(b.text, b.x, b.y, b.r * 0.9, "center", "center", ink)
        else
            modernPanel(b.x - b.w / 2, b.y - b.h / 2, b.w, b.h, b.round * 1.4, fill)
            if b.text then
                drawText(b.text, b.x, b.y, b.h * 0.42, "center", "center", ink)
            else
                var k = b.w * 0.2
                var pts = {
                    up: [0, -k, -k, k, k, k], down: [0, k, -k, -k, k, -k],
                    left: [-k, 0, k, -k, k, k], right: [k, 0, -k, -k, -k, k]
                }[b.name]
                fillC(ink)
                graphics.polygon([b.x + pts[1], b.y + pts[2], b.x + pts[3], b.y + pts[4], b.x + pts[5], b.y + pts[6]])
            end
        end
    end
end

## What tetris.ol sees of this style.
global styleModern = {
    name: "MODERN",
    font: "sans",
    smooth: true,
    ground: [0.028, 0.032, 0.078, 1],
    game: modernGame,
    items: modernItems,
    pads: modernPads
}
