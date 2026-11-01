## Tetris, as the handheld of 1989 plays it: a well of 10 by 18, the seven pieces turning by the original
## Nintendo rotation (no wall kicks, no hold, no ghost, no hard drop), the score of 40, 100, 300 and 1200 times the
## level, a speed that grows every ten lines, and the folk tune of Type A.
##
## Left and right move a piece (held, they repeat after a short wait), down drops it faster and pays a point a row,
## X or up turns it clockwise and Z counter-clockwise. Enter starts and pauses, M switches the music. On a touch
## screen the pads appear with the first touch: a cross, the two buttons A and B, and START.
##
## rules.ol holds the rules, sounds.ol the sound and play.ol the game itself, which runs on a clock of 60 steps a
## second whatever the speed of the screen, so that the counts of frames of the rules mean what they say; this file
## is what the player touches: the keyboard and the pads, and the picture. The picture is drawn in the 160 by 144
## points of the handheld's screen, scaled to fit the area (graphics.fitArea) and placed again whenever it is needed.

import "play.ol"
import "../lib/draw.ol"

## How it looks: the four greens of the screen, the blocks, and where a few things sit on it.
global look = {
    screenW: 160,               ## the handheld's screen, in points
    screenH: 144,
    wellX: 16,
    nextBox: {x: 108, y: 98, w: 48, h: 40},
    musicHit: {x: 36, y: 114, w: 88, h: 12},   ## where a tap switches the music on the title screen
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
look.blocks[Piece.I] = [[0, 0, 8, 8, 4], [1, 1, 6, 6, 1], [2, 2, 4, 4, 4]]
look.blocks[Piece.O] = [[0, 0, 8, 8, 4], [1, 1, 6, 6, 3], [2, 2, 2, 2, 1]]
look.blocks[Piece.T] = [[0, 0, 8, 8, 4], [1, 1, 6, 6, 2], [3, 3, 2, 2, 4]]
look.blocks[Piece.S] = [[0, 0, 8, 8, 3], [1, 1, 6, 6, 4], [2, 2, 3, 3, 2]]
look.blocks[Piece.Z] = [[0, 0, 8, 8, 4], [1, 1, 6, 6, 1], [1, 1, 6, 2, 3]]
look.blocks[Piece.J] = [[0, 0, 8, 8, 4], [1, 1, 2, 2, 1]]
look.blocks[Piece.L] = [[0, 0, 8, 8, 4], [1, 1, 6, 6, 3], [1, 1, 6, 1, 1]]

## What belongs to the screen and the fingers, not to the game.
global view = {
    pads: {},                   ## the pad buttons down now, and a step ago
    padsBefore: {},
    pointer: false,             ## a finger or the mouse was down at the last frame
    touchSeen: false,           ## a finger has touched the screen, so the pads are shown
    layout: {s: 1, ox: 0, oy: 0, buttons: [], left: nil, right: nil, pill: nil}
}

## ── Input ──────────────────────────────────────────────────────────────────────────────────────────

func keyboard.keypressed(key)
    var p = game.pressed
    if key == "x" or key == "up" or key == "w" then
        p.cw = true
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

func inScreenRect(r, px, py)
    var L = view.layout
    var x = L.ox + r.x * L.s
    var y = L.oy + r.y * L.s
    return px >= x and px <= x + r.w * L.s and py >= y and py <= y + r.h * L.s
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
    var before = view.padsBefore
    var ev = game.pressed
    if pads.a and not before.a then
        ev.cw = true
    end
    if pads.b and not before.b then
        ev.ccw = true
    end
    if pads.start and not before.start then
        ev.start = true
    end
    if pads.left and not before.left then
        ev.left = true
    end
    if pads.right and not before.right then
        ev.right = true
    end
    if tap and (game.state == "title" or game.state == "paused" or game.state == "over") and len(pads) == 0 then
        if game.state == "title" and len(pts) > 0 and inScreenRect(look.musicHit, pts[1].x, pts[1].y) then
            setMusic(not music.on)
        else
            ev.start = true
        end
    end
    view.pointer = len(pts) > 0
    view.padsBefore = pads
    view.pads = pads
    held.left = keyboard.isDown("left") or keyboard.isDown("a") or pads.left == true
    held.right = keyboard.isDown("right") or keyboard.isDown("d") or pads.right == true
    held.down = keyboard.isDown("down") or keyboard.isDown("s") or pads.down == true
end

## ── Layout ─────────────────────────────────────────────────────────────────────────────────────────

## Where the screen and the pads go. The screen keeps the handheld's proportions; with the pads shown it takes the
## top of a tall area, or the middle of a wide one, the pads standing below it or on either side.
func layoutCompute()
    var L = view.layout
    var pads = view.touchSeen
    var portrait = H > W * 1.1
    var s
    L.buttons = []
    if pads and portrait then
        s = math.min(W / look.screenW, H * 0.66 / look.screenH)
        L.ox = math.floor((W - look.screenW * s) / 2)
        L.oy = math.floor(math.max((H * 0.68 - look.screenH * s) / 2, 0))
        var top = L.oy + look.screenH * s
        var rest = H - top
        var u = math.min(W * 0.065, rest * 0.14)
        L.left = {x: W * 0.27, y: top + rest * 0.45, u: u}
        L.right = {x: W * 0.72, y: top + rest * 0.45, u: u}
        L.pill = {x: W * 0.5, y: top + rest * 0.88, w: u * 5, h: u * 1.6}
    elseif pads then
        s = math.min(H / look.screenH, W / (look.screenW * 1.7))
        L.ox = math.floor((W - look.screenW * s) / 2)
        L.oy = math.floor((H - look.screenH * s) / 2)
        var u = math.min(L.ox * 0.11, H * 0.1)
        L.left = {x: L.ox / 2, y: H * 0.58, u: u}
        L.right = {x: W - L.ox / 2, y: H * 0.58, u: u}
        L.pill = {x: W - L.ox / 2, y: H * 0.16, w: u * 5, h: u * 1.6}
    else
        s = math.min(W / look.screenW, H / look.screenH)
        L.ox = math.floor((W - look.screenW * s) / 2)
        L.oy = math.floor((H - look.screenH * s) / 2)
        L.left = nil
        L.right = nil
        L.pill = nil
    end
    L.s = s
    if pads then
        var l = L.left
        var r = L.right
        L.buttons = [
            {name: "up", x: l.x, y: l.y - 2 * l.u, w: 2 * l.u, h: 2 * l.u},
            {name: "left", x: l.x - 2 * l.u, y: l.y, w: 2 * l.u, h: 2 * l.u},
            {name: "right", x: l.x + 2 * l.u, y: l.y, w: 2 * l.u, h: 2 * l.u},
            {name: "down", x: l.x, y: l.y + 2 * l.u, w: 2 * l.u, h: 2 * l.u},
            {name: "b", x: r.x - 1.7 * r.u, y: r.y + 0.9 * r.u, r: 1.9 * r.u},
            {name: "a", x: r.x + 1.7 * r.u, y: r.y - 0.9 * r.u, r: 1.9 * r.u},
            {name: "start", x: L.pill.x, y: L.pill.y, w: L.pill.w, h: L.pill.h}
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
func label(str, x, y, size, h, shade)
    var L = view.layout
    drawText(str, L.ox + x * L.s, L.oy + y * L.s, size * L.s, h, "center", look.shade[shade])
end

func drawBlock(px, py, kind)
    for r in look.blocks[kind] do
        block(px + r[1], py + r[2], r[3], r[4], r[5])
    end
end

## A frame of one dark point round a lighter inside.
func box(x, y, w, h)
    block(x, y, w, h, 4)
    block(x + 1, y + 1, w - 2, h - 2, 1)
end

## The brick wall at either side of the well.
func drawWall(x, rows)
    for r = 0, rows - 1 do
        block(x, r * 8, 8, 8, 3)
        block(x, r * 8 + 7, 8, 1, 4)
        block(x + (r % 2 == 0 and 3 or 7), r * 8, 1, 7, 4)
    end
end

func drawPiece(kind, turn, px, py)
    for c in shapes.turns[kind][turn] do
        drawBlock(px + c[1] * 8, py + c[2] * 8, kind)
    end
end

func drawWell()
    var wx = look.wellX
    var flash = game.state == "clearing" and (config.clearFrames - game.wait) // config.clearFlash % 2 == 1
    var rowsClearing = {}
    for r in game.clearing do
        rowsClearing[r] = true
    end
    for r = 0, ROWS - 1 do
        for c = 0, COLS - 1 do
            var v = game.well[wellIdx(c, r)]
            if v <> 0 then
                if rowsClearing[r] then
                    block(wx + c * 8, r * 8, 8, 8, flash and 1 or 4)
                else
                    drawBlock(wx + c * 8, r * 8, v)
                end
            end
        end
    end
    if game.kind <> 0 and (game.state == "play") then
        for c in shapes.turns[game.kind][game.turn] do
            if game.y + c[2] >= 0 then
                drawBlock(wx + (game.x + c[1]) * 8, (game.y + c[2]) * 8, game.kind)
            end
        end
    end
end

## The curtain that falls over a lost game, row by row from the bottom.
func drawCurtain()
    for i = 0, game.curtain - 1 do
        var r = ROWS - 1 - i
        for c = 0, COLS - 1 do
            block(look.wellX + c * 8, r * 8, 8, 8, (c + r) % 2 == 0 and 3 or 4)
        end
    end
end

func drawPanel()
    box(108, 8, 48, 24)
    label("LEVEL", 132, 15, 8, "center", 4)
    label("{game.level}", 132, 25, 8, "center", 4)
    box(108, 36, 48, 24)
    label("LINES", 132, 43, 8, "center", 4)
    label("{game.lines}", 132, 53, 8, "center", 4)
    box(108, 64, 48, 28)
    label("SCORE", 132, 72, 8, "center", 4)
    label("{game.score:06d}", 132, 83, 8, "center", 4)
    var nb = look.nextBox
    box(nb.x, nb.y, nb.w, nb.h)
    label("NEXT", nb.x + nb.w / 2, nb.y + 7, 8, "center", 4)
    if game.state <> "title" and game.state <> "paused" then
        var cells = shapes.turns[game.next][1]
        var x0, x1, y0, y1 = 9, -9, 9, -9
        for c in cells do
            x0 = math.min(x0, c[1])
            x1 = math.max(x1, c[1])
            y0 = math.min(y0, c[2])
            y1 = math.max(y1, c[2])
        end
        var w = (x1 - x0 + 1) * 8
        var h = (y1 - y0 + 1) * 8
        var cx = nb.x + (nb.w - w) / 2 - x0 * 8
        var cy = nb.y + 12 + (nb.h - 12 - h) / 2 - y0 * 8
        drawPiece(game.next, 1, cx, cy)
    end
end

## The words in the well: PAUSE, and GAME OVER once the curtain is down.
func drawWellText()
    var cx = look.wellX + COLS * 4
    if game.state == "paused" then
        box(cx - 28, 60, 56, 24)
        label("PAUSE", cx, 72, 10, "center", 4)
    elseif game.state == "over" and game.curtain >= ROWS then
        box(cx - 32, 44, 64, 56)
        label("GAME", cx, 50, 10, "center", 4)
        label("OVER", cx, 62, 10, "center", 4)
        if game.newBest then
            label("NEW BEST", cx, 77, 8, "center", 3)
        else
            label("BEST", cx, 77, 8, "center", 3)
            label("{game.best:06d}", cx, 87, 8, "center", 3)
        end
        if game.frame % 60 < 40 then
            label("PUSH START", cx, 91, 8, "center", 4)
        end
    end
end

func drawGame()
    drawWall(0, ROWS)
    drawWall(8, ROWS)
    drawWall(look.wellX + COLS * 8, ROWS)
    block(look.wellX, 0, COLS * 8, ROWS * 8, 1)
    if game.state <> "paused" then
        drawWell()
    end
    if game.state == "over" then
        drawCurtain()
    end
    drawPanel()
    drawWellText()
end

## The first screen: the name, the starting level, the best score and the music.
func drawTitle()
    block(0, 0, 160, 144, 1)
    box(4, 4, 152, 136)
    label("TETRIS", 80, 23, 24, "center", 4)
    var show = [
        [Piece.I, 14, 48], [Piece.O, 54, 48], [Piece.T, 78, 48], [Piece.Z, 110, 44],
        [Piece.L, 22, 72], [Piece.J, 54, 76], [Piece.S, 86, 72]
    ]
    for item in show do
        drawPiece(item[1], 1, item[2], item[3] - 8)
    end
    var arrows = game.frame % 40 < 28
    label("LEVEL  {game.startLevel}", 80, 98, 10, "center", 4)
    if arrows then
        label("<", 38, 98, 10, "center", 4)
        label(">", 122, 98, 10, "center", 4)
    end
    label("HIGH {game.best:06d}", 80, 110, 8, "center", 3)
    label("MUSIC " + (music.on and "ON" or "OFF"), 80, 120, 8, "center", 3)
    if game.frame % 60 < 40 then
        label("PUSH START", 80, 130, 8, "center", 4)
    end
end

func padLit(name)
    return view.pads[name] == true
end

func drawArm(name, x, y, u)
    fillC(padLit(name) and look.padLit or look.padFill)
    graphics.rect(x - u, y - u, 2 * u, 2 * u, u * 0.3)
end

## The cross, the two buttons and START, drawn over the area outside the screen.
func drawPads()
    var L = view.layout
    var l = L.left
    var r = L.right
    drawArm("up", l.x, l.y - 2 * l.u, l.u)
    drawArm("left", l.x - 2 * l.u, l.y, l.u)
    drawArm("right", l.x + 2 * l.u, l.y, l.u)
    drawArm("down", l.x, l.y + 2 * l.u, l.u)
    fillC(look.padFill)
    graphics.rect(l.x - l.u, l.y - l.u, 2 * l.u, 2 * l.u)
    var names = ["b", "a"]
    var xs = [r.x - 1.7 * r.u, r.x + 1.7 * r.u]
    var ys = [r.y + 0.9 * r.u, r.y - 0.9 * r.u]
    for i = 1, 2 do
        fillC(padLit(names[i]) and look.padLit or look.padFill)
        graphics.circle(xs[i], ys[i], 1.9 * r.u)
        drawText(names[i].upper(), xs[i], ys[i], r.u * 1.6, "center", "center", look.padInk)
    end
    fillC(padLit("start") and look.padLit or look.padFill)
    graphics.rect(L.pill.x - L.pill.w / 2, L.pill.y - L.pill.h / 2, L.pill.w, L.pill.h, L.pill.h / 2)
    drawText("START", L.pill.x, L.pill.y, L.pill.h * 0.5, "center", "center", look.padInk)
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
    else
        drawGame()
    end
    if view.touchSeen then
        drawPads()
    end
end
