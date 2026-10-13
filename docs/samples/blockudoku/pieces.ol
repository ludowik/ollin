## The PIECES of Blockudoku. A piece is never rotated by the player, so each orientation is a shape
## of its own. A shape is drawn as rows of text: "#" is a cell, "." is a hole in its bounding box.

global shapes = []
global bag = []

## Each family has one colour, which the host maps to its palette, and optionally a weight: how many
## times each of its shapes sits in the bag a hand is drawn from. Most shapes weigh DEFAULT_WEIGHT; the
## single cell and the line of five come half as often.
const DEFAULT_WEIGHT = 2
const SHAPE_FAMILIES = [
    [1, [["#"]], 1],
    [2, [["##"], ["#", "#"]]],
    [3, [["###"], ["#", "#", "#"]]],
    [4, [["####"], ["#", "#", "#", "#"]]],
    [5, [["#####"], ["#", "#", "#", "#", "#"]], 1],
    [6, [["##", "##"]]],
    [7, [["#..", "#..", "###"], ["###", "#..", "#.."], ["###", "..#", "..#"], ["..#", "..#", "###"]]],
    [8, [["##", "#."], ["##", ".#"], ["#.", "##"], [".#", "##"]]],
    [2, [["#.", "#.", "##"], ["###", "#.."], ["##", ".#", ".#"], ["..#", "###"]]],
    [3, [[".#", ".#", "##"], ["#..", "###"], ["##", "#.", "#."], ["###", "..#"]]],
    [4, [["###", ".#."], [".#.", "###"], ["#.", "##", "#."], [".#", "##", ".#"]]],
    [5, [[".##", "##."], ["#.", "##", ".#"]]],
    [1, [["##.", ".##"], [".#", "##", "#."]]],
    [6, [["###", "#.#"], ["#.#", "###"], ["##", "#.", "##"], ["##", ".#", "##"]]],
    [3, [[".#.", "###", ".#."]]],
    [8, [["#.", ".#"], [".#", "#."]]],
    [4, [["#..", ".#.", "..#"], ["..#", ".#.", "#.."]]]
]

func parseShape(rows, color)
    var cells = []
    for r, row in rows do
        for c = 1, len(row) do
            if row.char(c) == "#" then
                cells.push([r - 1, c - 1])
            end
        end
    end
    ## key: the rows of the shape ("#./##"), which names it in a saved game without depending on the order of this list.
    return {cells: cells, h: len(rows), w: len(rows[1]), color: color, n: len(cells), key: rows.join("/")}
end

func buildShapes()
    shapes = []
    bag = []
    for family in SHAPE_FAMILIES do
        var weight = DEFAULT_WEIGHT
        if len(family) > 2 then
            weight = family[3]
        end
        for rows in family[2] do
            var shape = parseShape(rows, family[1])
            shapes.push(shape)
            for i = 1, weight do
                bag.push(shape)
            end
        end
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
