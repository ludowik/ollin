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
    var kept = data.get(BEST_KEY, 0)
    if typeof(kept) == "int" and kept >= 0 and kept <= 999999999 then
        best = kept
    end
    buildSprites()
    buildSounds()
    resetLanes()
    clearHomes()
    placeFrog()
    frog.ready = 0.0
end

func start()
    newGame(math.floor(time() * 1000) % 2147483647 + 1)
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

func keyboard.keypressed(key)
    if key == "space" then
        if not begin() and paused then
            paused = false
        end
    elseif key == "p" and state == "play" then
        paused = not paused
    elseif key == "m" then
        soundOn = not soundOn
    elseif key == "up" or key == "w" then
        tryHop("up")
    elseif key == "down" or key == "s" then
        tryHop("down")
    elseif key == "left" or key == "a" then
        tryHop("left")
    elseif key == "right" or key == "d" then
        tryHop("right")
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
    var dx = x - (frog.x + CELL / 2)
    var dy = y - (rowY(frog.row) + CELL / 2)
    if math.abs(dx) > math.abs(dy) then
        if dx > 0 then
            tryHop("right")
        else
            tryHop("left")
        end
    elseif dy < 0 then
        tryHop("up")
    else
        tryHop("down")
    end
end

func update(dt)
    dt = math.min(dt, 0.05)
    if state == "play" and not paused then
        updatePlay(dt)
    elseif state == "over" then
        frog.deadT += dt
        clock += dt
        for lane = 0, 10 do
            laneOff[lane + 1] = advanceLane(laneOff[lane + 1], lane, board, dt)
        end
    elseif state == "title" then
        demo += dt
        clock += dt
        for lane = 0, 10 do
            laneOff[lane + 1] = advanceLane(laneOff[lane + 1], lane, board, dt)
        end
    end
end

func draw()
    if state == "title" then
        drawTitle()
    else
        drawPlay()
    end
end
