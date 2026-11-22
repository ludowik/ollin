## The title screen, and the game in play.

## The title screen shows what the three creatures are worth — the score table the cabinet carried,
## and the only place the player is ever told. The frames alternate on the screen's own clock, so the
## fleet is seen marching before a shot is fired.
func drawTitle()
    gfx.clear(Color(0.02, 0.03, 0.05))
    ## The two frames alternate every four tenths of a second — an integer index, since a fractional
    ## one cannot address an array.
    var f = 1
    if math.frac(demo * 1.25) >= 0.5 then
        f = 2
    end

    gfx.fontSize(20)
    gfx.stroke(GUN_INK)
    gfx.textMode("center", "center")
    gfx.text("OLLIN INVADERS", FIELD_W / 2, 52)
    gfx.fontSize(8)
    gfx.stroke(DIM)
    gfx.text("*SCORE ADVANCE TABLE*", FIELD_W / 2, 78)

    ## The four rows are one list, the mystery ship included: written apart, its line could drift
    ## from the three above it without anything saying so.
    var table = []
    for i = 1, #kinds do
        table.push({img: kinds[i].frames[f], w: 8, h: 8, ink: kinds[i].ink,
                    text: "= {kinds[i].points} POINTS"})
    end
    table.push({img: ufoImg, w: UFO_W, h: UFO_H, ink: TOP_INK, text: "= MYSTERY"})

    gfx.fontSize(9)
    gfx.textMode("left", "center")
    for i = 1, #table do
        var row = table[i]
        var y = 96 + (i - 1) * 20
        gfx.tint(row.ink)
        gfx.sprite(row.img, FIELD_W / 2 - 34 - (row.w - 8) / 2, y - row.h / 2, row.w, row.h)
        gfx.noTint()
        gfx.stroke(INK)
        gfx.text(row.text, FIELD_W / 2 - 20, y)
    end

    gfx.fontSize(9)
    gfx.stroke(GUN_INK)
    gfx.textMode("center", "center")
    gfx.text("PRESS SPACE OR TAP TO PLAY", FIELD_W / 2, 190)
    gfx.fontSize(7)
    gfx.stroke(DIM)
    gfx.text("arrows to move, space to fire, P pauses", FIELD_W / 2, 206)
    gfx.text("one finger drags the cannon, firing is automatic", FIELD_W / 2, 218)
    gfx.text("tap the score band to pause", FIELD_W / 2, 228)
    if best > 0 then
        gfx.fontSize(8)
        gfx.stroke(INK)
        gfx.text("BEST {best}", FIELD_W / 2, 242)
    end
end

func drawPlay()
    gfx.clear(Color(0.02, 0.03, 0.05))

    ## The fleet is stored by rows, hence by kind, so three tint changes cover all 55 aliens — one
    ## per alien was fifty-five native state changes a frame for the same picture.
    var tinted = 0
    for a in fleet do
        if a.alive then
            var k = kinds[a.kind]
            if a.kind <> tinted then
                gfx.tint(k.ink)
                tinted = a.kind
            end
            gfx.sprite(k.frames[frame], a.x, a.y, 8, 8)
        end
    end

    if ufo <> nil then
        gfx.tint(TOP_INK)
        gfx.sprite(ufoImg, ufo.x, UFO_Y, UFO_W, UFO_H)
    end

    gfx.tint(SHIELD_INK)
    for sh in shields do
        gfx.sprite(sh.img, sh.x, SHIELD_Y, SHIELD_W, SHIELD_H)
    end

    ## During the pause the cannon blinks, so the eye finds where it died before it comes back.
    if respawn <= 0.0 or math.frac(respawn * 6.0) < 0.5 then
        gfx.tint(GUN_INK)
        gfx.sprite(gunImg, gunX, GUN_Y, GUN_W, GUN_H)
    end
    gfx.tint(INK)
    for b in bombs do
        gfx.sprite(bombImgs[1 + (ticks // 6) % 2], b.x - 1, b.y, 3, 4)
    end
    for b in bursts do
        gfx.sprite(burstImg, b.x, b.y, 10, 7)
    end
    gfx.noTint()

    if shotLive then
        gfx.noStroke()
        gfx.fill(INK)
        gfx.rect(shotX, shotY, 1, 4)
    end

    gfx.noStroke()
    gfx.fill(GUN_INK)
    gfx.rect(MARGIN, GUN_Y + 8, FIELD_W - 2 * MARGIN, 1)   ## the floor the cannon stands on

    if popup <> nil then
        gfx.fontSize(8)
        gfx.stroke(TOP_INK)
        gfx.textMode("center", "center")
        gfx.text(popup.text, popup.x, popup.y)
    end

    gfx.fontSize(9)
    gfx.stroke(INK)
    gfx.textMode("left", "top")
    gfx.text("SCORE {score}", MARGIN, 8)
    gfx.textMode("center", "top")
    gfx.text("BEST {best}", FIELD_W / 2, 8)
    gfx.textMode("right", "top")
    gfx.text("WAVE {wave}", FIELD_W - MARGIN, 8)
    ## The lives left, as cannons: a count of the thing itself reads faster than a number.
    gfx.tint(GUN_INK)
    for i = 1, lives - 1 do
        gfx.sprite(gunImg, MARGIN + (i - 1) * (GUN_W + 4), FIELD_H - 13, GUN_W, GUN_H)
    end
    gfx.noTint()

    gfx.fontSize(7)
    gfx.stroke(DIM)
    gfx.textMode("center", "bottom")
    var hint = "arrows + space — P pauses — or play with one finger"
    if touchPlay then
        hint = "drag to move — tap the score band to pause"
    end
    gfx.text(hint, FIELD_W / 2, FIELD_H - 3)

    if paused then
        gfx.fontSize(12)
        gfx.stroke(GUN_INK)
        gfx.textMode("center", "center")
        gfx.text("PAUSED", FIELD_W / 2, 150)
    end

    if state == "over" then
        gfx.fontSize(14)
        gfx.stroke(TOP_INK)
        gfx.textMode("center", "center")
        gfx.text("GAME OVER", FIELD_W / 2, 150)
        gfx.fontSize(8)
        gfx.stroke(INK)
        gfx.text("SCORE {score} — press or tap to play again", FIELD_W / 2, 168)
    end
end
