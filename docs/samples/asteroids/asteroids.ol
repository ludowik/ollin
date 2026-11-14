## Asteroids.
##
## The rule that makes the genre: the ship has NO brake. Thrust adds to a velocity that never goes away, so every manoeuvre
## is paid for with the opposite one. Turning is free and instant, moving is not — that asymmetry is the game, and any
## friction strong enough to stop the ship would delete it.
##
## The second rule: shooting a rock multiplies it. A large rock becomes two medium ones, a medium two small, and each
## generation moves faster than the one before, so clearing a wave makes the field more dangerous before it makes it empty.
## Everything wraps: the field has no walls, so there is no corner to hide in.

import "shapes.ol"
import "sounds.ol"
import "field.ol"
import "save.ol"
import "../lib/joystick.ol"
import "state.ol"
import "law.ol"
import "rocks.ol"
import "ship.ol"
import "saucer.ol"
import "frame.ol"
import "resume.ol"
import "draw.ol"

## It enters from one side, crosses in a lane of its own, and swerves now and then so it cannot be
## led like a clay pigeon. The SMALL one only turns up once the player has scored: it is the
## harder target and the bigger prize.

func update(dt)
    ## The sparks fade on their own clock: they are shown after the thing that made them is gone,
    ## so they belong to no other state.
    debris = debris.filter(func(d)
        advance(d, dt)
        d.left -= dt
        return d.left > 0.0
    end)
    keepGoing(dt, state, saveGame)

    if state == "title" then
        demo += dt
        for r in rocks do
            r.rot += r.spin * dt
            advance(r, dt)
        end
        return
    end
    if state == "over" or paused then
        hushVoices()
        return
    end

    if ship <> nil then
        steerShip(dt)
    else
        spawn -= dt
        if spawn <= 0.0 and centreClear() then
            newShip()
        end
    end
    ## A held trigger fires on its own clock, the four-shot rule doing the rest: a modern player
    ## holds the button down, and asking for one tap per shot is what a cabinet's spring did.
    fireTimer -= dt
    if (fireId <> nil or keyboard.isDown("space")) and fireTimer <= 0.0 then
        fire()
        fireTimer = FIRE_RATE
    end

    var thrusting = ship <> nil and ship.push > 0.0
    if thrusting and not thrustVoice.isPlaying() then
        thrustVoice.start()
    elseif not thrusting and thrustVoice.isPlaying() then
        thrustVoice.stop()
    end

    for r in rocks do
        r.rot += r.spin * dt
        advance(r, dt)
    end
    shots = ageShots(shots, dt)
    saucerShots = ageShots(saucerShots, dt)
    saucerUpdate(dt)
    shotsHit()
    shipHit()
    ## ONE sweep, after every pass that could have broken something: the collisions mark, this
    ## removes. Rebuilding the list mid-pass is what the marking exists to avoid.
    rocks = rocks.filter(func(r) return not r.dead end)
    beat(dt)

    if #rocks == 0 then
        waveWait -= dt
        if waveWait <= 0.0 then
            wave += 1
            newWave()
        end
    else
        waveWait = WAVE_WAIT
    end
end

## Any press means "go" on the title screen and on the end screen, and only fires while playing.
## One place decides that, so the four input paths below say the same thing.
func begin()
    if state == "play" then
        return false
    end
    startGame()
    return true
end

func startGame()
    score = 0
    lives = LIVES
    wave = 1
    nextExtra = EXTRA_AT
    debris = []
    paused = false
    ## A finger held across the end screen must not play the new game: the trigger and the stick
    ## are both let go, or the fresh ship would thrust off on the previous game's command.
    fireId = nil
    padId = nil
    pad.release()
    state = "play"
    newWave()
    newShip()
end

## A press ends the pause. A game kept by a run comes back in pause, and the way on from there must not be a key a
## player of the mouse or the screen does not have. Whether there was a pause to end.
func unpause()
    if state == "play" and paused then
        paused = false
        return true
    end
    return false
end

## Space does not fire from here: it is HELD, and the cadence in update reads it. Firing here too
## spent two of the four shots on a single press.
func keyboard.keypressed(key)
    if key == "space" then
        if not unpause() then
            begin()
        end
    elseif key == "p" and state == "play" then
        paused = not paused
    end
end

## The glass is cut in TWO, and the side a finger lands on decides what it does: the right half
## steers, the left half is the trigger. A side is a whole half and not a button, so neither thumb
## has to find a target while the field is moving — the drawn disc and ring are hints, not the
## hit test.
##
## A single finger also emulates the mouse, so the same gesture arrives twice. Each path is written
## to be IDEMPOTENT: the joystick only takes a finger it does not already have, and holding the
## trigger twice is holding it once.
func touch.began(id, x, y)
    touchPlay = true
    if unpause() or begin() then
        return
    end
    if x < W / 2 then
        fireId = id
        fireTimer = 0.0             ## the first shot leaves at once; the cadence starts after it
        return
    end
    if padId == nil then
        pad.press(x, y)             ## a floating stick: anywhere on this half arms it
        padId = id
    end
end

func touch.moved(id, x, y)
    if padId == id then
        pad.move(x, y)
    end
end

func touch.ended(id, x, y)
    if padId == id then
        padId = nil
        pad.release()
    elseif fireId == id then
        fireId = nil
    end
end

func mouse.pressed(x, y)
    if begin() or touchPlay or unpause() then    ## a finger was already answered by touch.began
        return
    end
    fire()                          ## a real click, on a desktop: it fires as space does
end

func draw()
    graphics.clear(Color(0.02, 0.02, 0.04))
    drawField()
    if state == "title" then
        drawTitle()
    else
        drawHud()
    end

    if touchPlay and state == "play" then
        drawTrigger()
        pad.draw()
    end
end

## Everything the program owns is built here, in the order it depends on.
func setup()
    graphics.canvas(W, H, "Ollin Asteroids")
    best = wholeOr(data.get(BEST_KEY, 0), 0, SAVE_WHOLES.score[2])
    ## From here on the script knows ONE frame of reference: the engine scales the field to the area
    ## and hands over the pointer and the contacts already converted.
    graphics.viewport(FIELD_W, FIELD_H)
    buildArt()
    buildSounds()
    ## The field is laid out but not started: the title screen holds it, and its rocks are the ones
    ## the first wave will drift — nothing is built twice.
    newWave()
    loadKept(SAVE_KEY, saveValid, restoreSave)
end
