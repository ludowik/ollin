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

## How it looks: the four greens of the screen, the blocks, and where a few things sit on it.
global look = {
    screenW: 160,               ## the handheld's screen, in points
    screenH: 144,
    wellX: 16,
    titlePieces: [
        [Piece.I, 14, 48], [Piece.O, 54, 48], [Piece.T, 78, 48], [Piece.Z, 110, 44],
        [Piece.L, 22, 72], [Piece.J, 54, 76], [Piece.S, 86, 72]
    ],
    nextBox: {x: 108, y: 98, w: 48, h: 42},
    shade: [
        [0.608, 0.737, 0.059, 1],   ## the lightest green, the screen itself
        [0.545, 0.675, 0.059, 1],
        [0.188, 0.384, 0.188, 1],
        [0.059, 0.220, 0.059, 1]    ## the darkest
    ],
    frameInk: [0.043, 0.13, 0.043, 1],   ## around the screen
    padFill: [0.188, 0.384, 0.188, 1],
    padLit: [0.545, 0.675, 0.059, 1],
    padInk: [0.608, 0.737, 0.059, 1]
}

## How each piece's block is painted in its 8 by 8 points: rectangles {x, y, w, h, shade}, drawn in order. The
## shades are told apart by their pattern as well as by their darkness, as on the handheld.
look.blocks = []
look.blocks[Piece.I] = [[0, 0, 8, 8, 4], [1, 1, 6, 6, 1]]
for dy = 1, 6 do
    for dx = 1, 6 do
        if (dx + dy) % 2 == 0 then
            look.blocks[Piece.I].push([dx, dy, 1, 1, 3])
        end
    end
end
look.blocks[Piece.O] = [[0, 0, 8, 8, 4], [1, 1, 6, 6, 1]]
look.blocks[Piece.T] = [[0, 0, 8, 8, 4], [1, 1, 6, 6, 2], [3, 3, 2, 2, 4]]
look.blocks[Piece.S] = [[0, 0, 8, 8, 3], [1, 1, 6, 6, 4], [2, 2, 3, 3, 2]]
look.blocks[Piece.Z] = [[0, 0, 8, 8, 4], [1, 1, 6, 6, 1], [1, 1, 6, 2, 3]]
look.blocks[Piece.J] = [[0, 0, 8, 8, 4], [1, 1, 2, 2, 1]]
look.blocks[Piece.L] = [[0, 0, 8, 8, 4], [1, 1, 6, 6, 3], [1, 1, 6, 1, 1]]

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

func drawBlock(px, py, kind)
    for r in look.blocks[kind] do
        block(px + r[1], py + r[2], r[3], r[4], r[5])
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

## The brick wall at either side of the well.
func drawWall(x)
    for r = 0, ROWS - 1 do
        block(x, r * 8, 8, 8, 3)
        block(x, r * 8 + 7, 8, 1, 4)
        block(x + (r % 2 == 0 and 3 or 7), r * 8, 1, 7, 4)
    end
end

func drawPiece(kind, turn, px, py)
    for c in shapes[kind][turn] do
        drawBlock(px + c[1] * 8, py + c[2] * 8, kind)
    end
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
                    drawBlock(wx + c * 8, r * 8, v)
                end
            end
        end
    end
    if game.state == "play" then
        for c in shapes[game.kind][game.turn] do
            if game.y + c[2] >= 0 then
                drawBlock(wx + (game.x + c[1]) * 8, (game.y + c[2]) * 8, game.kind)
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

## A box of the panel holding a title and, under it, a number: the handheld writes the numbers as they are, with no
## zeros in front.
func panelBox(title, value, y, h)
    box(108, y, 48, h, 2)
    label(title, 132, y + 7, 8, 4)
    label("{value}", 132, y + h - 6, 8, 4)
end

func drawPanel()
    var edge = look.wellX + COLS * 8 + 8
    block(edge, 0, look.screenW - edge, look.screenH, 2)
    panelBox("SCORE", game.score, 6, 28)
    panelBox("LEVEL", game.level, 40, 24)
    panelBox("LINES", linesShown(), 68, 24)
    var nb = look.nextBox
    box(nb.x, nb.y, nb.w, nb.h, 2)
    if game.state <> "paused" then
        var x0, x1, y0, y1 = shapeBounds(game.next, 1)
        var w = (x1 - x0 + 1) * 8
        var h = (y1 - y0 + 1) * 8
        var cx = nb.x + (nb.w - w) / 2 - x0 * 8
        var cy = nb.y + (nb.h - h) / 2 - y0 * 8
        drawPiece(game.next, 1, cx, cy)
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
    block(0, 0, 8, ROWS * 8, 3)
    drawWall(8)
    drawWall(look.wellX + COLS * 8)
    block(look.wellX, 0, COLS * 8, ROWS * 8, 1)
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
