## The save of Tetris, with no drawing: the whole state of the game as one map, written as the game goes and read back at
## the start, so that a run begins where the last one stopped — the screen it was on (title, menu, level, game), the
## well and the falling piece, the score, the level, the lines, the tune. The best scores are kept apart, as they always
## were (play.ol).
##
## `data` keeps the map as it is, arrays included, and does not write again a value that did not change. A save that
## cannot be trusted — another version, a field of the wrong sort or out of its range, a
## piece sitting in the rubble — is refused WHOLE and the game starts as if there were none: nothing of it is applied. A
## game that was running comes back in pause, and START goes on exactly from
## there: a piece that began to fall the moment a page opened would be a trap.

import "rules.ol"
import "sounds.ol"
import "play.ol"

const SAVE_KEY = "tetris.save"
const SAVE_VERSION = 1

## What is saved of `game`, by sort. The frame counter that blinks the texts, the clock of the steps, the keys held and
## pressed are not: they mean nothing a second run could use. The whole numbers, each with the range it can be in (the
## last four count frames).
const SAVE_RANGES = {
    height: [0, config.maxHeight], kind: [0, KINDS], turn: [1, 4], next: [1, KINDS],
    score: [0, config.maxScore], best: [0, config.maxScore], lines: [0, 99999], level: [0, 99],
    startLevel: [0, config.maxStartLevel], x: [-4, COLS + 4], y: [-4, ROWS + 4], dasDir: [-1, 1],
    fall: [0, 1000000000], softFrames: [0, 1000000000], dasFrames: [0, 1000000000], wait: [0, 1000000000]
}
const SAVE_BOOLS = ["won", "newBest", "downLock", "levelUp"]
const SAVE_STATES = ["title", "menu", "level", "play", "clearing", "entry", "paused", "over"]
const SAVE_RESUMES = ["play", "clearing", "entry"]
const SAVE_FOCUSES = ["type", "music", "level", "height"]

## The screen the game was last kept on (a change of screen is kept at once) and the step it was kept at (an update that
## makes no step, on a screen that refreshes faster than the game, is not a second chance to keep the same one).
global saved = {state: "", frame: -1}

## The state of the game as a map.
func saveState()
    var t = {
        v: SAVE_VERSION, state: game.state, focus: game.focus, type: game.type, resume: game.resume,
        well: game.well, clearing: game.clearing, beat: music.beat, beatNext: music.next
    }
    for name, range in SAVE_RANGES do
        t[name] = game[name]
    end
    for name in SAVE_BOOLS do
        t[name] = game[name]
    end
    return t
end

func isWhole(v, low, high)
    return typeof(v) == "int" and v >= low and v <= high
end

func isOneOf(v, list)
    return typeof(v) == "string" and list.contains(v)
end

## Whether a save read back can be trusted: every field there and of its sort, in its range, and a falling piece that fits.
func saveValid(t)
    if typeof(t) <> "map" or t.v <> SAVE_VERSION then
        return false
    end
    if not isOneOf(t.state, SAVE_STATES) or not isOneOf(t.focus, SAVE_FOCUSES) or not isOneOf(t.resume, SAVE_RESUMES) then
        return false
    end
    if t.type <> "A" and t.type <> "B" then
        return false
    end
    for name, range in SAVE_RANGES do
        if not isWhole(t[name], range[1], range[2]) then
            return false
        end
    end
    for name in SAVE_BOOLS do
        if typeof(t[name]) <> "bool" then
            return false
        end
    end
    if typeof(t.well) <> "array" or len(t.well) <> COLS * ROWS or typeof(t.clearing) <> "array" or len(t.clearing) > 4 then
        return false
    end
    for cell in t.well do
        if not isWhole(cell, 0, KINDS) then
            return false
        end
    end
    for row in t.clearing do
        if not isWhole(row, 0, ROWS - 1) then
            return false
        end
    end
    if (typeof(t.beat) <> "int" and typeof(t.beat) <> "float") or t.beat < 0 or t.beat >= musicLength() then
        return false
    end
    if not isWhole(t.beatNext, 1, len(music.events) + 1) then
        return false
    end
    if t.kind >= 1 and t.turn > len(shapes[t.kind]) then
        return false
    end
    var falling = t.state == "play" or (t.state == "paused" and t.resume == "play")
    if falling and (t.kind < 1 or not fits(t.well, t.kind, t.turn, t.x, t.y)) then
        return false
    end
    return true
end

## The state a value holds, or nil when it is not a save that can be trusted.
func readSave(value)
    return saveValid(value) and value or nil
end

## Puts a state read by readSave in the game. A game that was running comes back in pause.
func restoreSave(t)
    for name, range in SAVE_RANGES do
        game[name] = t[name]
    end
    for name in SAVE_BOOLS do
        game[name] = t[name]
    end
    game.state = t.state
    game.focus = t.focus
    game.type = t.type
    game.resume = t.resume
    game.well = t.well
    game.clearing = t.clearing
    game.frame = 0
    game.clock = 0
    game.held = {left: false, right: false, down: false}
    game.pressed = {}
    music.beat = t.beat
    music.next = t.beatNext
    if running() then
        pauseGame()
    end
end

## Keeps the state of the game; `data` leaves the file alone when it is what was kept last.
func saveGame()
    data.set(SAVE_KEY, saveState())
    saved.state = game.state
    saved.frame = game.frame
end

## The game as a run began it: put back where the last run left it when there is a save to trust. Whether it was.
func loadGame()
    var t = readSave(data.get(SAVE_KEY))
    if t == nil then
        return false
    end
    restoreSave(t)
    saved.state = game.state
    return true
end

## Called once a step: keeps the game when it changed screen, and twice a second while it goes on.
func autosave()
    if game.state <> saved.state or (game.frame % 30 == 0 and game.frame <> saved.frame) then
        saveGame()
    end
end
