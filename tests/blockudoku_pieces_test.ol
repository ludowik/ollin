## The shapes of the Blockudoku sample: the bounding box (w, h) is what centres a piece in its tray and
## under the finger, so it must be the real one — a row written without its trailing "." made the
## box one column too narrow and the piece sat half a cell off. Also the rules of the board and the sound switch.

import "../docs/samples/blockudoku/board.ol"
import "../docs/samples/blockudoku/pieces.ol"
import "../docs/samples/blockudoku/sounds.ol"

buildShapes()

var keys = {}
var footprints = {}
for s in pieces.shapes do
    var maxRow = 0
    var maxCol = 0
    var cellNames = []
    for off in s.cells do
        maxRow = math.max(maxRow, off[1] + 1)
        maxCol = math.max(maxCol, off[2] + 1)
        cellNames.push("{off[1]}.{off[2]}")
    end
    assert(s.w == maxCol and s.h == maxRow, "box of {s.key}: {s.w}x{s.h}, cells span {maxCol}x{maxRow}")
    assert(not keys[s.key], "two shapes share the key {s.key}")
    keys[s.key] = true
    var footprint = cellNames.join(",")
    assert(not footprints[footprint], "{s.key} has the same cells as another shape")
    footprints[footprint] = true
    assert(shapeFromKey(s.key) == s, "shapeFromKey does not find {s.key}")
end
assert(len(pieces.shapes) == 43, "expected 43 shapes, got {len(pieces.shapes)}")
assert(shapeFromKey("nope") == nil)

## The weights are those of the reference game: 83 draws, the single cell and the line of five at 1.
var total = 0
var light = []
for s in pieces.shapes do
    total += s.weight
    if s.weight == 1 then
        light.push(s.key)
    else
        assert(s.weight == 2, "{s.key} weighs {s.weight}")
    end
    assert(shapeWeight(s, DIFFICULTY.helpEnd) == s.weight, "{s.key} must weigh its own weight at the reference level")
end
assert(total == 83, "the weights add up to {total}, expected 83")
assert(len(light) == 3 and light.contains("#") and light.contains("#####") and light.contains("#/#/#/#/#"), "the weight-1 shapes are wrong")

## randomShape follows the weights: over many draws the light shapes come about half as often as a heavy one.
var drawn = {}
for i = 1, 8300 do
    var k = randomShape(DIFFICULTY.helpEnd).key
    drawn[k] = (drawn[k] or 0) + 1
end
assert(drawn["#"] > 0 and drawn["##"] > drawn["#"], "the single cell must be rarer than the domino")
## The catalogue layout: every shape appears once, inside the area, and no two boxes touch.
for u in [6, 20, 37] do
    var areaW = 5 * u + 3 * u
    var items, used = packShapes(u, areaW)
    assert(len(items) == len(pieces.shapes), "u={u}: {len(items)} pieces laid out")
    for i, a in items do
        assert(a.x >= -0.001 and a.x + a.shape.w * u <= areaW + 0.001, "u={u}: {a.shape.key} leaves the area")
        assert(a.y >= -0.001 and a.y + a.shape.h * u <= used + 0.001, "u={u}: {a.shape.key} leaves the height")
        for j = i + 1, len(items) do
            var b = items[j]
            var apart = a.x + a.shape.w * u <= b.x or b.x + b.shape.w * u <= a.x or a.y + a.shape.h * u <= b.y or b.y + b.shape.h * u <= a.y
            assert(apart, "u={u}: {a.shape.key} overlaps {b.shape.key}")
        end
    end
end
## A piece "fits nowhere" when boardAnyMove says so: the game greys such a piece out, and ends when the whole hand is
## in that state. Only the single cell fits a grid with one hole; a vertical domino fits once the hole has a
## free neighbour; nothing fits a full grid.
var g = boardNew()
for s in pieces.shapes do
    assert(boardAnyMove(g, s), "{s.key} must fit on an empty grid")
end
for i = 1, CELLS do
    g[i] = 1
end
g[boardIdx(5, 5)] = 0
for s in pieces.shapes do
    assert(boardAnyMove(g, s) == (s.key == "#"), "{s.key} on a grid with one hole: {boardAnyMove(g, s)}")
end
g[boardIdx(6, 5)] = 0
assert(boardAnyMove(g, shapeFromKey("#/#")) and boardAnyMove(g, shapeFromKey("#")), "a domino fits two stacked holes")
assert(not boardAnyMove(g, shapeFromKey("##")), "a horizontal domino does not fit two stacked holes")
## boardFull finds every full zone at once and lists a shared cell once; boardPreview shows what a placement would clear
## without touching the grid.
var f = boardNew()
var none, nzones = boardFull(f)
assert(len(none) == 0 and nzones == 0, "an empty grid has no full zone")
for c = 1, 8 do
    f[boardIdx(1, c)] = 1
end
none, nzones = boardFull(f)
assert(nzones == 0, "a row missing one cell is not full")
f[boardIdx(1, 9)] = 1
var row, rzones = boardFull(f)
assert(len(row) == 9 and rzones == 1, "a full row clears nine cells: {len(row)} in {rzones}")
for r = 2, 9 do
    f[boardIdx(r, 1)] = 1
end
var cross, czones = boardFull(f)
assert(len(cross) == 17 and czones == 2, "a row and a column share their corner: {len(cross)} in {czones}")
var box = boardNew()
for r = 1, 3 do
    for c = 1, 3 do
        box[boardIdx(r, c)] = 1
    end
end
var boxed, bzones = boardFull(box)
assert(len(boxed) == 9 and bzones == 1, "a full 3x3 box clears nine cells: {len(boxed)} in {bzones}")
var before = boardNew()
for c = 2, 9 do
    before[boardIdx(5, c)] = 1
end
var preview = boardPreview(before, shapeFromKey("#"), 5, 1)
assert(len(preview) == 9, "placing the last cell of a row would clear it: {len(preview)}")
assert(before[boardIdx(5, 1)] == 0, "the preview must leave the grid as it was")
assert(sounds.on and audio.volume() == 1, "the sound starts on")
setSound(false)
assert(not sounds.on and audio.volume() == 0, "switching the sound off mutes the master volume")
setSound(true)
assert(sounds.on and audio.volume() == 1, "switching the sound back on restores it")
print("blockudoku pieces ok")
