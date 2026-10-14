## The RULES of Blockudoku, with no drawing. The grid is a flat array of 81 numbers: 0 for an empty
## cell, 1 for a filled one. Rows and columns are 1-based.
##
## Imported by blockudoku.ol, which reads GRID from here — a const declared by a module is visible
## to the functions of the file that imports it.

const GRID = 9
const BOX = 3
const CELLS = GRID * GRID

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

## What placing the shape at (r, c) WOULD clear, on a copy: the grid is left as it is.
func boardPreview(g, shape, r, c)
    var copy = boardNew()
    for i = 1, CELLS do
        copy[i] = g[i]
    end
    boardPlace(copy, shape, r, c, 1)
    var cleared = boardFull(copy)
    return cleared
end

boardBuildZones()
