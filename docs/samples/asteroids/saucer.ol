## The saucer: its crossings, its aim, which improves with the score, and its death.

func spawnSaucer()
    var small = score >= SAUCER_SMALL_AT and math.rand() < 0.5
    var dir = 1
    var x = -SAUCER_BIG_R
    if math.rand() < 0.5 then
        dir = -1
        x = FIELD_W + SAUCER_BIG_R
    end
    saucer = {
        x: x, y: 40.0 + math.rand() * (FIELD_H - 80.0),
        vx: SAUCER_SPEED * dir, vy: 0.0,
        small: small,
        r: SAUCER_SMALL_R,
        shoot: SAUCER_SHOT,
        swerve: 1.0
    }
    if not small then
        saucer.r = SAUCER_BIG_R
    end
end

func dropSaucer()
    saucer = nil
    saucerVoice.stop()
    saucerTimer = SAUCER_PERIOD
end

## The saucer's AIM is the game's difficulty curve, and it is the score that draws it: the error on
## its shot shrinks from a whole quadrant to almost nothing. The small saucer aims better still, at
## every score.
func saucerFire()
    if ship == nil then
        return
    end
    var aim = math.atan2(ship.y - saucer.y, ship.x - saucer.x)
    var err = math.max(0.05, 0.8 - score / 12000.0)
    if saucer.small then
        err *= 0.4
    end
    aim += (math.rand() * 2 - 1) * err
    saucerShots.push({
        x: saucer.x, y: saucer.y,
        vx: math.cos(aim) * SHOT_SPEED * 0.7,
        vy: math.sin(aim) * SHOT_SPEED * 0.7,
        left: SHOT_LIFE * 1.3
    })
    sndFire.play()
end

func killSaucer()
    var points = SAUCER_BIG_SCORE
    if saucer.small then
        points = SAUCER_SMALL_SCORE
    end
    award(points)
    sndSaucerDie.play()
    burst(saucer.x, saucer.y, 14, 100.0)
    dropSaucer()
end

func saucerUpdate(dt)
    if saucer == nil then
        saucerTimer -= dt
        ## It stays away while the field is nearly clear: the last rocks must not have to be shot
        ## at through it.
        if saucerTimer <= 0.0 and #rocks > 1 and state == "play" then
            spawnSaucer()
        end
        return
    end
    saucer.swerve -= dt
    if saucer.swerve <= 0.0 then
        saucer.vy = (math.rand() * 2 - 1) * SAUCER_SPEED * 0.6
        saucer.swerve = 0.6 + math.rand() * 0.9
    end
    saucer.x += saucer.vx * dt
    saucer.y += saucer.vy * dt
    saucer.y = math.clamp(saucer.y, 20.0, FIELD_H - 20.0)
    ## The hum belongs to the saucer being THERE, not to the frame it appeared on: starting it here
    ## means a pause or an end that silenced it gets it back on resume, and nothing has to remember
    ## which of the two happened.
    if not saucerVoice.isPlaying() then
        saucerVoice.start()
    end
    saucerVoice.freq(SAUCER_HUM + SAUCER_WARBLE * math.sin(elapsedTime * SAUCER_RATE))
    ## It crosses the field ONCE. It does not wrap: a wrapping saucer would never leave, and the
    ## crossing is what makes it an event.
    if saucer.x < -saucer.r * 2 or saucer.x > FIELD_W + saucer.r * 2 then
        dropSaucer()
        return
    end
    saucer.shoot -= dt
    if saucer.shoot <= 0.0 then
        saucerFire()
        saucer.shoot = SAUCER_SHOT
    end
end
