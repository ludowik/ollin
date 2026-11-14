## Space Invaders. Only the mechanics follow the arcade original: the three creatures are ours (sprites.ol).
##
## The rule that makes the genre: the fleet does not move as a block. ONE alien advances per tick, so fifty-five aliens
## take fifty-five ticks to complete a pass and three take three. The game accelerates as it empties — a consequence of the
## rule, never a setting — and the wave only drops and reverses at the end of a pass, which keeps the formation square.
## The march sound plays one note per pass, so its beat follows the fleet's speed with nothing to time it.

import "sprites.ol"
import "sounds.ol"
import "field.ol"
import "save.ol"
import "state.ol"
import "shields.ol"
import "ufo.ol"
import "play.ol"
import "resume.ol"
import "draw.ol"

## Everything the program owns is built here, in the order it depends on: the window first, since a
## sprite is a texture and a texture needs a graphics context.
func setup()
    graphics.canvas(W, H, "Ollin Invaders")
    best = wholeOr(data.get(BEST_KEY, 0), 0, SAVE_WHOLES.score[2])
    ## From here on the script knows ONE frame of reference: the engine scales the field to the area
    ## and hands over the pointer and the contacts already converted.
    graphics.viewport(FIELD_W, FIELD_H)
    buildSprites()
    buildSounds()
    ## The field is laid out but not started: the title screen holds it, and its fleet is the one the
    ## first wave will march — nothing is built twice.
    newWave()
    loadKept(SAVE_KEY, saveValid, restoreSave)
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

## A press ends the pause. A game kept by a run comes back in pause, and the way on from there must not be a key a
## player of the mouse or the screen does not have. Whether there was a pause to end.
func unpause()
    if state == "play" and paused then
        paused = false
        return true
    end
    return false
end

## A tap in the top band pauses instead of aiming. It answers the same on both input paths — a single
## finger also emulates the mouse — so the band is read in ONE place.
func bandTap(y)
    if state <> "play" or y >= PAUSE_BAND then
        return false
    end
    paused = not paused
    return true
end

func keyboard.keypressed(key)
    if key == "space" then
        if not unpause() and not begin() then
            fire()
        end
    elseif key == "p" and state == "play" then
        paused = not paused
    end
end

## A single finger also emulates the mouse, so the same gesture arrives twice. Each path is written
## to be IDEMPOTENT: aiming twice at the same place is one aim, and firing twice is one shot, only
## one being allowed in the air.
func touch.began(id, x, y)
    touchPlay = true
    if unpause() or begin() or bandTap(y) then    ## the band pauses, and none of them takes hold of the cannon
        return
    end
    aimId = id
    grab(x)
end

func touch.moved(id, x, y)
    if aimId == id then
        dragTo(x)
    end
end

func touch.ended(id, x, y)
    if aimId == id then
        aimId = nil
    end
end

func mouse.pressed(x, y)
    if begin() then
        return
    end
    ## A finger has already been answered by touch.began, band included: the emulated click must not
    ## pause a second time, which would undo it.
    if touchPlay or unpause() then
        return
    end
    grab(x)
    fire()                                   ## a real click, on a desktop: it fires as space does
end

func mouse.moved(x, y)
    if mouse.isDown() and not touchPlay then
        dragTo(x)
    end
end

## The bursts fade on their own clock: they are shown after the thing that made them is gone, so
## they belong to no other state. A filter says it in one line — the countdown is the only change.
func burstsFade(dt)
    bursts = bursts.filter(func(b)
        b.left -= dt
        return b.left > 0.0
    end)
end

func update(dt)
    burstsFade(dt)
    keepGoing(dt, state, saveGame)
    if state == "title" then
        demo += dt
        return
    end
    if state == "over" or paused then
        return
    end

    ## The field holds still while the cannon is being replaced — the pause is what tells the player
    ## they were hit, so nothing marches, falls or fires during it.
    if respawn > 0.0 then
        respawn -= dt
        if respawn <= 0.0 then
            gunX = FIELD_W / 2 - GUN_W / 2
        end
        return
    end

    if keyboard.isDown("left") then
        gunX = math.max(MARGIN, gunX - GUN_SPEED * dt)
    end
    if keyboard.isDown("right") then
        gunX = math.min(FIELD_W - MARGIN - GUN_W, gunX + GUN_SPEED * dt)
    end

    ## Automatic once a finger has played: fire() is a no-op while a shot is in the air, so the
    ## cadence is the shot's travel time and nothing has to time it. It holds fire under a shield —
    ## the finger only aims, and a thumb parked in the shelter would otherwise dig through it at
    ## sixty shots a second. Space still fires wherever the cannon stands: destroying one's own
    ## shelter is the player's right, not an accident of the automatic cadence.
    ## The cheapest test first: with a shot in the air fire() would do nothing anyway, and a shot is
    ## in the air most of the time — reading the shelter's pixels before knowing that was the cost of
    ## a whole frame for no decision.
    if touchPlay and not shotLive and not sheltered() then
        fire()
    end

    if shotLive then
        shotY -= SHOT_SPEED * dt
        var hit = shieldAt(shotX, shotY)
        if hit <> nil then
            bite(hit, shotX - hit.x, shotY - SHIELD_Y, SHOT_BITE, -1)
            shotLive = false
        elseif shotY < MARGIN or ufoHit() or shotHits() then
            shotLive = false
        end
    end

    ufoUpdate(dt)
    if popup <> nil then
        popup.left -= dt
        if popup.left <= 0.0 then
            popup = nil
        end
    end

    bombsFall(dt)
    if respawn > 0.0 then     ## the cannon was just hit: this frame is over
        return
    end

    ## A FIXED tick, so the march keeps its pace whatever the frame rate.
    acc += dt
    while acc >= TICK do
        acc -= TICK
        ticks += 1
        if alive > 0 then
            fleetTick()
            dropBomb()
        end
    end

    ## A landed fleet ends the game outright: a cannon replaced under it would be shot at once, so
    ## the last life goes with the landing.
    if landed then
        lives = 1
        hitCannon()
        return
    end

    if alive == 0 then
        wave += 1
        newWave()
    end
end

func draw()
    if state == "title" then
        drawTitle()
    else
        drawPlay()
    end
end
