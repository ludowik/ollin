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
## height at TRACK_WIDTH and beyond, blended down to a near-flat road bed on the centreline.
func heightAt(x, z)
    var h = rawHeight(x, z)
    var d = nearestOnTrack(x, z)
    if d >= TRACK_WIDTH then
        return h
    end
    var t = d / TRACK_WIDTH     ## 0 on the centreline, 1 at the verge
    return h * t + 1.0 * (1 - t)
end

## Road grey inside TRACK_WIDTH, grass beyond it, blended over a couple of world units so the
## edge reads as a verge rather than a per-cell step — the geometry is smooth now, so a hard
## color boundary would be the only jagged thing left. The grass also darkens a little with
## altitude, the same idea as voxel_world/terrain.ol's biome-by-height.
func colorAt(x, z, h)
    var d = nearestOnTrack(x, z)
    var road = Color(0.55, 0.55, 0.58)
    var t = math.clamp((h + 1.0) / 6.0, 0, 1)
    var grass = Color(0.16 + 0.10 * t, 0.40 - 0.06 * t, 0.16)
    var FEATHER = 2.0
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
    ## Heights at the LATTICE POINTS (cell corners, not centres): (2n+2) samples per axis, shared
    ## by every cell that touches them — the thing that makes neighbours line up.
    var W = 2 * n + 2
    var lat = []
    for j = -n, n + 1 do
        for i = -n, n + 1 do
            lat[(j + n) * W + (i + n) + 1] = heightAt(i * CELL, j * CELL)
        end
    end
    for cz = -n, n do
        for cx = -n, n do
            var sw = lat[(cz + n) * W + (cx + n) + 1]
            var se = lat[(cz + n) * W + (cx + n + 1) + 1]
            var nw = lat[(cz + n + 1) * W + (cx + n) + 1]
            var ne = lat[(cz + n + 1) * W + (cx + n + 1) + 1]
            var x = (cx + 0.5) * CELL
            var z = (cz + 0.5) * CELL
            var h = (sw + se + nw + ne) / 4
            graphics.fill(colorAt(x, z, h))
            graphics.corners(sw, se, nw, ne)
            graphics.cube(x, -SKIRT / 2, z,  CELL, SKIRT, CELL)
        end
    end
    graphics.corners(0, 0, 0, 0)
    graphics.fill(colors.WHITE)
    return graphics.endChunk()
end
