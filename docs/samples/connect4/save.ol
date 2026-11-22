## The save of a game in progress, with no drawing: the list of columns played, the level, and who plays first. The position is played
## again from the list when the game comes back, which keeps the save small and easy to check: a list that is not a game that can have
## been played — a column out of range, a column over its six discs, a move after the game was won — makes the whole save refused,
## and the game starts as if there were none. Only a game that is going on is kept; a finished one is in the scores.

import "state.ol"
import "../lib/keep.ol"

const GAME_KEY = "connect4.game"
const GAME_VERSION = 1

func gameSaveState()
    return {v: GAME_VERSION, level: levelIdx, human: human, moves: game.moves.copy()}
end

## Whether what was read back is a game that can be played on from where it was left.
func gameSaveValid(t)
    if typeof(t) <> "map" or t.v <> GAME_VERSION then
        return false
    end
    if not isWhole(t.level, 1, #LEVELS) or not isWhole(t.human, 1, 2) then
        return false
    end
    if typeof(t.moves) <> "array" then
        return false
    end
    var b = replay(t.moves)          ## which refuses a column that does not exist, a full one, and a move after the game was won
    return b <> nil and not justWon(b) and not isFull(b)
end

func forgetGame()
    data.delete(GAME_KEY)
    resumable = nil
end

## Keeps the game in progress. A game with no disc in it is nothing to go on with, and takes back what an earlier one had kept.
func saveGame()
    if state <> "play" then
        return
    end
    if game.count == 0 then
        forgetGame()
        return
    end
    var t = gameSaveState()
    data.set(GAME_KEY, t)
    resumable = t
end

## At the start: the game a previous run kept, when there is one to trust.
func loadGame()
    resumable = trusted(data.get(GAME_KEY), gameSaveValid)
end
