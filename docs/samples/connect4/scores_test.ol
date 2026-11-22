## The scores of Connect Four (docs/samples/connect4/scores.ol): what each result adds, the run of wins, the fastest win, the levels
## being apart, what is written and read back, and that a store that cannot be trusted gives empty scores.

import "scores.ol"

func reset()
    data.delete(SCORES_KEY)
    scores = freshScores()
end

## The scores as text, to compare two of them whole.
func text()
    return json.stringify(scores)
end

## ── Empty ────────────────────────────────────────────────────────────────────────────────────────────────────────────────
reset()
assert(#scores == #LEVELS and gamesPlayed(1) == 0 and gamesPlayed(3) == 0)
assert(scores[1].wins == 0 and scores[1].losses == 0 and scores[1].draws == 0 and scores[1].streak == 0 and scores[1].fastest == 0)

## ── What a result adds ───────────────────────────────────────────────────────────────────────────────────────────────────
recordResult(2, "win", 14)
assert(scores[2].wins == 1 and scores[2].streak == 1 and scores[2].bestStreak == 1 and scores[2].fastest == 14)
recordResult(2, "win", 17)
assert(scores[2].wins == 2 and scores[2].streak == 2 and scores[2].bestStreak == 2 and scores[2].fastest == 14, "a slower win leaves the fastest alone")
recordResult(2, "win", 9)
assert(scores[2].fastest == 9 and scores[2].streak == 3, "a quicker win replaces it")
recordResult(2, "loss", 12)
assert(scores[2].losses == 1 and scores[2].streak == 0 and scores[2].bestStreak == 3, "a loss ends the run, and the best run stays")
recordResult(2, "win", 20)
recordResult(2, "draw", 21)
assert(scores[2].draws == 1 and scores[2].streak == 0 and scores[2].bestStreak == 3, "so does a draw")
assert(scores[2].wins == 4 and scores[2].fastest == 9 and gamesPlayed(2) == 6, "{gamesPlayed(2)} games in all")
assert(gamesPlayed(1) == 0 and gamesPlayed(3) == 0 and scores[1].wins == 0, "the other levels are not touched")

## ── Written and read back ────────────────────────────────────────────────────────────────────────────────────────────────
var kept = text()
scores = freshScores()
assert(text() <> kept)
loadScores()
assert(text() == kept, "what was written is what comes back")
assert(typeof(scores[2].wins) == "int" and scores[2].fastest == 9)

## ── What is not trusted ──────────────────────────────────────────────────────────────────────────────────────────────────
func levelsOf(entry)
    return [entry, freshLevel(), freshLevel()]
end

## `store` is written as the store holds it, and the scores come back empty.
func refused(store, why)
    scores = freshScores()
    recordResult(1, "win", 5)
    data.set(SCORES_KEY, store)
    loadScores()
    assert(text() == json.stringify(freshScores()), "{why}: the scores start again")
end

var good = levelsOf({wins: 3, losses: 1, draws: 0, streak: 2, bestStreak: 2, fastest: 7})
reset()
data.set(SCORES_KEY, {v: SCORES_VERSION, levels: good})
loadScores()
assert(scores[1].wins == 3 and scores[1].fastest == 7, "a store that is right is read")

refused({v: SCORES_VERSION + 1, levels: good}, "another version")
refused({v: SCORES_VERSION}, "no levels")
refused({levels: good}, "no version")
refused({v: SCORES_VERSION, levels: [freshLevel(), freshLevel()]}, "too few levels")
refused({v: SCORES_VERSION, levels: [freshLevel(), freshLevel(), freshLevel(), freshLevel()]}, "too many levels")
refused({v: SCORES_VERSION, levels: levelsOf({wins: -1, losses: 0, draws: 0, streak: 0, bestStreak: 0, fastest: 0})}, "a negative count")
refused({v: SCORES_VERSION, levels: levelsOf({wins: 1.5, losses: 0, draws: 0, streak: 0, bestStreak: 0, fastest: 0})}, "a count that is not whole")
refused({v: SCORES_VERSION, levels: levelsOf({wins: "3", losses: 0, draws: 0, streak: 0, bestStreak: 0, fastest: 0})}, "a count that is a text")
refused({v: SCORES_VERSION, levels: levelsOf({wins: 1, losses: 0, draws: 0, streak: 0, bestStreak: 0})}, "a field missing")
refused({v: SCORES_VERSION, levels: levelsOf({wins: 1, losses: 0, draws: 0, streak: 3, bestStreak: 2, fastest: 5})}, "a run longer than the best run")
refused({v: SCORES_VERSION, levels: levelsOf({wins: 1, losses: 0, draws: 0, streak: 1, bestStreak: 1, fastest: MOVES_MAX + 1})}, "a win in more moves than a game holds")
refused({v: SCORES_VERSION, levels: levelsOf({wins: COUNT_MAX + 1, losses: 0, draws: 0, streak: 0, bestStreak: 0, fastest: 0})}, "a count out of range")
refused({v: SCORES_VERSION, levels: [5, freshLevel(), freshLevel()]}, "a level that is a number")
refused({v: SCORES_VERSION, levels: "levels"}, "levels that are a text")
refused("scores", "a text")
refused(7, "a number")
refused([1, 2, 3], "an array")
scores = freshScores()
data.delete(SCORES_KEY)
loadScores()
assert(text() == json.stringify(freshScores()), "no store, no scores")
print("connect4 scores ok")
