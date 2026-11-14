## The rocks: a wave of them, what a hit breaks them into, and what they score.

func addRock(x, y, size)
    var a = math.rand() * math.TAU
    var sp = ROCK_SPEED[size] * (0.6 + math.rand() * 0.7)
    rocks.push({
        x: x, y: y,
        dead: false,
        vx: math.cos(a) * sp, vy: math.sin(a) * sp,
        size: size,
        shape: math.randInt(1, #ROCKS),
        rot: math.rand() * math.TAU,
        spin: (math.rand() * 2 - 1) * ROCK_SPIN
    })
end

## A new rock is placed AWAY from the centre, where the ship stands: dropping one on the ship would
## kill it before the player has touched a key, and no reflex could save it.
func newWave()
    if saucer <> nil then
        dropSaucer()
    end
    rocks = []
    shots = []
    saucerShots = []
    var n = math.min(WAVE_ROCKS + (wave - 1) * 2, WAVE_MAX)
    for i = 1, n do
        var x = 0.0
        var y = 0.0
        var tries = 0
        ## A bounded search, then whatever it holds: an unbounded one would hang the frame on a
        ## crowded field, and the worst it can give here is a rock a little close.
        while tries < 40 do
            x = math.rand() * FIELD_W
            y = math.rand() * FIELD_H
            tries += 1
            if not near(x, y, FIELD_W / 2, FIELD_H / 2, CLEAR_R + ROCK_R[3]) then
                tries = 40
            end
        end
        addRock(x, y, 3)
    end
    saucerTimer = SAUCER_PERIOD
end

## Scoring passes through here alone, so the extra ship cannot be missed on one of the four things
## worth points.
func award(points)
    score += points
    while score >= nextExtra do
        lives += 1
        nextExtra += EXTRA_AT
    end
    if score > best then
        best = score
        data.set(BEST_KEY, best)
    end
end

func burst(x, y, n, spread)
    for i = 1, n do
        var a = math.rand() * math.TAU
        var sp = spread * (0.3 + math.rand() * 0.7)
        debris.push({x: x, y: y, vx: math.cos(a) * sp, vy: math.sin(a) * sp, left: 0.35 + math.rand() * 0.4})
    end
end

## Breaking a rock is the game's central act: it REPLACES the rock with two faster, smaller ones,
## and only the smallest leaves nothing behind. The rock is MARKED and not removed: a single sweep
## at the end of the frame takes the dead away, so a collision pass never has to rebuild the list
## it is walking — and a child pushed during it cannot be thrown away with its parent.
func breakRock(r)
    r.dead = true
    award(ROCK_SCORE[r.size])
    sndBang[r.size].play()
    burst(r.x, r.y, 6 + r.size * 3, 60.0 + r.size * 20.0)
    if r.size > 1 then
        addRock(r.x, r.y, r.size - 1)
        addRock(r.x, r.y, r.size - 1)
    end
end

## The first live rock a point touches, or nil. Every collision in the game asks this one question
## — the shots ask it, the ship asks it — and it answers with a plain loop that STOPS on the hit,
## instead of a filter that has to walk the rest of the list to rebuild it.
func rockAt(x, y, extra)
    for r in rocks do
        if not r.dead and near(x, y, r.x, r.y, ROCK_R[r.size] + extra) then
            return r
        end
    end
    return nil
end
