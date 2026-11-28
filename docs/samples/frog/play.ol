## What happens in a frame of play, and what a hop, a death and a home do. The rules themselves are in rules.ol; this is the
## game that applies them to the frog and the lanes in state.ol.

import "field.ol"
import "rules.ol"
import "state.ol"
import "sounds.ol"
import "../lib/area.ol"

const DIRS = {up: {dr: 1, dx: 0}, down: {dr: -1, dx: 0}, left: {dr: 0, dx: -CELL}, right: {dr: 0, dx: CELL}}

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
    if frog.hop <> nil then
        ## the wreck is where the frog was hit, not where it started the hop
        frog.x = hopX(frog.hop)
        frog.row = hopRow(frog.hop)
        frog.hop = nil
    end
    if DEATHS[kind].thud then
        play(sndThud)
    else
        play(sndSplash)
    end
end

## A life is over: the next frog, or the end of the game.
func endLife()
    lives -= 1
    if lives <= 0 then
        saveBest()
        state = "over"
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
    if not homes.has(false) then
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
        if frog.row < ROW_HOMES then
            earn(SCORE_HOP)       ## the homes pay for themselves, and only to a frog that gets in
        end
    end
    if frog.row == ROW_HOMES then
        arriveHome()
    end
end

## What a button does, whether it is pressed on the screen or by its key.
func pressButton(name)
    if name == "pause" then
        if state == "play" then
            paused = not paused
        end
    elseif name == "sound" then
        soundOn = not soundOn
    else
        tryHop(name)
    end
end

func start()
    newGame()
    play(sndStart)
end

## Space and a tap start a game from the title and from the end screen, and the same press must not hop the frog: one place
## decides. True when the press was spent on starting (or on waiting out the end screen).
func begin()
    if state == "play" then
        return false
    end
    if state == "over" and frog.deadT < 1.5 then
        return true
    end
    start()
    return true
end

## A tap on the screen at (x, y) of the viewport: it starts a game, resumes a paused one, and otherwise presses the button it is on.
func tap(x, y)
    if begin() then
        return
    end
    if paused then
        paused = false
        return
    end
    var b = rectAt(buttons, x, y)
    if b <> nil then
        pressButton(b.name)
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

## Time goes by on the field: the clock, and the lanes that run whatever the frog does.
func tickWorld(dt)
    clock += dt
    for lane = 0, 10 do
        laneOff[lane + 1] = advanceLane(laneOff[lane + 1], lane, board, dt)
    end
end

func updatePlay(dt)
    tickWorld(dt)
    updateEvent(dt)
    if banner <> nil then
        banner.left -= dt
        if banner.left <= 0 then
            banner = nil
        end
    end
    if frog.dead <> nil then
        frog.deadT += dt
        if frog.deadT >= DEATH_TIME then
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
            var row = hopRow(frog.hop)
            if isRoadRow(row) then
                checkGround(row, hopX(frog.hop))
            end
            return
        end
        if frog.dead <> nil then
            return
        end
    end

    if isRiverRow(frog.row) then
        frog.x += laneVelocity(laneOfRow(frog.row), board) * dt
        if not onField(frog.x) then
            die("edge")
            return
        end
    end
    checkGround(frog.row, frog.x)
end

## One frame, whatever the screen: play, the end screen (whose wreck stays) and the title (whose lanes run).
func updateFrame(dt)
    dt = math.min(dt, 0.05)
    if state == "play" then
        if not paused then
            updatePlay(dt)
        end
        return
    end
    tickWorld(dt)
    if state == "over" then
        frog.deadT += dt
    end
end
