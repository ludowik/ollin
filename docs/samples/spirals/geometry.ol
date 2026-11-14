## The geometry of the drawing: a scatter of seeds cuts the paper into cells (the part of the paper nearer to a seed than to
## any other), and each cell is filled with an angular spiral of evenly spaced lines. A polygon is an array of [x, y] points.

## The area of a polygon: positive when its points go round the way the left-hand normals used below point inwards.
func polygonArea(poly)
    var sum = 0
    var n = #poly
    for i = 1, n do
        var a = poly[i]
        var b = poly[i % n + 1]
        sum += a[1] * b[2] - b[1] * a[2]
    end
    return sum / 2
end

## The part of a convex polygon where nx * x + ny * y <= c.
func clipHalfPlane(poly, nx, ny, c)
    var out = []
    var n = #poly
    for i = 1, n do
        var a = poly[i]
        var b = poly[i % n + 1]
        var da = nx * a[1] + ny * a[2] - c
        var db = nx * b[1] + ny * b[2] - c
        if da <= 0 then
            out.push(a)
        end
        if (da < 0 and db > 0) or (da > 0 and db < 0) then
            var t = da / (da - db)
            out.push([math.lerp(a[1], b[1], t), math.lerp(a[2], b[2], t)])
        end
    end
    return out
end

## The polygon without the points that sit on their successor: clipping leaves some, and an edge of no length has no direction.
func withoutRepeats(poly)
    var out = []
    var n = #poly
    for i = 1, n do
        var a = poly[i]
        var b = poly[i % n + 1]
        if math.hypot(b[1] - a[1], b[2] - a[2]) > 1e-6 then
            out.push(a)
        end
    end
    return out
end

## The cell of the seed (sx, sy) among `others`, inside the rectangle box = [x0, y0, x1, y1].
func cellOf(sx, sy, others, box)
    var cell = [[box[1], box[2]], [box[3], box[2]], [box[3], box[4]], [box[1], box[4]]]
    for o in others do
        var dx = o[1] - sx
        var dy = o[2] - sy
        var d = math.hypot(dx, dy)
        if d > 0 then
            var nx = dx / d
            var ny = dy / d
            cell = clipHalfPlane(cell, nx, ny, nx * (sx + o[1]) / 2 + ny * (sy + o[2]) / 2)
        end
    end
    return withoutRepeats(cell)
end

## An angular spiral inside a convex polygon of positive area (its points turn towards the side the left-hand normals point
## to). The spiral runs along the line of an edge, moved inwards, until that line meets the line of another edge; the lines
## are moved a little further in at every corner, in proportion to the angle turned, so that after a whole turn the spiral
## lies `spacing` further in. An edge that has shrunk to nothing is never met, because its line meets the spiral later than
## the next one does. `first` is the edge it starts on. It ends where it can no longer go on inside the polygon, and gives
## its points in order.
func spiralOf(poly, spacing, first)
    var m = #poly
    if m < 3 then
        return []
    end
    var dx = []
    var dy = []
    var c = []
    for i = 1, m do
        var a = poly[i]
        var b = poly[i % m + 1]
        var d = math.hypot(b[1] - a[1], b[2] - a[2])
        dx.push((b[1] - a[1]) / d)
        dy.push((b[2] - a[2]) / d)
        c.push(-dy[i] * a[1] + dx[i] * a[2])
    end
    var before = (first + m - 2) % m + 1
    var turn = math.atan2(dx[before] * dy[first] - dy[before] * dx[first], dx[before] * dx[first] + dy[before] * dy[first])
    var edge = first
    var offset = spacing / 2
    var from = cornerOf(dx, dy, c, before, offset - spacing * turn / math.TAU, edge, offset)
    var points = [from]
    for step = 1, 40 * m do
        var best = nil
        var bestLength = nil
        for k = 1, m do
            var cross = dx[edge] * dy[k] - dy[edge] * dx[k]
            if k <> edge and cross > 1e-3 then
                var angle = math.atan2(cross, dx[edge] * dx[k] + dy[edge] * dy[k])
                var next = offset + spacing * angle / math.TAU
                var corner = cornerOf(dx, dy, c, edge, offset, k, next)
                var length = (corner[1] - from[1]) * dx[edge] + (corner[2] - from[2]) * dy[edge]
                if length > 1e-6 and (best == nil or length < bestLength) then
                    best = {edge: k, offset: next, corner: corner}
                    bestLength = length
                end
            end
        end
        if best == nil or bestLength < spacing * 0.5 then
            break
        end
        var corner = best.corner
        var inside = true
        for k = 1, m do
            if -dy[k] * corner[1] + dx[k] * corner[2] - c[k] < spacing * 0.3 then
                inside = false
                break
            end
        end
        if not inside then
            break
        end
        points.push(corner)
        from = corner
        edge = best.edge
        offset = best.offset
    end
    return points
end

## Where the line of edge i, moved inwards by ti, meets the line of edge j, moved inwards by tj. The normal of an edge is
## (-dy, dx), so its line is -dy * x + dx * y = c + t.
func cornerOf(dx, dy, c, i, ti, j, tj)
    var det = -dy[i] * dx[j] + dx[i] * dy[j]
    var k1 = c[i] + ti
    var k2 = c[j] + tj
    return [(k1 * dx[j] - k2 * dx[i]) / det, (-dy[i] * k2 + dy[j] * k1) / det]
end

## The same spiral turning the other way: the polygon is mirrored, which turns it inside out, and so is the spiral.
func spiralOfMirrored(poly, spacing, first)
    var flipped = []
    for i = #poly, 1, -1 do
        flipped.push([-poly[i][1], poly[i][2]])
    end
    var points = spiralOf(flipped, spacing, first)
    for p in points do
        p[1] = -p[1]
    end
    return points
end

## Seeds on a grid of cells `size` wide, each moved a little at random, with a ring beyond the area so that the cells at
## its edge are whole. Rows of [x, y] seeds.
func seedGrid(w, h, size)
    var cols = math.ceil(w / size) + 2
    var rows = math.ceil(h / size) + 2
    var grid = []
    for gy = 1, rows do
        var row = []
        for gx = 1, cols do
            row.push([(gx - 1.5 + math.rand(-0.4, 0.4)) * size, (gy - 1.5 + math.rand(-0.4, 0.4)) * size])
        end
        grid.push(row)
    end
    return grid
end

## The seeds within two cells of grid[gy][gx], itself excluded.
func neighboursOf(grid, gx, gy)
    var out = []
    for y = math.max(1, gy - 2), math.min(#grid, gy + 2) do
        for x = math.max(1, gx - 2), math.min(#grid[y], gx + 2) do
            if x <> gx or y <> gy then
                out.push(grid[y][x])
            end
        end
    end
    return out
end

## Whether a polygon has a point in [0, w] x [0, h].
func reaches(poly, w, h)
    var x0 = poly[1][1]
    var x1 = x0
    var y0 = poly[1][2]
    var y1 = y0
    for p in poly do
        x0 = math.min(x0, p[1])
        x1 = math.max(x1, p[1])
        y0 = math.min(y0, p[2])
        y1 = math.max(y1, p[2])
    end
    return x1 >= 0 and x0 <= w and y1 >= 0 and y0 <= h
end

## The drawing of an area w by h: one spiral in each cell, the cells taken one after the other from a random place outwards
## (a little ragged, as a hand is), as the lines of a pen would lay them. {segments, ends}: the segments [x1, y1, x2, y2] in
## the order they are drawn, and for each the length of pen travel, the moves between two cells included, at which it is done.
func drawing(w, h, size, spacing)
    var grid = seedGrid(w, h, size)
    var box = [-1.5 * size, -1.5 * size, w + 1.5 * size, h + 1.5 * size]
    var startX = math.rand(0, w)
    var startY = math.rand(0, h)
    var cells = []
    for gy = 1, #grid do
        for gx = 1, #grid[gy] do
            var seed = grid[gy][gx]
            var poly = cellOf(seed[1], seed[2], neighboursOf(grid, gx, gy), box)
            if #poly >= 3 and reaches(poly, w, h) then
                var points = nil
                if math.rand() < 0.5 then
                    points = spiralOf(poly, spacing, math.randInt(1, #poly))
                else
                    points = spiralOfMirrored(poly, spacing, math.randInt(1, #poly))
                end
                cells.push({
                    points: points,
                    order: math.hypot(seed[1] - startX, seed[2] - startY) + math.rand(0, size)
                })
            end
        end
    end
    cells.sort(func(a, b) return a.order < b.order end)
    var segments = []
    var ends = []
    var total = 0.0
    var penX = nil
    var penY = nil
    for cell in cells do
        var pts = cell.points
        for i = 1, #pts - 1 do
            var a = pts[i]
            var b = pts[i + 1]
            if i == 1 and penX <> nil then
                total += math.hypot(a[1] - penX, a[2] - penY)
            end
            total += math.hypot(b[1] - a[1], b[2] - a[2])
            segments.push([a[1], a[2], b[1], b[2]])
            ends.push(total)
        end
        if #pts > 1 then
            penX = pts[#pts][1]
            penY = pts[#pts][2]
        end
    end
    return {segments: segments, ends: ends}
end
