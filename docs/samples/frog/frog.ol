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
    graphics.canvas(W, H, "Ollin Frog")
    graphics.fitArea()                      ## the area is the whole screen of the phone: the field is scaled up to it, whatever it is
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
    graphics.viewport(FIELD_W, viewH)
end

func window.resized(w, h)
    fitView(window.width, window.height)
end

func start()
    newGame()
    play(sndStart)
end

## Space starts a game from the title and from the end screen, and the same press must not hop the frog: one place decides.
func begin()
    if state == "play" then
        return false
    end
    if state == "over" and frog.deadT < 1.5 then
        return true
    end
    start()
    return true
end

const KEY_BUTTON = {
    up: "up", w: "up", down: "down", s: "down", left: "left", a: "left", right: "right", d: "right", p: "pause", m: "sound"
}

func keyboard.keypressed(key)
    if key == "space" then
        if not begin() and paused then
            paused = false
        end
    elseif KEY_BUTTON[key] <> nil then
        pressButton(KEY_BUTTON[key])
    end
end

## The buttons under the field. A tap starts a game from the title and the end screen, resumes a paused one, and otherwise
## presses the button it is on. A single finger also emulates the mouse, so that is the path of the first finger; a second
## finger arrives only as a touch (touchPress).
func mouse.pressed(x, y)
    if begin() then
        return
    end
    if paused then
        paused = false
        return
    end
    var name = buttonAt(buttons, x, y)
    if name <> nil then
        pressButton(name)
    end
end

func touch.began(id, x, y)
    touchPress(touch.count(), x, y)
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
