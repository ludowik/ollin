## The mystery ship: its crossings, what it is worth, and what happens when it is hit.

## The ship's tone belongs to the crossing: it stops with the ship, whether it left, was shot, or the
## cannon died under it.
func hushUfo()
    if ufoVoice <> nil and ufoVoice.isPlaying() then
        ufoVoice.stop()
    end
end

## The value of the mystery ship for the shot that just hit it, read from the table as the original
## read it — the count wraps, so the 300 comes back within reach.
func ufoValue()
    return UFO_VALUES[1 + shots % #UFO_VALUES]
end

## One crossing at a time, from alternating sides, and never while the wave is nearly cleared.
func ufoUpdate(dt)
    if ufo == nil then
        ufoWait -= dt
        if ufoWait <= 0.0 and alive >= UFO_MIN_ALIVE then
            var x = -UFO_W
            if ufoDir < 0 then
                x = FIELD_W
            end
            ufo = {x: x, dir: ufoDir}
            ufoDir = -ufoDir
            ufoWait = UFO_PERIOD
        end
        return
    end
    ufo.x = ufo.x + UFO_SPEED * ufo.dir * dt
    if not ufoVoice.isPlaying() then
        ufoVoice.start()        ## at the start of a crossing, and again for one that a save brought back
    end
    ufoVoice.freq(UFO_HUM + UFO_WARBLE * math.sin(elapsedTime * UFO_RATE * 6.28318))
    if ufo.x < -UFO_W or ufo.x > FIELD_W then    ## it left the field: it was worth nothing
        ufo = nil
        hushUfo()
    end
end

func ufoHit()
    if ufo == nil or not shotLive then
        return false
    end
    if shotX < ufo.x or shotX >= ufo.x + UFO_W or shotY > UFO_Y + UFO_H or shotY < UFO_Y then
        return false
    end
    var points = ufoValue()
    sndUfo.play()
    showBurst(ufo.x + 3, UFO_Y)
    hushUfo()
    addScore(points)
    showPopup("{points}", ufo.x + UFO_W / 2, UFO_Y + 3)
    ufo = nil
    return true
end
