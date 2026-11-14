## The title screen.

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
