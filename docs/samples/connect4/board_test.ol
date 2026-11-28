## The rules of Connect Four (docs/samples/connect4/board.ol): gravity, the columns, the four kinds of line and what is NOT a line,
## undoing, the full grid, and the replay of a list of columns. The bit tricks are checked against a plain scan of a grid kept
## on the side by this test, on thousands of random games: the two share no code.

import "board.ol"
import "connect4_testlib.ol"

## A grid by columns, for the control: cell[col][row + 1] is 0, 1 or 2, kept by the test itself.
func naiveNew()
    var g = []
    for col = 1, COLS do
        g.push([0, 0, 0, 0, 0, 0])
    end
    return g
end

func naiveDrop(g, col, who)
    for row = 1, ROWS do
        if g[col][row] == 0 then
            g[col][row] = who
            return
        end
    end
end

## The player with four in a row on the grid, by looking at every cell in every direction.
func naiveWinner(g)
    for col = 1, COLS do
        for row = 1, ROWS do
            var who = g[col][row]
            if who == 0 then
                continue
            end
            for dir in [[1, 0], [0, 1], [1, 1], [1, -1]] do
                var n = 1
                while n < 4 do
                    var c = col + dir[1] * n
                    var r = row + dir[2] * n
                    if c < 1 or c > COLS or r < 1 or r > ROWS or g[c][r] <> who then
                        break
                    end
                    n += 1
                end
                if n == 4 then
                    return who
                end
            end
        end
    end
    return 0
end

## ── An empty grid ────────────────────────────────────────────────────────────────────────────────────────────────────────
var b = newBoard()
assert(b.count == 0 and toMove(b) == 1 and winner(b) == 0 and not justWon(b) and not isFull(b))
assert(openColumns(b).join(",") == "1,2,3,4,5,6,7", "every column is open")
assert(undo(b) == nil, "there is nothing to take back")

## ── Gravity, and who is who ──────────────────────────────────────────────────────────────────────────────────────────────
drop(b, 4)
drop(b, 4)
drop(b, 5)
assert(cellAt(b, 4, 0) == 1 and cellAt(b, 4, 1) == 2 and cellAt(b, 4, 2) == 0, "a disc falls on the one below")
assert(cellAt(b, 5, 0) == 1 and cellAt(b, 5, 1) == 0 and cellAt(b, 3, 0) == 0)
assert(toMove(b) == 2 and b.count == 3 and b.moves.join(",") == "4,4,5")

## ── The columns ──────────────────────────────────────────────────────────────────────────────────────────────────────────
b = newBoard()
for i = 1, ROWS do
    assert(canDrop(b, 1), "row {i} of a column can be played")
    drop(b, 1)
end
assert(not canDrop(b, 1) and canDrop(b, 2), "a column holds six discs")
assert(openColumns(b).len() == COLS - 1 and not openColumns(b).has(1))
assert(not canDrop(b, 0) and not canDrop(b, COLS + 1) and not canDrop(b, -1), "and there is no column outside the grid")
assert(not canDrop(b, 2.5) and not canDrop(b, "3") and not canDrop(b, nil) and not canDrop(b, true), "that is not a whole number")

## ── The four kinds of line ───────────────────────────────────────────────────────────────────────────────────────────────
## player 1 plays columns 1, 2, 3, 4 along the bottom row; player 2 piles up in column 7
assert(winner(play([1, 7, 2, 7, 3, 7, 4])) == 1, "four across")
b = play([1, 7, 2, 7, 3, 7])
assert(winner(b) == 0 and not justWon(b), "three across is not four")
drop(b, 4)
assert(justWon(b), "the disc that completes the line wins")
assert(winner(play([1, 2, 1, 2, 1, 2, 1])) == 1, "four up")
assert(winner(play([1, 2, 1, 2, 1, 2])) == 0, "three up is not four")
assert(winner(play([1, 2, 1, 2, 1, 2, 3, 2])) == 2, "the second player wins as well")
## a diagonal rising to the right: 1 at row 0, 2 at row 1, 3 at row 2, 4 at row 3, and the support under each
assert(winner(play([1, 2, 2, 3, 3, 4, 3, 4, 4, 7, 4])) == 1, "a rising diagonal")
## the mirror image, falling to the right
assert(winner(play([4, 3, 3, 2, 2, 1, 2, 1, 1, 7, 1])) == 1, "a falling diagonal")
assert(winner(play([1, 2, 2, 3, 3, 4, 3, 4, 4, 7])) == 0, "and a diagonal one disc short is not a line")

## ── What is not a line: the grid has no wrap-around ──────────────────────────────────────────────────────────────────────
## three discs at the top of column 1 and one at the foot of column 2 would be four in a row in a grid stored without a guard
b = newBoard()
b.mine[1] = (1 << 3) | (1 << 4) | (1 << 5) | (1 << STRIDE)
assert(not hasFour(b.mine[1]), "the top of a column does not run into the foot of the next")
b.mine[1] = (1 << 4) | (1 << 5) | (1 << STRIDE) | (1 << (STRIDE + 1))
assert(not hasFour(b.mine[1]), "nor does a diagonal wrap round the top")
b.mine[1] = (1 << 3) | (1 << (STRIDE + 4)) | (1 << (2 * STRIDE + 5))
assert(not hasFour(b.mine[1]), "three discs of a diagonal that has no room for a fourth")
b.mine[1] = (1 << 2) | (1 << (STRIDE + 3)) | (1 << (2 * STRIDE + 4)) | (1 << (3 * STRIDE + 5))
assert(hasFour(b.mine[1]), "a diagonal that ends on the top row is a line")
## the last cell of the last column: the highest bit in use
b.mine[1] = (1 << (COLS * STRIDE - 2)) | (1 << (COLS * STRIDE - 3)) | (1 << (COLS * STRIDE - 4)) | (1 << (COLS * STRIDE - 5))
assert(hasFour(b.mine[1]), "four at the top of the last column")

## ── Taking a disc back ───────────────────────────────────────────────────────────────────────────────────────────────────
b = play([4, 3, 4, 3, 4, 3])
var before = [b.mine[1], b.mine[2], b.count, b.next.join(",")]
drop(b, 4)
assert(justWon(b) and winner(b) == 1)
assert(undo(b) == 4, "undo gives the column it took the disc from")
assert(not justWon(b) and winner(b) == 0 and toMove(b) == 1)
assert(b.mine[1] == before[1] and b.mine[2] == before[2] and b.count == before[3] and b.next.join(",") == before[4], "and leaves the grid as it was")
assert(b.moves.join(",") == "4,3,4,3,4,3")

## ── Against the plain scan, on random games ──────────────────────────────────────────────────────────────────────────────
var rng = Random(2024)
var wins = [0, 0, 0]
for game = 1, 400 do
    var g = naiveNew()
    b = newBoard()
    while not isFull(b) do
        var open = openColumns(b)
        var col = open[rng.randInt(1, #open)]
        var who = toMove(b)
        naiveDrop(g, col, who)
        drop(b, col)
        var scan = 0
        for c in openColumns(b) do
            scan = scan | (1 << b.next[c])
        end
        assert(playableCells(b) == scan, "game {game}, move {b.count}: the squares to play, by addition and by a scan of the columns")
        var expected = naiveWinner(g)
        assert(winner(b) == expected, "game {game}, move {b.count}: the bits say {winner(b)}, the scan says {expected}")
        assert(justWon(b) == (expected <> 0), "game {game}, move {b.count}: justWon disagrees")
        if expected <> 0 then
            var cells = winningCells(b)
            assert(#cells == 4, "game {game}: a won game shows four cells")
            for c in cells do
                assert(cellAt(b, c.col, c.row) == expected, "game {game}: a winning cell belongs to the winner")
            end
            break
        end
    end
    assert(winningCells(b).len() == 0 or winner(b) <> 0, "a game nobody has won lights nothing")
    wins[winner(b) + 1] += 1
end
var tally = wins.join(" ")
assert(wins[2] > 50 and wins[3] > 50, "both players win random games: {tally}")

## undoing a whole random game, move by move, comes back to the empty grid
b = newBoard()
for i = 1, 30 do
    var open = openColumns(b)
    drop(b, open[rng.randInt(1, #open)])
    if justWon(b) then
        break
    end
end
while b.count > 0 do
    undo(b)
end
assert(b.mine[1] == 0 and b.mine[2] == 0 and b.next.join(",") == newBoard().next.join(",") and #b.moves == 0, "everything taken back is an empty grid")

## the four cells of a line, in each of the four directions
func cellList(b)
    var out = []
    for c in winningCells(b) do
        out.push("{c.col}.{c.row}")
    end
    return out.join(" ")
end
assert(cellList(replay([1, 1, 2, 2, 3, 3, 4])) == "1.0 2.0 3.0 4.0", "across")
assert(cellList(replay([2, 3, 2, 3, 2, 3, 2])) == "2.0 2.1 2.2 2.3", "up")
assert(cellList(replay([1, 2, 2, 3, 4, 3, 3, 4, 5, 4, 4])) == "1.0 2.1 3.2 4.3", "up and to the right")
assert(cellList(replay([7, 6, 6, 5, 4, 5, 5, 4, 3, 4, 4])) == "4.3 5.2 6.1 7.0", "up and to the left")
assert(cellList(newBoard()) == "", "no line, no cells")

## place and lift are drop and undo without the history
b = play([4, 4, 3])
var kept = [b.mine[1], b.mine[2], b.count, b.next.join(","), b.moves.join(",")]
place(b, 3)
assert(b.count == 4 and cellAt(b, 3, 1) == 2 and b.moves.join(",") == "4,4,3", "a disc is placed, and moves does not know")
lift(b, 3)
assert([b.mine[1], b.mine[2], b.count, b.next.join(","), b.moves.join(",")].join(" ") == kept.join(" "), "and lifted, the grid is as it was")

## ── A full grid with no line ─────────────────────────────────────────────────────────────────────────────────────────────
b = play(DRAW)
var gd = naiveNew()
var who = 1
for col in DRAW do
    naiveDrop(gd, col, who)
    who = 3 - who
end
assert(isFull(b) and winner(b) == 0 and naiveWinner(gd) == 0, "a drawn game: full, and nobody has four")
assert(openColumns(b).len() == 0 and winningCells(b).len() == 0)
for col = 1, COLS do
    assert(not canDrop(b, col), "no column is open in a full grid")
end

## ── Replaying a list of columns ──────────────────────────────────────────────────────────────────────────────────────────
assert(replay(DRAW).count == CELLS and replay([]).count == 0)
assert(replay([4, 4, 3]).mine[1] == play([4, 4, 3]).mine[1], "a replay is the game")
assert(replay([0]) == nil and replay([8]) == nil and replay([3.5]) == nil and replay(["4"]) == nil, "a column that does not exist")
assert(replay([1, 1, 1, 1, 1, 1, 1]) == nil, "a seventh disc in a column")
assert(replay([1, 7, 2, 7, 3, 7, 4, 5]) == nil, "a move after the game was won")
assert(replay([1, 7, 2, 7, 3, 7, 4]).count == 7, "the winning move itself is part of the game")
## ── The facts of the grid ────────────────────────────────────────────────────────────────────────────────────────────────
assert(LINE_SHIFTS.join(",") == "7,1,8,6", "the four ways a line runs, in bits: across, up, the two diagonals")
b = newBoard()
assert(isOpen(b, 1) and isOpen(b, COLS) and heightOf(b, 3) == 0)
drop(b, 3)
drop(b, 3)
assert(heightOf(b, 3) == 2 and heightOf(b, 4) == 0 and isOpen(b, 3), "a column's height is the discs in it")
for i = 3, ROWS do
    drop(b, 3)
end
assert(heightOf(b, 3) == ROWS and not isOpen(b, 3) and isOpen(b, 2), "a column with six discs is not open")

## ── The threats ──────────────────────────────────────────────────────────────────────────────────────────────────────────
## player 1 has the cells 1, 2 and 3 of the bottom row: the cell that would complete the line is column 4, and column 0 is not one
b = replay([1, 7, 2, 7, 3, 7])
assert((threatCells(b.mine[1]) & (1 << 3 * STRIDE)) <> 0, "three across threaten the cell next to them")
assert((threatCells(b.mine[1]) & (1 << 0)) == 0, "and not a cell that holds a disc of theirs")
b = replay([1, 2, 1, 2, 1])
assert((threatCells(b.mine[1]) & (1 << 3)) <> 0, "three up threaten the cell above")
assert((threatCells(b.mine[2]) & playableCells(b)) == 0, "two discs threaten nothing")
## a gap: 1 _ 3 4 in the bottom row, the gap being column 2
b = replay([1, 7, 3, 7, 4, 7])
assert((threatCells(b.mine[1]) & (1 << STRIDE)) <> 0, "a gap between discs is a threat")
## a rising diagonal with the cell at its foot missing: three discs on (2,1) (3,2) (4,3) threaten (1,0) and (5,4)
b = newBoard()
b.mine[1] = (1 << (STRIDE + 1)) | (1 << (2 * STRIDE + 2)) | (1 << (3 * STRIDE + 3))
assert((threatCells(b.mine[1]) & (1 << 0)) <> 0 and (threatCells(b.mine[1]) & (1 << (4 * STRIDE + 4))) <> 0, "both ends of a diagonal")
## no wrap: the top of column 1 and the foot of column 2 are no line
b = newBoard()
b.mine[1] = (1 << 4) | (1 << 5) | (1 << STRIDE)
assert((threatCells(b.mine[1]) & BOARD_MASK) == 0, "nothing is threatened across the guard")
assert(countBits(0) == 0 and countBits(1) == 1 and countBits(0b1011) == 3 and countBits(1 << 48) == 1)
var feet = 0
for col = 1, COLS do
    feet = feet | (1 << ((col - 1) * STRIDE))
end
assert(playableCells(newBoard()) == feet, "an empty grid can be played at the foot of every column")
assert(countBits(BOARD_MASK) == CELLS and (BOARD_MASK & (1 << (STRIDE - 1))) == 0, "and none on the guards")
print("connect4 board ok")
