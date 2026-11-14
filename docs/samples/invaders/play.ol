## The rules in motion: the wave, the fleet's tick, the bombs, the shot, the score and the cannon's drag.

## The fleet is stored bottom row first, left to right — the order the ticks advance it in, so the
## wave ripples upwards as it did on the original hardware.
func newWave()
    fleet = []
    for row = ROWS, 1, -1 do
        for col = 1, COLS do
            var kind = 3
            if row == 1 then
                kind = 1
            elseif row <= 3 then
                kind = 2
            end
            fleet.push({
                x: FLEET_X + (col - 1) * CELL_W,
                y: FLEET_Y + (row - 1) * CELL_H + (wave - 1) * WAVE_DROP,
                col: col,
                kind: kind,
                alive: true
            })
        end
    end
    buildShields()
    alive = #fleet
    cursor = 1
    heading = 1
    turning = false
    landed = false
    frame = 1
end

func startGame()
    wave = 1
    score = 0
    lives = LIVES
    respawn = 0.0
    ticks = 0
    gunX = FIELD_W / 2 - GUN_W / 2
    state = "play"
    paused = false
    shotLive = false
    bombs = []
    bursts = []
    nextLife = EXTRA_LIFE
    shots = 0
    ufo = nil
    ufoWait = UFO_PERIOD
    ufoDir = 1
    hushUfo()
    popup = nil
    marchStep = 0
    acc = 0.0        ## the previous game's leftover would be spent on this one's first frame
    newWave()
end

## A life every EXTRA_LIFE points, and the threshold moves up: crossing it twice in one hit still
## gives one life, which is what the original did.
func addScore(points)
    score += points
    if score > best then
        best = score
        data.set(BEST_KEY, best)
    end
    if score >= nextLife then
        lives += 1
        nextLife += EXTRA_LIFE
        showPopup("EXTRA LIFE", FIELD_W / 2, SHIELD_Y - 14)
    end
end

func showBurst(x, y)
    bursts.push({x: x, y: y, left: BLAST_TIME})
end

func showPopup(text, x, y)
    popup = {text: text, x: x, y: y, left: POPUP_TIME}
end

## The fleet is stored bottom row first, so the FIRST living alien of a column is its lowest one —
## the only one with a clear line to the cannon. No column bookkeeping is needed: the storage order
## already answers the question.
func lowestOf(col)
    for a in fleet do
        if a.alive and a.col == col then
            return a
        end
    end
    return nil
end

func dropBomb()
    if #bombs >= BOMB_MAX or alive == 0 then
        return
    end
    if math.randInt(1, BOMB_ODDS) <> 1 then
        return
    end
    var a = lowestOf(math.randInt(1, COLS))
    if a == nil then
        return
    end
    bombs.push({x: a.x + 4, y: a.y + 8})
end

## Losing a life clears the air: the bombs already falling belonged to the cannon that just died,
## and a fresh one must not walk into them.
func hitCannon()
    sndGun.play()
    showBurst(gunX + 1, GUN_Y - 1)
    hushUfo()
    bombs = []
    shotLive = false
    lives -= 1
    respawn = RESPAWN
    if lives <= 0 then
        state = "over"
    end
end

func bombsFall(dt)
    var i = 1
    while i <= #bombs do
        var b = bombs[i]
        b.y = b.y + BOMB_SPEED * dt
        var gone = b.y > FIELD_H
        var sh = shieldAt(b.x, b.y)
        if sh <> nil then
            bite(sh, b.x - sh.x, b.y - SHIELD_Y, BOMB_BITE, 1)
            gone = true
        elseif b.y + 4 > GUN_Y and b.y < GUN_Y + GUN_H and b.x >= gunX and b.x < gunX + GUN_W then
            hitCannon()
            return
        end
        ## A bomb and the cannon's shot cancel each other: two things crossing in the same lane
        ## cannot pass through one another. A bomb already stopped by a shield is spent, and must not
        ## take a shot down with it.
        if not gone and shotLive and math.abs(b.x - shotX) <= 2 and math.abs(b.y - shotY) <= 4 then
            shotLive = false
            gone = true
        end
        if gone then
            bombs.delete(i)
        else
            i += 1
        end
    end
end

## One tick: the next LIVING alien advances. A dead one costs nothing, and that is the whole
## mechanism of the acceleration. Reaching the end of the fleet ends the pass.
func fleetTick()
    for i = 1, #fleet do
        var a = fleet[cursor]
        cursor += 1
        if cursor > #fleet then
            cursor = 1
            frame = 3 - frame            ## the pass is over: the fleet changes frame
            marchStep = marchStep % #sndMarch + 1
            sndMarch[marchStep].play()   ## one note per pass: the beat IS the fleet's speed
            if turning then
                turning = false
                heading = -heading
                ## The descent moves the WHOLE fleet, so the landing is judged here as well: testing
                ## only the alien that advances would leave the fleet standing on the cannon for up
                ## to a full pass before the game noticed.
                for b in fleet do
                    b.y = b.y + WAVE_DROP
                    if b.alive and b.y + 8 >= GUN_Y then
                        landed = true
                    end
                end
            end
        end
        if a.alive then
            a.x = a.x + STEP_X * heading
            if a.x <= MARGIN or a.x + 8 >= FIELD_W - MARGIN then
                turning = true
            end
            ## Level with the shields, it eats its way through: the arch is no shelter once the fleet
            ## reaches it. Tested only when the fleet is low enough — for most of a game the aliens
            ## are a hundred pixels above, and the four rectangles would be compared for nothing.
            if a.y + 8 > SHIELD_Y then
                for sh in shields do
                    if a.x + 8 > sh.x and a.x < sh.x + SHIELD_W and a.y < SHIELD_Y + SHIELD_H then
                        eraseBox(sh, a.x - sh.x, a.y - SHIELD_Y, 8, 8)
                    end
                end
            end
            ## The fleet landing is as fatal as a bomb, and the alien that just moved is the only one
            ## that can have crossed the line: asking the whole fleet once per frame was 55 tests for
            ## at most one transition in a game.
            if a.y + 8 >= GUN_Y then
                landed = true
            end
            return
        end
    end
end

func fire()
    if shotLive or alive == 0 then
        return
    end
    shots += 1
    sndShoot.play()
    shotLive = true
    shotX = gunX + GUN_W / 2
    shotY = GUN_Y - 4
end

## A shot hits the first living alien whose 8x8 box holds its tip.
func shotHits()
    for a in fleet do
        if a.alive and shotX >= a.x and shotX < a.x + 8 and shotY >= a.y and shotY < a.y + 8 then
            a.alive = false
            alive -= 1
            sndAlien.play()
            showBurst(a.x - 1, a.y)
            addScore(kinds[a.kind].points)
            return true
        end
    end
    return false
end

## Taking hold: the cannon stays where it is, and the offset between the finger and it is what the
## drag preserves.
func grab(x)
    grabX = x
    grabGun = gunX
end

## The cannon follows the finger's DISPLACEMENT. When the wall stops it, the hold is re-anchored on
## the spot: without that, a finger carried on past the wall would owe the same distance back before
## the cannon moved again — a dead zone that feels like a stuck control.
func dragTo(x)
    var wanted = grabGun + (x - grabX)
    var stopped = math.clamp(wanted, MARGIN, FIELD_W - MARGIN - GUN_W)
    if stopped <> wanted then
        grabX = x
        grabGun = stopped
    end
    gunX = stopped
end
