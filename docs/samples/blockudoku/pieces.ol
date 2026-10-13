## The PIECES of Blockudoku. A piece is never rotated by the player, so each orientation is a shape
## of its own. A shape is drawn as rows of text: "#" is a cell, "." is a hole in its bounding box.

global shapes = []

## Each family has one colour, which the host maps to its palette.
const SHAPE_FAMILIES = [
    [1, [["#"]]],
    [2, [["##"], ["#", "#"]]],
    [3, [["###"], ["#", "#", "#"]]],
    [4, [["####"], ["#", "#", "#", "#"]]],
    [5, [["#####"], ["#", "#", "#", "#", "#"]]],
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
    for family in SHAPE_FAMILIES do
        for rows in family[2] do
            shapes.push(parseShape(rows, family[1]))
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
    return shapes[math.randInt(1, len(shapes))]
end
