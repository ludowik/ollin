## The game put away and taken back: what is kept from one run to the next, and when.

## The game under way as a map. What is not kept means nothing a second run could use: the kills coming apart, the
## value written where the ship died, the fingers and the clock that spends the ticks. The best score has its own key.
func saveState()
    var t = {
        v: SAVE_VERSION, state: state, wave: wave, score: score, lives: lives, nextLife: nextLife, shots: shots,
        ticks: ticks, marchStep: marchStep, cursor: cursor, heading: heading, turning: turning, frame: frame,
        fx: [], fy: [], fa: [], shields: [], gunX: gunX, shotLive: shotLive, shotX: shotX, shotY: shotY,
        bombs: bombs, respawn: respawn, ufoWait: ufoWait, ufoDir: ufoDir, ufo: ufo
    }
    clampToRanges(t, SAVE_WHOLES, SAVE_NUMBERS)
    for a in fleet do
        t.fx.push(a.x)
        t.fy.push(a.y)
        t.fa.push(a.alive)
    end
    for sh in shields do
        t.shields.push(shieldRows(sh))
    end
    return t
end

## Puts a state read by readSave in the game. The wave is built first, so that the fleet and the shields exist as a wave
## makes them, and the save then moves them to where they were. A game that was running comes back in pause.
func restoreSave(t)
    wave = t.wave
    newWave()
    alive = 0
    for i = 1, #fleet do
        fleet[i].x = t.fx[i]
        fleet[i].y = t.fy[i]
        fleet[i].alive = t.fa[i]
        if t.fa[i] then
            alive += 1
        end
    end
    for i = 1, SHIELDS do
        carveShield(shields[i], t.shields[i])
    end
    state = t.state
    score = t.score
    lives = t.lives
    nextLife = t.nextLife
    shots = t.shots
    ticks = t.ticks
    marchStep = t.marchStep
    cursor = t.cursor
    heading = t.heading
    turning = t.turning
    frame = t.frame
    gunX = t.gunX
    shotLive = t.shotLive
    shotX = t.shotX
    shotY = t.shotY
    bombs = t.bombs
    respawn = t.respawn
    ufoWait = t.ufoWait
    ufoDir = t.ufoDir
    ufo = t.ufo
    paused = state == "play"
end

func saveGame()
    keepSaved(SAVE_KEY, saveState())
end
