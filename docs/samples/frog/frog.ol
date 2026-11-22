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
    graphics.viewport(FIELD_W, FIELD_H)
    loadBest()
    buildSprites()
    buildSounds()
    resetField()
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

const KEY_DIR = {up: "up", w: "up", down: "down", s: "down", left: "left", a: "left", right: "right", d: "right"}

func keyboard.keypressed(key)
    if key == "space" then
        if not begin() and paused then
            paused = false
        end
    elseif key == "p" and state == "play" then
        paused = not paused
    elseif key == "m" then
        soundOn = not soundOn
    elseif KEY_DIR[key] <> nil then
        tryHop(KEY_DIR[key])
    end
end

## A tap hops the frog the way it points from the frog: the side the tap is on more than the other. A single finger also
## emulates the mouse, so this one path serves both.
func mouse.pressed(x, y)
    if begin() then
        return
    end
    if paused then
        paused = false
        return
    end
    tryHop(tapDirection(x - (frog.x + CELL / 2), y - (rowY(frog.row) + CELL / 2)))
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
