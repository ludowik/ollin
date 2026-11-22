## What changes as a game runs: the screen, the grid, who is who, the disc in the air, the computer's thinking, and how a game ended.

import "board.ol"
import "ai.ol"
import "scores.ol"
import "layout.ol"

global state = "title"      ## "title", "play" or "over"
global game = newBoard()    ## the grid and the moves made
global human = 1            ## the number of the human player: 1 plays first
global computer = 2
global levelIdx = 2         ## the level the title shows, and the game in progress is played at: an index into LEVELS
global humanFirst = true    ## what the title says about who plays first
global thinker = nil        ## the computer's search, a coroutine, while it is its turn
global thought = nil        ## the column the search has found, kept until the computer has been seen to think for a moment
global thinkTime = 0.0
global fall = nil           ## the disc in the air: {col, row, who, t, dur}
global outcome = nil        ## how the game ended: {winner (1, 2, or 0 for a draw), cells (the four, or none)}
global hover = 4            ## the column the next disc is aimed at
global rng = nil
global clock = 0.0          ## seconds since the program began, for what blinks
global resumable = nil      ## a game in progress that was kept, which the title can go on with
global viewH = VIEW_MIN    ## the height of the field: it follows the shape of the area
global pointer = nil        ## the finger or the mouse that is down: {id, aiming}

func levelName()
    return LEVELS[levelIdx].name
end

## The result for the human, "win", "loss" or "draw", of a game that ended with `winner`.
func resultFor(winner)
    if winner == 0 then
        return "draw"
    elseif winner == human then
        return "win"
    end
    return "loss"
end

## How many discs the human has put in the grid.
func humanDiscs()
    if human == 1 then
        return (game.count + 1) // 2
    end
    return game.count // 2
end

func humansTurn()
    return state == "play" and fall == nil and toMove(game) == human
end

## Whether a move can be taken back now. When the computer opens, its opening disc is not the human's to take back.
func canUndo()
    var floor = 0
    if human == 2 then
        floor = 1
    end
    return state == "play" and fall == nil and game.count > floor
end
