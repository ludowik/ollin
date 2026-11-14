## Tests of geometry.ol: cells, spirals and the drawing built from them.

import "geometry.ol"

func near(a, b)
    return math.abs(a - b) < 1e-6
end

var square = [[0, 0], [10, 0], [10, 10], [0, 10]]
assert(near(polygonArea(square), 100))

var half = clipHalfPlane(square, 1, 0, 4)
assert(near(polygonArea(half), 40))
assert(#clipHalfPlane(square, 1, 0, -1) == 0)
assert(near(polygonArea(clipHalfPlane(square, 1, 0, 20)), 100))

assert(#withoutRepeats([[0, 0], [0, 0], [5, 0], [5, 5]]) == 3)

## Two seeds share the box along the line halfway between them.
var box = [0, 0, 10, 10]
assert(near(polygonArea(cellOf(2, 5, [[8, 5]], box)), 50))
assert(near(polygonArea(cellOf(2, 5, [], box)), 100))

## The cells of a scatter of seeds cover the box exactly.
var seeds = [[1, 2], [7, 1], [4, 6], [9, 8], [2, 9], [6, 4]]
var covered = 0
for i = 1, #seeds do
    var others = []
    for j = 1, #seeds do
        if j <> i then
            others.push(seeds[j])
        end
    end
    covered += polygonArea(cellOf(seeds[i][1], seeds[i][2], others, box))
end
assert(near(covered, 100))

## A spiral lies inside its polygon and runs from one line to the next at right angles on a rectangle.
var rect = [[0, 0], [100, 0], [100, 80], [0, 80]]
var spiral = spiralOf(rect, 8, 1)
assert(#spiral > 10)
for p in spiral do
    assert(p[1] >= 0 and p[1] <= 100 and p[2] >= 0 and p[2] <= 80)
end
for i = 1, #spiral - 1 do
    var a = spiral[i]
    var b = spiral[i + 1]
    assert(near(a[1], b[1]) or near(a[2], b[2]))
end
## One turn further in is one spacing further in: the first line and the one a whole turn later.
assert(near(spiral[2][2] - spiral[1][2], 0) and near(spiral[6][2] - spiral[2][2], 8))

## A mirrored spiral is the same spiral turning the other way.
var turned = spiralOfMirrored(rect, 8, 1)
assert(#turned > 10)
for p in turned do
    assert(p[1] >= 0 and p[1] <= 100 and p[2] >= 0 and p[2] <= 80)
end
assert(near(turned[1][1], turned[2][1]) or near(turned[1][2], turned[2][2]))
assert(not near(turned[2][1], spiral[2][1]) or not near(turned[2][2], spiral[2][2]))

## Irregular polygons still give a spiral, and a sliver gives one that ends.
var pentagon = [[0, 0], [100, 10], [70, 90], [20, 60], [5, 30]]
assert(#spiralOf(pentagon, 8, 3) > 8)
assert(#spiralOf([[0, 0], [100, 0], [100, 3], [0, 3]], 8, 1) < 4)
assert(#spiralOf([[0, 0], [1, 0]], 8, 1) == 0)

## A point on a straight side is not a corner: a spiral asked to start there starts at the next real one.
var collinear = [[0, 0], [50, 0], [100, 0], [100, 80], [0, 80]]
for first = 1, 5 do
    var line = spiralOf(collinear, 8, first)
    assert(#line > 10)
    for p in line do
        assert(p[1] >= 0 and p[1] <= 100 and p[2] >= 0 and p[2] <= 80)
    end
end
assert(#spiralOf([[0, 0], [50, 0], [100, 0]], 8, 1) == 0)

## A drawing covers the area with segments whose end lengths only grow.
var art = drawing(200, 300, 50, 4)
assert(#art.segments > 100)
assert(#art.segments == #art.ends)
for i = 2, #art.ends do
    assert(art.ends[i] > art.ends[i - 1])
end
