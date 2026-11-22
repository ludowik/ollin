## Everything the game draws on the field, and the art it draws it with.

func drawField()
    gfx.noFill()
    gfx.strokeSize(1.4)
    gfx.stroke(INK)

    for r in rocks do
        drawWrapped(rockArt[r.shape][r.size], r.x, r.y, r.rot, ROCK_R[r.size], FIELD_W, FIELD_H)
    end

    if saucer <> nil then
        var art = saucerArt.big
        if saucer.small then
            art = saucerArt.small
        end
        gfx.stroke(WARM)
        drawAt(art.hull, saucer.x, saucer.y, 0.0, true)
        drawAt(art.deck, saucer.x, saucer.y, 0.0, false)
        gfx.stroke(INK)
    end

    if ship <> nil then
        drawWrapped(shipArt, ship.x, ship.y, ship.ang, SHIP_R, FIELD_W, FIELD_H)
        ## The flame is drawn every other frame, so it flickers as the original's did — a steady
        ## flame reads as part of the hull.
        if ship.push > 0.0 and math.frac(elapsedTime * 20.0) < 0.5 then
            gfx.stroke(WARM)
            drawAt(flameArt, ship.x, ship.y, ship.ang, false)
            gfx.stroke(INK)
        end
    end

    gfx.noStroke()
    gfx.fill(INK)
    for s in shots do
        gfx.circle(s.x, s.y, 1.6)
    end
    gfx.fill(WARM)
    for s in saucerShots do
        gfx.circle(s.x, s.y, 1.6)
    end
    gfx.fill(DIM)
    for d in debris do
        gfx.circle(d.x, d.y, 1.2)
    end
end

## The lives left, as ships: a count of the thing itself reads faster than a number.
func drawLives()
    gfx.noFill()
    gfx.stroke(INK)
    for i = 1, lives - 1 do
        drawAt(shipIcon, 22 + (i - 1) * 20, 46, -math.PI / 2, true)
    end
end

## The trigger has no hit test of its own — the whole left half fires — so what is drawn is a
## HINT: a ring where the thumb naturally sits, filled while it is held.
func drawTrigger()
    ## Mirrored from the stick's own placing, never re-typed: moving the stick moves the trigger
    ## with it, instead of leaving it silently behind at an old height.
    var r = pad.radius() * 0.5
    var cx = W * (1.0 - pad.centerXFrac)
    var cy = H * pad.centerFrac
    gfx.noStroke()
    gfx.fill(Color(1, 1, 1, 0.06))
    gfx.circle(cx, cy, r)
    if fireId <> nil then
        gfx.fill(Color(1.0, 0.55, 0.3, 0.7))
        gfx.circle(cx, cy, r * 0.55)
    else
        gfx.fill(Color(1, 1, 1, 0.16))
        gfx.circle(cx, cy, r * 0.4)
    end
end

func drawTitle()
    gfx.fontSize(30)
    gfx.stroke(INK)
    gfx.textMode("center", "center")
    gfx.text("OLLIN ASTEROIDS", FIELD_W / 2, 120)
    gfx.fontSize(11)
    gfx.stroke(DIM)
    gfx.text("a large rock breaks into two faster ones — and there is no brake", FIELD_W / 2, 158)
    gfx.stroke(INK)
    gfx.fontSize(12)
    gfx.text("large 20    medium 50    small 100    saucer 200 or 1000", FIELD_W / 2, 210)
    gfx.fontSize(11)
    gfx.stroke(WARM)
    var go = "arrows turn, up thrusts, hold space to fire"
    if touchPlay then
        go = "right thumb aims and thrusts — hold the left half to fire"
    end
    gfx.text(go, FIELD_W / 2, 250)
    if math.frac(demo) < 0.6 then
        gfx.stroke(INK)
        gfx.text("press or tap to play", FIELD_W / 2, 280)
    end
    if best > 0 then
        gfx.stroke(DIM)
        gfx.text("BEST {best}", FIELD_W / 2, 310)
    end
end

## The outlines at every size the game draws them. Sizing is loading work, not frame work, and the
## sizes are a fixed handful — so this runs once and draw() only ever turns and places.
func buildArt()
    rockArt = []
    for i = 1, #ROCKS do
        var sizes = []
        for k = 1, #ROCK_R do
            sizes.push(scaleShape(ROCKS[i], ROCK_R[k]))
        end
        rockArt.push(sizes)
    end
    shipArt = scaleShape(SHIP, SHIP_R)
    shipIcon = scaleShape(SHIP, 7.0)
    flameArt = scaleShape(FLAME, SHIP_R)
    saucerArt = {
        big: {hull: scaleShape(SAUCER, SAUCER_BIG_R), deck: scaleShape(SAUCER_DECK, SAUCER_BIG_R)},
        small: {hull: scaleShape(SAUCER, SAUCER_SMALL_R), deck: scaleShape(SAUCER_DECK, SAUCER_SMALL_R)}
    }
end

## The score, the wave and the ships left belong to a game in progress: showing them on the title screen would announce a
## score of zero and two spare ships before anything has started.
func drawHud()
    gfx.fontSize(14)
    gfx.stroke(INK)
    gfx.textMode("left", "top")
    gfx.text("{score}", 18, 14)
    gfx.textMode("right", "top")
    gfx.text("WAVE {wave}", FIELD_W - 18, 14)
    drawLives()
    if state == "over" then
        gfx.fontSize(24)
        gfx.stroke(WARM)
        gfx.textMode("center", "center")
        gfx.text("GAME OVER", FIELD_W / 2, FIELD_H / 2 - 14)
        gfx.fontSize(12)
        gfx.stroke(INK)
        gfx.text("SCORE {score} — press or tap to play again", FIELD_W / 2, FIELD_H / 2 + 14)
    elseif paused then
        gfx.fontSize(20)
        gfx.stroke(WARM)
        gfx.textMode("center", "center")
        gfx.text("PAUSED", FIELD_W / 2, FIELD_H / 2)
    end
end
