## What a frame of Connect Four does, with no drawing: a disc dropped and falling, the computer's turn (a search that is given a few
## milliseconds a frame), the end of a game and what it is worth, taking a move back, and going on with a game that was kept.

import "state.ol"
import "save.ol"
import "sounds.ol"

const MIN_THINK = 0.45          ## seconds before the computer answers, however quick the search: a reply that is seen to come
const THINK_BUDGET = 0.006      ## seconds a frame the search may take; the rest of the frame is the game's
const FALL_BASE = 0.14          ## how long a disc takes to fall: this, and a little more for each row it falls through
const FALL_PER_ROW = 0.035

func beginThinking()
    thinker = startThinking(game, LEVELS[levelIdx], rng)
    thought = nil
    thinkTime = 0.0
end

## Puts the game in the state a game is in when it begins or goes on: nothing in the air, nothing being thought, nobody has won.
func settle()
    computer = 3 - human
    outcome = nil
    fall = nil
    thinker = nil
    thought = nil
    hover = 4
    state = "play"
    if rng == nil then
        rng = Random()
    end
    if toMove(game) == computer then
        beginThinking()
    end
end

## A new game at the level and with the first move that the title shows. What was in progress is given up, and is not counted.
func newGame()
    forgetGame()
    game = newBoard()
    if humanFirst then
        human = 1
    else
        human = 2
    end
    settle()
end

## Goes on with the game that was kept.
func continueGame()
    var t = resumable
    levelIdx = t.level
    human = t.human
    humanFirst = human == 1
    game = replay(t.moves)
    settle()
end

## The game ended with `winner` (1, 2, or 0 for a draw): it is worth what it is worth at once, and the screen follows when the disc lands.
func endGame(winner)
    outcome = {winner: winner, result: resultFor(winner), cells: winningCells(game)}
    recordResult(levelIdx, outcome.result, humanDiscs())
    forgetGame()
end

## Drops a disc for whoever's turn it is, in a column that is open.
func place(col)
    var row = heightOf(game, col)
    fall = {col: col, row: row, who: toMove(game), t: 0.0, dur: FALL_BASE + FALL_PER_ROW * (ROWS - 1 - row)}
    drop(game, col)
    playSound(sndDrop)
    if justWon(game) then
        endGame(winner(game))
    elseif isFull(game) then
        endGame(0)
    else
        saveGame()
    end
end

## The human drops a disc in `col`. Whether the disc went in: it is refused outside the human's turn, while another is falling, and in a full column.
func humanDrop(col)
    if humansTurn() and canDrop(game, col) then
        place(col)
        return true
    end
    return false
end

func moveHover(dx)
    hover = math.clamp(hover + dx, 1, COLS)
end

func land()
    fall = nil
    playSound(sndLand)
    if outcome == nil then
        if toMove(game) == computer then
            beginThinking()
        end
        return
    end
    state = "over"
    playSound({win: sndWin, loss: sndLose, draw: sndDraw}[outcome.result])
end

func think(dt)
    thinkTime += dt
    if thought == nil then
        thought = thinkFor(thinker, THINK_BUDGET)
    end
    if thought <> nil and thinkTime >= MIN_THINK then
        var col = thought
        thought = nil
        thinker = nil
        place(col)
    end
end

## One frame of `dt` seconds.
func updateFrame(dt)
    if state == "title" then
        return
    end
    if fall <> nil then
        fall.t += dt
        if fall.t >= fall.dur then
            land()
        end
    elseif state == "play" and thinker <> nil then
        think(dt)
    end
end

## Takes back the human's last disc, and the computer's reply to it, which brings the game back to the human's turn.
func undoMove()
    if not canUndo() then
        return false
    end
    thinker = nil
    thought = nil
    undo(game)
    while toMove(game) <> human and game.count > 0 do
        undo(game)
    end
    if toMove(game) == computer then
        beginThinking()
    end
    saveGame()
    playSound(sndClick)
    return true
end

## Back to the title: a game in progress is kept, and can be gone on with.
func goTitle()
    thinker = nil
    thought = nil
    fall = nil
    state = "title"
end
