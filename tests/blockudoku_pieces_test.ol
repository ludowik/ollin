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
assert(len(shapes) == 38, "expected 38 orientations, got {len(shapes)}")
assert(shapeFromKey("nope") == nil)
print("blockudoku pieces ok")
