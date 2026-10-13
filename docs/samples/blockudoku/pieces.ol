## The PIECES of Blockudoku. A piece is never rotated by the player, so each orientation is a shape
## of its own. A shape is drawn as rows of text: "#" is a cell, "." is a hole in its bounding box.

global shapes = []
global bag = []

## A family groups the orientations of one piece and optionally gives a weight: how many
## times each of its shapes sits in the bag a hand is drawn from. Most shapes weigh DEFAULT_WEIGHT; the
## single cell and the line of five come half as often.
const DEFAULT_WEIGHT = 2
const SHAPE_FAMILIES = [
    [[["#"]], 1],
    [[["##"], ["#", "#"]]],
    [[["###"], ["#", "#", "#"]]],
    [[["####"], ["#", "#", "#", "#"]]],
    [[["#####"], ["#", "#", "#", "#", "#"]], 1],
    [[["##", "##"]]],
    [[["#..", "#..", "###"], ["###", "#..", "#.."], ["###", "..#", "..#"], ["..#", "..#", "###"]]],
    [[["##", "#."], ["##", ".#"], ["#.", "##"], [".#", "##"]]],
    [[["#.", "#.", "##"], ["###", "#.."], ["##", ".#", ".#"], ["..#", "###"]]],
    [[[".#", ".#", "##"], ["#..", "###"], ["##", "#.", "#."], ["###", "..#"]]],
    [[["###", ".#."], [".#.", "###"], ["#.", "##", "#."], [".#", "##", ".#"]]],
    [[[".##", "##."], ["#.", "##", ".#"]]],
    [[["##.", ".##"], [".#", "##", "#."]]],
    [[["###", "#.#"], ["#.#", "###"], ["##", "#.", "##"], ["##", ".#", "##"]]],
    [[[".#.", "###", ".#."]]],
    [[["#.", ".#"], [".#", "#."]]],
    [[["#..", ".#.", "..#"], ["..#", ".#.", "#.."]]]
]

func parseShape(rows)
    var cells = []
    for r, row in rows do
        for c = 1, len(row) do
            if row.char(c) == "#" then
                cells.push([r - 1, c - 1])
            end
        end
    end
    ## key: the rows of the shape ("#./##"), which names it in a saved game without depending on the order of this list.
    return {cells: cells, h: len(rows), w: len(rows[1]), n: len(cells), key: rows.join("/")}
end

func buildShapes()
    shapes = []
    bag = []
    for family in SHAPE_FAMILIES do
        var weight = DEFAULT_WEIGHT
        if len(family) > 1 then
            weight = family[2]
        end
        for rows in family[1] do
            var shape = parseShape(rows)
            shapes.push(shape)
            for i = 1, weight do
                bag.push(shape)
            end
        end
    end
end

## Lays every shape out in rows, for a catalogue: a piece takes its bounding box at cell size u, one cell of air
## separates two pieces and two rows, and each row is centred in areaW. Gives {shape, x, y} per piece (the
## top-left of its box, measured from the top-left of the area) and the height used.
func packShapes(u, areaW)
    var items = []
    var x = 0
    var y = 0
    var rowH = 0
    var first = 1
    for s in shapes do
        if x > 0 and x + s.w * u > areaW then
            closeRow(items, first, (areaW - (x - u)) / 2, rowH, u)
            y += rowH + u
            x = 0
            rowH = 0
            first = len(items) + 1
        end
        items.push({shape: s, x: x, y: y})
        x += (s.w + 1) * u
        rowH = math.max(rowH, s.h * u)
    end
    closeRow(items, first, (areaW - (x - u)) / 2, rowH, u)
    return items, y + rowH
end

## Centres a finished row: shifts it sideways by dx and each piece down to the middle of the row's height.
func closeRow(items, first, dx, rowH, u)
    for i = first, len(items) do
        var item = items[i]
        item.x += dx
        item.y += (rowH - item.shape.h * u) / 2
    end
end

func shapeFromKey(key)
    for s in shapes do
        if s.key == key then
            return s
        end
    end
    return nil
end

func randomShape()
    return bag[math.randInt(1, len(bag))]
end
