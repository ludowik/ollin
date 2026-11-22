## The rules of Frog with no drawing and no state but their arguments, so that they can be tested alone. A lane is a STRIP of
## 32 tiles scrolling past, with its objects spread along it: the arcade draws them from tables (arcade.ol) and moves the whole
## strip, and so does this. Where an object is, who rides it, what runs the frog over and whether a turtle is under water are
## all worked out from a lane's offset and the time.
##
## What comes from the arcade game's own tables: the picture of every lane object, how many tiles long it is, the gap that
## follows it, how many there are in a lane, and the way each lane runs. The SPEEDS, the turtles' diving, the timer and the
## points are ours, set by playing: the program's code is not readable that far (see README.md).

import "field.ol"
import "arcade.ol"

## The way each lane runs, from the top of the river: 1 to the right, -1 to the left, 0 for the median strip.
const LANE_DIR   = [1, -1, 1, 1, -1, 0, -1, 1, -1, 1, -1]
## Pixels per second on the first board; every board after it is a little faster.
const LANE_SPEED = [28.0, 24.0, 44.0, 20.0, 32.0, 0.0, 28.0, 36.0, 30.0, 52.0, 24.0]
## The turtles, which are the lanes that dive.
const LANE_DIVES = [false, true, false, false, true, false, false, false, false, false, false]

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
const LIVES       = 3
const TIME_LIMIT  = 30.0

func wrapTo(v, size)
    return v - size * math.floor(v / size)
end

func isRoadRow(row)
    return row >= 1 and row <= 5
end

func isRiverRow(row)
    return row >= 7 and row <= 11
end

## The lane of a row, or nil for the start strip, the median strip and the homes.
func laneOfRow(row)
    if row < 1 or row > 11 or row == ROW_MEDIAN then
        return nil
    end
    return 11 - row
end

func tierOfBoard(board)
    return (board - 1) % 5 + 1
end

func speedFactor(board)
    return math.min(1.0 + SPEED_PER_BOARD * (board - 1), SPEED_MAX)
end

## What a lane is made of on a board: the length of an object, the period of the strip (an object and the gap after it) and
## how many objects there are. A lane is numbered 0..10, a tier 1..5 (a board's tier comes round every five boards).
func laneSpec(tier, lane)
    var t = TIERS[tier][lane + 1]
    var rows = t[2]
    return {len: rows * TILE, period: (rows + t[1] // 32) * TILE, count: t[3], tiles: rows}
end

## The offset of a lane's strip, advanced by dt seconds on a board.
func advanceLane(pos, lane, board, dt)
    return wrapTo(pos + LANE_DIR[lane + 1] * LANE_SPEED[lane + 1] * speedFactor(board) * dt, STRIP)
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
    for it in laneItems(tier, lane, pos) do
        if x + CELL - BODY_INSET > it.x0 and x + BODY_INSET < it.x1 then
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
            if LANE_DIVES[lane + 1] and turtleFrame(t, it.group) == 3 then
                return nil
            end
            return it
        end
    end
    return nil
end

## A frog the river carries goes where the lane goes. Whether it is still inside the field.
func onField(x)
    return x >= 0 and x + CELL <= FIELD_W
end

## The cell, from 1 to 5, a frog arriving at x is in, or nil when it is against a wall.
func homeAt(x)
    for h = 1, HOMES do
        if math.abs(x - (HOME_X0 + (h - 1) * HOME_STEP)) <= HOME_REACH then
            return h
        end
    end
    return nil
end

func homeX(h)
    return HOME_X0 + (h - 1) * HOME_STEP
end

## The cell of the grid nearest to x, which a frog that has been carried comes back to when it hops sideways.
func nearestColumn(x)
    var c = math.floor((x - COLUMN_X0) / CELL + 0.5)
    return math.clamp(c, 0, COLUMNS - 1)
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
    var now = score + points
    if not extraGiven and now >= EXTRA_AT then
        return now, true
    end
    return now, false
end
