## The computer's play (docs/samples/connect4/ai.ol): the threats it sees, that it takes a win and stops a loss, that it never plays a
## full column, that pruning changes no value (against a plain minimax kept in this test), how ties are broken, that a thinker
## answers the same as a direct search, and that a deeper level beats a shallower one.

import "ai.ol"
import "connect4_testlib.ol"

## The value of a position for the player to move by looking `depth` moves ahead, with nothing but wins and losses counted: no
## pruning, no shortcut, no evaluation — what the pruned search has to agree with.
func pure(b, depth, ply)
    if b.count == CELLS or depth == 0 then
        return 0
    end
    var best = -INFINITY
    for col = 1, COLS do
        if canDrop(b, col) then
            drop(b, col)
            var v = WIN - ply
            if not justWon(b) then
                v = -pure(b, depth - 1, ply + 1)
            end
            undo(b)
            if v > best then
                best = v
            end
        end
    end
    return best
end

func nothing(b, bal)
    return 0
end

var b = newBoard()

## ── What a position is worth when the search stops ──────────────────────────────────────────────────────────────────────
assert(positional(newBoard()) == 0 and positional(replay([4])) == -COLUMN_WEIGHT[4], "the player to move is behind by the disc the other has played")
assert(positional(replay([4, 3])) == COLUMN_WEIGHT[4] - COLUMN_WEIGHT[3] and positional(replay([4, 4])) == 0)
assert(positional(replay([1, 4, 1])) == COLUMN_WEIGHT[4] - 2 * COLUMN_WEIGHT[1], "and the weights add up")
## a threat counts for the player who holds it, and against the one who does not
assert(evaluate(replay([1, 7, 2, 7, 3, 6]), 0) == THREAT, "the player to move holds a threat")
assert(evaluate(replay([5, 1, 7, 2, 5, 3]), 0) == -THREAT, "the other side holds one")
assert(evaluate(replay([4]), positional(replay([4]))) == -COLUMN_WEIGHT[4], "no threat, so the positions of the discs alone")

## ── Taking a win, stopping a loss ────────────────────────────────────────────────────────────────────────────────────────
var rng = Random(11)
b = replay([1, 7, 2, 7, 3, 7])
for depth = 1, 5 do
    assert(bestColumn(b, depth, rng) == 4, "depth {depth}: three across, the fourth wins")
end
b = replay([1, 4, 1, 4, 2, 4])
assert(toMove(b) == 1 and not justWon(b))
for depth = 2, 5 do
    assert(bestColumn(b, depth, rng) == 4, "depth {depth}: the other side has three up, and only column 4 stops it")
end
## a win beats a block: the player to move has three across and the other side three up
b = replay([1, 4, 2, 4, 3, 4])
for depth = 1, 4 do
    assert(bestColumn(b, depth, rng) == 4, "depth {depth}: winning comes before blocking")
end
## two open ends are a win in three moves: 3 and 4 on the bottom row, then 2 or 5 makes three with a free cell on each side
b = replay([3, 7, 4, 7])
assert(negamax(b, 4, -INFINITY, INFINITY, positional(b), 0) > WIN - 10, "a line open at both ends wins by force")
assert([2, 5].contains(bestColumn(b, 4, rng)), "and the search plays the move that makes it")
## the player to move cannot stop two threats: the other side has 2, 3 and 4 on the bottom row, and columns 1 and 5 are both open
b = replay([7, 2, 6, 3, 7, 4])
assert(toMove(b) == 1 and (threatCells(b.mine[2]) & playableCells(b)) == (1 << 0 | 1 << 4 * STRIDE), "two cells to block")
assert(negamax(b, 2, -INFINITY, INFINITY, 0, 0) == -(WIN - 1), "and only one disc to block with: the other side wins next move")
assert(openColumns(b).contains(bestColumn(b, 3, rng)), "a lost position still gets a move")

## ── Never a full column ──────────────────────────────────────────────────────────────────────────────────────────────────
b = newBoard()
for i = 1, ROWS do
    drop(b, 4)
end
for level in LEVELS do
    for i = 1, 6 do
        assert(canDrop(b, chooseMove(b, level, rng)), "{level.name}: a full column is not played")
    end
end
var almost = []
for i = 1, CELLS - 1 do
    almost.push(DRAW[i])
end
b = replay(almost)
assert(openColumns(b).len() == 1, "one cell of the grid is left")
for level in LEVELS do
    assert(chooseMove(b, level, rng) == openColumns(b)[1], "{level.name}: the only open column is the move")
end

## ── Pruning changes no value ─────────────────────────────────────────────────────────────────────────────────────────────
leaf = nothing
var checked = 0
rng = Random(99)
for n = 1, 80 do
    var p = randomPosition(rng, 6 + n % 20)
    if p == nil then
        continue
    end
    var depth = 1 + n % 4
    var expected = pure(p, depth, 0)
    var got = negamax(p, depth, -INFINITY, INFINITY, 0, 0)
    assert(got == expected, "position {n}, depth {depth}: pruned search says {got}, the plain one {expected}")
    ## and the move found is one of the best
    var col = bestColumn(p, depth, rng)
    drop(p, col)
    var v = WIN
    if not justWon(p) then
        v = -pure(p, depth - 1, 1)
    end
    undo(p)
    assert(v == expected, "position {n}, depth {depth}: column {col} is worth {v} and the best is {expected}")
    checked += 1
end
assert(checked > 45, "enough positions were checked: {checked}")
leaf = evaluate

## ── Ties are broken at random, among the best ────────────────────────────────────────────────────────────────────────────
leaf = nothing
var seen = {}
rng = Random(5)
for i = 1, 80 do
    seen[bestColumn(newBoard(), 1, rng)] = true
end
assert(map.len(seen) == COLS, "with nothing to choose by, every column is played in turn")
leaf = evaluate
seen = {}
for i = 1, 20 do
    seen[bestColumn(newBoard(), 4, rng)] = true
end
assert(seen[4] == true or seen[3] == true or seen[5] == true, "and with something to choose by, one of the middle columns")

## ── A thinker answers like a direct search, and gives the screen back ───────────────────────────────────────────────────
b = replay([4, 4, 3, 5])
var level = {name: "t", depth: 6, blunder: 0.0}
var direct = chooseMove(replay(b.moves), level, Random(8))
var thinker = startThinking(b, level, Random(8))
assert(coroutine.status(thinker) == "suspended" and b.count == 4, "nothing is searched before the first turn")
var turns = 0
var answer = nil
while answer == nil do
    answer = thinkFor(thinker, 0.0)
    turns += 1
    assert(turns < 100000, "the thinker finishes")
end
assert(answer == direct, "the thinker found {answer}, a direct search {direct}")
assert(turns > 2, "a search of {nodes} positions is given in several turns, not at once: {turns}")
assert(coroutine.status(thinker) == "dead" and b.count == 4 and b.moves.join(",") == "4,4,3,5", "and the game was left alone")

## ── A deeper level beats a shallower one ────────────────────────────────────────────────────────────────────────────────
func game(first, second, seed)
    var g = newBoard()
    var r = Random(seed)
    var levels = [first, second]
    while not isFull(g) and not justWon(g) do
        drop(g, chooseMove(g, levels[toMove(g)], r))
    end
    if justWon(g) then
        return winner(g)
    end
    return 0
end
## (the real levels at their depths: the hard one is too slow to play whole games in a test, so a search six moves deep stands for it)
var easy = LEVELS[1]
var hard = {name: "Deep", depth: 6, blunder: 0.0}
var hardWins = 0
var easyWins = 0
for seed = 1, 4 do
    var w = game(hard, easy, seed)
    if w == 1 then
        hardWins += 1
    elseif w == 2 then
        easyWins += 1
    end
    w = game(easy, hard, seed)
    if w == 2 then
        hardWins += 1
    elseif w == 1 then
        easyWins += 1
    end
end
assert(hardWins >= 6 and easyWins <= 1, "the deeper search wins {hardWins} of 8 games, the shallow one {easyWins}")
print("connect4 ai ok")
