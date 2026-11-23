## The save of a game in progress (docs/samples/connect4/save.ol): what is kept, that it comes back as it was, that a game with no disc
## is not kept, and that a save that cannot be trusted — a column that does not exist, a seventh disc in a column, a move after the game
## was won — is refused whole.

import "save.ol"
import "connect4_testlib.ol"

func clear()
    forgetGame()
    game = newBoard()
    human = 1
    levelIdx = 2
    state = "play"
end

## `t` is written as the store holds it; whether the game comes back.
func comesBack(t)
    forgetGame()
    data.set(GAME_KEY, t)
    loadGame()
    return resumable <> nil
end

func good(moves)
    return {v: GAME_VERSION, level: 2, human: 1, moves: moves}
end

## ── What is kept ─────────────────────────────────────────────────────────────────────────────────────────────────────────
clear()
saveGame()
assert(data.get(GAME_KEY) == nil and resumable == nil, "a game with no disc is nothing to go on with")
game = play([4, 3, 4])
levelIdx = 3
human = 2
saveGame()
var t = data.get(GAME_KEY)
assert(t.v == GAME_VERSION and t.level == 3 and t.human == 2 and t.moves.join(",") == "4,3,4", "the list of columns, the level, and who plays first")
assert(resumable.moves.join(",") == "4,3,4" and resumable.level == 3)
assert(gameSaveValid(t), "what is kept can be gone on with")

## ── Back as it was ───────────────────────────────────────────────────────────────────────────────────────────────────────
resumable = nil
loadGame()
assert(resumable <> nil and resumable.moves.join(",") == "4,3,4" and resumable.level == 3 and resumable.human == 2, "read back")
var again = replay(resumable.moves)
assert(again.mine[1] == game.mine[1] and again.mine[2] == game.mine[2] and again.count == 3, "and the list plays the same game again")

## ── A game over is not kept ──────────────────────────────────────────────────────────────────────────────────────────────
clear()
game = play([1, 7, 2, 7, 3, 7, 4])
saveGame()
assert(data.get(GAME_KEY) == nil or not gameSaveValid(data.get(GAME_KEY)), "a won game is no game in progress")
state = "over"
forgetGame()
game = play([4, 4])
saveGame()
assert(data.get(GAME_KEY) == nil, "and nothing is kept outside a game that goes on")
state = "play"

## ── What is trusted ──────────────────────────────────────────────────────────────────────────────────────────────────────
assert(comesBack(good([])), "no disc yet is a game")
assert(comesBack(good([4, 3, 4, 3])))
assert(comesBack(good(ALMOST_DRAW)), "a grid with one cell left is a game")
assert(comesBack({v: GAME_VERSION, level: 1, human: 2, moves: [4]}) and resumable.human == 2 and resumable.level == 1)

## ── What is not ──────────────────────────────────────────────────────────────────────────────────────────────────────────
func refused(t, why)
    assert(not comesBack(t), "{why}: the save is refused")
    assert(resumable == nil, "{why}: and nothing of it is kept")
end

refused(good(DRAW), "a full grid")
refused(good([1, 7, 2, 7, 3, 7, 4]), "a game that was won")
refused(good([1, 7, 2, 7, 3, 7, 4, 5]), "a move after the game was won")
refused(good([1, 1, 1, 1, 1, 1, 1]), "a seventh disc in a column")
refused(good([0]), "column 0")
refused(good([8]), "column 8")
refused(good([4, 3.5]), "a column that is not whole")
refused(good(["4"]), "a column that is a text")
refused(good([4, nil, 3]), "a hole in the list")
refused(good([4, true]), "a column that is a boolean")
refused(good("4,3"), "a list that is a text")
refused(good({a: 1}), "a list that is a map")
refused(good(nil), "no list")
var long = []
for i = 1, CELLS do
    long.push(4)
end
refused(good(long), "a list longer than a game")
refused({v: GAME_VERSION + 1, level: 2, human: 1, moves: [4]}, "another version")
refused({level: 2, human: 1, moves: [4]}, "no version")
refused({v: GAME_VERSION, level: 0, human: 1, moves: [4]}, "level 0")
refused({v: GAME_VERSION, level: #LEVELS + 1, human: 1, moves: [4]}, "a level that does not exist")
refused({v: GAME_VERSION, level: 1.5, human: 1, moves: [4]}, "a level that is not whole")
refused({v: GAME_VERSION, level: "2", human: 1, moves: [4]}, "a level that is a text")
refused({v: GAME_VERSION, level: 2, human: 3, moves: [4]}, "a third player")
refused({v: GAME_VERSION, level: 2, human: 0, moves: [4]}, "player 0")
refused({v: GAME_VERSION, level: 2, moves: [4]}, "no player")
refused("a save", "a text")
refused(12, "a number")
refused([4, 3], "an array")
forgetGame()
loadGame()
assert(resumable == nil, "nothing was kept")
print("connect4 save ok")
