## The RULES of Sudoku, with no drawing. The grid is a flat array of 81 numbers: 0 for an empty cell, 1 to 9 for a
## digit; the cells are numbered row by row, from 1. A set of digits is a bit mask, bit d standing for the digit d.
##
## Imported by sudoku.ol, which reads N and CELLS from here — a const declared by a module is visible to the
## functions of the file that imports it.

const N = 9
const BOX = 3
const CELLS = N * N
const ALL = 0x3FE                 ## the mask of the digits 1 to 9

## The tables every rule needs, filled once by boardBuild(): the row, column and box of each cell, the 27 units
## (nine rows, nine columns, nine boxes, each a list of 9 cells), the 20 peers of each cell (the cells that share a
## unit with it), and, for a mask, how many digits it holds and the lowest one.
global board = {rowOf: [], colOf: [], boxOf: [], units: [], peers: [], count: [], low: []}

func boardIdx(r, c)
    return (r - 1) * N + c
end

func maskCount(mask)
    return board.count[mask + 1]
end

func maskLow(mask)
    return board.low[mask + 1]
end

## The digits of a mask, in order.
func maskDigits(mask)
    var out = []
    for d = 1, N do
        if (mask & (1 << d)) <> 0 then
            out.push(d)
        end
    end
    return out
end

func boardBuild()
    board.rowOf = []
    board.colOf = []
    board.boxOf = []
    board.units = []
    board.peers = []
    board.count = []
    board.low = []
    for i = 1, CELLS do
        var r = (i - 1) // N + 1
        var c = (i - 1) % N + 1
        board.rowOf.push(r)
        board.colOf.push(c)
        board.boxOf.push((r - 1) // BOX * BOX + (c - 1) // BOX + 1)
    end
    for r = 1, N do
        var unit = []
        for c = 1, N do
            unit.push(boardIdx(r, c))
        end
        board.units.push(unit)
    end
    for c = 1, N do
        var unit = []
        for r = 1, N do
            unit.push(boardIdx(r, c))
        end
        board.units.push(unit)
    end
    for b = 1, N do
        var unit = []
        for i = 1, CELLS do
            if board.boxOf[i] == b then
                unit.push(i)
            end
        end
        board.units.push(unit)
    end
    for i = 1, CELLS do
        var list = []
        for j = 1, CELLS do
            var shares = board.rowOf[j] == board.rowOf[i] or board.colOf[j] == board.colOf[i] or board.boxOf[j] == board.boxOf[i]
            if j <> i and shares then
                list.push(j)
            end
        end
        board.peers.push(list)
    end
    for mask = 0, ALL + 1 do
        var n = 0
        var low = 0
        for d = 1, N do
            if (mask & (1 << d)) <> 0 then
                n += 1
                if low == 0 then
                    low = d
                end
            end
        end
        board.count.push(n)
        board.low.push(low)
    end
end

func boardNew()
    var g = []
    for i = 1, CELLS do
        g.push(0)
    end
    return g
end

func boardCopy(g)
    var copy = []
    for i = 1, CELLS do
        copy.push(g[i])
    end
    return copy
end

## The digits cell i could take, looking at its peers only: a mask.
func boardCandidates(g, i)
    var used = 0
    for p in board.peers[i] do
        if g[p] <> 0 then
            used = used | (1 << g[p])
        end
    end
    return ALL & ~used
end

## The cells that hold a digit another cell of one of their units holds too: 1 for such a cell, 0 for the others.
func boardConflicts(g)
    var marks = boardNew()
    for unit in board.units do
        var first = {}
        for i in unit do
            var d = g[i]
            if d <> 0 then
                if first.has(d) then
                    marks[i] = 1
                    marks[first[d]] = 1
                else
                    first[d] = i
                end
            end
        end
    end
    return marks
end

func boardHasConflict(g)
    var marks = boardConflicts(g)
    for i = 1, CELLS do
        if marks[i] <> 0 then
            return true
        end
    end
    return false
end

func boardFilled(g)
    var n = 0
    for i = 1, CELLS do
        if g[i] <> 0 then
            n += 1
        end
    end
    return n
end

## Every cell filled and no digit repeated in a unit.
func boardComplete(g)
    return boardFilled(g) == CELLS and not boardHasConflict(g)
end

## How many cells hold the digit d.
func boardDigitCount(g, d)
    var n = 0
    for i = 1, CELLS do
        if g[i] == d then
            n += 1
        end
    end
    return n
end

## ── Notes: a mask per cell of the digits the player has pencilled in ─────────────────────────────

func notesNew()
    return boardNew()
end

func notesToggle(notes, i, d)
    notes[i] = notes[i] ~ (1 << d)
end

## A digit placed in cell i leaves the notes of its peers.
func notesClean(notes, i, d)
    var bit = 1 << d
    for p in board.peers[i] do
        notes[p] = notes[p] & ~bit
    end
end

## ── Saved text ──────────────────────────────────────────────────────────────────────────────────

func boardEncode(g)
    return g.join()
end

## The grid a text of 81 digits stands for, or nil when the text is not one.
func boardDecode(text)
    if typeof(text) <> "string" or len(text) <> CELLS then
        return nil
    end
    var g = []
    for i = 1, CELLS do
        var d = text.char(i).number()
        if d == nil or d < 0 or d > N then
            return nil
        end
        g.push(d)
    end
    return g
end

## The game in progress, as one text: the clues, the grid, the notes, the hints left, the level, the day (a map with
## year, month and day, or nil for a puzzle of no particular day).
func gameEncode(puzzle, grid, notes, hints, level, daily)
    var day = "-"
    if daily <> nil then
        day = "{daily.year},{daily.month},{daily.day}"
    end
    return "{boardEncode(puzzle)}|{boardEncode(grid)}|{notes.join(",")}|{hints}|{level}|{day}"
end

## What a saved text stands for: {puzzle, grid, notes, hints, level, daily}, or nil when anything in it is wrong. The
## hints and the level are held to the limits the game has; a grid must keep the clues of the puzzle.
func gameDecode(text, maxHints, maxLevel)
    if typeof(text) <> "string" then
        return nil
    end
    var parts = text.split("|")
    if len(parts) <> 6 then
        return nil
    end
    var puzzle = boardDecode(parts[1])
    var grid = boardDecode(parts[2])
    var hints = parts[4].number()
    var level = parts[5].number()
    if puzzle == nil or grid == nil or hints == nil or level == nil or hints < 0 or hints > maxHints or level < 1 or level > maxLevel then
        return nil
    end
    var noteTexts = parts[3].split(",")
    if len(noteTexts) <> CELLS then
        return nil
    end
    var notes = []
    for t in noteTexts do
        var v = t.number()
        if v == nil or v < 0 or v > ALL then
            return nil
        end
        notes.push(v)
    end
    for i = 1, CELLS do
        if puzzle[i] <> 0 and grid[i] <> puzzle[i] then
            return nil
        end
    end
    var daily = nil
    if parts[6] <> "-" then
        var d = parts[6].split(",")
        if len(d) <> 3 or d[1].number() == nil or d[2].number() == nil or d[3].number() == nil then
            return nil
        end
        daily = {year: d[1].number(), month: d[2].number(), day: d[3].number()}
    end
    return {puzzle: puzzle, grid: grid, notes: notes, hints: hints, level: level, daily: daily}
end

boardBuild()
