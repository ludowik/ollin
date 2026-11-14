## The game put away and taken back: what is kept from one run to the next, and when.

## The game under way as a map. What is not kept means nothing a second run could use: the sparks, the fingers, the
## cadence of a held trigger, the heartbeat. The best score has its own key. A rock keeps its `dead` mark and the
## saucer its radius, which restoreSave puts right.
func saveState()
    var t = {
        v: SAVE_VERSION, state: state, score: score, lives: lives, wave: wave, nextExtra: nextExtra, spawn: spawn,
        waveWait: waveWait, saucerTimer: saucerTimer, ship: ship, rocks: rocks, shots: shots,
        saucer: saucer, saucerShots: saucerShots
    }
    clampToRanges(t, SAVE_WHOLES, SAVE_NUMBERS)
    return t
end

## Puts a state read by readSave in the game. A game that was running comes back in pause.
func restoreSave(t)
    state = t.state
    score = t.score
    lives = t.lives
    wave = t.wave
    nextExtra = t.nextExtra
    spawn = t.spawn
    waveWait = t.waveWait
    saucerTimer = t.saucerTimer
    ship = t.ship
    rocks = t.rocks
    for r in rocks do
        r.dead = false
    end
    shots = t.shots
    saucerShots = t.saucerShots
    saucer = t.saucer
    if saucer <> nil then
        saucer.r = saucer.small and SAUCER_SMALL_R or SAUCER_BIG_R
    end
    debris = []
    fireId = nil
    padId = nil
    pad.release()
    fireTimer = 0.0
    paused = state == "play"
end

## Keeps the game; `data` leaves the file alone when it is what was kept last.
func saveGame()
    data.set(SAVE_KEY, saveState())
    markKept(state)
end

## The game as a run began it: put back where the last run left it when there is a save to trust. Whether it was.
func loadGame()
    if not loadKept(SAVE_KEY, saveValid, restoreSave) then
        return false
    end
    markKept(state)
    return true
end

func autosave(dt)
    keepGoing(dt, state, saveGame)
end
