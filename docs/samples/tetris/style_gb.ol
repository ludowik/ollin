## The ORIGINAL style of Tetris: the screen of the handheld of 1989, drawn from its own picture, a point at a time,
## in its four greens (see pictures.ol), on a screen of 160 by 144 points that the layout scales to fit the area.
## The style is a map of what tetris.ol asks of a style: `game`, `title`, `menu`, `level` and `pads` draw the screens and
## the pads over the state of the game, which they only read. Every name of this file is global, as in any module:
## the ones of this style are the ones it has always had, and the other style's start with `modern`.

import "rules.ol"
import "play.ol"
import "pictures.ol"
import "screens.ol"
import "places.ol"
import "../lib/draw.ol"

## How it looks: the four greens of the screen, and the ink of the pads.
global look = {
    shade: [
        [0.890, 0.973, 0.835, 1],   ## the lightest green, the screen itself
        [0.612, 0.757, 0.643, 1],
        [0.349, 0.490, 0.424, 1],
        [0.102, 0.231, 0.247, 1]    ## the darkest
    ],
    frameInk: [0.102, 0.231, 0.247, 1],   ## around the screen
    padFill: [0.349, 0.490, 0.424, 1],
    padLit: [0.612, 0.757, 0.643, 1],
    padInk: [0.890, 0.973, 0.835, 1]
}

## ── Pictures ───────────────────────────────────────────────────────────────────────────────────────

## The pictures of pictures.ol, as the rectangles that paint them. The long piece has a block for each of its 16 sets of
## edges (look.stipple[sides + 1], the sides being 1 left, 2 right, 4 top and 8 bottom), the others one block each.
look.stipple = []
for sides = 0, 15 do
    look.stipple[sides + 1] = pictureRects(STIPPLE_ROWS["{sides}"] or stippleRows(STIPPLE_DOTS, sides))
end
look.blocks = []
look.blocks[Piece.I] = []
look.blocks[Piece.O] = pictureRects(BLOCK_ROWS.O)
look.blocks[Piece.T] = pictureRects(BLOCK_ROWS.T)
look.blocks[Piece.S] = pictureRects(BLOCK_ROWS.S)
look.blocks[Piece.Z] = pictureRects(BLOCK_ROWS.Z)
look.blocks[Piece.J] = pictureRects(BLOCK_ROWS.J)
look.blocks[Piece.L] = pictureRects(BLOCK_ROWS.L)
look.font = {}
for ch, rows in FONT_ROWS do
    look.font[ch] = pictureRects(rows)
end
look.art = screenArt(look.font)

## ── Drawing ────────────────────────────────────────────────────────────────────────────────────────

## A rectangle given in points of the handheld's screen, in one of its four greens. Its edges are rounded down to
## whole pixels, so that two neighbours always meet with no seam between them at any scale.
func block(x, y, w, h, shade)
    var L = view.layout
    var x0 = math.floor(L.ox + x * L.s)
    var y0 = math.floor(L.oy + y * L.s)
    fillC(look.shade[shade])
    graphics.rect(x0, y0, math.floor(L.ox + (x + w) * L.s) - x0, math.floor(L.oy + (y + h) * L.s) - y0)
end

## A text at a point of the screen, `size` points high, in one of the greens.
func label(str, x, y, size, shade)
    var L = view.layout
    drawText(str, L.ox + x * L.s, L.oy + y * L.s, size * L.s, "center", "center", look.shade[shade])
end

func drawRects(rects, ox, oy)
    for r in rects do
        block(ox + r[1], oy + r[2], r[3], r[4], r[5])
    end
end

## A block of a piece at a point of the screen. The long piece takes `sides`, the edges it has (see look.stipple).
func drawBlock(px, py, kind, sides = 0)
    if kind == Piece.I then
        drawRects(look.stipple[sides + 1], px, py)
    else
        drawRects(look.blocks[kind], px, py)
    end
end

## A frame of one dark point round a lighter inside, its four corners rounded off in the green `outside` it stands on.
func box(x, y, w, h, outside = 1)
    block(x, y, w, h, 4)
    block(x + 1, y + 1, w - 2, h - 2, 1)
    block(x, y, 1, 1, outside)
    block(x + w - 1, y, 1, 1, outside)
    block(x, y + h - 1, 1, 1, outside)
    block(x + w - 1, y + h - 1, 1, 1, outside)
end

## The edges of a cell of the long piece (1 left, 2 right, 4 top, 8 bottom): those with no cell of that piece beside
## them, `there(x, y)` telling whether one is at a place.
func edgeSides(x, y, there)
    var sides = 0
    if not there(x - 1, y) then
        sides += 1
    end
    if not there(x + 1, y) then
        sides += 2
    end
    if not there(x, y - 1) then
        sides += 4
    end
    if not there(x, y + 1) then
        sides += 8
    end
    return sides
end

func cellSides(cells, c)
    return edgeSides(c[1], c[2], func(x, y)
        for other in cells do
            if other[1] == x and other[2] == y then
                return true
            end
        end
        return false
    end)
end

func drawPiece(kind, turn, px, py)
    var cells = shapes[kind][turn]
    for c in cells do
        drawBlock(px + c[1] * 8, py + c[2] * 8, kind, kind == Piece.I and cellSides(cells, c) or 0)
    end
end

func wellSides(c, r)
    return edgeSides(c, r, func(x, y)
        return x >= 0 and x < COLS and y >= 0 and y < ROWS and game.well[wellIdx(x, y)] == Piece.I
    end)
end

func drawWell()
    var wx = WELL.x
    var flash = game.state == "clearing" and (config.clearFrames - game.wait) // config.clearFlash % 2 == 1
    for r = 0, ROWS - 1 do
        for c = 0, COLS - 1 do
            var v = game.well[wellIdx(c, r)]
            if v <> 0 then
                if game.clearing.contains(r) then
                    block(wx + c * 8, r * 8, 8, 8, flash and 1 or 4)
                else
                    drawBlock(wx + c * 8, r * 8, v, v == Piece.I and wellSides(c, r) or 0)
                end
            end
        end
    end
    if game.state == "play" then
        var cells = shapes[game.kind][game.turn]
        for c in cells do
            if game.y + c[2] >= 0 then
                drawBlock(wx + (game.x + c[1]) * 8, (game.y + c[2]) * 8, game.kind,
                    game.kind == Piece.I and cellSides(cells, c) or 0)
            end
        end
    end
end

## The curtain that falls over a lost game, row by row from the bottom.
func drawCurtain()
    for i = 0, curtainRows() - 1 do
        var r = ROWS - 1 - i
        for c = 0, COLS - 1 do
            block(WELL.x + c * 8, r * 8, 8, 8, (c + r) % 2 == 0 and 3 or 4)
        end
    end
end

## A number on the panel, with its last digit in the slot (a place of 8 points, the first 4 points in from the cards) and
## its top at y.
func drawNumber(n, slot, y)
    var str = "{n}"
    var count = len(str)
    for i = 1, count do
        var glyph = look.font[str.char(i)]
        drawRects(glyph, SCORE_CARD.x + 4 + 8 * (slot - count + i), y)
    end
end

## What changes on the panel: the numbers, with no zeros in front as on the handheld, and the next piece in its box.
func drawPanel()
    drawNumber(game.score, 4, SCORE_CARD.y + 20)
    drawNumber(game.level, 3, LEVEL_CARD.y + 12)
    drawNumber(linesShown(), 3, LINES_CARD.y + 12)
    if game.state <> "paused" then
        drawPiece(game.next, 1, NEXT_GRID.x, NEXT_GRID.y)
    end
end

## The words in the well: PAUSE, and GAME OVER once the curtain is down.
func drawWellText()
    var cx = WELL.x + WELL.w / 2
    if game.state == "paused" then
        box(cx - 28, 60, 56, 24)
        label("PAUSE", cx, 72, 10, 4)
    elseif game.state == "over" and overDone() then
        box(cx - 32, 44, 64, 56)
        label(game.won and "WELL" or "GAME", cx, 50, 10, 4)
        label(game.won and "DONE" or "OVER", cx, 62, 10, 4)
        if game.newBest then
            label("NEW BEST", cx, 77, 8, 3)
        else
            label("BEST", cx, 77, 8, 3)
            label("{game.best:06d}", cx, 87, 8, 3)
        end
        if game.frame % 60 < 40 then
            label("PUSH START", cx, 91, 8, 4)
        end
    end
end

func gbGame()
    drawRects(look.art, 0, 0)
    if game.state <> "paused" then
        drawWell()
    end
    if game.state == "over" and not game.won then
        drawCurtain()
    end
    drawPanel()
    drawWellText()
end

## A choice: dark with light ink when it is on, a plain box otherwise.
func choice(it)
    if it.lit then
        block(it.x, it.y, it.w, it.h, 4)
    else
        box(it.x, it.y, it.w, it.h)
    end
    label(it.text, it.x + it.w / 2, it.y + it.h / 2, it.size, it.lit and 1 or 4)
end

func drawScreenFrame()
    block(0, 0, SCREEN.w, SCREEN.h, 1)
    box(4, 4, 152, 136)
end

## One of the screens before the game: its frame and its items (see screens.ol).
func drawItems(items)
    drawScreenFrame()
    for it in items do
        if it.piece then
            drawPiece(it.piece, 1, it.x, it.y)
        elseif it.w then
            choice(it)
        else
            label(it.text, it.x, it.y, it.size, it.dim and 3 or 4)
        end
    end
end

func gbTitle()
    drawItems(titleItems(view.hint))
end

func gbMenu()
    drawItems(menuItems(view.hint))
end

func gbLevel()
    drawItems(levelItems())
end

## The ink of a pad button: lit while a finger is on it.
func padFill(name)
    return view.pads[name] == true and look.padLit or look.padFill
end

## The cross, the two buttons and START, drawn over the area outside the screen from the very buttons that answer a
## touch.
func gbPads()
    var c = view.layout.cross
    fillC(look.padFill)
    graphics.rect(c.x - c.u, c.y - c.u, 2 * c.u, 2 * c.u)
    for b in view.layout.buttons do
        fillC(padFill(b.name))
        if b.r then
            graphics.circle(b.x, b.y, b.r)
            drawText(b.text, b.x, b.y, b.r * 0.84, "center", "center", look.padInk)
        else
            graphics.rect(b.x - b.w / 2, b.y - b.h / 2, b.w, b.h, b.round)
            if b.text then
                drawText(b.text, b.x, b.y, b.h * 0.5, "center", "center", look.padInk)
            end
        end
    end
end

## What tetris.ol sees of this style.
global styleGb = {
    name: "ORIGINAL",
    font: "pixel",
    smooth: false,                               ## crisp points: no smoothing of the picture
    ground: look.frameInk,
    game: gbGame,
    title: gbTitle,
    menu: gbMenu,
    level: gbLevel,
    pads: gbPads
}
