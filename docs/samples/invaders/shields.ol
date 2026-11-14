## The four shields: each one its own texture, eroded pixel by pixel by what hits it.

## A fresh set of shields: they are rebuilt for every wave, so a cleared wave hands back four whole
## arches — and the erosion of the previous one is genuinely gone, the textures being new.
func buildShields()
    shields = []
    for i = 1, SHIELDS do
        shields.push({img: image.fromPattern(SHIELD), x: SHIELD_GAP * i + SHIELD_W * (i - 1)})
    end
end

## Carves a pattern out of a shield, in the texture's own coordinates. `dir` is where the projectile
## was going: -1 for the cannon's shot, which eats UPWARDS from the pixel it struck, +1 for a bomb,
## which eats downwards. The pattern is centred horizontally and anchored on the impact, so the
## crater opens on the side the hit came from — a bite taken symmetrically would hollow the shield
## from the middle and let a second shot straight through.
func bite(sh, cx, cy, rows, dir)
    sh.rows = nil
    var w = len(rows[1])
    var top = cy
    if dir < 0 then
        top = cy - #rows + 1
    end
    image.beginPixels(sh.img)
    for r = 1, #rows do
        for c = 1, w do
            if string.char(rows[r], c) == "#" then
                image.setPixel(sh.img, cx - w // 2 + c - 1, top + r - 1, 0, 0, 0, 0)
            end
        end
    end
    image.endPixels(sh.img)
end

## An alien that has descended into a shield does not nibble it: it erases its whole footprint, which
## is what makes the fleet's arrival final.
func eraseBox(sh, cx, cy, w, h)
    sh.rows = nil
    image.beginPixels(sh.img)
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            image.setPixel(sh.img, cx + x, cy + y, 0, 0, 0, 0)
        end
    end
    image.endPixels(sh.img)
end

## The first shield whose SOLID pixel is under (x, y) — a hole is passed through, which is the whole
## point of eroding a texture rather than shrinking a box.
func shieldAt(x, y)
    for sh in shields do
        if x >= sh.x and x < sh.x + SHIELD_W and y >= SHIELD_Y and y < SHIELD_Y + SHIELD_H then
            var r, g, b, a = image.getPixel(sh.img, x - sh.x, y - SHIELD_Y)
            if a > 0.5 then
                return sh
            end
        end
    end
    return nil
end

## One shield as save.ol writes it: a `#` for a pixel still whole and a `.` for one that was eaten. Read from the
## texture once and kept in `sh.rows` until a hit changes the shield: reading its pixels twice a second was a hitch.
func shieldRows(sh)
    if sh.rows then
        return sh.rows
    end
    var rows = []
    for y = 0, SHIELD_H - 1 do
        var row = ""
        for x = 0, SHIELD_W - 1 do
            var r, g, b, a = image.getPixel(sh.img, x, y)
            row += a > 0.5 and "#" or "."
        end
        rows.push(row)
    end
    sh.rows = rows
    return rows
end

## Eats from a shield what the save says was eaten: it starts whole, as a wave builds it, and erosion only removes.
func carveShield(sh, rows)
    sh.rows = nil
    image.beginPixels(sh.img)
    for y = 1, SHIELD_H do
        for x = 1, SHIELD_W do
            if string.char(rows[y], x) == "." then
                image.setPixel(sh.img, x - 1, y - 1, 0, 0, 0, 0)
            end
        end
    end
    image.endPixels(sh.img)
end
