## The save of Invaders, with no drawing: the game under way as one map, written as it goes and read back at the
## start, so that a run begins where the last one stopped — the fleet as it marches, the shields as they were eaten,
## the shot and the bombs in the air, the score, the wave and the lives. The best score is kept apart,
## so that an older save can never lower it. A game that was running comes back in pause.
##
## Only the shape of a save is settled here: resume.ol reads the game into a map and puts a map back. A save that
## cannot be trusted — another version, a field missing or of the wrong sort, a number out of its range, a fleet or a
## shield that is not the size of the field's — is refused WHOLE, and the game starts as if there were none.

import "field.ol"
import "../lib/keep.ol"

const SAVE_KEY = "save"
const SAVE_VERSION = 1
const SAVE_STATES = ["play", "over"]

## The whole numbers of a save, with the range each can be in.
const SAVE_WHOLES = {
    wave: [1, 999], score: [0, 999999999], lives: [0, 99], nextLife: [0, 999999999], shots: [0, 999999999],
    ticks: [0, 999999999], marchStep: [0, 4], cursor: [1, COLS * ROWS], frame: [1, 2]
}

## The numbers that may have a fraction, with their ranges. The wait for the mystery ship goes below zero while the
## fleet is too small for it to cross, and keeps falling. The wait for the cannon ends a little BELOW zero — the frame
## that spent it — and stays there until the cannon is hit again.
const SAVE_NUMBERS = {
    gunX: [0, FIELD_W], shotX: [-FIELD_W, 2 * FIELD_W], shotY: [-FIELD_H, 2 * FIELD_H], respawn: [-1, 2],
    ufoWait: [-999999999, 100]
}

func isSign(v)
    return v == 1 or v == -1
end

## One shield: SHIELD_H rows of SHIELD_W characters, `#` where it is whole and `.` where it was eaten.
func isShield(rows)
    return isArrayOf(rows, SHIELD_H, SHIELD_H, func(row)
        if typeof(row) <> "string" or len(row) <> SHIELD_W then
            return false
        end
        for c = 1, SHIELD_W do
            var ch = string.char(row, c)
            if ch <> "#" and ch <> "." then
                return false
            end
        end
        return true
    end)
end

## An alien's place: it may stand a little outside the field on its way to a wall, and as low as the waves push it.
func isAlienX(v)
    return isWhole(v, -2 * FIELD_W, 2 * FIELD_W)
end

func isAlienY(v)
    return isWhole(v, 0, 4 * FIELD_H)
end

func isBomb(b)
    return typeof(b) == "map" and isNumber(b.x, 0, FIELD_W) and isNumber(b.y, 0, FIELD_H)
end

func isUfo(u)
    return typeof(u) == "map" and isNumber(u.x, -UFO_W, FIELD_W) and isSign(u.dir)
end

## Whether a save read back can be trusted: every field there and of its sort, in its range.
func saveValid(t)
    if typeof(t) <> "map" or t.v <> SAVE_VERSION or not isOneOf(t.state, SAVE_STATES) then
        return false
    end
    if not inRanges(t, SAVE_WHOLES, SAVE_NUMBERS) then
        return false
    end
    if not isSign(t.heading) or not isSign(t.ufoDir) or not isBool(t.turning) or not isBool(t.shotLive) then
        return false
    end
    var aliens = COLS * ROWS
    if not isArrayOf(t.fx, aliens, aliens, isAlienX) or not isArrayOf(t.fy, aliens, aliens, isAlienY)
        or not isArrayOf(t.fa, aliens, aliens, isBool) then
        return false
    end
    if not isArrayOf(t.shields, SHIELDS, SHIELDS, isShield) then
        return false
    end
    if not isArrayOf(t.bombs, 0, BOMB_MAX, isBomb) then
        return false
    end
    return t.ufo == nil or isUfo(t.ufo)
end

## The state a value holds, or nil when it is not a save that can be trusted.
func readSave(value)
    return trusted(value, saveValid)
end
