## The rules of Frog (docs/samples/frog/rules.ol): the field, the lanes the arcade tables lay out, what runs a frog down and
## what holds it up, the turtles that dive, the homes and the score.

import "rules.ol"

## ── The field ────────────────────────────────────────────────────────────────────────────────────────────────────────────
assert(rowY(0) == 224 and rowY(6) == 128 and rowY(12) == 32, "a row is 16 pixels high, the homes at the top")
assert(laneOfRow(0) == nil and laneOfRow(6) == nil and laneOfRow(12) == nil, "the start, the median strip and the homes are no lane")
assert(laneOfRow(1) == 10 and laneOfRow(5) == 6 and laneOfRow(7) == 4 and laneOfRow(11) == 0, "lane 0 is the top of the river")
for row = 1, 11 do
    if row <> ROW_MEDIAN then
        assert(isRoadRow(row) <> isRiverRow(row), "row {row} is the road or the river, not both")
    end
end
assert(isRoadRow(5) and not isRoadRow(6) and isRiverRow(7) and not isRiverRow(12))

## ── What the arcade tables say of the lanes ──────────────────────────────────────────────────────────────────────────────
assert(#TIERS == 5 and #LANE_TILES == 11 and #LANE_DIR == 11 and #LANE_SPEED == 11 and #LANE_DIVES == 11 and #LANE_PHASES == 11)
for lane = 0, 10 do
    if lane <> 5 then
        var phases = LANE_PHASES[lane + 1]
        assert(#LANE_TILES[lane + 1] % phases == 0, "lane {lane}: its pictures follow each other the same distance apart")
        assert((phases == 3) == LANE_DIVES[lane + 1], "only the turtles have poses")
        assert(#LANE_TILES[lane + 1] // phases >= laneSpec(1, lane).tiles * 2, "a picture holds the tiles of a lane object")
    end
end
assert(laneSpec(1, 0).len == 64 and laneSpec(1, 0).period == 88 and laneSpec(1, 0).count == 3, "a log of eight tiles, three to a lane")
assert(laneSpec(1, 6).len == 32 and laneSpec(1, 7).len == 16, "a truck is four tiles long and a car two")
assert(laneSpec(5, 0).count == 1 and laneSpec(5, 8).count == 5, "the fifth tier has one log in lane 0 and five cars in lane 8")
for tier = 1, 5 do
    for lane = 0, 10 do
        if lane <> 5 then
            var spec = laneSpec(tier, lane)
            assert(spec.count >= 1 and spec.len >= 16, "tier {tier} lane {lane} holds objects")
            assert(spec.tiles * 2 == #LANE_TILES[lane + 1] or LANE_DIVES[lane + 1], "tier {tier} lane {lane}: the table has a picture for every tile")
            assert((spec.count - 1) * spec.period + spec.len <= STRIP, "tier {tier} lane {lane}: the objects fit the strip without touching at the seam")
        end
    end
end
for lane = 0, 10 do
    var stands = LANE_DIR[lane + 1] == 0
    assert(stands == (lane == 5), "only the median strip stands still")
end

## ── Where the objects are, and the strip that wraps ──────────────────────────────────────────────────────────────────────
var items = laneItems(1, 0, 0.0)
assert(#items == 3 and items[1].x0 == 0 and items[1].x1 == 64 and items[2].x0 == 88 and items[3].x0 == 176, "three logs from the offset")
var wrapped = laneItems(1, 0, 200.0)
var ends = []
for it in wrapped do
    ends.push("{it.x0}-{it.x1}")
end
var endsText = ends.join(" ")
assert(#wrapped == 4, "an object across the seam of the strip shows at both edges: {endsText}")
assert(wrapTo(-10.0, 256) == 246.0 and wrapTo(260.0, 256) == 4.0 and wrapTo(5.0, 256) == 5.0)
assert(advanceLane(0.0, 0, 1, 1.0) == 28.0, "lane 0 runs to the right at its own speed")
assert(advanceLane(0.0, 1, 1, 1.0) == 256.0 - 24.0, "lane 1 runs to the left and the strip wraps")
assert(advanceLane(10.0, 5, 3, 5.0) == 10.0, "the median strip does not move")
assert(speedFactor(1) == 1.0 and math.abs(speedFactor(3) - 1.2) < 0.0001 and speedFactor(99) == SPEED_MAX, "each board is a tenth faster, up to a ceiling")
assert(tierOfBoard(1) == 1 and tierOfBoard(5) == 5 and tierOfBoard(6) == 1 and tierOfBoard(12) == 2, "the tier comes round every five boards")

## ── The road ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
## Lane 7 is the second lane of the road from the top: cars of two tiles. At offset 0 the first is over x 0..16.
assert(roadHit(1, 7, 0.0, 8), "a frog across a car is run down")
assert(roadHit(1, 7, 0.0, 0), "and one standing over its tail")
assert(not roadHit(1, 7, 0.0, 16), "a frog that only touches the edge of a car is not hit: its body is smaller than its cell")
assert(not roadHit(1, 7, 0.0, 40), "a free cell of the road is safe")
assert(roadHit(1, 6, 0.0, 20), "a truck is as long as four tiles")

## ── The river ────────────────────────────────────────────────────────────────────────────────────────────────────────────
assert(riverSupport(1, 0, 0.0, 0.0, 8) <> nil, "a frog with its middle over a log is held")
assert(riverSupport(1, 0, 0.0, 0.0, 70) == nil, "and in the gap between two logs it falls in the water")
assert(riverSupport(1, 0, 0.0, 0.0, 52) <> nil, "the middle decides: a frog with only half of it over the end is still held")
assert(riverSupport(1, 0, 0.0, 0.0, 58) == nil and riverSupport(1, 0, 0.0, 0.0, 72) == nil, "but not one whose middle is past it")
assert(onField(0) and onField(208) and not onField(-1) and not onField(209), "the river carries a frog off the field")

## ── The turtles ──────────────────────────────────────────────────────────────────────────────────────────────────────────
## Lane 1 holds groups of two turtles from x 0, 56, 112 and 168: group 1 is at 56..88, which a frog at x 64 is over.
assert(turtleFrame(0.0, 0) == 0 and turtleFrame(4.5, 2) == 0, "every other group never dives")
assert(turtleFrame(0.0, 1) == 0, "a group that is not yet diving is on the surface")
assert(turtleFrame(3.3, 1) == 1 and turtleFrame(3.9, 1) == 2 and turtleFrame(4.5, 1) == 3, "it sinks in two steps and is under")
assert(turtleFrame(6.2, 1) == 2 and turtleFrame(6.8, 1) == 1 and turtleFrame(7.0, 1) == 0, "then it comes up in two steps")
assert(riverSupport(1, 1, 0.0, 0.0, 64) <> nil, "a frog on turtles that are up is held")
assert(riverSupport(1, 1, 0.0, 3.9, 64) <> nil, "and still when they are only sinking")
assert(riverSupport(1, 1, 0.0, 4.5, 64) == nil, "but not when they are under")
assert(riverSupport(1, 1, 0.0, 4.5, 8) <> nil, "the group before it, which does not dive, holds a frog")
assert(riverSupport(1, 0, 0.0, 4.5, 8) <> nil, "and a log never goes under")

## ── The homes ────────────────────────────────────────────────────────────────────────────────────────────────────────────
assert(homeX(1) == 8 and homeX(3) == 104 and homeX(5) == 200, "five homes 48 pixels apart")
assert(homeAt(104) == 3 and homeAt(60) == 2 and homeAt(111) == 3, "a frog within a few pixels of a home is in it")
assert(homeAt(80) == nil and homeAt(130) == nil, "between two homes it is against the wall")
assert(homeAt(START_X) == 3, "the frog starts under the middle home")

## ── The score ────────────────────────────────────────────────────────────────────────────────────────────────────────────
assert(homeScore(12.7, false) == 170 and homeScore(0.0, false) == 50 and homeScore(12.7, true) == 370, "a home is worth more the sooner it is reached")
var s, given = addScore(19990, 10, false)
assert(s == 20000 and given, "the extra frog comes at twenty thousand")
s, given = addScore(20000, 50, true)
assert(s == 20050 and not given, "and only once")
s, given = addScore(0, 50, false)
assert(s == 50 and not given)
s, given = addScore(SCORE_MAX - 5, 50, true)
assert(s == SCORE_MAX, "the score stops where a score can be kept")
print("frog rules ok")
