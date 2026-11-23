## What the tests of Connect Four share: a game written as a list of columns, a game that ends in a draw, and random positions.

import "board.ol"

## A full game in which nobody has four in a row: 42 columns, found by random play.
const DRAW = [2,7,2,3,3,7,6,4,7,3,7,3,1,2,6,1,1,1,2,6,6,3,2,2,5,1,3,1,4,4,6,7,6,4,7,5,4,4,5,5,5,5]

## The same game one move short: one cell of the grid is left.
func makeAlmostDraw()
    var list = []
    for i = 1, CELLS - 1 do
        list.push(DRAW[i])
    end
    return list
end

const ALMOST_DRAW = makeAlmostDraw()

## The grid after a list of columns, with no rule applied but gravity.
func play(list)
    var b = newBoard()
    for col in list do
        drop(b, col)
    end
    return b
end

## A position `moves` moves in, from random play that nobody has won yet; nil when the game ended on the way.
func randomPosition(rng, moves)
    var b = newBoard()
    for i = 1, moves do
        var open = openColumns(b)
        if #open == 0 then
            return nil
        end
        drop(b, open[rng.randInt(1, #open)])
        if justWon(b) then
            return nil
        end
    end
    return b
end
