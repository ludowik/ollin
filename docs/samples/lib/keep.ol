## What the games that keep themselves as they go have in common: the checks that decide whether a value read back from the
## store can be trusted (invaders, asteroids, tetris) — a store is written by a program and can be edited by anyone —, the
## clamp that keeps what a game writes inside what the check accepts, and the cadence of the keeping (invaders and
## asteroids; tetris counts its own frames). Imported with a path relative to the importing file, "../lib/keep.ol".

const KEEP_EVERY = 0.5          ## seconds between two keepings of a game that goes on

global keepWait = 0.0           ## the time left before the game is kept again
global keptState = ""           ## the screen it was last kept on: a change of screen is kept at once

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

## Whether `list` is an array of `least` to `most` entries that all pass `check`.
func isArrayOf(list, least, most, check)
    if typeof(list) <> "array" or len(list) < least or len(list) > most then
        return false
    end
    for v in list do
        if not check(v) then
            return false
        end
    end
    return true
end

## Whether every field named by `wholes` (a map of name to [low, high]) is a whole number in its range, and every field
## of `numbers` a number in its range.
func inRanges(t, wholes, numbers)
    for name, range in wholes do
        if not isWhole(t[name], range[1], range[2]) then
            return false
        end
    end
    for name, range in numbers do
        if not isNumber(t[name], range[1], range[2]) then
            return false
        end
    end
    return true
end

## Brings the fields of `t` that `inRanges` checks back inside their ranges, for a writer: a wait that kept falling during a
## long frame must not make the whole save refused at the next run.
func clampToRanges(t, wholes, numbers)
    for ranges in [wholes, numbers] do
        for name, range in ranges do
            t[name] = math.clamp(t[name], range[1], range[2])
        end
    end
end

## The value when `valid` accepts it, nil otherwise: what a read of the store gives back.
func trusted(value, valid)
    if valid(value) then
        return value
    end
    return nil
end

## A whole number read from the store, 0 when it is anything else: a best score that is a text would stop the game at its
## first comparison.
func wholeOr(value, low, high)
    if isWhole(value, low, high) then
        return value
    end
    return 0
end

## Called every frame while a game goes on: whether it must be kept now, because it changed screen or because the time came.
func keepDue(dt, state)
    keepWait -= dt
    return state <> keptState or keepWait <= 0.0
end

## The game has just been kept, or just put back, on this screen.
func markKept(state)
    keepWait = KEEP_EVERY
    keptState = state
end

## Called every frame: keeps the game (`save` does) when it changed screen, and twice a second while it goes on. The title
## holds nothing worth keeping.
func keepGoing(dt, state, save)
    if state <> "title" and keepDue(dt, state) then
        save()
    end
end

## Puts the game back from the store: `restore` is given what `valid` accepts, and is not called when there is nothing to
## trust. Whether it was.
func loadKept(key, valid, restore)
    var t = trusted(data.get(key), valid)
    if t == nil then
        return false
    end
    restore(t)
    return true
end
