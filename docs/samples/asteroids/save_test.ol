## The save of Asteroids (docs/samples/asteroids/save.ol): that a game written and read back through `data` is
## accepted, and that a save which cannot be trusted — another version, a field missing or of the wrong sort, a number
## out of its range, a rock of a size or a shape that does not exist — is refused WHOLE. What resume.ol does with a
## save it has accepted needs the screen, and is looked at there.

import "save.ol"

func rock(x, size, shape)
    return {x: x, y: 100.5, vx: -30.0, vy: 12.25, size: size, shape: shape, rot: 3.5, spin: -0.8}
end

func shot(left)
    return {x: 200.0, y: 50.0, vx: 300.5, vy: -120.0, left: left}
end

## A game under way, with everything a save has to keep.
func goodSave()
    return {
        v: SAVE_VERSION, state: "play", score: 4310, lives: 2, wave: 3, nextExtra: 10000,
        spawn: 0.4, waveWait: 1.8, saucerTimer: 9.5,
        ship: {x: 256.5, y: 192.0, vx: 40.5, vy: -80.25, ang: -1.2, push: 0.5},
        rocks: [rock(30.0, 3, 1), rock(300.25, 2, #ROCKS), rock(450.0, 1, 2)],
        shots: [shot(0.4), shot(0.9)],
        saucer: {x: 100.0, y: 90.5, vx: 95.0, vy: -20.0, small: true, shoot: 0.7, swerve: 0.3},
        saucerShots: [shot(1.1)]
    }
end

## ── A save written and read back ──────────────────────────────────────────────────────────────────

data.clear()
data.set(SAVE_KEY, goodSave())
var back = readSave(data.get(SAVE_KEY))
assert(back <> nil, "a save written by the game was refused")
assert(back.score == 4310 and back.lives == 2 and back.wave == 3 and back.nextExtra == 10000, "the numbers come back")
assert(back.ship.x == 256.5 and back.ship.vy == -80.25 and back.ship.ang == -1.2, "the ship comes back")
assert(#back.rocks == 3 and back.rocks[2].x == 300.25 and back.rocks[2].shape == #ROCKS and back.rocks[3].size == 1, "the rocks come back")
assert(#back.shots == 2 and back.shots[2].left == 0.9 and #back.saucerShots == 1, "the shots come back")
assert(back.saucer.small == true and back.saucer.swerve == 0.3, "the saucer comes back")

assert(readSave(nil) == nil, "nothing is no save")
assert(readSave(data.get("never written")) == nil, "a key that was never written is no save")

## ── What is accepted ──────────────────────────────────────────────────────────────────────────────

func accepts(name, change)
    var t = goodSave()
    change(t)
    assert(readSave(t) <> nil, "a save with " + name + " was refused")
end

accepts("the game over", func(t) t.state = "over" t.ship = nil end)
accepts("no ship on the field", func(t) t.ship = nil end)
accepts("no saucer in the air", func(t) t.saucer = nil end)
accepts("a field cleared of rocks", func(t) t.rocks = [] end)
accepts("no shot", func(t) t.shots = [] t.saucerShots = [] end)
accepts("every shot the ship may have in the air", func(t) t.shots = [shot(0.1), shot(0.2), shot(0.3), shot(0.4)] end)
accepts("whole numbers where there are fractions", func(t) t.ship.x = 256 t.ship.push = 1 t.rocks[1].spin = 0 end)
accepts("the saucer a little outside the field, about to leave", func(t) t.saucer.x = FIELD_W + SAUCER_BIG_R end)
accepts("the wait for the saucer run far below zero", func(t) t.saucerTimer = -123456.5 end)
accepts("the wait for a ship run far below zero", func(t) t.spawn = -9876.5 end)
accepts("the wait for a wave run a frame below zero", func(t) t.waveWait = -0.016 end)
accepts("a shot born past an edge, before the next step wraps it", func(t) t.shots[1].x = -8.0 t.saucerShots[1].x = FIELD_W + 20.0 end)
accepts("a ship turned many times round", func(t) t.ship.ang = -54321.5 end)

## What a long frame leaves in the game is brought inside the ranges by the writer, so that the save is not refused.
var long_frame = goodSave()
long_frame.waveWait = -5.0
long_frame.spawn = 99.0
clampToRanges(long_frame, SAVE_WHOLES, SAVE_NUMBERS)
assert(readSave(long_frame) <> nil and long_frame.waveWait == -1, "a wait that fell far below zero is clamped into a save that is trusted")

## ── What is refused ───────────────────────────────────────────────────────────────────────────────

func refuses(name, change)
    var t = goodSave()
    change(t)
    assert(readSave(t) == nil, "a save with " + name + " was trusted")
end

assert(readSave(5) == nil and readSave("play") == nil and readSave([]) == nil, "only a map can be a save")
refuses("another version", func(t) t.v = SAVE_VERSION + 1 end)
refuses("no version", func(t) t.v = nil end)
refuses("a screen that is not kept", func(t) t.state = "title" end)
refuses("a screen that is no screen", func(t) t.state = "pause" end)
refuses("a state that is not a text", func(t) t.state = 1 end)
for name in ["score", "lives", "wave", "nextExtra", "spawn", "waveWait", "saucerTimer", "rocks", "shots", "saucerShots"] do
    refuses("{name} missing", func(t) t[name] = nil end)
    refuses("{name} a text", func(t) t[name] = "1" end)
end
refuses("a score with a fraction", func(t) t.score = 10.5 end)
refuses("a negative score", func(t) t.score = -1 end)
refuses("a wave before the first", func(t) t.wave = 0 end)
refuses("more lives than a game can give", func(t) t.lives = 1000 end)
refuses("a wait for a ship that never ends", func(t) t.spawn = 99 end)
refuses("a wait for a wave far below zero", func(t) t.waveWait = -5 end)
refuses("a saucer wait that never ends", func(t) t.saucerTimer = 1000 end)

refuses("a ship that is not a map", func(t) t.ship = 5 end)
refuses("a ship outside the field", func(t) t.ship.x = FIELD_W + 1 end)
refuses("a ship above the field", func(t) t.ship.y = -1 end)
refuses("a ship faster than the engine allows", func(t) t.ship.vx = 900 end)
refuses("a ship with no heading", func(t) t.ship.ang = nil end)
refuses("a thrust past the full thrust", func(t) t.ship.push = 1.5 end)
refuses("a ship with no position", func(t) t.ship.x = nil end)

refuses("a rock that is not a map", func(t) t.rocks[2] = 5 end)
refuses("a rock of a size that does not exist", func(t) t.rocks[1].size = 4 end)
refuses("a rock of size zero", func(t) t.rocks[1].size = 0 end)
refuses("a rock of a size with a fraction", func(t) t.rocks[1].size = 2.5 end)
refuses("a rock of a shape that does not exist", func(t) t.rocks[1].shape = #ROCKS + 1 end)
refuses("a rock outside the field", func(t) t.rocks[3].x = -5 end)
refuses("a rock turning too fast", func(t) t.rocks[3].spin = 10 end)
refuses("a rock with no speed", func(t) t.rocks[3].vx = nil end)
refuses("more rocks than a field can hold", func(t) t.rocks = [] for i = 1, 201 do t.rocks.push(rock(10.0, 1, 1)) end end)

refuses("more shots than the ship may have in the air", func(t) t.shots = [shot(0.1), shot(0.2), shot(0.3), shot(0.4), shot(0.5)] end)
refuses("a shot with no life left to spend", func(t) t.shots[1].left = nil end)
refuses("a shot that lives for ever", func(t) t.shots[1].left = 30 end)
refuses("a shot that is already dead", func(t) t.shots[1].left = -1 end)
refuses("a shot far outside the field", func(t) t.shots[2].y = FIELD_H + SAVE_EDGE + 1 end)
refuses("a shot that is not a map", func(t) t.shots = [5] end)
refuses("more saucer shots than can be", func(t) t.saucerShots = [] for i = 1, 9 do t.saucerShots.push(shot(0.5)) end end)
refuses("a saucer shot far outside the field", func(t) t.saucerShots[1].x = -SAVE_EDGE - 1 end)

refuses("a saucer that is not a map", func(t) t.saucer = 5 end)
refuses("a saucer far outside", func(t) t.saucer.x = FIELD_W + 3 * SAUCER_BIG_R end)
refuses("a saucer off the field vertically", func(t) t.saucer.y = FIELD_H + SAVE_EDGE + 1 end)
refuses("a saucer with no size", func(t) t.saucer.small = nil end)
refuses("a saucer whose size is a number", func(t) t.saucer.small = 1 end)
refuses("a saucer too fast", func(t) t.saucer.vx = 500 end)
refuses("a saucer that never shoots", func(t) t.saucer.shoot = nil end)
refuses("a saucer that never swerves", func(t) t.saucer.swerve = 50 end)
