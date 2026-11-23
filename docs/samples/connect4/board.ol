## The rules of Connect Four, with no game, no screen and no drawing: the grid, the legal moves and the lines of four.
##
## Each player's discs are ONE integer, a bit per cell. A column takes STRIDE bits, its six cells and a guard bit above them
## that is never set, so that a line of discs cannot run from the top of one column into the foot of the next: a line of four
## is then two shifts and two ANDs a direction, which is what makes a search fast enough for an interpreter. Bit
## (col - 1) * STRIDE + row is the cell of column col (1 to COLS, from the left) and row `row` (0 to ROWS - 1, from the bottom).

const COLS = 7
const ROWS = 6
const CELLS = COLS * ROWS
const STRIDE = ROWS + 1

## The four ways a line can run, as the distance in bits between two neighbours of a line: across, up, and the two diagonals.
const LINE_SHIFTS = [STRIDE, 1, STRIDE + 1, STRIDE - 1]
const SHIFT_A = LINE_SHIFTS[1]          ## the four, named, for the loops that run a million times and must not iterate a list
const SHIFT_B = LINE_SHIFTS[2]
const SHIFT_C = LINE_SHIFTS[3]
const SHIFT_D = LINE_SHIFTS[4]

## The first bit of a column that is no square — its guard: a disc goes in while the next bit of the column is below it.
func makeColumnTops()
    var tops = []
    for col = 1, COLS do
        tops.push(col * STRIDE - 1)
    end
    return tops
end

const COLUMN_TOP = makeColumnTops()

func makeFeet()
    var m = 0
    for col = 1, COLS do
        m = m | (1 << ((col - 1) * STRIDE))
    end
    return m
end

const FEET = makeFeet()                 ## the bit of the lowest square of every column
const BOARD_MASK = FEET * ((1 << ROWS) - 1)     ## the bits that are squares, not guards

## An empty grid. `mine` holds the discs of player 1 (who moves first) and of player 2; `next` the index of the bit a disc
## dropped in each column takes; `moves` the columns played, in order, which is also how a game is undone and saved.
func newBoard()
    var next = []
    for col = 1, COLS do
        next.push((col - 1) * STRIDE)
    end
    return {mine: [0, 0], next: next, count: 0, moves: []}
end

## Whether column `col` (1 to COLS) has a free square.
func isOpen(b, col)
    return b.next[col] < COLUMN_TOP[col]
end

func canDrop(b, col)
    return typeof(col) == "int" and col >= 1 and col <= COLS and isOpen(b, col)
end

## How many discs are in a column.
func heightOf(b, col)
    return b.next[col] - (col - 1) * STRIDE
end

## The player who plays the i-th move of a game (1 to ...): the first moves first.
func playerOfMove(i)
    return (i - 1) % 2 + 1
end

## The player whose turn it is, 1 or 2.
func toMove(b)
    return playerOfMove(b.count + 1)
end

## Puts a disc of the player to move in column `col`, which must be open, and takes it back: the grid without its history. A
## search that goes up and down a million times uses these, and leaves `moves` alone — so while it runs `moves` does not say how
## the grid got there, and only drop and undo keep it.
func place(b, col)
    var who = toMove(b)
    b.mine[who] = b.mine[who] | (1 << b.next[col])
    b.next[col] += 1
    b.count += 1
end

func lift(b, col)
    b.count -= 1
    b.next[col] -= 1
    var who = toMove(b)
    b.mine[who] = b.mine[who] ~ (1 << b.next[col])
end

## Drops a disc of the player to move in column `col`, which must be open.
func drop(b, col)
    place(b, col)
    b.moves.push(col)
end

## Takes the last disc back, and gives its column; nil when nothing was played.
func undo(b)
    if b.count == 0 then
        return nil
    end
    var col = b.moves.pop()
    lift(b, col)
    return col
end

## Whether a set of discs holds four in a row.
func hasFour(bits)
    for s in LINE_SHIFTS do
        var m = bits & (bits >> s)
        if (m & (m >> 2 * s)) <> 0 then
            return true
        end
    end
    return false
end

## Whether the disc just played completed a line: only the player who moved last can have, so the other's discs are not looked at.
func justWon(b)
    return b.count > 0 and hasFour(b.mine[playerOfMove(b.count)])
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

## The columns that are still open, from the left.
func openColumns(b)
    var list = []
    for col = 1, COLS do
        if isOpen(b, col) then
            list.push(col)
        end
    end
    return list
end

## The squares a disc can be dropped on now, one per open column: adding one at the foot of a column carries up through its discs to
## the first free square, and into the guard bit, which BOARD_MASK drops, when the column is full.
func playableCells(b)
    return ((b.mine[1] | b.mine[2]) + FEET) & BOARD_MASK
end

func countBits(m)
    var n = 0
    while m <> 0 do
        m = m & (m - 1)
        n += 1
    end
    return n
end

## The squares where a disc would complete four for the owner of `p`, along one direction (`s` is the distance in bits between two
## neighbours): the square has three discs of `p` in a window with it, in each of the four places it can have in the window.
func threatsAlong(p, s)
    var a = p << s
    var c = p >> s
    var ab = a & (p << 2 * s)
    var cd = c & (p >> 2 * s)
    return (ab & ((p << 3 * s) | c)) | (cd & ((p >> 3 * s) | a))
end

## Every square where a disc would give `p` four in a row, empty or not.
func threatCells(p)
    return threatsAlong(p, SHIFT_A) | threatsAlong(p, SHIFT_B) | threatsAlong(p, SHIFT_C) | threatsAlong(p, SHIFT_D)
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

## The first line of four found, as a list of {col, row}, or an empty list: what the screen lights when a game is won. A line of
## four starts at a bit that is set where `bits & (bits >> s)` has a pair two steps further on; the lowest such bit is found.
func winningCells(b)
    for who = 1, 2 do
        var bits = b.mine[who]
        for s in LINE_SHIFTS do
            var pairs = bits & (bits >> s)
            var starts = pairs & (pairs >> 2 * s)
            if starts <> 0 then
                var low = countBits((starts & -starts) - 1)
                var cells = []
                for i = 0, 3 do
                    var at = low + i * s
                    cells.push({col: at // STRIDE + 1, row: at % STRIDE})
                end
                return cells
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
