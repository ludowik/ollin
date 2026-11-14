## The title screen, and the game in play.

## The title screen shows what the three creatures are worth — the score table the cabinet carried,
## and the only place the player is ever told. The frames alternate on the screen's own clock, so the
## fleet is seen marching before a shot is fired.
func drawTitle()
    graphics.clear(Color(0.02, 0.03, 0.05))
    ## The two frames alternate every four tenths of a second — an integer index, since a fractional
    ## one cannot address an array.
    var f = 1
    if math.frac(demo * 1.25) >= 0.5 then
        f = 2
    end

    graphics.fontSize(20)
    graphics.stroke(GUN_INK)
    graphics.textMode("center", "center")
    graphics.text("OLLIN INVADERS", FIELD_W / 2, 52)
    graphics.fontSize(8)
    graphics.stroke(DIM)
    graphics.text("*SCORE ADVANCE TABLE*", FIELD_W / 2, 78)

    ## The four rows are one list, the mystery ship included: written apart, its line could drift
    ## from the three above it without anything saying so.
    var table = []
    for i = 1, #kinds do
        table.push({img: kinds[i].frames[f], w: 8, h: 8, ink: kinds[i].ink,
                    text: "= {kinds[i].points} POINTS"})
    end
    table.push({img: ufoImg, w: UFO_W, h: UFO_H, ink: TOP_INK, text: "= MYSTERY"})

    graphics.fontSize(9)
    graphics.textMode("left", "center")
    for i = 1, #table do
        var row = table[i]
        var y = 96 + (i - 1) * 20
        graphics.tint(row.ink)
        graphics.sprite(row.img, FIELD_W / 2 - 34 - (row.w - 8) / 2, y - row.h / 2, row.w, row.h)
        graphics.noTint()
        graphics.stroke(INK)
        graphics.text(row.text, FIELD_W / 2 - 20, y)
    end

    graphics.fontSize(9)
    graphics.stroke(GUN_INK)
    graphics.textMode("center", "center")
    graphics.text("PRESS SPACE OR TAP TO PLAY", FIELD_W / 2, 190)
    graphics.fontSize(7)
    graphics.stroke(DIM)
    graphics.text("arrows to move, space to fire, P pauses", FIELD_W / 2, 206)
    graphics.text("one finger drags the cannon, firing is automatic", FIELD_W / 2, 218)
    graphics.text("tap the score band to pause", FIELD_W / 2, 228)
    if best > 0 then
        graphics.fontSize(8)
        graphics.stroke(INK)
        graphics.text("BEST {best}", FIELD_W / 2, 242)
    end
end

func drawPlay()
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
