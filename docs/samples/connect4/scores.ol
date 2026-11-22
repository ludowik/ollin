## The scores of Connect Four, with no screen: wins, losses and draws at each level, the run of wins that is going and the best one, and
## the fewest moves a game was won in. They are written when a game ends, and read back at the start; what cannot be trusted is
## put aside whole and the scores start again from nothing, as the other games' saves do.

import "ai.ol"
import "../lib/keep.ol"

const SCORES_KEY = "connect4.scores"
const SCORES_VERSION = 1
const COUNT_MAX = 1000000
const MOVES_MAX = (CELLS + 1) // 2   ## the most moves one player makes in a game

const SCORE_RANGES = {
    wins: [0, COUNT_MAX], losses: [0, COUNT_MAX], draws: [0, COUNT_MAX], streak: [0, COUNT_MAX], bestStreak: [0, COUNT_MAX],
    fastest: [0, MOVES_MAX]     ## 0 until a game is won
}

func freshLevel()
    return {wins: 0, losses: 0, draws: 0, streak: 0, bestStreak: 0, fastest: 0}
end

func freshScores()
    var list = []
    for level in LEVELS do
        list.push(freshLevel())
    end
    return list
end

global scores = freshScores()    ## one entry a level, in the order of LEVELS

func levelValid(t)
    return typeof(t) == "map" and inRanges(t, SCORE_RANGES, {}) and t.streak <= t.bestStreak
end

func scoresValid(t)
    return typeof(t) == "map" and t.v == SCORES_VERSION and isArrayOf(t.levels, #LEVELS, #LEVELS, levelValid)
end

func saveScores()
    data.set(SCORES_KEY, {v: SCORES_VERSION, levels: scores})
end

## Reads the scores back; a store that cannot be trusted gives empty ones.
func loadScores()
    var t = trusted(data.get(SCORES_KEY), scoresValid)
    if t == nil then
        scores = freshScores()
    else
        scores = t.levels
    end
end

## A game ended at `level` ("win", "loss" or "draw" for the human), after `humanMoves` discs of the human's.
func recordResult(level, result, humanMoves)
    var s = scores[level]
    if result == "win" then
        s.wins += 1
        s.streak += 1
        s.bestStreak = math.max(s.bestStreak, s.streak)
        if s.fastest == 0 or humanMoves < s.fastest then
            s.fastest = humanMoves
        end
    elseif result == "loss" then
        s.losses += 1
        s.streak = 0
    else
        s.draws += 1
        s.streak = 0
    end
    saveScores()
end
