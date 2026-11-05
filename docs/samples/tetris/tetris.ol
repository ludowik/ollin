## Tetris, as the handheld of 1989 plays it: a well of 10 by 18, the seven pieces turning by the original
## Nintendo rotation (no wall kicks, no hold, no ghost, no hard drop), the score of 40, 100, 300 and 1200 times the
## level, a speed that grows with the level, and the folk tune of Type A. The screens are the handheld's: the title,
## the choice of A-TYPE (the level rises every ten lines) or B-TYPE (rubble to dig through, 25 lines to clear) and of
## the music, then the level, and for B-TYPE the height of the rubble.
##
## Left and right move a piece (held, they repeat after a short wait), down drops it faster and pays a point a row,
## X or up turns it clockwise and Z counter-clockwise. On the screens before the game the arrows choose, X or Enter
## confirms and Z goes back. Enter starts and pauses, M switches the music, V switches the style (see below). On a
## touch screen the pads appear with the first touch: a cross, the two buttons A and B, START and STYLE.
##
## rules.ol holds the rules, sounds.ol the sound and play.ol the game itself, which runs on a clock of 60 steps a
## second whatever the speed of the screen, so that the counts of frames of the rules mean what they say; this file
## is what the player touches: the keyboard and the pads, where the picture goes, and the style it is seen in. There
## are two, the same game in both: the ORIGINAL (style_gb.ol), the screen of the handheld in 160 by 144 points scaled to
## fit the area (graphics.fitArea), and the MODERN (style_modern.ol), in the very same places. A style only reads the
## state of the game; V or the STYLE pad changes it, and the one chosen is kept for the next run. So is the game
## itself (save.ol): a run begins on the screen the last one left, in pause if a game was on.

import "rules.ol"
import "sounds.ol"
import "play.ol"
import "save.ol"
import "places.ol"
import "style_gb.ol"
import "style_modern.ol"

## The styles, the first being the one the game starts in, and the key that keeps the choice between two runs.
global styles = [styleGb, styleModern]
const STYLE_KEY = "tetris.style"

## What belongs to the screen and the fingers, not to the game.
global view = {
    pads: {},                   ## the pad buttons down at the last frame
    pointer: false,             ## a finger or the mouse was down at the last frame
    touchSeen: false,           ## a finger has touched the screen, so the pads are shown
    hint: "",                   ## what the title screens say of the key V
    style: 1,                   ## the index in `styles` of the style the game is seen in
    layout: {s: 1, ox: 0, oy: 0, buttons: [], cross: nil, w: 0, h: 0, padsShown: false}
}

## The pad buttons that start events of the game when they go down, and the events (A turns a piece and confirms).
const PAD_EVENTS = {
    a: ["cw", "confirm"], b: ["ccw"], start: ["start"], left: ["left"], right: ["right"], up: ["up"], down: ["down"]
}

## The style the game is seen in, and the one after it: the layout, the font and the smoothing follow it.
func applyStyle()
    graphics.antialias(styles[view.style].smooth)
    view.hint = "V  " + styles[view.style % len(styles) + 1].name + " STYLE"
end

func toggleStyle()
    view.style = view.style % len(styles) + 1
    data.set(STYLE_KEY, styles[view.style].name)
    applyStyle()
end

func loadStyle()
    var name = data.get(STYLE_KEY, styles[1].name)
    view.style = 1
    for i = 1, len(styles) do
        if styles[i].name == name then
            view.style = i
        end
    end
    applyStyle()
end

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
    elseif key == "v" then
        toggleStyle()
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
    if pads.style and not before.style then
        toggleStyle()
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
## top of a tall area, or the middle of a wide one, the pads standing below it or on either side. It is the same
## whatever the style, which draws in these places. It is worked out again only when the area or the pads shown change.
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
    var kx
    var ky
    var u
    if pads and portrait then
        s = math.min(W / SCREEN.w, H * 0.66 / SCREEN.h)
        L.ox = math.floor((W - SCREEN.w * s) / 2)
        L.oy = math.floor(math.max((H * 0.68 - SCREEN.h * s) / 2, 0))
        var top = L.oy + SCREEN.h * s
        var rest = H - top
        u = math.min(W * 0.065, rest * 0.14)
        lx, ly = W * 0.27, top + rest * 0.45
        rx, ry = W * 0.72, top + rest * 0.45
        px, py = W * 0.5, top + rest * 0.88
        kx, ky = W * 0.86, top + rest * 0.88
    elseif pads then
        s = math.min(H / SCREEN.h, W / (SCREEN.w * 1.7))
        L.ox = math.floor((W - SCREEN.w * s) / 2)
        L.oy = math.floor((H - SCREEN.h * s) / 2)
        u = math.min(L.ox * 0.11, H * 0.1)
        lx, ly = L.ox / 2, H * 0.58
        rx, ry = W - L.ox / 2, H * 0.58
        px, py = W - L.ox / 2, H * 0.16
        kx, ky = L.ox / 2, H * 0.16
    else
        s = math.min(W / SCREEN.w, H / SCREEN.h)
        L.ox = math.floor((W - SCREEN.w * s) / 2)
        L.oy = math.floor((H - SCREEN.h * s) / 2)
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
end

## ── Engine entry points ────────────────────────────────────────────────────────────────────────────

func setup()
    graphics.canvas(W, H, "Tetris")
    graphics.fitArea()
    gameInit()
    loadGame()
    loadStyle()
    layoutCompute()
end

func update(dt)
    readInput()
    layoutCompute()
    advance(dt)
    autosave()
end

func draw()
    var st = styles[view.style]
    graphics.font(st.font)
    graphics.noStroke()
    graphics.clear(st.ground[1], st.ground[2], st.ground[3])
    if game.state == "title" then
        st.title()
    elseif game.state == "menu" then
        st.menu()
    elseif game.state == "level" then
        st.level()
    else
        st.game()
    end
    if view.touchSeen then
        st.pads()
    end
end
