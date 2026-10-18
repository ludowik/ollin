## The PIECES of Blockudoku. A piece is never rotated by the player, so each orientation is a shape
## of its own. A shape is drawn as rows of text: "#" is a cell, "." is a hole in its bounding box.

global pieces = {shapes: [], tables: {}}

## How awkward a piece is to place; the draw favours the soft ones at the start of a game and the hard ones late.
const SOFT = -1
const NORMAL = 0
const HARD = 1

## A family groups the orientations of one piece, says how hard it is, and optionally gives a weight: the
## chance each of its shapes has of being drawn at the reference level. Most shapes weigh DEFAULT_WEIGHT; the
## single cell and the line of five come half as often.
const DEFAULT_WEIGHT = 2
const SHAPE_FAMILIES = [
    [[["#"]], SOFT, 1],
    [[["##"], ["#", "#"]], SOFT],
    [[["###"], ["#", "#", "#"]], SOFT],
    [[["####"], ["#", "#", "#", "#"]], NORMAL],
    [[["#####"], ["#", "#", "#", "#", "#"]], HARD, 1],
    [[["##", "##"]], SOFT],
    [[["#..", "#..", "###"], ["###", "#..", "#.."], ["###", "..#", "..#"], ["..#", "..#", "###"]], HARD],
    [[["##", "#."], ["##", ".#"], ["#.", "##"], [".#", "##"]], SOFT],
    [[["#.", "#.", "##"], ["###", "#.."], ["##", ".#", ".#"], ["..#", "###"]], NORMAL],
    [[[".#", ".#", "##"], ["#..", "###"], ["##", "#.", "#."], ["###", "..#"]], NORMAL],
    [[["###", ".#."], [".#.", "###"], ["#.", "##", "#."], [".#", "##", ".#"]], NORMAL],
    [[[".##", "##."], ["#.", "##", ".#"]], HARD],
    [[["##.", ".##"], [".#", "##", "#."]], HARD],
    [[["###", "#.#"], ["#.#", "###"], ["##", "#.", "##"], ["##", ".#", "##"]], HARD],
    [[[".#.", "###", ".#."]], HARD],
    [[["#.", ".#"], [".#", "#."]], NORMAL],
    [[["#..", ".#.", "..#"], ["..#", ".#.", "#.."]], HARD]
]

## The difficulty, by level. The level is the score divided by pointsPerLevel. Up to helpEnd the game helps (see
## deal.ol) and the soft shapes are drawn more often; helpEnd is the game as it was before levels, and from there
## to hardEnd the hard shapes become more frequent. A level past hardEnd draws like hardEnd.
const DIFFICULTY = {pointsPerLevel: 1000, helpEnd: 8, hardEnd: 13}

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
    pieces.shapes = []
    pieces.tables = {}
    for family in SHAPE_FAMILIES do
        var weight = DEFAULT_WEIGHT
        if len(family) > 2 then
            weight = family[3]
        end
        for rows in family[1] do
            var shape = parseShape(rows)
            shape.hardness = family[2]
            shape.weight = weight
            pieces.shapes.push(shape)
        end
    end
end

func levelOf(score)
    return score // DIFFICULTY.pointsPerLevel
end

## 1 at level 0, down to 0 at helpEnd: how much the game helps.
func helpAt(level)
    return math.clamp(1 - level / DIFFICULTY.helpEnd, 0, 1)
end

## 0 up to helpEnd, 1 from hardEnd: how far the hard shapes have been pushed.
func hardAt(level)
    return math.clamp((level - DIFFICULTY.helpEnd) / (DIFFICULTY.hardEnd - DIFFICULTY.helpEnd), 0, 1)
end

## What a shape weighs in the draw at this level. At helpEnd every shape weighs its own weight: the game before levels.
func shapeWeight(shape, level)
    var help = helpAt(level)
    var hard = hardAt(level)
    if shape.hardness == SOFT then
        return shape.weight * (1 + 2 * help - 0.5 * hard)
    elseif shape.hardness == HARD then
        return shape.weight * (1 - 0.6 * help + 1.5 * hard)
    end
    return shape.weight
end

## The weights of every shape at a level, and their sum, worked out once per level.
func weightTable(level)
    var key = "{math.min(level, DIFFICULTY.hardEnd)}"
    if not pieces.tables.has(key) then
        var weights = []
        var total = 0
        for s in pieces.shapes do
            var w = shapeWeight(s, level)
            weights.push(w)
            total += w
        end
        pieces.tables[key] = {weights: weights, total: total}
    end
    return pieces.tables[key]
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
    for s in pieces.shapes do
        if x > 0 and x + s.w * u > areaW then
            closeRow(items, first, x, areaW, rowH, u)
            y += rowH + u
            x = 0
            rowH = 0
            first = len(items) + 1
        end
        items.push({shape: s, x: x, y: y})
        x += (s.w + 1) * u
        rowH = math.max(rowH, s.h * u)
    end
    closeRow(items, first, x, areaW, rowH, u)
    return items, y + rowH
end

## Centres a finished row, whose cursor stopped at x (one cell of air past its last piece): sideways in areaW,
## and each piece down to the middle of the row's height.
func closeRow(items, first, x, areaW, rowH, u)
    var dx = (areaW - (x - u)) / 2
    for i = first, len(items) do
        var item = items[i]
        item.x += dx
        item.y += (rowH - item.shape.h * u) / 2
    end
end

func shapeFromKey(key)
    for s in pieces.shapes do
        if s.key == key then
            return s
        end
    end
    return nil
end

## A shape drawn at random, by the weights of the level (helpEnd when none is given).
func randomShape(level)
    if level == nil then
        level = DIFFICULTY.helpEnd
    end
    var table = weightTable(level)
    var pick = math.rand() * table.total
    for i, s in pieces.shapes do
        pick -= table.weights[i]
        if pick < 0 then
            return s
        end
    end
    return pieces.shapes[len(pieces.shapes)]
end
