## The rules of Connect Four, with no game, no screen and no drawing: the grid, the legal moves and the lines of four.
##
## Each player's discs are ONE integer, a bit per cell. A column takes STRIDE bits, its six cells and a guard bit above them
## that is never set, so that a line of discs cannot run from the top of one column into the foot of the next: a line of four
## is then four shifts and four ANDs, which is what makes a search fast enough for an interpreter. Bit (col - 1) * STRIDE + row
## is the cell of column col (1 to COLS, from the left) and row `row` (0 to ROWS - 1, from the bottom).

const COLS = 7
const ROWS = 6
const CELLS = COLS * ROWS
const STRIDE = ROWS + 1

## The order the columns are tried in, centre first: a disc in the middle is part of more lines, and a search that meets the
## good moves first cuts off more.
const CENTRE_FIRST = [4, 3, 5, 2, 6, 1, 7]

## An empty grid. `mine` holds the discs of player 1 (who moves first) and of player 2; `next` the index of the bit a disc
## dropped in each column takes; `moves` the columns played, in order, which is also how a game is undone and saved.
func newBoard()
    var next = []
    for col = 1, COLS do
        next.push((col - 1) * STRIDE)
    end
    return {mine: [0, 0], next: next, count: 0, moves: []}
end

func canDrop(b, col)
    return typeof(col) == "int" and col >= 1 and col <= COLS and b.next[col] < col * STRIDE - 1
end

## The player whose turn it is, 1 or 2.
func toMove(b)
    return b.count % 2 + 1
end

## Drops a disc of the player to move in column `col`, which must be open.
func drop(b, col)
    var who = b.count % 2 + 1
    b.mine[who] = b.mine[who] | (1 << b.next[col])
    b.next[col] += 1
    b.count += 1
    b.moves.push(col)
end

## Takes the last disc back, and gives its column; nil when nothing was played.
func undo(b)
    if b.count == 0 then
        return nil
    end
    var col = b.moves.pop()
    b.count -= 1
    b.next[col] -= 1
    var who = b.count % 2 + 1
    b.mine[who] = b.mine[who] ~ (1 << b.next[col])
    return col
end

## Whether a set of discs holds four in a row: across, up, and the two diagonals.
func hasFour(bits)
    var m = bits & (bits >> STRIDE)
    if (m & (m >> 2 * STRIDE)) <> 0 then
        return true
    end
    m = bits & (bits >> 1)
    if (m & (m >> 2)) <> 0 then
        return true
    end
    m = bits & (bits >> STRIDE + 1)
    if (m & (m >> 2 * (STRIDE + 1))) <> 0 then
        return true
    end
    m = bits & (bits >> STRIDE - 1)
    return (m & (m >> 2 * (STRIDE - 1))) <> 0
end

## Whether the disc just played completed a line: only the player who moved last can have, so the other's discs are not looked at.
func justWon(b)
    return b.count > 0 and hasFour(b.mine[(b.count - 1) % 2 + 1])
end

## The player who has four in a row, 1 or 2, or 0 when nobody has.
func winner(b)
    if hasFour(b.mine[1]) then
        return 1
    elseif hasFour(b.mine[2]) then
        return 2
    end
    return 0
end

func isFull(b)
    return b.count == CELLS
end

## The columns that are still open, centre first.
func openColumns(b)
    var list = []
    for col in CENTRE_FIRST do
        if b.next[col] < col * STRIDE - 1 then
            list.push(col)
        end
    end
    return list
end

## Who owns a cell: 1, 2, or 0 when it is empty.
func cellAt(b, col, row)
    var bit = 1 << ((col - 1) * STRIDE + row)
    if (b.mine[1] & bit) <> 0 then
        return 1
    elseif (b.mine[2] & bit) <> 0 then
        return 2
    end
    return 0
end

## The first line of four cells found, as a list of {col, row}, or an empty list: what the screen lights when a game is won.
func winningCells(b)
    for col = 1, COLS do
        for row = 0, ROWS - 1 do
            var who = cellAt(b, col, row)
            if who == 0 then
                continue
            end
            for dir in [[1, 0], [0, 1], [1, 1], [1, -1]] do
                var cells = [{col: col, row: row}]
                var c = col
                var r = row
                while #cells < 4 do
                    c += dir[1]
                    r += dir[2]
                    if c < 1 or c > COLS or r < 0 or r >= ROWS or cellAt(b, c, r) <> who then
                        break
                    end
                    cells.push({col: c, row: r})
                end
                if #cells == 4 then
                    return cells
                end
            end
        end
    end
    return []
end

## The grid a list of columns makes, or nil when the list is not a game that can have been played: a column out of range, a
## full column, or a move after the game was won. What a save is checked with.
func replay(list)
    var b = newBoard()
    for col in list do
        if not canDrop(b, col) or justWon(b) then
            return nil
        end
        drop(b, col)
    end
    return b
end
