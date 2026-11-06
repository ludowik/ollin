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
## is what the player touches: the keyboard and the pads, where the picture goes (layout.ol), and the style it is seen in. There
## are two, the same game in both: the ORIGINAL (style_gb.ol), the screen of the handheld in 160 by 144 points scaled to
## fit the area (graphics.fitArea), and the MODERN (style_modern.ol), in the very same places. A style only reads the
## state of the game; V or the STYLE pad changes it, and the one chosen is kept for the next run. So is the game
## itself (save.ol): a run begins on the screen the last one left, in pause if a game was on.

import "rules.ol"
import "sounds.ol"
import "play.ol"
import "save.ol"
import "places.ol"
import "layout.ol"
import "style_gb.ol"
import "style_modern.ol"

## The styles, the first being the one the game starts in, and the key that keeps the choice between two runs.
global styles = [styleGb, styleModern]
const STYLE_KEY = "tetris.style"
const TOUCH_KEY = "tetris.touch"

## What belongs to the screen and the fingers, not to the game.
global view = {
    pads: {},                   ## the pad buttons down at the last frame
    pointer: false,             ## a finger or the mouse was down at the last frame
    touchSeen: false,           ## a finger has touched the screen (in this run or an earlier one), so the pads are shown
    hint: "",                   ## what the title screens say of the key V
    style: 1,                   ## the index in `styles` of the style the game is seen in
    layout: {s: 1, ox: 0, oy: 0, buttons: [], cross: nil, w: 0, h: 0, padsShown: false}
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

func commandStyle()
    toggleStyle()
end

## Which command each pad button gives when it goes down, and which each key gives. No rule here: what a command means
## is in play.ol, and commandStyle above.
const PAD_COMMANDS = {
    a: commandPrimary, b: commandSecondary, start: commandStart, style: commandStyle,
    left: commandLeft, right: commandRight, up: commandUp, down: commandDown
}
const KEY_COMMANDS = {
    x: [commandPrimary], z: [commandSecondary], up: [commandTurn, commandUp], w: [commandTurn, commandUp],
    down: [commandDown], s: [commandDown], left: [commandLeft], a: [commandLeft], right: [commandRight],
    d: [commandRight], ["return"]: [commandStart], p: [commandStart], escape: [commandStart],
    m: [commandMusic], v: [commandStyle]
}

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
    var commands = KEY_COMMANDS[key]
    if commands then
        for command in commands do
            command()
        end
    elseif key == "space" and game.state <> "play" then
        commandStart()   ## space only starts while no game is on: during one it would be a key pressed by mistake
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

## Reads the keyboard, the pads and the taps once a frame. A direction and down are HELD, tested by the steps; a
## turn, START and a tap are EVENTS, kept until a step uses them.
func readInput()
    var held = game.held
    var pts = pointers()
    if touch.count() > 0 and not view.touchSeen then
        view.touchSeen = true
        data.set(TOUCH_KEY, true)
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
    for name, command in PAD_COMMANDS do
        if pads[name] and not before[name] then
            command()
        end
    end
    if tap and not running() and len(pads) == 0 then
        commandStart()
    end
    view.pointer = len(pts) > 0
    view.pads = pads
    held.left = keyboard.isDown("left") or keyboard.isDown("a") or pads.left == true
    held.right = keyboard.isDown("right") or keyboard.isDown("d") or pads.right == true
    held.down = keyboard.isDown("down") or keyboard.isDown("s") or pads.down == true
end

## ── Layout ─────────────────────────────────────────────────────────────────────────────────────────

## Works the layout out again only when the area or the pads shown change (layout.ol holds how).
func layoutCompute()
    var L = view.layout
    if L.w == W and L.h == H and L.padsShown == view.touchSeen then
        return
    end
    view.layout = computeLayout(W, H, view.touchSeen)
end

## ── Engine entry points ────────────────────────────────────────────────────────────────────────────

func setup()
    graphics.canvas(W, H, "Tetris")
    graphics.fitArea()
    gameInit()
    loadGame()
    loadStyle()
    view.touchSeen = data.get(TOUCH_KEY, false)
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
    var items = screenItems(view.hint)
    if items <> nil then
        st.items(items)
    else
        st.game()
    end
    if view.touchSeen then
        st.pads()
    end
end
