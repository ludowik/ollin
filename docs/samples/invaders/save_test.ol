## The save of Invaders (docs/samples/invaders/save.ol): that a game written and read back through `data` is accepted,
## and that a save which cannot be trusted — another version, a field missing or of the wrong sort, a number out of its
## range, a fleet or a shield of the wrong size — is refused WHOLE. What resume.ol does with a save it has accepted
## needs the screen, and is looked at there.

import "save.ol"

## A game under way, with everything a save has to keep.
func goodSave()
    var t = {
        v: SAVE_VERSION, state: "play", wave: 3, score: 1240, lives: 2, nextLife: 3000, shots: 41, ticks: 5000,
        marchStep: 2, cursor: 17, heading: -1, turning: false, frame: 2, fx: [], fy: [], fa: [], shields: [],
        gunX: 80.5, shotLive: true, shotX: 90.5, shotY: 120.0, bombs: [{x: 40.0, y: 100.5}], respawn: 0.0,
        ufoWait: -3.5, ufoDir: -1, ufo: {x: 100.0, dir: 1}
    }
    for i = 1, COLS * ROWS do
        t.fx.push(24 + (i % COLS) * 16)
        t.fy.push(40 + i)
        t.fa.push(i % 3 <> 0)
    end
    for s = 1, SHIELDS do
        var rows = []
        for y = 1, SHIELD_H do
            rows.push(string.repeat(y % 2 == 0 and "#" or ".", SHIELD_W))
        end
        t.shields.push(rows)
    end
    return t
end

## ── A save written and read back ──────────────────────────────────────────────────────────────────

data.clear()
data.set(SAVE_KEY, goodSave())
var back = readSave(data.get(SAVE_KEY))
assert(back <> nil, "a save written by the game was refused")
assert(back.wave == 3 and back.score == 1240 and back.lives == 2 and back.cursor == 17, "the numbers come back")
assert(back.gunX == 80.5 and back.shotY == 120.0 and back.ufoWait == -3.5, "the fractions come back")
assert(back.heading == -1 and back.turning == false and back.shotLive == true, "the signs and the flags come back")
assert(#back.fx == COLS * ROWS and back.fx[2] == 24 + 2 * 16 and back.fa[3] == false and back.fa[4] == true, "the fleet comes back")
assert(#back.shields == SHIELDS and #back.shields[1] == SHIELD_H and back.shields[2][2] == string.repeat("#", SHIELD_W), "the shields come back")
assert(#back.bombs == 1 and back.bombs[1].y == 100.5 and back.ufo.dir == 1, "the bombs and the mystery ship come back")

assert(readSave(nil) == nil, "nothing is no save")
assert(readSave(data.get("never written")) == nil, "a key that was never written is no save")

## ── What is accepted ──────────────────────────────────────────────────────────────────────────────

func accepts(name, change)
    var t = goodSave()
    change(t)
    assert(readSave(t) <> nil, "a save with " + name + " was refused")
end

accepts("the game over", func(t) t.state = "over" end)
accepts("no mystery ship in the air", func(t) t.ufo = nil end)
accepts("no bomb", func(t) t.bombs = [] end)
accepts("every bomb the fleet may keep", func(t) t.bombs = [{x: 1, y: 2}, {x: 3, y: 4}, {x: 5, y: 6}] end)
accepts("the limits of a whole number", func(t) t.lives = 0 t.wave = 999 t.cursor = COLS * ROWS end)
accepts("a whole number for a fraction", func(t) t.gunX = 80 t.respawn = 1 end)
accepts("the wait for the mystery ship run far below zero", func(t) t.ufoWait = -123456.5 end)
accepts("the wait for the cannon ended a frame below zero", func(t) t.respawn = -0.0406 end)

## What a long frame leaves in the game is brought inside the ranges by the writer, so that the save is not refused.
var long_frame = goodSave()
long_frame.respawn = -5.0
long_frame.shotY = -900.0
clampToRanges(long_frame, SAVE_WHOLES, SAVE_NUMBERS)
assert(readSave(long_frame) <> nil and long_frame.respawn == -1 and long_frame.shotY == -FIELD_H, "a wait or a shot that went far is clamped into a save that is trusted")

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
for name in ["wave", "score", "lives", "nextLife", "shots", "ticks", "marchStep", "cursor", "frame", "gunX", "shotX",
             "shotY", "respawn", "ufoWait", "heading", "ufoDir", "turning", "shotLive", "fx", "fy", "fa", "shields", "bombs"] do
    refuses("{name} missing", func(t) t[name] = nil end)
    refuses("{name} a text", func(t) t[name] = "1" end)
end
refuses("a whole number that has a fraction", func(t) t.wave = 2.5 end)
refuses("the wave below the first", func(t) t.wave = 0 end)
refuses("a negative score", func(t) t.score = -1 end)
refuses("more lives than a game can give", func(t) t.lives = 100 end)
refuses("a cursor past the fleet", func(t) t.cursor = COLS * ROWS + 1 end)
refuses("a cursor before the fleet", func(t) t.cursor = 0 end)
refuses("a march step that is no note", func(t) t.marchStep = 5 end)
refuses("a frame of the fleet that does not exist", func(t) t.frame = 3 end)
refuses("a heading that is not a direction", func(t) t.heading = 0 end)
refuses("a cannon outside the field", func(t) t.gunX = FIELD_W + 1 end)
refuses("a cannon left of the field", func(t) t.gunX = -1 end)
refuses("a shot far outside the field", func(t) t.shotY = 3 * FIELD_H end)
refuses("a respawn that never ends", func(t) t.respawn = 50 end)
refuses("a respawn far below zero", func(t) t.respawn = -5 end)
refuses("a mystery ship waiting for ever", func(t) t.ufoWait = 1000 end)
refuses("one alien too few", func(t) t.fx.pop() end)
refuses("one alien too many", func(t) t.fy.push(0) end)
refuses("a fleet that is not an array", func(t) t.fa = "yes" end)
refuses("an alien outside the field", func(t) t.fx[5] = 3 * FIELD_W end)
refuses("an alien below the waves", func(t) t.fy[5] = 5 * FIELD_H end)
refuses("an alien that is not whole", func(t) t.fy[5] = 40.5 end)
refuses("an alive flag that is not a flag", func(t) t.fa[5] = 1 end)
refuses("a shield missing", func(t) t.shields.pop() end)
refuses("a shield with a row missing", func(t) t.shields[2].pop() end)
refuses("a shield row too short", func(t) t.shields[1][3] = "###" end)
refuses("a shield row that is not a text", func(t) t.shields[1][3] = 5 end)
refuses("a shield pixel that is neither", func(t) t.shields[4][1] = string.repeat("x", SHIELD_W) end)
refuses("more bombs than the fleet keeps", func(t) t.bombs = [{x: 1, y: 2}, {x: 3, y: 4}, {x: 5, y: 6}, {x: 7, y: 8}] end)
refuses("a bomb that is not a map", func(t) t.bombs = [5] end)
refuses("a bomb outside the field", func(t) t.bombs[1].y = FIELD_H + 1 end)
refuses("a bomb without a position", func(t) t.bombs[1].x = nil end)
refuses("a mystery ship that is not a map", func(t) t.ufo = 5 end)
refuses("a mystery ship far outside", func(t) t.ufo.x = FIELD_W + 1 end)
refuses("a mystery ship going nowhere", func(t) t.ufo.dir = 0 end)
