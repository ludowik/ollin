## The rules of Frog with no drawing and no state but their arguments, so that they can be tested alone. A lane is a STRIP of
## 32 tiles scrolling past, with its objects spread along it: the arcade draws them from tables (arcade.ol) and moves the whole
## strip, and so does this. Where an object is, who rides it, what runs the frog over and whether a turtle is under water are
## all worked out from a lane's offset and the time.
##
## What comes from the arcade game's own tables: the picture of every lane object, how many tiles long it is, the gap that
## follows it and how many there are in a lane. The way each lane runs was read by hand from the routine that moves them.
## The SPEEDS, the turtles' diving, the timer and the points are ours, set by playing: the program's code is not readable
## that far (see README.md).

import "field.ol"
import "arcade.ol"
import "tiles.ol"
import "../lib/area.ol"

## The way each lane runs, from the top of the river (read from the arcade routine that moves the eleven lane objects):
## 1 to the right, -1 to the left, 0 for the median strip.
const LANE_DIR   = [1, -1, 1, 1, -1, 0, -1, 1, -1, 1, -1]
## Pixels per second on the first board; every board after it is a little faster.
const LANE_SPEED = [28.0, 24.0, 44.0, 20.0, 32.0, 0.0, 28.0, 36.0, 30.0, 52.0, 24.0]
## What each lane carries: logs and turtles in the river, vehicles on the road, nothing on the median strip.
const LANE_KIND  = ["log", "turtle", "log", "log", "turtle", "none", "truck", "car", "car", "car", "car"]

## The turtles are the lanes that dive.
func divesIn(lane)
    return LANE_KIND[lane + 1] == "turtle"
end

func hasObjects(lane)
    return LANE_KIND[lane + 1] <> "none"
end

const SPEED_PER_BOARD = 0.1
const SPEED_MAX       = 2.2

## The frog's body is smaller than its cell: a vehicle must touch the 12 pixels in the middle.
const BODY_INSET = 2

const DIVE_CYCLE = 9.0         ## seconds from one dive to the next, for a group of turtles
const DIVE_AT    = 5.0         ## the second of the cycle when the group starts to sink
const DIVE_STEP  = 0.6         ## how long it takes to sink one step, and to come up one
const DIVE_UNDER = 1.6         ## how long it stays under

const SCORE_HOP   = 10         ## a row nearer the homes than it has been before
const SCORE_HOME  = 50
const SCORE_FLY   = 200
const SCORE_BOARD = 1000
const SCORE_SECOND = 10        ## per second left on the clock, when a frog gets home
const EXTRA_AT    = 20000      ## an extra frog the first time the score gets here
const SCORE_MAX   = 999999999
const LIVES       = 3
const TIME_LIMIT  = 30.0
const TIME_LOW    = 8.0        ## the clock is shown in alarm colours under this

const HOP_TIME    = 0.14       ## seconds a hop lasts: the frog cannot be steered meanwhile
const DEATH_TIME  = 1.3        ## how long the wreck is shown before the next frog, or the end
const READY_TIME  = 1.2        ## a new frog is held that long before it can move
const EVENT_LIFE  = 6.0        ## how long a fly or a crocodile stays in its home
const EVENT_GAP   = 9.0        ## seconds between two, at least; the rest is drawn by the game's own Random

## How a frog dies: whether the sound is a thud (run over, eaten) or a splash, and whether it is shown as a splash of bubbles
## (SPLASH_STEP seconds for each of the three pictures) before the skull.
const DEATHS = {
    car:   {thud: true,  splash: false},
    croc:  {thud: true,  splash: false},
    drown: {thud: false, splash: true},
    edge:  {thud: false, splash: true},
    wall:  {thud: false, splash: true},
    time:  {thud: false, splash: false}
}
const SPLASH_STEP = 0.15
const SPLASH_TIME = 0.45

func wrapTo(v, size)
    return v - size * math.floor(v / size)
end

func isRoadRow(row)
    return row > ROW_START and row < ROW_MEDIAN
end

func isRiverRow(row)
    return row > ROW_MEDIAN and row < ROW_HOMES
end

## The lane of a row, or nil for the start strip, the median strip and the homes.
func laneOfRow(row)
    if not isRoadRow(row) and not isRiverRow(row) then
        return nil
    end
    return ROW_HOMES - 1 - row
end

func tierOfBoard(board)
    return (board - 1) % 5 + 1
end

func speedFactor(board)
    return math.min(1.0 + SPEED_PER_BOARD * (board - 1), SPEED_MAX)
end

## What a lane is made of on each tier: the length of an object, the period of the strip (an object and the gap after it) and
## how many objects there are, worked out once.
func buildSpecs()
    var out = []
    for tier = 1, #TIERS do
        var lanes = []
        for t in TIERS[tier] do
            var rows = t[2]
            lanes.push({len: rows * TILE, period: (rows + t[1] // (STRIP // TILE)) * TILE, count: t[3], tiles: rows})
        end
        out.push(lanes)
    end
    return out
end

const SPECS = buildSpecs()

## A lane is numbered 0..10, a tier 1..5 (a board's tier comes round every five boards).
func laneSpec(tier, lane)
    return SPECS[tier][lane + 1]
end

## The picture of a lane's object: its tiles in pairs, the first pair at the right-hand end (the arcade draws its strips
## that way round), a pair being the 8 pixels of one tile above the 8 of the other. `phase` picks one of the poses of
## swimming a turtle has: the pictures follow each other in the table a fixed distance apart, which is more than the tiles a
## group of turtles takes of each.
func laneRows(lane, phase)
    var rows = laneSpec(1, lane).tiles
    var codes = LANE_TILES[lane + 1]
    var base = phase * (#codes // LANE_PHASES[lane + 1])
    var out = []
    for y = 0, CELL - 1 do
        var line = []
        for x = 0, rows * TILE - 1 do
            var code = codes[base + 2 * (rows - 1 - x // TILE) + y // TILE + 1]
            line.push(TILES[code + 1].char((y % TILE) * TILE + x % TILE + 1))
        end
        out.push(line.join(""))
    end
    return out
end

## The columns of a lane's object that are drawn, [first, one past the last]: a vehicle runs the frog down where it SHOWS, and
## its picture has margins that are blank.
func laneArt(lane)
    var rows = laneRows(lane, 0)
    var lo = len(rows[1])
    var hi = 0
    for row in rows do
        for x = 1, len(row) do
            if row.char(x) <> "0" then
                lo = math.min(lo, x - 1)
                hi = math.max(hi, x)
            end
        end
    end
    return [lo, hi]
end

func buildArt()
    var out = []
    for lane = 0, 10 do
        if hasObjects(lane) then
            out.push(laneArt(lane))
        else
            out.push(nil)
        end
    end
    return out
end

const LANE_ART = buildArt()

## How fast a lane's strip runs on a board, in pixels per second, and which way (negative to the left).
func laneVelocity(lane, board)
    return LANE_DIR[lane + 1] * LANE_SPEED[lane + 1] * speedFactor(board)
end

## The offset of a lane's strip, advanced by dt seconds on a board.
func advanceLane(pos, lane, board, dt)
    return wrapTo(pos + laneVelocity(lane, board) * dt, STRIP)
end

## 0 a group of turtles on the surface, 1 and 2 sinking or coming up, 3 under water. Only every other group dives, and they
## do not all dive together: a group's turn comes two seconds after the one before it.
func turtleFrame(t, group)
    if group % 2 == 0 then
        return 0
    end
    var u = wrapTo(t + group * 2.0, DIVE_CYCLE)
    if u < DIVE_AT then
        return 0
    elseif u < DIVE_AT + DIVE_STEP then
        return 1
    elseif u < DIVE_AT + 2 * DIVE_STEP then
        return 2
    elseif u < DIVE_AT + 2 * DIVE_STEP + DIVE_UNDER then
        return 3
    elseif u < DIVE_AT + 3 * DIVE_STEP + DIVE_UNDER then
        return 2
    end
    return 1
end

## The objects of a lane that show: where each starts and ends on the field, and which of the strip's objects it is (for the
## turtles, which group). One that crosses the seam of the strip shows twice, at the two edges.
func laneItems(tier, lane, pos)
    var spec = laneSpec(tier, lane)
    var out = []
    for i = 0, spec.count - 1 do
        var s = wrapTo(pos + i * spec.period, STRIP)
        for copy = 0, 1 do
            var x0 = s - copy * STRIP
            if x0 < FIELD_W and x0 + spec.len > 0 then
                out.push({x0: x0, x1: x0 + spec.len, group: i})
            end
        end
    end
    return out
end

## Whether a vehicle of the road lane runs the frog down, its cell being at x.
func roadHit(tier, lane, pos, x)
    var art = LANE_ART[lane + 1]
    for it in laneItems(tier, lane, pos) do
        if x + CELL - BODY_INSET > it.x0 + art[1] and x + BODY_INSET < it.x0 + art[2] then
            return true
        end
    end
    return false
end

## What holds a frog in the river lane: the object its middle is over, or nil — the water — and a group of turtles that is under
## water holds nothing.
func riverSupport(tier, lane, pos, t, x)
    var mid = x + CELL / 2
    for it in laneItems(tier, lane, pos) do
        if mid >= it.x0 and mid <= it.x1 then
            if divesIn(lane) and turtleFrame(t, it.group) == 3 then
                return nil
            end
            return it
        end
    end
    return nil
end

## Whether a cell whose left edge is at x is still inside the field.
func onField(x)
    return x >= 0 and x + CELL <= FIELD_W
end

## The cell, from 1 to 5, a frog arriving at x is in, or nil when it is against a wall.
func homeAt(x)
    for h = 1, HOMES do
        if math.abs(x - homeX(h)) <= HOME_REACH then
            return h
        end
    end
    return nil
end

## Where a hop has taken the frog: the share of it done, and the x and the row it is over — the row it left for the first half of
## the hop, the one it is going to for the second.
func hopFraction(hop)
    return math.min(hop.t / HOP_TIME, 1.0)
end

func hopX(hop)
    return hop.fromX + (hop.toX - hop.fromX) * hopFraction(hop)
end

func hopRow(hop)
    if hopFraction(hop) >= 0.5 then
        return hop.toRow
    end
    return hop.fromRow
end

## Which of the three pictures of a splash is shown t seconds after the frog went in the water.
func splashFrame(t)
    return 1 + math.floor(t / SPLASH_STEP)
end

## The button of a list under a point of the viewport, by name, or nil.
func buttonAt(buttons, x, y)
    for b in buttons do
        if inRect(x, y, b) then
            return b.name
        end
    end
    return nil
end

## What a frog is given for arriving home with `left` seconds on the clock, `fly` saying it ate the fly.
func homeScore(left, fly)
    var s = SCORE_HOME + SCORE_SECOND * math.floor(left)
    if fly then
        s += SCORE_FLY
    end
    return s
end

## The score after earning `points`, and whether it earned the extra frog (only the first time it gets to EXTRA_AT).
func addScore(score, points, extraGiven)
    var now = math.min(score + points, SCORE_MAX)
    if not extraGiven and now >= EXTRA_AT then
        return now, true
    end
    return now, false
end
