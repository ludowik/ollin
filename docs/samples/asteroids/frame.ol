## What each frame does besides moving things: the heartbeat, the age of the shots, and what a shot hits.

## The two held sounds, silenced together. A game that has stopped must not go on humming, and
## listing them in one place is what stops the next one from being forgotten — the saucer's was.
func hushVoices()
    if thrustVoice.isPlaying() then
        thrustVoice.stop()
    end
    if saucerVoice.isPlaying() then
        saucerVoice.stop()
    end
end

## The heartbeat's tempo is the number of rocks left, from slow on a full field to urgent on the
## last one. Nothing schedules it: this is read from the field itself, every frame.
func beat(dt)
    beatTimer -= dt
    if beatTimer > 0.0 then
        return
    end
    var period = math.clamp(0.28 + #rocks * 0.09, 0.28, 1.1)
    beatTimer = period
    sndBeat[beatStep + 1].play()
    beatStep = (beatStep + 1) % 2
end

## Anything the player fired, or was fired at, dies of OLD AGE — that is what gives a shot its
## range. The two lists differ only in what they hit, so the ageing is written once.
func ageShots(list, dt)
    return list.filter(func(s)
        advance(s, dt)
        s.left -= dt
        return s.left > 0.0
    end)
end

## The player's shots against the rocks and the saucer. A shot is spent by the first thing it
## touches, so it cannot cut a line through a cluster.
func shotsHit()
    shots = shots.filter(func(s)
        if saucer <> nil and near(s.x, s.y, saucer.x, saucer.y, saucer.r) then
            killSaucer()
            return false
        end
        var r = rockAt(s.x, s.y, 0.0)
        if r == nil then
            return true
        end
        breakRock(r)
        return false
    end)
end
