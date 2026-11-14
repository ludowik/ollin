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
    loadGame()
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
    autosave(dt)
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
        return
    end

    graphics.clear(Color(0.02, 0.03, 0.05))

    ## The fleet is stored by rows, hence by kind, so three tint changes cover all 55 aliens — one
    ## per alien was fifty-five native state changes a frame for the same picture.
    var tinted = 0
    for a in fleet do
        if a.alive then
            var k = kinds[a.kind]
            if a.kind <> tinted then
                graphics.tint(k.ink)
                tinted = a.kind
            end
            graphics.sprite(k.frames[frame], a.x, a.y, 8, 8)
        end
    end

    if ufo <> nil then
        graphics.tint(TOP_INK)
        graphics.sprite(ufoImg, ufo.x, UFO_Y, UFO_W, UFO_H)
    end

    graphics.tint(SHIELD_INK)
    for sh in shields do
        graphics.sprite(sh.img, sh.x, SHIELD_Y, SHIELD_W, SHIELD_H)
    end

    ## During the pause the cannon blinks, so the eye finds where it died before it comes back.
    if respawn <= 0.0 or math.frac(respawn * 6.0) < 0.5 then
        graphics.tint(GUN_INK)
        graphics.sprite(gunImg, gunX, GUN_Y, GUN_W, GUN_H)
    end
    graphics.tint(INK)
    for b in bombs do
        graphics.sprite(bombImgs[1 + (ticks // 6) % 2], b.x - 1, b.y, 3, 4)
    end
    for b in bursts do
        graphics.sprite(burstImg, b.x, b.y, 10, 7)
    end
    graphics.noTint()

    if shotLive then
        graphics.noStroke()
        graphics.fill(INK)
        graphics.rect(shotX, shotY, 1, 4)
    end

    graphics.noStroke()
    graphics.fill(GUN_INK)
    graphics.rect(MARGIN, GUN_Y + 8, FIELD_W - 2 * MARGIN, 1)   ## the floor the cannon stands on

    if popup <> nil then
        graphics.fontSize(8)
        graphics.stroke(TOP_INK)
        graphics.textMode("center", "center")
        graphics.text(popup.text, popup.x, popup.y)
    end

    graphics.fontSize(9)
    graphics.stroke(INK)
    graphics.textMode("left", "top")
    graphics.text("SCORE {score}", MARGIN, 8)
    graphics.textMode("center", "top")
    graphics.text("BEST {best}", FIELD_W / 2, 8)
    graphics.textMode("right", "top")
    graphics.text("WAVE {wave}", FIELD_W - MARGIN, 8)
    ## The lives left, as cannons: a count of the thing itself reads faster than a number.
    graphics.tint(GUN_INK)
    for i = 1, lives - 1 do
        graphics.sprite(gunImg, MARGIN + (i - 1) * (GUN_W + 4), FIELD_H - 13, GUN_W, GUN_H)
    end
    graphics.noTint()

    graphics.fontSize(7)
    graphics.stroke(DIM)
    graphics.textMode("center", "bottom")
    var hint = "arrows + space — P pauses — or play with one finger"
    if touchPlay then
        hint = "drag to move — tap the score band to pause"
    end
    graphics.text(hint, FIELD_W / 2, FIELD_H - 3)

    if paused then
        graphics.fontSize(12)
        graphics.stroke(GUN_INK)
        graphics.textMode("center", "center")
        graphics.text("PAUSED", FIELD_W / 2, 150)
    end

    if state == "over" then
        graphics.fontSize(14)
        graphics.stroke(TOP_INK)
        graphics.textMode("center", "center")
        graphics.text("GAME OVER", FIELD_W / 2, 150)
        graphics.fontSize(8)
        graphics.stroke(INK)
        graphics.text("SCORE {score} — press or tap to play again", FIELD_W / 2, 168)
    end
end
