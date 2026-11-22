## What happens in a frame of play, and what a hop, a death and a home do. The rules themselves are in rules.ol; this is the
## game that applies them to the frog and the lanes in state.ol.

import "field.ol"
import "rules.ol"
import "state.ol"
import "sounds.ol"

const DIRS = {up: {dr: 1, dx: 0}, down: {dr: -1, dx: 0}, left: {dr: 0, dx: -CELL}, right: {dr: 0, dx: CELL}}
const BEST_KEY = "best"

func earn(points)
    var now, extra = addScore(score, points, extraGiven)
    score = now
    if extra then
        extraGiven = true
        lives += 1
        play(sndExtra)
    end
end

func die(kind)
    if frog.dead <> nil then
        return
    end
    frog.dead = kind
    frog.deadT = 0.0
    frog.hop = nil
    if kind == "car" or kind == "croc" then
        play(sndThud)
    else
        play(sndSplash)
    end
end

## A life is over: the next frog, or the end of the game.
func endLife()
    lives -= 1
    if lives <= 0 then
        if score > best then
            best = score
            data.set(BEST_KEY, best)
        end
        state = "over"
        frog.dead = "over"
        return
    end
    placeFrog()
end

func tryHop(dir)
    if state <> "play" or paused or frog.dead <> nil or frog.hop <> nil or frog.ready > 0 then
        return
    end
    var d = DIRS[dir]
    var row = frog.row + d.dr
    var x = frog.x + d.dx
    if row < ROW_START or row > ROW_HOMES or not onField(x) then
        return
    end
    frog.hop = {t: 0.0, fromX: frog.x, fromRow: frog.row, toX: x, toRow: row}
    frog.face = dir
    play(sndHop)
end

func arriveHome()
    var h = homeAt(frog.x)
    if h == nil or homes[h] then
        die("wall")
        return
    end
    if event <> nil and event.kind == "crocodile" and event.home == h then
        die("croc")
        return
    end
    var fly = event <> nil and event.kind == "fly" and event.home == h
    earn(homeScore(timeLeft, fly))
    homes[h] = true
    if fly then
        event = nil
    end
    play(sndHome)
    var all = true
    for filled in homes do
        all = all and filled
    end
    if all then
        earn(SCORE_BOARD)
        lives += 1
        board += 1
        clearHomes()
        event = nil
        banner = {text: "LEVEL {board}", left: 2.0}
        play(sndExtra)
    end
    placeFrog()
end

func land()
    var h = frog.hop
    frog.row = h.toRow
    frog.x = h.toX
    frog.hop = nil
    if frog.row > furthest then
        furthest = frog.row
        earn(SCORE_HOP)
    end
    if frog.row == ROW_HOMES then
        arriveHome()
    end
end

## A fly or a crocodile in one of the homes that is still empty, from time to time.
func updateEvent(dt)
    if event <> nil then
        event.left -= dt
        if event.left <= 0 then
            event = nil
            eventWait = EVENT_GAP + rng.rand() * 8
        end
        return
    end
    eventWait -= dt
    if eventWait > 0 then
        return
    end
    var free = []
    for h = 1, HOMES do
        if not homes[h] then
            free.push(h)
        end
    end
    if #free == 0 then
        eventWait = EVENT_GAP
        return
    end
    var kind = "crocodile"
    if rng.rand() < 0.65 then
        kind = "fly"
    end
    event = {kind: kind, home: free[rng.randInt(#free)], left: EVENT_LIFE}
end

## What the frog standing on a row meets this frame: the vehicles of a road lane, the water or what floats in a river lane.
func checkGround(row, x)
    var lane = laneOfRow(row)
    if lane == nil then
        return
    end
    var tier = tierOfBoard(board)
    if isRoadRow(row) then
        if roadHit(tier, lane, laneOff[lane + 1], x) then
            die("car")
        end
    elseif riverSupport(tier, lane, laneOff[lane + 1], clock, x) == nil then
        die("drown")
    end
end

func updatePlay(dt)
    clock += dt
    for lane = 0, 10 do
        laneOff[lane + 1] = advanceLane(laneOff[lane + 1], lane, board, dt)
    end
    updateEvent(dt)
    if banner <> nil then
        banner.left -= dt
        if banner.left <= 0 then
            banner = nil
        end
    end
    if frog.dead <> nil then
        frog.deadT += dt
        if frog.dead <> "over" and frog.deadT >= DEATH_TIME then
            endLife()
        end
        return
    end
    if frog.ready > 0 then
        frog.ready -= dt
    end
    timeLeft -= dt
    if timeLeft <= 0 then
        die("time")
        return
    end

    if frog.hop <> nil then
        frog.hop.t += dt
        if frog.hop.t >= HOP_TIME then
            land()
        else
            ## in the air a frog is only run down: it is over the row it left for the first half of the hop, the other after
            var h = frog.hop
            var row = h.fromRow
            if h.t >= HOP_TIME / 2 then
                row = h.toRow
            end
            if isRoadRow(row) then
                checkGround(row, h.fromX + (h.toX - h.fromX) * h.t / HOP_TIME)
            end
            return
        end
        if frog.dead <> nil or state <> "play" then
            return
        end
    end

    var lane = laneOfRow(frog.row)
    if lane <> nil and isRiverRow(frog.row) then
        frog.x += LANE_DIR[lane + 1] * LANE_SPEED[lane + 1] * speedFactor(board) * dt
        if not onField(frog.x) then
            die("edge")
            return
        end
    end
    checkGround(frog.row, frog.x)
end
