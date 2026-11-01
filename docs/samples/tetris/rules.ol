## The RULES of Tetris as the handheld of 1989 plays them, with no drawing: the well, the seven pieces and the way
## they turn, what a line is worth, how fast the pieces fall, and how the next one is drawn.
##
## The well is a flat array of COLS * ROWS numbers, 0 for an empty cell and the number of the piece for a filled one.
## Columns and rows are 0-based here, rows counting down from the top, as the pieces are drawn. Imported by
## play.ol and by tetris.ol, which read COLS, ROWS and Piece from here — a const or an enum declared by a module is
## visible to the functions of the file that imports it.

const COLS = 10
const ROWS = 18             ## the handheld shows 18 rows, not the 20 of the home computers
const SPAWN_X = 3           ## the column of the left edge of a piece's box when it appears
const SPAWN_Y = -1          ## the flat row of a piece lands on the first row of the well, the rest hangs below

## The seven pieces, numbered as the well stores them.
enum Piece
    I, O, T, S, Z, J, L
end
const KINDS = 7

## Where a piece is, in its box: shapes[kind][turn] is its four cells as [x, y], x to the right and y down.
global shapes = []

## A turn of a piece in a 3x3 box, a quarter turn clockwise about the centre of the box.
func turnClockwise(cells)
    return cells.map(func(c)
        return [2 - c[2], c[1]]
    end)
end

## A piece as it appears, then the turns it can take. The pieces that are the same shape turned half a circle
## (I, S, Z) have two positions and swing between them, and the square has one: that is how the original turns them.
func turnsFrom(spawn, count)
    var list = [spawn]
    for i = 2, count do
        list.push(turnClockwise(list[i - 1]))
    end
    return list
end

shapes[Piece.I] = [
    [[0, 1], [1, 1], [2, 1], [3, 1]],
    [[2, 0], [2, 1], [2, 2], [2, 3]]
]
shapes[Piece.O] = [[[1, 1], [2, 1], [1, 2], [2, 2]]]
shapes[Piece.T] = turnsFrom([[0, 1], [1, 1], [2, 1], [1, 2]], 4)
shapes[Piece.S] = turnsFrom([[1, 1], [2, 1], [0, 2], [1, 2]], 2)
shapes[Piece.Z] = turnsFrom([[0, 1], [1, 1], [1, 2], [2, 2]], 2)
shapes[Piece.J] = turnsFrom([[0, 1], [1, 1], [2, 1], [2, 2]], 4)
shapes[Piece.L] = turnsFrom([[0, 1], [1, 1], [2, 1], [0, 2]], 4)

## The smallest rectangle of the box that holds the cells of a position: its first and last column, first and last row.
func shapeBounds(kind, turn)
    var x0, x1, y0, y1 = 9, -9, 9, -9
    for c in shapes[kind][turn] do
        x0 = math.min(x0, c[1])
        x1 = math.max(x1, c[1])
        y0 = math.min(y0, c[2])
        y1 = math.max(y1, c[2])
    end
    return x0, x1, y0, y1
end

## The position a quarter turn from `turn`: dir is 1 clockwise or -1 counter-clockwise.
func turnedBy(kind, turn, dir)
    var n = len(shapes[kind])
    return (turn - 1 + dir + n) % n + 1
end

func newWell()
    var g = []
    for i = 1, COLS * ROWS do
        g[i] = 0
    end
    return g
end

func wellIdx(x, y)
    return y * COLS + x + 1
end

## True when the piece fits in the well with its box at (x, y): inside the walls and the floor, on empty cells. The
## cells above the first row are free, since a piece appears half above it.
func fits(well, kind, turn, x, y)
    for c in shapes[kind][turn] do
        var cx = x + c[1]
        var cy = y + c[2]
        if cx < 0 or cx >= COLS or cy >= ROWS then
            return false
        end
        if cy >= 0 and well[wellIdx(cx, cy)] <> 0 then
            return false
        end
    end
    return true
end

## Writes the piece into the well. The lowest row it touches is returned, which tells how high it came to rest.
func lockPiece(well, kind, turn, x, y)
    var lowest = -1
    for c in shapes[kind][turn] do
        var cy = y + c[2]
        if cy >= 0 then
            well[wellIdx(x + c[1], cy)] = kind
            lowest = math.max(lowest, cy)
        end
    end
    return lowest
end

## The rows that are full, from the top down.
func fullRows(well)
    var rows = []
    for r = 0, ROWS - 1 do
        var full = true
        for c = 0, COLS - 1 do
            if well[wellIdx(c, r)] == 0 then
                full = false
                break
            end
        end
        if full then
            rows.push(r)
        end
    end
    return rows
end

## Removes the rows given: what was above them falls, and the top is left empty.
func collapse(well, rows)
    var to = ROWS - 1
    for from = ROWS - 1, 0, -1 do
        if not rows.contains(from) then
            if to <> from then
                for c = 0, COLS - 1 do
                    well[wellIdx(c, to)] = well[wellIdx(c, from)]
                end
            end
            to -= 1
        end
    end
    while to >= 0 do
        for c = 0, COLS - 1 do
            well[wellIdx(c, to)] = 0
        end
        to -= 1
    end
end

## What clearing `count` rows at once is worth: 40, 100, 300 or 1200, times one more than the level.
func lineScore(count, level)
    return [40, 100, 300, 1200][count] * (level + 1)
end

## The frames a piece takes to fall one row, level by level (0 to 20; past it the pieces fall every third frame),
## the game running at about 60 frames a second.
const FALL_FRAMES = [53, 49, 45, 41, 37, 33, 28, 22, 17, 11, 10, 9, 8, 7, 6, 6, 5, 5, 4, 4, 3]

func fallFrames(level)
    return FALL_FRAMES[math.min(level, len(FALL_FRAMES) - 1) + 1]
end

## The level of an A game goes up with every ten lines, from the one it began at; a B game stays at its own.
func levelFor(startLevel, lines, gameType)
    if gameType == "B" then
        return startLevel
    end
    return startLevel + lines // 10
end

## The rows of a B game's start: two rows for each step of height, each cell filled or not by chance with one hole
## left in the row, so that no row is full from the start.
func addGarbage(well, height)
    for r = ROWS - height * 2, ROWS - 1 do
        var hole = math.randInt(0, COLS - 1)
        for c = 0, COLS - 1 do
            if c <> hole and math.randInt(1, 2) == 1 then
                well[wellIdx(c, r)] = math.randInt(1, KINDS)
            end
        end
    end
end

## The frames before the next piece appears: the higher the last one came to rest, the longer.
func entryDelay(lockedRow)
    var gap = ROWS - 1 - lockedRow
    return 10 + 2 * math.min(gap // 4, 4)
end

## The next piece: drawn at random, and drawn once more when it is the one just played, so that a piece rarely comes
## twice in a row.
func nextKind(prev)
    var k = math.randInt(1, KINDS)
    if k == prev then
        k = math.randInt(1, KINDS)
    end
    return k
end
