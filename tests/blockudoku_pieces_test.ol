## The shapes of the Blockudoku sample: the bounding box (w, h) is what centres a piece in its tray and
## under the finger, so it must be the real one — a row written without its trailing "." made the
## box one column too narrow and the piece sat half a cell off.

import "../docs/samples/blockudoku/pieces.ol"

buildShapes()

var keys = {}
var footprints = {}
for s in shapes do
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
assert(len(shapes) == 43, "expected 43 shapes, got {len(shapes)}")
assert(shapeFromKey("nope") == nil)

## The weights are those of the reference game: 83 draws, the single cell and the line of five at 1.
assert(len(bag) == 83, "the bag holds {len(bag)} entries, expected 83")
var counts = {}
for s in bag do
    counts[s.key] = (counts[s.key] or 0) + 1
end
var light = []
for s in shapes do
    if counts[s.key] == 1 then
        light.push(s.key)
    else
        assert(counts[s.key] == 2, "{s.key} weighs {counts[s.key]}")
    end
end
assert(len(light) == 3 and light.contains("#") and light.contains("#####") and light.contains("#/#/#/#/#"), "the weight-1 shapes are wrong")

## randomShape follows the bag: over many draws the light shapes come about half as often as a heavy one.
var drawn = {}
for i = 1, 8300 do
    var k = randomShape().key
    drawn[k] = (drawn[k] or 0) + 1
end
assert(drawn["#"] > 0 and drawn["##"] > drawn["#"], "the single cell must be rarer than the domino")
## The catalogue layout: every shape appears once, inside the area, and no two boxes touch.
for u in [6, 20, 37] do
    var areaW = 5 * u + 3 * u
    var items, used = packShapes(u, areaW)
    assert(len(items) == len(shapes), "u={u}: {len(items)} pieces laid out")
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
print("blockudoku pieces ok")
