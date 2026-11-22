## The game of Connect Four as it is played (docs/samples/connect4/play.ol): a disc and its fall, the computer taking its turn and not
## answering at once, the end of a game and what it is worth, taking a move back, and going on with a game that was kept.

import "play.ol"
import "connect4_testlib.ol"

const FRAME = 0.016

## A new game at `level`, with the human playing first or not, and a computer that plays the same game every time.
func fresh(level, first)
    data.delete(SCORES_KEY)
    scores = freshScores()
    rng = Random(21)
    levelIdx = level
    humanFirst = first
    newGame()
end

func run(seconds)
    for i = 1, math.floor(seconds / FRAME + 0.5) do
        updateFrame(FRAME)
    end
end

## Runs until the computer has played, and the disc has landed: the number of moves the grid then holds, or the time ran out.
func untilMoves(count)
    for i = 1, 600 do
        if game.count >= count and fall == nil then
            return game.count
        end
        updateFrame(FRAME)
    end
    return game.count
end

## The grid is set to `list`, with the human as player `who`, as it is when a game is begun or gone on with.
func position(list, who)
    game = replay(list)
    human = who
    settle()
end

## ── A new game ───────────────────────────────────────────────────────────────────────────────────────────────────────────
fresh(2, true)
assert(state == "play" and human == 1 and computer == 2 and game.count == 0 and humansTurn() and thinker == nil and outcome == nil)
assert(hover == 4 and fall == nil, "the aim starts in the middle")
fresh(2, false)
assert(human == 2 and computer == 1 and not humansTurn() and thinker <> nil, "the computer that plays first starts thinking at once")
assert(levelName() == "Medium")

## ── A disc and its fall ──────────────────────────────────────────────────────────────────────────────────────────────────
fresh(2, true)
assert(humanDrop(4), "a disc goes in")
assert(game.count == 1 and cellAt(game, 4, 0) == 1 and fall.col == 4 and fall.row == 0 and fall.who == 1, "the grid has it at once, the screen has it in the air")
assert(fall.dur > FALL_BASE and not humansTurn(), "nothing else can be played while it falls")
assert(not humanDrop(3) and game.count == 1, "a second disc is refused")
run(fall.dur + FRAME)
assert(fall == nil and thinker <> nil, "it lands, and the computer's turn begins")
fresh(2, true)
humanDrop(4)
assert(fall.row == 0 and math.abs(fall.dur - (FALL_BASE + FALL_PER_ROW * (ROWS - 1))) < 0.000001, "the foot of a column is the longest fall")
position([4, 4], 1)
assert(humanDrop(4) and fall.row == 2 and math.abs(fall.dur - (FALL_BASE + FALL_PER_ROW * (ROWS - 3))) < 0.000001, "a disc falls through the rows above it only")

## ── The computer's turn ──────────────────────────────────────────────────────────────────────────────────────────────────
fresh(2, true)
humanDrop(4)
run(fall.dur + FRAME)
run(MIN_THINK / 2)
assert(game.count == 1 and thinker <> nil, "the computer does not answer at once, however quick the search")
assert(not humanDrop(3), "and it is not the human's turn")
assert(untilMoves(2) == 2, "then it answers")
assert(thinker == nil and humansTurn() and toMove(game) == 1, "and the turn is the human's again")
assert(cellAt(game, game.moves[2], heightOf(game, game.moves[2]) - 1) == 2, "which is the computer's")

## while the computer's disc is falling it is the human's turn in the grid, and still not in the game
fresh(2, true)
humanDrop(4)
while game.count < 2 do
    updateFrame(FRAME)
end
assert(fall <> nil and fall.who == 2 and toMove(game) == 1, "the computer's disc is in the air")
assert(not humansTurn() and not humanDrop(3) and game.count == 2, "the human waits for it to land")
run(fall.dur + FRAME)
assert(humansTurn() and humanDrop(3), "and then plays")

## a full column is refused
fresh(2, true)
game = replay([4, 4, 4, 4, 4, 4])
assert(not humanDrop(4) and game.count == 6, "a full column takes no disc")
assert(not humanDrop(0) and not humanDrop(8) and not humanDrop(nil) and not humanDrop("3"), "nor a column that does not exist")

## the aim
moveHover(-10)
assert(hover == 1)
moveHover(20)
assert(hover == COLS)
moveHover(-1)
assert(hover == COLS - 1)

## ── A win for the human ──────────────────────────────────────────────────────────────────────────────────────────────────
fresh(2, true)
position([1, 7, 2, 7, 3, 7], 1)
assert(humansTurn() and humanDrop(4))
assert(outcome.winner == 1 and outcome.result == "win" and #outcome.cells == 4, "a win is known the moment the disc is in")
assert(state == "play" and fall <> nil, "the screen waits for the disc to land")
assert(scores[2].wins == 1 and scores[2].streak == 1 and scores[2].fastest == 4, "the game is worth what it is worth at once")
assert(data.get(GAME_KEY) == nil and resumable == nil, "and is no game in progress")
run(fall.dur + FRAME)
assert(state == "over" and fall == nil and thinker == nil)
assert(not humanDrop(1) and not canUndo() and not humansTurn(), "nothing is played after the end")
run(1.0)
assert(game.count == 7 and state == "over", "and nothing moves")

## ── A win for the computer ───────────────────────────────────────────────────────────────────────────────────────────────
fresh(2, true)
scores[2].streak = 2
scores[2].bestStreak = 2
position([5, 7, 6, 7, 5, 7], 1)
assert(humansTurn() and humanDrop(1), "the human does not block")
untilMoves(8)
assert(game.moves[8] == 7 and outcome.winner == 2 and outcome.result == "loss" and #outcome.cells == 4, "the computer takes the win it has")
assert(scores[2].losses == 1 and scores[2].streak == 0 and scores[2].bestStreak == 2 and scores[2].wins == 0, "a loss ends the run")
run(1.0)
assert(state == "over" and fall == nil)

## ── Whichever number the human has ──────────────────────────────────────────────────────────────────────────────────────
fresh(2, false)
position([7, 1, 7, 2, 7, 3], 2)
assert(not humansTurn() and thinker <> nil, "player 1 is the computer, to move with three in a column")
untilMoves(7)
assert(outcome.winner == 1 and scores[2].losses == 1 and scores[2].wins == 0, "the computer's win is the human's loss")
fresh(2, false)
position([1, 4, 1, 4, 2, 4, 2], 2)
assert(humansTurn() and humanDrop(4), "the human is player 2, with three in column 4")
assert(outcome.winner == 2 and scores[2].wins == 1 and scores[2].fastest == 4, "and wins as player 2: four discs of its own")

## ── A drawn game ─────────────────────────────────────────────────────────────────────────────────────────────────────────
var almost = []
for i = 1, CELLS - 1 do
    almost.push(DRAW[i])
end
fresh(2, true)
position(almost, 1)
assert(not humansTurn() and thinker <> nil, "the last disc is the computer's")
untilMoves(CELLS)
assert(outcome.winner == 0 and outcome.result == "draw" and #outcome.cells == 0 and scores[2].draws == 1 and scores[2].streak == 0, "a full grid is a draw")
run(1.0)
assert(state == "over")
fresh(2, true)
scores[2].streak = 1
scores[2].bestStreak = 1
position(almost, 2)
assert(humansTurn() and humanDrop(DRAW[CELLS]), "the human can play the last disc as well")
assert(outcome.winner == 0 and scores[2].draws == 1 and scores[2].streak == 0)

## ── Taking a move back ───────────────────────────────────────────────────────────────────────────────────────────────────
fresh(2, true)
assert(not canUndo() and not undoMove(), "there is nothing to take back")
humanDrop(4)
assert(not canUndo() and not undoMove() and game.count == 1, "nor while a disc is falling")
untilMoves(2)
assert(canUndo())
assert(undoMove() and game.count == 0 and humansTurn() and thinker == nil, "the human's disc and the reply to it go, and it is the human's turn")
assert(data.get(GAME_KEY) == nil, "nothing is left to go on with")
## while the computer is thinking
humanDrop(4)
run(fall.dur + FRAME + 0.1)
assert(game.count == 1 and thinker <> nil)
assert(undoMove() and game.count == 0 and thinker == nil and thought == nil and humansTurn(), "the human's disc goes, and the search is given up")
run(2)
assert(game.count == 0, "and the computer does not move afterwards")
## two moves back, one after the other
humanDrop(3)
untilMoves(2)
humanDrop(5)
untilMoves(4)
var kept = game.moves[1] + game.moves[2] * 10
assert(undoMove() and game.count == 2 and game.moves[1] + game.moves[2] * 10 == kept, "back to where it was two moves before")
assert(resumable.moves.len() == 2 and data.get(GAME_KEY).moves.len() == 2, "and what is kept follows")
## when the computer opens
fresh(2, false)
untilMoves(1)
assert(game.count == 1 and not canUndo(), "the computer's opening disc is not the human's to take back")
humanDrop(3)
untilMoves(3)
assert(canUndo() and undoMove() and game.count == 1 and humansTurn(), "back to the position the computer opened")
## after the end
position([1, 7, 2, 7, 3, 7], 1)
humanDrop(4)
run(1.0)
assert(state == "over" and not canUndo() and not undoMove() and game.count == 7 and scores[2].wins == 1, "a game that is over stays over, and counted once")

## ── What is kept as the game goes ────────────────────────────────────────────────────────────────────────────────────────
fresh(3, true)
humanDrop(4)
assert(data.get(GAME_KEY).moves.join(",") == "4" and data.get(GAME_KEY).level == 3 and resumable <> nil, "a disc is kept as it falls")
untilMoves(2)
assert(#data.get(GAME_KEY).moves == 2, "and so is the reply")
var moves = game.moves.copy()
## the program is run again: the title shows a game to go on with
game = newBoard()
state = "title"
resumable = nil
levelIdx = 1
humanFirst = false
loadGame()
assert(resumable <> nil and resumable.moves.join(",") == moves.join(","))
continueGame()
assert(state == "play" and game.moves.join(",") == moves.join(",") and levelIdx == 3 and human == 1 and humanFirst and humansTurn(), "it comes back as it was")
## and when it is the computer's turn it thinks again
fresh(2, true)
humanDrop(4)
run(fall.dur + FRAME)
game = newBoard()
state = "title"
resumable = nil
thinker = nil
loadGame()
continueGame()
assert(game.count == 1 and not humansTurn() and thinker <> nil, "the search starts again when the computer was to move")
assert(untilMoves(2) == 2)

## ── The title ────────────────────────────────────────────────────────────────────────────────────────────────────────────
fresh(2, true)
humanDrop(4)
run(fall.dur + FRAME + 0.1)
goTitle()
assert(state == "title" and thinker == nil and fall == nil and resumable <> nil, "leaving a game keeps it")
var count = game.count
run(2)
assert(game.count == count, "and nothing moves on the title")
newGame()
assert(game.count == 0 and data.get(GAME_KEY) == nil and resumable == nil and state == "play", "a new game gives the old one up")
print("connect4 play ok")
