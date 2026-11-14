## Everything the game draws on the field, and the art it draws it with.

func drawField()
    graphics.noFill()
    graphics.strokeSize(1.4)
    graphics.stroke(INK)

    for r in rocks do
        drawWrapped(rockArt[r.shape][r.size], r.x, r.y, r.rot, ROCK_R[r.size], FIELD_W, FIELD_H)
    end

    if saucer <> nil then
        var art = saucerArt.big
        if saucer.small then
            art = saucerArt.small
        end
        graphics.stroke(WARM)
        drawAt(art.hull, saucer.x, saucer.y, 0.0, true)
        drawAt(art.deck, saucer.x, saucer.y, 0.0, false)
        graphics.stroke(INK)
    end

    if ship <> nil then
        drawWrapped(shipArt, ship.x, ship.y, ship.ang, SHIP_R, FIELD_W, FIELD_H)
        ## The flame is drawn every other frame, so it flickers as the original's did — a steady
        ## flame reads as part of the hull.
        if ship.push > 0.0 and math.frac(elapsedTime * 20.0) < 0.5 then
            graphics.stroke(WARM)
            drawAt(flameArt, ship.x, ship.y, ship.ang, false)
            graphics.stroke(INK)
        end
    end

    graphics.noStroke()
    graphics.fill(INK)
    for s in shots do
        graphics.circle(s.x, s.y, 1.6)
    end
    graphics.fill(WARM)
    for s in saucerShots do
        graphics.circle(s.x, s.y, 1.6)
    end
    graphics.fill(DIM)
    for d in debris do
        graphics.circle(d.x, d.y, 1.2)
    end
end

## The lives left, as ships: a count of the thing itself reads faster than a number.
func drawLives()
    graphics.noFill()
    graphics.stroke(INK)
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
    graphics.noStroke()
    graphics.fill(Color(1, 1, 1, 0.06))
    graphics.circle(cx, cy, r)
    if fireId <> nil then
        graphics.fill(Color(1.0, 0.55, 0.3, 0.7))
        graphics.circle(cx, cy, r * 0.55)
    else
        graphics.fill(Color(1, 1, 1, 0.16))
        graphics.circle(cx, cy, r * 0.4)
    end
end

func drawTitle()
    graphics.fontSize(30)
    graphics.stroke(INK)
    graphics.textMode("center", "center")
    graphics.text("OLLIN ASTEROIDS", FIELD_W / 2, 120)
    graphics.fontSize(11)
    graphics.stroke(DIM)
    graphics.text("a large rock breaks into two faster ones — and there is no brake", FIELD_W / 2, 158)
    graphics.stroke(INK)
    graphics.fontSize(12)
    graphics.text("large 20    medium 50    small 100    saucer 200 or 1000", FIELD_W / 2, 210)
    graphics.fontSize(11)
    graphics.stroke(WARM)
    var go = "arrows turn, up thrusts, hold space to fire"
    if touchPlay then
        go = "right thumb aims and thrusts — hold the left half to fire"
    end
    graphics.text(go, FIELD_W / 2, 250)
    if math.frac(demo) < 0.6 then
        graphics.stroke(INK)
        graphics.text("press or tap to play", FIELD_W / 2, 280)
    end
    if best > 0 then
        graphics.stroke(DIM)
        graphics.text("BEST {best}", FIELD_W / 2, 310)
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
