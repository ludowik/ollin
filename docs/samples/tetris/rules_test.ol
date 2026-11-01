## The rules of Tetris (docs/samples/tetris/rules.ol): the shapes and how they turn, the walls, the lines, the score,
## the speed and the draw of the next piece.

import "rules.ol"

## A position as text, trimmed to the cells it holds: "XXX/.X." for the T as it appears.
func shapeText(kind, turn)
    var cells = shapes[kind][turn]
    var x0, x1, y0, y1 = shapeBounds(kind, turn)
    var rows = []
    for y = y0, y1 do
        var line = ""
        for x = x0, x1 do
            var on = false
            for c in cells do
                if c[1] == x and c[2] == y then
                    on = true
                end
            end
            line = line + (on and "X" or ".")
        end
        rows.push(line)
    end
    return rows.join("/")
end

## The seven pieces and every position they take, as the original draws them (the Nintendo rotation).
var expected = {
    [Piece.I]: ["XXXX", "X/X/X/X"],
    [Piece.O]: ["XX/XX"],
    [Piece.T]: ["XXX/.X.", ".X/XX/.X", ".X./XXX", "X./XX/X."],
    [Piece.S]: [".XX/XX.", "X./XX/.X"],
    [Piece.Z]: ["XX./.XX", ".X/XX/X."],
    [Piece.J]: ["XXX/..X", ".X/.X/XX", "X../XXX", "XX/X./X."],
    [Piece.L]: ["XXX/X..", "XX/.X/.X", "..X/XXX", "X./X./XX"]
}
for kind = 1, KINDS do
    assert(len(shapes[kind]) == len(expected[kind]), "piece {kind} has {len(shapes[kind])} positions")
    for turn, text in expected[kind] do
        assert(shapeText(kind, turn) == text, "piece {kind}, position {turn}: {shapeText(kind, turn)}, wanted {text}")
        assert(len(shapes[kind][turn]) == 4)
    end
end

## A turn goes round: four clockwise turns bring a piece back, a counter-clockwise turn undoes a clockwise one, and
## the pieces with two positions swing between them.
for kind = 1, KINDS do
    var turn = 1
    for i = 1, 4 do
        turn = turnedBy(kind, turn, 1)
    end
    assert(turn == 1, "four turns of piece {kind}")
    assert(turnedBy(kind, turnedBy(kind, 1, 1), -1) == 1)
    assert(turnedBy(kind, turnedBy(kind, 1, -1), 1) == 1)
end
assert(turnedBy(Piece.S, 1, 1) == 2 and turnedBy(Piece.S, 2, 1) == 1 and turnedBy(Piece.S, 1, -1) == 2)
assert(turnedBy(Piece.O, 1, 1) == 1 and turnedBy(Piece.O, 1, -1) == 1)
assert(turnedBy(Piece.T, 1, 1) == 2 and turnedBy(Piece.T, 1, -1) == 4)

## Every piece appears on the top row, in the middle, and fits in an empty well.
var well = newWell()
assert(len(well) == COLS * ROWS)
for kind = 1, KINDS do
    var firstColumn, lastColumn, firstRow = shapeBounds(kind, 1)
    var top = SPAWN_Y + firstRow
    assert(top == 0, "piece {kind} appears on row {top}")
    assert(fits(well, kind, 1, SPAWN_X, SPAWN_Y))
end

## The walls, the floor and the filled cells stop a piece; the space above the well does not.
assert(not fits(well, Piece.O, 1, -2, 5), "the left wall")
assert(fits(well, Piece.O, 1, -1, 5))
assert(not fits(well, Piece.O, 1, COLS - 2, 5), "the right wall")
assert(fits(well, Piece.O, 1, COLS - 3, 5))
assert(fits(well, Piece.O, 1, 3, ROWS - 3) and not fits(well, Piece.O, 1, 3, ROWS - 2), "the floor")
assert(fits(well, Piece.I, 2, 3, -3), "a vertical bar may stand half above the well")
well[wellIdx(5, 5)] = Piece.T
assert(not fits(well, Piece.O, 1, 3, 4) and fits(well, Piece.O, 1, 3, 2), "a filled cell")
well[wellIdx(5, 5)] = 0

## A piece locks into the well, and the lowest row it touches comes back.
var lowest = lockPiece(well, Piece.L, 1, 3, ROWS - 3)
assert(lowest == ROWS - 1)
assert(well[wellIdx(3, ROWS - 2)] == Piece.L and well[wellIdx(5, ROWS - 2)] == Piece.L and well[wellIdx(3, ROWS - 1)] == Piece.L)
assert(well[wellIdx(4, ROWS - 1)] == 0)

## Lines: a row is full when no cell is empty, and clearing rows lets what is above fall.
well = newWell()
assert(len(fullRows(well)) == 0)
for c = 0, COLS - 1 do
    well[wellIdx(c, ROWS - 1)] = Piece.I
    well[wellIdx(c, ROWS - 3)] = Piece.O
end
well[wellIdx(3, ROWS - 2)] = Piece.T
well[wellIdx(0, ROWS - 4)] = Piece.S
var rows = fullRows(well)
assert(len(rows) == 2 and rows[1] == ROWS - 3 and rows[2] == ROWS - 1)
collapse(well, rows)
assert(len(fullRows(well)) == 0)
assert(well[wellIdx(3, ROWS - 1)] == Piece.T and well[wellIdx(0, ROWS - 2)] == Piece.S, "what was above falls by the rows below it")
assert(len(well.filter(func(v)
    return v <> 0
end)) == 2, "only the two loose cells are left")

## Four rows at once, at the top and at the bottom of the well.
well = newWell()
for r = 0, 3 do
    for c = 0, COLS - 1 do
        well[wellIdx(c, r)] = Piece.Z
    end
end
collapse(well, fullRows(well))
assert(len(fullRows(well)) == 0 and well[wellIdx(0, 0)] == 0 and well[wellIdx(0, 3)] == 0)

## The score: 40, 100, 300 and 1200 times one more than the level.
assert(lineScore(1, 0) == 40 and lineScore(2, 0) == 100 and lineScore(3, 0) == 300 and lineScore(4, 0) == 1200)
assert(lineScore(4, 9) == 12000 and lineScore(2, 3) == 400)

## The speed: every level is faster than the last up to 20, and then it stays.
assert(fallFrames(0) == 53 and fallFrames(9) == 11 and fallFrames(20) == 3 and fallFrames(99) == 3)
for level = 1, 20 do
    assert(fallFrames(level) <= fallFrames(level - 1))
end

## The level: an A game goes up with every ten lines from its own level, a B game does not move.
assert(levelFor(0, 0, "A") == 0 and levelFor(0, 9, "A") == 0 and levelFor(0, 10, "A") == 1 and levelFor(0, 95, "A") == 9)
assert(levelFor(5, 0, "A") == 5 and levelFor(5, 9, "A") == 5 and levelFor(5, 10, "A") == 6, "an A game climbs from its own level")
assert(levelFor(5, 24, "B") == 5, "a B game stays at its own level")

## The start of a B game: two rows of rubble for each step of height, none of them full.
for height = 0, 5 do
    var rubble = newWell()
    addGarbage(rubble, height)
    assert(len(fullRows(rubble)) == 0, "no row is full at height {height}")
    var cells = len(rubble.filter(func(v)
        return v <> 0
    end))
    for r = 0, ROWS - height * 2 - 1 do
        for c = 0, COLS - 1 do
            assert(rubble[wellIdx(c, r)] == 0, "nothing above the rubble")
        end
    end
    assert(cells <= height * 2 * (COLS - 1), "a hole is left in every row")
    assert(height == 0 and cells == 0 or height > 0 and cells > 0, "the rubble is there from height 1")
end

## The wait before the next piece grows as the last one rests higher.
assert(entryDelay(ROWS - 1) == 10 and entryDelay(0) == 18)
assert(entryDelay(ROWS - 1) <= entryDelay(ROWS - 6) and entryDelay(ROWS - 6) <= entryDelay(3))

## The draw: all seven pieces come, and a repeat is rare (the draw is made a second time on a repeat).
math.seed(7)
var seen = {}
var repeats = 0
var prev = 0
var draws = 6000
for i = 1, draws do
    var k = nextKind(prev)
    assert(k >= 1 and k <= KINDS)
    seen[k] = (seen[k] or 0) + 1
    if k == prev then
        repeats += 1
    end
    prev = k
end
assert(len(seen) == KINDS, "every piece is drawn")
for kind = 1, KINDS do
    assert(seen[kind] > draws / KINDS * 0.7 and seen[kind] < draws / KINDS * 1.3, "piece {kind} came {seen[kind]} times")
end
assert(repeats < draws * 0.05, "{repeats} repeats in {draws} draws")
print("tetris rules ok")
