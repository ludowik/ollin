## Tetris, as the handheld of 1989 plays it: a well of 10 by 18, the seven pieces turning by the original
## Nintendo rotation (no wall kicks, no hold, no ghost, no hard drop), the score of 40, 100, 300 and 1200 times the
## level, a speed that grows with the level, and the folk tune of Type A. The screens are the handheld's: the title,
## the choice of A-TYPE (the level rises every ten lines) or B-TYPE (rubble to dig through, 25 lines to clear) and of
## the music, then the level, and for B-TYPE the height of the rubble.
##
## Left and right move a piece (held, they repeat after a short wait), down drops it faster and pays a point a row,
## X or up turns it clockwise and Z counter-clockwise. On the screens before the game the arrows choose, X or Enter
## confirms and Z goes back. Enter starts and pauses, M switches the music. On a touch screen the pads appear with
## the first touch: a cross, the two buttons A and B, and START.
##
## rules.ol holds the rules, sounds.ol the sound and play.ol the game itself, which runs on a clock of 60 steps a
## second whatever the speed of the screen, so that the counts of frames of the rules mean what they say; this file
## is what the player touches: the keyboard and the pads, and the picture. The picture is drawn in the 160 by 144
## points of the handheld's screen, scaled to fit the area (graphics.fitArea) and placed again whenever it is needed.

import "rules.ol"
import "sounds.ol"
import "play.ol"
import "../lib/draw.ol"

## How it looks: the four greens of the screen, and where a few things sit on it.
global look = {
    screenW: 160,               ## the handheld's screen, in points
    screenH: 144,
    wellX: 16,
    titlePieces: [
        [Piece.I, 14, 48], [Piece.O, 54, 48], [Piece.T, 78, 48], [Piece.Z, 110, 44],
        [Piece.L, 22, 72], [Piece.J, 54, 76], [Piece.S, 86, 72]
    ],
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

## The pictures are drawn as the handheld draws them, a point at a time, from rows of text: ' ' is the lightest green,
## '.' the next, '+' the next and '#' the darkest, and '_' leaves the point as it is.
func inkOf(ch)
    if ch == " " then
        return 1
    elseif ch == "." then
        return 2
    elseif ch == "+" then
        return 3
    elseif ch == "#" then
        return 4
    end
    return 0
end

## The rectangles {x, y, w, h, shade} that paint a picture: a run of one green is one rectangle, and the same run in
## the rows below makes it taller, so that a picture costs few rectangles.
func pictureRects(rows)
    var out = []
    var open = {}
    for j = 1, len(rows) do
        var row = rows[j]
        var n = len(row)
        var fresh = {}
        var i = 1
        while i <= n do
            var ch = row.char(i)
            var shade = inkOf(ch)
            var k = i
            while k < n and row.char(k + 1) == ch do
                k += 1
            end
            if shade > 0 then
                var key = "{i},{k},{shade}"
                var rect = open[key]
                if rect then
                    rect[4] += 1
                else
                    rect = [i - 1, j - 1, k - i + 1, 1, shade]
                    out.push(rect)
                end
                fresh[key] = rect
            end
            i = k + 1
        end
        open = fresh
    end
    return out
end

## The rows of a framed box: its four corners are the same `corner` picture turned over, and between them the frame is
## `rings`, one character a point from the outside in, with `inside` in the middle.
func boxRows(w, h, corner, rings, inside)
    var n = len(corner)
    var rows = []
    for j = 0, h - 1 do
        var jj = math.min(j, h - 1 - j)
        var row = ""
        for i = 0, w - 1 do
            var ii = math.min(i, w - 1 - i)
            var ch = inside
            if ii < n and jj < n then
                ch = corner[jj + 1].char(ii + 1)
            elseif math.min(ii, jj) < len(rings) then
                ch = rings.char(math.min(ii, jj) + 1)
            end
            row = row + ch
        end
        rows.push(row)
    end
    return rows
end

func borderOn(sides, bit)
    return (sides & bit) <> 0
end

## How each piece's block is painted in its 8 by 8 points. The shades are told apart by their pattern as well as by
## their darkness, as on the handheld. The long piece is a stipple that has a dark edge only where the piece ends:
## stipple[sides + 1] is it with the edges 1 left, 2 right, 4 top and 8 bottom.
look.dots = ["..+..+", "+.....", "...+.+", ".+....", ".....+", "+.+...", "....+.", ".+...."]
look.stipple = []
for sides = 0, 15 do
    var rows = []
    for j = 1, 8 do
        var row = ""
        for i = 1, 8 do
            var ch = "."
            if i > 1 and i < 8 then
                ch = look.dots[j].char(i - 1)
            end
            if (i == 1 and borderOn(sides, 1)) or (i == 8 and borderOn(sides, 2)) then
                ch = "#"
            end
            if (j == 1 and borderOn(sides, 4)) or (j == 8 and borderOn(sides, 8)) then
                ch = "#"
            end
            row = row + ch
        end
        rows.push(row)
    end
    look.stipple[sides + 1] = pictureRects(rows)
end
## The six cells the handheld shows of it, a bar standing (its top, a middle, its bottom) and a bar lying (its left end,
## a middle, its right end), with the dots exactly where it puts them.
look.stipple[8] = pictureRects([
    "########", "#...+..#", "#.+...+#", "#......#", "#+..+..#", "#.....+#", "#.+.+..#", "#......#"
])
look.stipple[4] = pictureRects([
    "#..+..+#", "#+.....#", "#...+.+#", "#.+....#", "#.....+#", "#+.+...#", "#....+.#", "#.+....#"
])
look.stipple[12] = pictureRects([
    "#.....+#", "#..+...#", "#+...+.#", "#..+...#", "#+....+#", "#...+..#", "#.+....#", "########"
])
look.stipple[14] = pictureRects([
    "########", "#.+..+..", "#.......", "#+..+.+.", "#.......", "#.+...+.", "#...+...", "########"
])
look.stipple[13] = pictureRects([
    "########", "+.+.+...", "......+.", "..+.....", "+....+..", "...+...+", ".+...+..", "########"
])
look.stipple[15] = pictureRects([
    "########", "+...+..#", "..+....#", ".....+.#", ".+.+...#", "......+#", "..+.+..#", "########"
])
look.blocks = []
look.blocks[Piece.I] = []
look.blocks[Piece.O] = pictureRects([
    "########", "#      #", "# #### #", "# #### #", "# #### #", "# #### #", "#      #", "########"
])
look.blocks[Piece.T] = pictureRects([
    "########", "#......#", "#.    .#", "#. ..#.#", "#. ..#.#", "#.####.#", "#......#", "########"
])
look.blocks[Piece.S] = pictureRects([
    "########", "#++++++#", "#+####+#", "#+#  #+#", "#+#  #+#", "#+####+#", "#++++++#", "########"
])
look.blocks[Piece.Z] = pictureRects([
    "########", "#......#", "#......#", "#..##..#", "#..##..#", "#......#", "#......#", "########"
])
look.blocks[Piece.J] = pictureRects([
    "########", "#++++++#", "#++++++#", "#++++++#", "#++++++#", "#++++++#", "#++++++#", "########"
])
look.blocks[Piece.L] = pictureRects([
    "########", "#++++++#", "#++  ++#", "#+    +#", "#+    +#", "#++  ++#", "#++++++#", "########"
])

## The handheld's letters and digits, 6 points wide and 6 high on a pitch of 8; '#' is ink, '_' is not.
look.font = {}
for g in [
    ["S", "_####_", "##____", "_####_", "___###", "#__###", "_####_"],
    ["C", "_####_", "##__##", "##____", "##____", "##__##", "_####_"],
    ["O", "_####_", "##__##", "##__##", "##__##", "##__##", "_####_"],
    ["R", "#####_", "##__##", "##__##", "#####_", "##_#__", "##__##"],
    ["E", "######", "##____", "#####_", "##____", "##____", "######"],
    ["L", "##____", "##____", "##____", "##____", "##____", "######"],
    ["V", "#___##", "#___##", "#___##", "#___##", "_#_##_", "__##__"],
    ["I", "_####_", "__##__", "__##__", "__##__", "__##__", "_####_"],
    ["N", "#___##", "##__##", "###_##", "#_####", "#__###", "#___##"],
    ["0", "_####_", "##__##", "##__##", "##__##", "##__##", "_####_"],
    ["1", "__##__", "_###__", "__##__", "__##__", "__##__", "_####_"],
    ["2", "_####_", "#__###", "___###", "_####_", "###___", "######"],
    ["3", "#####_", "___###", "_####_", "___###", "___###", "#####_"],
    ["4", "___##_", "__###_", "_#_##_", "#__##_", "######", "___##_"],
    ["5", "######", "##____", "#####_", "___###", "#__###", "_####_"],
    ["6", "_####_", "##____", "#####_", "##__##", "##__##", "_####_"],
    ["7", "######", "____##", "___##_", "__##__", "_##___", "_##___"],
    ["8", "_####_", "##__##", "_####_", "##__##", "##__##", "_####_"],
    ["9", "_####_", "#__###", "#__###", "_#####", "___###", "_####_"]
] do
    look.font[g[1]] = pictureRects([g[2], g[3], g[4], g[5], g[6], g[7]])
end

func addPicture(art, rects, ox, oy)
    for r in rects do
        art.push([ox + r[1], oy + r[2], r[3], r[4], r[5]])
    end
end

## The rectangles of a text in that font.
func textRects(str)
    var out = []
    for i = 1, len(str) do
        var glyph = look.font[str.char(i)]
        if glyph then
            addPicture(out, glyph, (i - 1) * 8, 0)
        end
    end
    return out
end

## What the screen of a game shows whatever happens: the wall of bricks, the well, and the panel with its frames and
## its three words. The panel is a dark ground with a light line at its edge, boxes framed in a light and a mid-dark
## line, a ribbon of the same behind the score, and the box of the next piece, framed in four greens.
look.wallTile = pictureRects(["_# __# _", "_#___#__", "########", " __# __#", "___#___#", "########"])
look.panelCorner = ["_   ", "  ++", " ++ ", " +  "]
look.nextCorner = ["__...", "_.   ", ".  .+", ". .+#", ". +# "]

func addWall(art, x)
    art.push([x, 0, 8, 144, 2])
    for t = 0, 23 do
        addPicture(art, look.wallTile, x, t * 6)
    end
end

func buildArt()
    var art = []
    art.push([0, 0, 160, 144, 4])
    art.push([7, 0, 1, 144, 1])
    addWall(art, 8)
    art.push([16, 0, 80, 144, 1])
    addWall(art, 96)
    art.push([104, 0, 1, 144, 1])
    art.push([104, 13, 56, 1, 1])
    art.push([105, 14, 55, 7, 3])
    art.push([104, 21, 56, 14, 1])
    art.push([105, 22, 55, 1, 3])
    art.push([105, 33, 55, 1, 3])
    addPicture(art, pictureRects(boxRows(46, 14, look.panelCorner, " +", " ")), 109, 5)
    addPicture(art, pictureRects(boxRows(46, 22, look.panelCorner, " +", " ")), 109, 45)
    addPicture(art, pictureRects(boxRows(46, 22, look.panelCorner, " +", " ")), 109, 69)
    addPicture(art, pictureRects(boxRows(42, 42, look.nextCorner, ". +#", " ")), 115, 99)
    addPicture(art, textRects("SCORE"), 113, 9)
    addPicture(art, textRects("LEVEL"), 113, 49)
    addPicture(art, textRects("LINES"), 113, 73)
    return art
end
look.art = buildArt()

## What belongs to the screen and the fingers, not to the game.
global view = {
    pads: {},                   ## the pad buttons down at the last frame
    pointer: false,             ## a finger or the mouse was down at the last frame
    touchSeen: false,           ## a finger has touched the screen, so the pads are shown
    layout: {s: 1, ox: 0, oy: 0, buttons: [], cross: nil, w: 0, h: 0, padsShown: false}
}

## The pad buttons that start events of the game when they go down, and the events (A turns a piece and confirms).
const PAD_EVENTS = {
    a: ["cw", "confirm"], b: ["ccw"], start: ["start"], left: ["left"], right: ["right"], up: ["up"], down: ["down"]
}

## ── Input ──────────────────────────────────────────────────────────────────────────────────────────

func keyboard.keypressed(key)
    var p = game.pressed
    if key == "x" then
        p.cw = true
        p.confirm = true
    elseif key == "up" or key == "w" then
        p.cw = true
        p.up = true
    elseif key == "down" or key == "s" then
        p.down = true
    elseif key == "z" then
        p.ccw = true
    elseif key == "return" or key == "p" or key == "escape" or (key == "space" and game.state <> "play") then
        p.start = true
    elseif key == "left" or key == "a" then
        p.left = true
    elseif key == "right" or key == "d" then
        p.right = true
    elseif key == "m" then
        setMusic(not music.on)
    end
end

## Where the fingers (or the mouse) are now.
func pointers()
    if touch.count() > 0 then
        return touch.points()
    end
    if mouse.isDown() then
        var mx, my = mouse.position()
        return [{id: 0, x: mx, y: my}]
    end
    return []
end

func inButton(b, px, py)
    if b.r <> nil then
        var dx = px - b.x
        var dy = py - b.y
        return dx * dx + dy * dy <= b.r * b.r
    end
    return math.abs(px - b.x) <= b.w / 2 and math.abs(py - b.y) <= b.h / 2
end

## Reads the keyboard, the pads and the taps once a frame. A direction and down are HELD, tested by the steps; a
## turn, START and a tap are EVENTS, kept until a step uses them.
func readInput()
    var held = game.held
    var pts = pointers()
    if touch.count() > 0 then
        view.touchSeen = true
    end
    var pads = {}
    var tap = len(pts) > 0 and not view.pointer
    for p in pts do
        for b in view.layout.buttons do
            if inButton(b, p.x, p.y) then
                pads[b.name] = true
            end
        end
    end
    var before = view.pads
    var ev = game.pressed
    for name, events in PAD_EVENTS do
        if pads[name] and not before[name] then
            for event in events do
                ev[event] = true
            end
        end
    end
    if tap and not running() and len(pads) == 0 then
        ev.start = true
    end
    view.pointer = len(pts) > 0
    view.pads = pads
    held.left = keyboard.isDown("left") or keyboard.isDown("a") or pads.left == true
    held.right = keyboard.isDown("right") or keyboard.isDown("d") or pads.right == true
    held.down = keyboard.isDown("down") or keyboard.isDown("s") or pads.down == true
end

## ── Layout ─────────────────────────────────────────────────────────────────────────────────────────

## A button of the pads: the area that answers a touch, and how it is drawn (`round` is the radius of its corners, and
## `text` the letters on it).
func padButton(name, x, y, w, h, round, text)
    return {name: name, x: x, y: y, w: w, h: h, round: round, text: text}
end

## Where the screen and the pads go. The screen keeps the handheld's proportions; with the pads shown it takes the
## top of a tall area, or the middle of a wide one, the pads standing below it or on either side. It is worked out
## again only when the area or the pads shown change.
func layoutCompute()
    var L = view.layout
    var pads = view.touchSeen
    if L.w == W and L.h == H and L.padsShown == pads then
        return
    end
    L.w = W
    L.h = H
    L.padsShown = pads
    var portrait = H > W * 1.1
    var s
    var lx
    var ly
    var rx
    var ry
    var px
    var py
    var u
    if pads and portrait then
        s = math.min(W / look.screenW, H * 0.66 / look.screenH)
        L.ox = math.floor((W - look.screenW * s) / 2)
        L.oy = math.floor(math.max((H * 0.68 - look.screenH * s) / 2, 0))
        var top = L.oy + look.screenH * s
        var rest = H - top
        u = math.min(W * 0.065, rest * 0.14)
        lx, ly = W * 0.27, top + rest * 0.45
        rx, ry = W * 0.72, top + rest * 0.45
        px, py = W * 0.5, top + rest * 0.88
    elseif pads then
        s = math.min(H / look.screenH, W / (look.screenW * 1.7))
        L.ox = math.floor((W - look.screenW * s) / 2)
        L.oy = math.floor((H - look.screenH * s) / 2)
        u = math.min(L.ox * 0.11, H * 0.1)
        lx, ly = L.ox / 2, H * 0.58
        rx, ry = W - L.ox / 2, H * 0.58
        px, py = W - L.ox / 2, H * 0.16
    else
        s = math.min(W / look.screenW, H / look.screenH)
        L.ox = math.floor((W - look.screenW * s) / 2)
        L.oy = math.floor((H - look.screenH * s) / 2)
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
            padButton("start", px, py, u * 5, u * 1.6, u * 0.8, "START")
        ]
    end
end

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

func hasCell(cells, x, y)
    for c in cells do
        if c[1] == x and c[2] == y then
            return true
        end
    end
    return false
end

## The edges of a cell of the long piece: those with no cell of the piece beside them.
func cellSides(cells, c)
    var sides = 0
    if not hasCell(cells, c[1] - 1, c[2]) then
        sides += 1
    end
    if not hasCell(cells, c[1] + 1, c[2]) then
        sides += 2
    end
    if not hasCell(cells, c[1], c[2] - 1) then
        sides += 4
    end
    if not hasCell(cells, c[1], c[2] + 1) then
        sides += 8
    end
    return sides
end

func drawPiece(kind, turn, px, py)
    var cells = shapes[kind][turn]
    for c in cells do
        drawBlock(px + c[1] * 8, py + c[2] * 8, kind, kind == Piece.I and cellSides(cells, c) or 0)
    end
end

func isLong(c, r)
    return c >= 0 and c < COLS and r >= 0 and r < ROWS and game.well[wellIdx(c, r)] == Piece.I
end

## The edges of a cell of the long piece in the well: those with no other such cell beside them.
func wellSides(c, r)
    var sides = 0
    if not isLong(c - 1, r) then
        sides += 1
    end
    if not isLong(c + 1, r) then
        sides += 2
    end
    if not isLong(c, r - 1) then
        sides += 4
    end
    if not isLong(c, r + 1) then
        sides += 8
    end
    return sides
end

func drawWell()
    var wx = look.wellX
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
            block(look.wellX + c * 8, r * 8, 8, 8, (c + r) % 2 == 0 and 3 or 4)
        end
    end
end

## A number on the panel, with its last digit in the slot (a place of 8 points from x = 113) and its top at y.
func drawNumber(n, slot, y)
    var str = "{n}"
    var count = len(str)
    for i = 1, count do
        var glyph = look.font[str.char(i)]
        drawRects(glyph, 113 + 8 * (slot - count + i), y)
    end
end

## What changes on the panel: the numbers, with no zeros in front as on the handheld, and the next piece in its box.
func drawPanel()
    drawNumber(game.score, 4, 25)
    drawNumber(game.level, 3, 57)
    drawNumber(linesShown(), 3, 81)
    if game.state <> "paused" then
        drawPiece(game.next, 1, 120, 104)
    end
end

## The words in the well: PAUSE, and GAME OVER once the curtain is down.
func drawWellText()
    var cx = look.wellX + COLS * 4
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

func drawGame()
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

## A cell of a choice: dark with light ink when it is the one chosen, a plain box otherwise. The chosen one of the
## line the arrows are on blinks.
func choice(str, x, y, w, h, size, chosen, focused)
    var on = chosen and (not focused or game.frame % 40 < 28)
    if on then
        block(x, y, w, h, 4)
    else
        box(x, y, w, h)
    end
    label(str, x + w / 2, y + h / 2, size, on and 1 or 4)
end

func drawScreenFrame()
    block(0, 0, look.screenW, look.screenH, 1)
    box(4, 4, 152, 136)
end

## The first screen: the name, and the pieces, until START.
func drawTitle()
    drawScreenFrame()
    label("TETRIS", 80, 30, 24, 4)
    for item in look.titlePieces do
        drawPiece(item[1], 1, item[2], item[3] + 4)
    end
    if game.frame % 60 < 40 then
        label("PUSH START", 80, 124, 8, 4)
    end
end

## The second screen: the type of game, and the music.
func drawMenu()
    drawScreenFrame()
    label("GAME TYPE", 80, 20, 8, 4)
    var onType = game.focus == "type"
    choice("A-TYPE", 18, 30, 60, 28, 8, game.type == "A", onType)
    choice("B-TYPE", 82, 30, 60, 28, 8, game.type == "B", onType)
    label("MUSIC", 80, 78, 8, 4)
    var onMusic = game.focus == "music"
    choice("MUSIC-A", 18, 88, 60, 20, 8, music.on, onMusic)
    choice("OFF", 82, 88, 60, 20, 8, not music.on, onMusic)
    if game.frame % 60 < 40 then
        label("PUSH START", 80, 124, 8, 4)
    end
end

## The third screen: the level the game begins at, and for a B game the height of its rubble.
func drawLevelScreen()
    drawScreenFrame()
    label(game.type + "-TYPE", 80, 16, 10, 4)
    label("LEVEL", 80, 32, 8, 4)
    var onLevel = game.focus == "level"
    for i = 0, config.maxStartLevel do
        choice("{i}", 20 + i % 5 * 24, 40 + i // 5 * 18, 20, 14, 8, i == game.startLevel, onLevel)
    end
    if game.type == "B" then
        label("HEIGHT", 80, 88, 8, 4)
        for i = 0, config.maxHeight do
            choice("{i}", 12 + i * 22, 96, 18, 14, 8, i == game.height, not onLevel)
        end
    end
    label("HIGH {game.best:06d}", 80, 124, 8, 3)
end

## The ink of a pad button: lit while a finger is on it.
func padFill(name)
    return view.pads[name] == true and look.padLit or look.padFill
end

## The cross, the two buttons and START, drawn over the area outside the screen from the very buttons that answer a
## touch.
func drawPads()
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

## ── Engine entry points ────────────────────────────────────────────────────────────────────────────

func setup()
    graphics.canvas(W, H, "Tetris")
    graphics.fitArea()
    graphics.antialias(false)
    gameInit()
    layoutCompute()
end

func update(dt)
    readInput()
    layoutCompute()
    advance(dt)
end

func draw()
    graphics.font("pixel")
    graphics.noStroke()
    graphics.clear(look.frameInk[1], look.frameInk[2], look.frameInk[3])
    if game.state == "title" then
        drawTitle()
    elseif game.state == "menu" then
        drawMenu()
    elseif game.state == "level" then
        drawLevelScreen()
    else
        drawGame()
    end
    if view.touchSeen then
        drawPads()
    end
end
