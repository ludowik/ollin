## Frog: the arcade game of 1981 in which a frog crosses a road and a river to fill five homes. The pictures of the lanes and of
## everything on them, and the way the lanes are laid out, are the arcade game's own (tiles.ol and arcade.ol, decoded from the
## information published about its ROM by tools/convert_frog_data.py); the speeds, the diving of the turtles, the clock and the
## points were set by playing (README.md says which is which).
##
## The rule that makes the genre: nothing in the field is ever safe for long. The road wants the frog in its gaps; the river
## wants it ON something that is moving, and carries it to the edge of the field if it stays — a frog that rides a log is on its
## way off the screen, and has to leave it before it gets there.

import "field.ol"
import "rules.ol"
import "state.ol"
import "sounds.ol"
import "sprites.ol"
import "play.ol"
import "draw.ol"

func setup()
    gfx.canvas(W, H, "Ollin Frog")
    gfx.fitArea()                      ## the area is the whole screen of the phone: the field is scaled up to it, whatever it is
    fitView(window.width, window.height)
    loadBest()
    buildSprites()
    buildSounds()
    resetField()
end

## The viewport and the buttons for an area of w x h pixels.
func fitView(w, h)
    viewH = viewHeight(w, h)
    buttons = padButtons(viewH)
    gfx.viewport(FIELD_W, viewH)
end

func window.resized(w, h)
    fitView(w, h)
end

const KEY_BUTTON = {
    up: "up", w: "up", down: "down", s: "down", left: "left", a: "left", right: "right", d: "right", p: "pause", m: "sound"
}

func keyboard.pressed(key)
    if key == "space" then
        if not begin() and paused then
            paused = false
        end
    elseif KEY_BUTTON[key] <> nil then
        pressButton(KEY_BUTTON[key])
    end
end

## A tap, from the mouse or from a finger. A finger also emulates the mouse, and touch.count() tells the two apart (it is
## already counted when the mouse callback runs), so each tap is heard once, by the path that knows about every finger.
func mouse.pressed(x, y)
    if touch.count() == 0 then
        tap(x, y)
    end
end

func touch.pressed(id, x, y)
    tap(x, y)
end

func update(dt)
    updateFrame(dt)
end

func draw()
    if state == "title" then
        drawTitle()
    else
        drawPlay()
    end
end
