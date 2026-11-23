## The computer's play: negamax with alpha-beta pruning over the bitboards of board.ol.
##
## A search is plain recursion, written as it reads. Run inside a coroutine, it gives the screen back every SLICE nodes with a
## bare `yield`, so that "thinking" costs a few milliseconds a frame and not one long freeze; run outside one (the tests), it
## simply goes on. `thinker` is the coroutine, and the game resumes it once a frame until it is dead.

import "board.ol"

const WIN = 100000              ## a won game; a quicker win is worth more, a slower loss less
const INFINITY = 1000000
const SLICE = 500               ## nodes between two yields: a few milliseconds, even where the machine is slow (play.ol gives the search
                                ## THINK_BUDGET a frame, and a turn goes on to the next yield, so it runs about one slice past it)
const THREAT = 12               ## what a threat — an empty cell that would complete four — counts for in the evaluation

## What a disc in each column is worth by where it is: the middle is part of more lines than the edge.
const COLUMN_WEIGHT = [1, 2, 3, 4, 3, 2, 1]

## The order the columns are tried in, the best weight first: a search that meets the good moves first cuts off more.
const CENTRE_FIRST = [4, 3, 5, 2, 6, 1, 7]

## The levels. The depth is how many moves ahead the search looks; `blunder` the chance that the computer plays a column at random
## instead of the one it found, which is what makes a level beatable without making it play stupidly in between.
const LEVELS = [
    {name: "Easy",   depth: 2, blunder: 0.3},
    {name: "Medium", depth: 5, blunder: 0.0},
    {name: "Hard",   depth: 9, blunder: 0.0}
]

global nodes = 0                ## how many positions the last search looked at

## How much the player to move is ahead by the positions of the discs alone: the weight of the columns, for them minus for the other.
func positional(b)
    var who = toMove(b)
    var total = 0
    for i, col in b.moves do
        if playerOfMove(i) == who then
            total += COLUMN_WEIGHT[col]
        else
            total -= COLUMN_WEIGHT[col]
        end
    end
    return total
end

## What a position is worth to the player to move when the search stops: the positions of the discs, and the threats each side holds.
## `mineThreats` is threatCells of the player to move when the caller has it already.
func evaluate(b, bal, mineThreats = nil)
    var who = toMove(b)
    var mine = b.mine[who]
    var theirs = b.mine[3 - who]
    var empty = BOARD_MASK & ~(mine | theirs)
    if mineThreats == nil then
        mineThreats = threatCells(mine)
    end
    return bal + THREAT * (countBits(mineThreats & empty) - countBits(threatCells(theirs) & empty))
end

global leaf = evaluate          ## what is worth a position when the search stops looking: a test replaces it

func checkpoint()
    if coroutine.isYieldable() then
        yield
    end
end

## The value of the position for the player to move, looking `depth` moves ahead, between alpha and beta. `bal` is the positional
## balance for the player to move (see positional), `ply` how many moves have been made since the search began. `mineThreats` is
## threatCells of the player to move: the move that led here changed only the other side's discs, so the parent has it already.
func negamax(b, depth, alpha, beta, bal, ply, mineThreats = nil)
    nodes += 1
    if nodes % SLICE == 0 then
        checkpoint()
    end
    if b.count == CELLS then
        return 0
    end
    if depth == 0 then
        return leaf(b, bal, mineThreats)
    end
    var who = toMove(b)
    var playable = playableCells(b)
    if mineThreats == nil then
        mineThreats = threatCells(b.mine[who])
    end
    if (mineThreats & playable) <> 0 then
        return WIN - ply
    end
    var theirThreats = threatCells(b.mine[3 - who])
    var danger = theirThreats & playable
    var forced = 0                        ## the square that has to be blocked, when the other side threatens exactly one
    if danger <> 0 and depth >= 2 then
        if (danger & (danger - 1)) <> 0 then
            return -(WIN - ply - 1)       ## two squares to block, and only one disc to block with: the other side wins next move
        end
        forced = danger
    end
    var best = -INFINITY
    for col in CENTRE_FIRST do
        if (forced == 0 or (1 << b.next[col]) == forced) and b.next[col] < COLUMN_TOP[col] then
            place(b, col)
            var v = -negamax(b, depth - 1, -beta, -alpha, -(bal + COLUMN_WEIGHT[col]), ply + 1, theirThreats)
            lift(b, col)
            if v > best then
                best = v
            end
            if best > alpha then
                alpha = best
            end
            if alpha >= beta then
                break
            end
        end
    end
    return best
end

## The best column for the player to move, looking `depth` moves ahead; among the columns that are equally good, one at random.
func bestColumn(b, depth, rng)
    nodes = 0
    var bal = positional(b)
    var best = -INFINITY
    var ties = []
    for col in CENTRE_FIRST do
        if not isOpen(b, col) then
            continue
        end
        drop(b, col)
        var v = WIN
        if not justWon(b) then
            v = -negamax(b, depth - 1, -INFINITY, -(best - 1), -(bal + COLUMN_WEIGHT[col]), 1)
        end
        undo(b)
        if v > best then
            best = v
            ties = [col]
        elseif v == best then
            ties.push(col)
        end
    end
    return ties[rng.randInt(1, #ties)]
end

## The column the computer plays at a level: the search's, or one at random when it blunders. `b` is changed while it thinks and
## put back before it answers.
func chooseMove(b, level, rng)
    if level.blunder > 0 and rng.rand() < level.blunder then
        var open = openColumns(b)
        return open[rng.randInt(1, #open)]
    end
    return bestColumn(b, level.depth, rng)
end

## A coroutine that works the move out on a COPY of the game, so that the game goes on being drawn, and read, meanwhile.
func startThinking(b, level, rng)
    var copy = replay(b.moves)
    return coroutine.create(func()
        return chooseMove(copy, level, rng)
    end)
end

## Gives the thinker a turn for at most `seconds`: the column when it has found it, nil while it is still at work.
func thinkFor(thinker, seconds)
    var start = cpuTime()
    while coroutine.status(thinker) == "suspended" do
        var col = coroutine.resume(thinker)
        if coroutine.status(thinker) == "dead" then
            return col
        end
        if cpuTime() - start >= seconds then
            return nil
        end
    end
    return nil
end
