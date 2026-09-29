## The circuit's shape and the ground beneath it — nothing here touches the camera or the input.
## heightAt is the ONE function the terrain mesh and the car's ground-follow (added later) both
## read, so the two can never disagree about where the ground is, the same discipline as
## voxel_world/terrain.ol's heightAt.

## The road: a closed loop of hand-placed waypoints, so the circuit is a recognisable shape
## rather than a wandering noise field.
global TRACK = [
    { x: 50,  z: 0   },
    { x: 42,  z: 26  },
    { x: 18,  z: 34  },
    { x: -10, z: 22  },
    { x: -30, z: 30  },
    { x: -48, z: 6   },
    { x: -38, z: -22 },
    { x: -8,  z: -34 },
    { x: 20,  z: -20 },
    { x: 40,  z: -18 }
]
global TRACK_WIDTH = 6.0    ## half-width of the road bed, in world units

global CELL = 3.0           ## the terrain lattice's spacing, in world units
global WORLD_HALF = 64.0    ## the baked ground spans [-WORLD_HALF; WORLD_HALF] on both axes
global SKIRT = 1.0          ## each cube's own (undeformed) height — see bakeTerrain

## The nearest point ON the closed loop to (x, z), and its distance: one pass over every
## segment, keeping the closer of the two each time.
func nearestOnTrack(x, z)
    var best = 1e30
    var n = #TRACK
    for i = 1, n do
        var a = TRACK[i]
        var b = TRACK[i % n + 1]
        var abx = b.x - a.x
        var abz = b.z - a.z
        var len2 = abx * abx + abz * abz
        var t = ((x - a.x) * abx + (z - a.z) * abz) / len2
        if t < 0 then t = 0 end
        if t > 1 then t = 1 end
        var px = a.x + abx * t
        var pz = a.z + abz * t
        var dx = x - px
        var dz = z - pz
        var d = math.sqrt(dx * dx + dz * dz)
        if d < best then best = d end
    end
    return best
end

## The surrounding relief: two octaves of noise, kept gentle so the hills off the road stay
## driveable — Art of Rally's off-track grass, not a wall.
func rawHeight(x, z)
    return math.noise(x * 0.02, z * 0.02) * 5.0
         + math.noise(x * 0.06, z * 0.06) * 1.5
end

## Flattens the relief within the road's width, so a hill never buries the track: full ground
## height at TRACK_WIDTH and beyond, blended down to a near-flat road bed on the centreline. Takes
## the distance already computed by the caller when it has one (bakeTerrain's lattice), so the
## same nearestOnTrack pass serves the height AND the color below instead of running twice.
func heightFromDist(x, z, d)
    var h = rawHeight(x, z)
    if d >= TRACK_WIDTH then
        return h
    end
    var t = d / TRACK_WIDTH     ## 0 on the centreline, 1 at the verge
    return h * t + 1.0 * (1 - t)
end

func heightAt(x, z)
    return heightFromDist(x, z, nearestOnTrack(x, z))
end

## Road grey inside TRACK_WIDTH, grass beyond it. FEATHER spans several cells (not a fraction of
## one), and d is the CELL's own average distance (its four lattice corners, from the same array
## heightAt reads) rather than one point sampled at its centre — a single-point sample changes
## from one cell to the next faster than the color could blend, which read as speckle rather than
## a gradient. Averaging over the cell is what makes the transition read as smooth at this scale.
func colorAt(d, h)
    var road = Color(0.55, 0.55, 0.58)
    var t = math.clamp(h / 8.0, 0, 1)
    var grass = Color(0.17 + 0.05 * t, 0.40 - 0.03 * t, 0.16)
    var FEATHER = CELL
    if d >= TRACK_WIDTH + FEATHER then
        return grass
    end
    if d <= TRACK_WIDTH then
        return road
    end
    var g = (d - TRACK_WIDTH) / FEATHER
    return Color(road.r + (grass.r - road.r) * g,
                 road.g + (grass.g - road.g) * g,
                 road.b + (grass.b - road.b) * g)
end

## Bakes the whole ground into ONE retained instance group (graphics.beginChunk/endChunk): the
## circuit never changes, so this runs once from setup(), not every frame.
##
## Blocky pillars (one flat-topped cube per cell) were tried first and looked exactly like
## that: a Minecraft grid, wrong for Art of Rally's smooth low-poly hills. graphics.corners is
## built for this instead — it bends a cube's TOP face by the bilinear interpolation of 4 corner
## heights, given in LOCAL units, i.e. before the instance's own scale is applied. Every cube
## here is emitted at a FIXED height (SKIRT, so its Y-scale is 1) precisely so a local unit
## equals a world unit: the four corners passed to graphics.corners are then heightAt's own
## values, unscaled. Two neighbouring cells share the SAME lattice point, and therefore the SAME
## corner height, so their tops meet exactly — one continuous surface, no crack, no step.
func bakeTerrain()
    graphics.beginChunk()
    var n = math.floor(WORLD_HALF / CELL)
    ## Heights AND distances-to-track at the LATTICE POINTS (cell corners, not centres):
    ## (2n+2) samples per axis, shared by every cell that touches them — the thing that makes
    ## neighbours line up, for the geometry as well as for colorAt's per-cell average below.
    var W = 2 * n + 2
    var latH = []
    var latD = []
    for j = -n, n + 1 do
        for i = -n, n + 1 do
            var d = nearestOnTrack(i * CELL, j * CELL)
            var idx = (j + n) * W + (i + n) + 1
            latD[idx] = d
            latH[idx] = heightFromDist(i * CELL, j * CELL, d)
        end
    end
    for cz = -n, n do
        for cx = -n, n do
            var i00 = (cz + n) * W + (cx + n) + 1
            var i10 = (cz + n) * W + (cx + n + 1) + 1
            var i01 = (cz + n + 1) * W + (cx + n) + 1
            var i11 = (cz + n + 1) * W + (cx + n + 1) + 1
            var sw = latH[i00]
            var se = latH[i10]
            var nw = latH[i01]
            var ne = latH[i11]
            var x = (cx + 0.5) * CELL
            var z = (cz + 0.5) * CELL
            var avgH = (sw + se + nw + ne) / 4
            var avgD = (latD[i00] + latD[i10] + latD[i01] + latD[i11]) / 4
            graphics.fill(colorAt(avgD, avgH))
            graphics.corners(sw, se, nw, ne)
            graphics.cube(x, -SKIRT / 2, z,  CELL, SKIRT, CELL)
        end
    end
    graphics.corners(0, 0, 0, 0)
    graphics.fill(colors.WHITE)
    return graphics.endChunk()
end
