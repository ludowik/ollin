## The computer's play: negamax with alpha-beta pruning over the bitboards of board.ol.
##
## A search is plain recursion, written as it reads. Run inside a coroutine, it gives the screen back every SLICE nodes with a
## bare `yield`, so that "thinking" costs a few milliseconds a frame and not one long freeze; run outside one (the tests), it
## simply goes on. `thinker` is the coroutine, and the game resumes it once a frame until it is dead.

import "board.ol"

const WIN = 100000              ## a won game; a quicker win is worth more, a slower loss less
const INFINITY = 1000000
const SLICE = 500               ## nodes between two yields: a few milliseconds, even where the machine is slow
const THREAT = 12               ## what a threat — an empty cell that would complete four — counts for in the evaluation

## What a disc in each column is worth by where it is: the middle is part of more lines than the edge.
const COLUMN_WEIGHT = [1, 2, 3, 4, 3, 2, 1]

## The levels. The depth is how many moves ahead the search looks; `blunder` the chance that the computer plays a column at random
## instead of the one it found, which is what makes a level beatable without making it play stupidly in between.
const LEVELS = [
    {name: "Easy",   depth: 2, blunder: 0.3},
    {name: "Medium", depth: 5, blunder: 0.0},
    {name: "Hard",   depth: 9, blunder: 0.0}
]

func makeBoardMask()
    var mask = 0
    for col = 1, COLS do
        mask = mask | (((1 << ROWS) - 1) << ((col - 1) * STRIDE))
    end
    return mask
end

const BOARD_MASK = makeBoardMask()      ## the bits that are cells, not guards

global nodes = 0                ## how many positions the last search looked at
global leaf = nil               ## what is worth a position when the search stops looking: set below, and replaced by a test

func countBits(m)
    var n = 0
    while m <> 0 do
        m = m & (m - 1)
        n += 1
    end
    return n
end

## The cells where a disc would complete four for the owner of `p`, along one direction (`s` is the distance in bits between two
## neighbours): the cell has three discs of `p` in a window with it, in each of the four places it can have in the window.
func threatsAlong(p, s)
    var a = p << s
    var b = p << 2 * s
    var c = p >> s
    var d = p >> 2 * s
    return (a & b & (p << 3 * s)) | (c & d & (p >> 3 * s)) | (a & c & d) | (a & b & c)
end

## Every cell where a disc would give `p` four in a row, empty or not.
func threatCells(p)
    return threatsAlong(p, 1) | threatsAlong(p, STRIDE) | threatsAlong(p, STRIDE + 1) | threatsAlong(p, STRIDE - 1)
end

## The cells a disc can be dropped on now, one per open column.
func playableCells(b)
    var m = 0
    for col = 1, COLS do
        if b.next[col] < col * STRIDE - 1 then
            m = m | (1 << b.next[col])
        end
    end
    return m
end

## How much the player to move is ahead by the positions of the discs alone: the weight of the columns, for them minus for the other.
func positional(b)
    var who = toMove(b)
    var total = 0
    for i, col in b.moves do
        if (i - 1) % 2 + 1 == who then
            total += COLUMN_WEIGHT[col]
        else
            total -= COLUMN_WEIGHT[col]
        end
    end
    return total
end

## What a position is worth to the player to move when the search stops: the positions of the discs, and the threats each side holds.
func evaluate(b, bal)
    var who = toMove(b)
    var mine = b.mine[who]
    var theirs = b.mine[3 - who]
    var empty = BOARD_MASK & ~(mine | theirs)
    return bal + THREAT * (countBits(threatCells(mine) & empty) - countBits(threatCells(theirs) & empty))
end

leaf = evaluate

func checkpoint()
    if coroutine.isYieldable() then
        yield
    end
end

## The value of the position for the player to move, looking `depth` moves ahead, between alpha and beta. `bal` is the positional
## balance for the player to move (see positional), `ply` how many moves have been made since the search began.
func negamax(b, depth, alpha, beta, bal, ply)
    nodes += 1
    if nodes % SLICE == 0 then
        checkpoint()
    end
    if b.count == CELLS then
        return 0
    end
    if depth == 0 then
        return leaf(b, bal)
    end
    var who = toMove(b)
    var playable = playableCells(b)
    if (threatCells(b.mine[who]) & playable) <> 0 then
        return WIN - ply
    end
    var danger = threatCells(b.mine[3 - who]) & playable
    var forced = 0
    if danger <> 0 then
        if (danger & (danger - 1)) <> 0 and depth >= 2 then
            return -(WIN - ply - 1)       ## two cells to block, and only one disc to block with: the other side wins next move
        end
        if depth >= 2 then
            for col = 1, COLS do
                if (1 << b.next[col]) == danger then
                    forced = col
                end
            end
        end
    end
    var best = -INFINITY
    for col in CENTRE_FIRST do
        if (forced == 0 or col == forced) and b.next[col] < col * STRIDE - 1 then
            drop(b, col)
            var v = -negamax(b, depth - 1, -beta, -alpha, -(bal + COLUMN_WEIGHT[col]), ply + 1)
            undo(b)
            if v > best then
                best = v
                if v > alpha then
                    alpha = v
                    if alpha >= beta then
                        break
                    end
                end
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
    for col in openColumns(b) do
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
