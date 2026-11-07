## The save of Asteroids, with no drawing: the game under way as one map, written as it goes and read back at the
## start, so that a run begins where the last one stopped — the ship and its speed, every rock, the shots and the
## saucer in the air, the score, the wave and the lives. The best score is kept apart (asteroids.ol), so that an
## older save can never lower it. A game that was running comes back in pause.
##
## Only the shape of a save is settled here: asteroids.ol reads the game into a map and puts a map back. A save that
## cannot be trusted — another version, a field missing or of the wrong sort, a number out of its range, a rock of a
## size or a shape that does not exist — is refused WHOLE, and the game starts as if there were none.

import "shapes.ol"
import "field.ol"

const SAVE_KEY = "save"
const SAVE_VERSION = 1
const SAVE_STATES = ["play", "over"]
const SAVE_MAX_ROCKS = 200
const SAVE_MAX_SAUCER_SHOTS = 8

## The whole numbers of a save, with the range each can be in.
const SAVE_WHOLES = {
    score: [0, 999999999], lives: [0, 999], wave: [1, 999], nextExtra: [0, 999999999]
}

## The numbers that may have a fraction, with their ranges. The waits go below zero while what they wait for cannot
## happen — a ship is not put back under a rock, the saucer stays away from a clear field — and keep falling.
const SAVE_NUMBERS = {
    spawn: [-999999999, 10], waveWait: [-1, 10], saucerTimer: [-999999999, 100]
}

func isWhole(v, low, high)
    return typeof(v) == "int" and v >= low and v <= high
end

func isNumber(v, low, high)
    return (typeof(v) == "int" or typeof(v) == "float") and v >= low and v <= high
end

func isOneOf(v, list)
    return typeof(v) == "string" and list.contains(v)
end

func isBool(v)
    return typeof(v) == "bool"
end

## Whether `list` holds at most `most` entries that all pass `check`.
func allOf(list, most, check)
    if typeof(list) <> "array" or len(list) > most then
        return false
    end
    for v in list do
        if not check(v) then
            return false
        end
    end
    return true
end

## What every moving thing has: a place on the field, which wraps, and a speed.
func isMover(o, speed)
    return typeof(o) == "map" and isNumber(o.x, 0, FIELD_W) and isNumber(o.y, 0, FIELD_H)
        and isNumber(o.vx, -speed, speed) and isNumber(o.vy, -speed, speed)
end

func isShip(o)
    return isMover(o, 400) and isNumber(o.ang, -999999999, 999999999) and isNumber(o.push, 0, 1)
end

func isRock(o)
    return isMover(o, 200) and isWhole(o.size, 1, 3) and isWhole(o.shape, 1, #ROCKS)
        and isNumber(o.rot, -999999999, 999999999) and isNumber(o.spin, -2, 2)
end

## A shot of the ship, or of the saucer: it dies of old age, so its `left` is what makes it a shot.
func isShot(o)
    return isMover(o, 800) and isNumber(o.left, 0, 2)
end

## The saucer crosses the field once and does not wrap, so it may stand a little outside; its radius is its size's.
func isSaucer(o)
    return typeof(o) == "map" and isNumber(o.x, -2 * SAUCER_BIG_R, FIELD_W + 2 * SAUCER_BIG_R)
        and isNumber(o.y, 0, FIELD_H) and isNumber(o.vx, -100, 100) and isNumber(o.vy, -100, 100)
        and isBool(o.small) and isNumber(o.shoot, -1, 2) and isNumber(o.swerve, -1, 2)
end

## Whether a save read back can be trusted: every field there and of its sort, in its range.
func saveValid(t)
    if typeof(t) <> "map" or t.v <> SAVE_VERSION or not isOneOf(t.state, SAVE_STATES) then
        return false
    end
    for name, range in SAVE_WHOLES do
        if not isWhole(t[name], range[1], range[2]) then
            return false
        end
    end
    for name, range in SAVE_NUMBERS do
        if not isNumber(t[name], range[1], range[2]) then
            return false
        end
    end
    if not allOf(t.rocks, SAVE_MAX_ROCKS, isRock) or not allOf(t.shots, SHOTS_MAX, isShot) then
        return false
    end
    if not allOf(t.saucerShots, SAVE_MAX_SAUCER_SHOTS, isShot) then
        return false
    end
    return (t.ship == nil or isShip(t.ship)) and (t.saucer == nil or isSaucer(t.saucer))
end

## The state a value holds, or nil when it is not a save that can be trusted.
func readSave(value)
    return saveValid(value) and value or nil
end
