## The RULES of Blockudoku, with no drawing. The grid is a flat array of 81 numbers: 0 for an empty
## cell, 1 for a filled one. Rows and columns are 1-based.
##
## Imported by blockudoku.ol, which reads GRID from here — a const declared by a module is visible
## to the functions of the file that imports it.

const GRID = 9
const BOX = 3
const CELLS = GRID * GRID
const HAND = 3                  ## the pieces on offer at once
const PLAY_BUDGET = 120         ## placements boardPlayAll tries before saying no

## The 27 zones that clear when full: nine rows, nine columns, nine boxes, each a list of 9 indices.
global board = {zones: []}

func boardIdx(r, c)
    return (r - 1) * GRID + c
end

func boardRow(i)
    return (i - 1) // GRID + 1
end

func boardCol(i)
    return (i - 1) % GRID + 1
end

func boardInside(r, c)
    return r >= 1 and r <= GRID and c >= 1 and c <= GRID
end

func boardNew()
    var g = []
    for i = 1, CELLS do
        g[i] = 0
    end
    return g
end

func boardBuildZones()
    board.zones = []
    for r = 1, GRID do
        var z = []
        for c = 1, GRID do
            z.push(boardIdx(r, c))
        end
        board.zones.push(z)
    end
    for c = 1, GRID do
        var z = []
        for r = 1, GRID do
            z.push(boardIdx(r, c))
        end
        board.zones.push(z)
    end
    for br = 0, BOX - 1 do
        for bc = 0, BOX - 1 do
            var z = []
            for r = 1, BOX do
                for c = 1, BOX do
                    z.push(boardIdx(br * BOX + r, bc * BOX + c))
                end
            end
            board.zones.push(z)
        end
    end
end

## The shape is anchored by its top-left cell at (r, c).
func boardCanPlace(g, shape, r, c)
    for off in shape.cells do
        var rr = r + off[1]
        var cc = c + off[2]
        if not boardInside(rr, cc) then
            return false
        end
        if g[boardIdx(rr, cc)] <> 0 then
            return false
        end
    end
    return true
end

func boardAnyMove(g, shape)
    for r = 1, GRID do
        for c = 1, GRID do
            if boardCanPlace(g, shape, r, c) then
                return true
            end
        end
    end
    return false
end

func boardPlace(g, shape, r, c)
    for off in shape.cells do
        g[boardIdx(r + off[1], c + off[2])] = 1
    end
end

## Every zone that is full RIGHT NOW, all found before any is cleared: a cell shared by a row and a
## box is listed once. Gives the cells to clear and how many zones they come from.
func boardFull(g)
    var mark = boardNew()
    var cleared = []
    var zones = 0
    for z in board.zones do
        var full = true
        for i in z do
            if g[i] == 0 then
                full = false
                break
            end
        end
        if full then
            zones += 1
            for i in z do
                if mark[i] == 0 then
                    mark[i] = 1
                    cleared.push(i)
                end
            end
        end
    end
    return cleared, zones
end

func boardClear(g, cleared)
    for i in cleared do
        g[i] = 0
    end
end

func boardCopy(g)
    var copy = boardNew()
    for i = 1, CELLS do
        copy[i] = g[i]
    end
    return copy
end

## What placing the shape at (r, c) WOULD clear, on a copy: the grid is left as it is.
func boardPreview(g, shape, r, c)
    var copy = boardCopy(g)
    boardPlace(copy, shape, r, c)
    var cleared = boardFull(copy)
    return cleared
end

## How many cells are filled.
func boardFilled(g)
    var n = 0
    for i = 1, CELLS do
        n += g[i]
    end
    return n
end

## Whether the shape can be placed so that it fills every empty cell of `gap` (the empty cells of one zone),
## and so clears that zone. It is anchored on the first cell of the gap, one of its own cells at a time.
func boardFillsGap(g, shape, gap)
    var r0 = boardRow(gap[1])
    var c0 = boardCol(gap[1])
    for anchor in shape.cells do
        var r = r0 - anchor[1]
        var c = c0 - anchor[2]
        if boardCanPlace(g, shape, r, c) then
            var covered = 0
            for off in shape.cells do
                if gap.contains(boardIdx(r + off[1], c + off[2])) then
                    covered += 1
                end
            end
            if covered == len(gap) then
                return true
            end
        end
    end
    return false
end

## The shapes, among `shapes`, that would clear a zone if placed well on this grid. Only a zone with few enough
## empty cells for a shape to fill is looked at, so the search stays short.
func boardCompleting(g, shapes)
    var most = 0
    for s in shapes do
        most = math.max(most, s.n)
    end
    var gaps = []
    for z in board.zones do
        var gap = []
        for i in z do
            if g[i] == 0 then
                gap.push(i)
            end
        end
        if len(gap) > 0 and len(gap) <= most then
            gaps.push(gap)
        end
    end
    var out = []
    for s in shapes do
        for gap in gaps do
            if len(gap) <= s.n and boardFillsGap(g, s, gap) then
                out.push(s)
                break
            end
        end
    end
    return out
end

## Whether every shape of the hand can be placed, one after the other in some order. A line cleared on the way
## is not counted, which asks a little more than the game does; the search stops after PLAY_BUDGET placements
## tried and then says no, which only makes the caller draw another hand.
func boardPlayAll(g, shapes)
    for s in shapes do
        if not boardAnyMove(g, s) then
            return false
        end
    end
    return boardPlaysFrom(g, shapes, {tries: PLAY_BUDGET})
end

func boardPlaysFrom(g, left, budget)
    if len(left) == 0 then
        return true
    end
    for k, s in left do
        var rest = []
        for j, other in left do
            if j <> k then
                rest.push(other)
            end
        end
        for r = 1, GRID do
            for c = 1, GRID do
                if boardCanPlace(g, s, r, c) then
                    budget.tries -= 1
                    if budget.tries < 0 then
                        return false
                    end
                    var after = boardCopy(g)
                    boardPlace(after, s, r, c)
                    if boardPlaysFrom(after, rest, budget) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

boardBuildZones()
