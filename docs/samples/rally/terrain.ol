## The circuit's shape and the ground beneath it — nothing here touches the camera or the input.
## heightAt is the true height field the terrain mesh is sampled from; surfaceAt is the height of
## the mesh as actually RENDERED, which is what the car must rest on (the two differ between lattice
## points, see surfaceAt).

## The road: a closed loop of hand-placed waypoints, so the circuit is a recognisable shape
## rather than a wandering noise field.
## Four times the first draft's scale — a track this small barely gave a car room to turn.
## TRACK_WIDTH only doubled, not quadrupled: a real stage is a narrow ribbon across a big
## landscape, not a road as wide as the terrain grew.
global TRACK = [
    { x: 200,  z: 0    },
    { x: 168,  z: 104  },
    { x: 72,   z: 136  },
    { x: -40,  z: 88   },
    { x: -120, z: 120  },
    { x: -192, z: 24   },
    { x: -152, z: -88  },
    { x: -32,  z: -136 },
    { x: 80,   z: -80  },
    { x: 160,  z: -72  }
]
global TRACK_WIDTH = 10.0   ## half-width of the road bed, in world units
global ROAD_COLOR = Color(0.55, 0.55, 0.58)   ## flat — see roadMixAt/bakeTerrain
global FEATHER = 6.0        ## world units over which the road blends into the grass

global CELL = 6.0           ## the terrain lattice's spacing, in world units
global WORLD_HALF = 260.0   ## the baked ground spans [-WORLD_HALF; WORLD_HALF] on both axes
global SKIRT = 1.0          ## each cube's own (undeformed) height — see bakeTerrain

## The distance from (x, z) to the closed loop: one pass over every segment, keeping the closest.
func distanceToTrack(x, z)
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
## same distanceToTrack pass serves the height AND the color below instead of running twice.
func heightFromDist(x, z, d)
    var h = rawHeight(x, z)
    if d >= TRACK_WIDTH then
        return h
    end
    var t = d / TRACK_WIDTH     ## 0 on the centreline, 1 at the verge
    return h * t + 1.0 * (1 - t)
end

func heightAt(x, z)
    return heightFromDist(x, z, distanceToTrack(x, z))
end

## Grass tint, height-dependent — unlike ROAD_COLOR, which stays flat: the darker green at low
## altitude, lighter toward the hilltops, the same idea as voxel_world/terrain.ol's biome-by-height.
func grassAt(h)
    var t = math.clamp(h / 8.0, 0, 1)
    return Color(0.17 + 0.05 * t, 0.40 - 0.03 * t, 0.16)
end

## How much of ROAD_COLOR graphics.mixCorners should blend in AT THIS LATTICE POINT: 1 on the
## centreline, fading to 0 over FEATHER world units past the verge. This is deliberately the
## per-CORNER value, not a cell average — the GPU interpolates it per PIXEL across the cube's top
## (the same bilinear scheme as the height corners), which is what makes the road's edge follow
## the actual within-cell position instead of a single flat tone per cube.
func roadMixAt(d)
    if d <= TRACK_WIDTH then
        return 1.0
    end
    if d >= TRACK_WIDTH + FEATHER then
        return 0.0
    end
    return 1.0 - (d - TRACK_WIDTH) / FEATHER
end

## The lattice bakeTerrain fills, kept so surfaceAt reads exactly what the mesh renders.
global LATTICE = nil
global LATTICE_N = 0

## Where lattice point (i, j), each in [-n; n + 1], lives in the flat arrays: (2n + 2) points per row.
func latticeIndex(i, j, n)
    return (j + n) * (2 * n + 2) + (i + n) + 1
end

## The height of the RENDERED ground at (x, z). heightAt is the true field, but the mesh only
## reproduces it at the lattice corners: between them each cell's top is two triangles split on
## the diagonal from its (-x,-z) corner to its (+x,+z) corner (the unit cube's top face). On the
## road bed, where the height changes quickly, the two differ by more than a wheel's radius —
## which is what buried the car when it read heightAt.
func surfaceAt(x, z)
    if LATTICE == nil then
        return heightAt(x, z)
    end
    var n = LATTICE_N
    var fx = x / CELL
    var fz = z / CELL
    var cx = math.floor(fx)
    var cz = math.floor(fz)
    if cx < -n or cx > n or cz < -n or cz > n then
        return heightAt(x, z)
    end
    var u = fx - cx
    var v = fz - cz
    var sw = LATTICE[latticeIndex(cx, cz, n)]
    var se = LATTICE[latticeIndex(cx + 1, cz, n)]
    var nw = LATTICE[latticeIndex(cx, cz + 1, n)]
    var ne = LATTICE[latticeIndex(cx + 1, cz + 1, n)]
    if v >= u then
        return sw + u * (ne - nw) + v * (nw - sw)
    end
    return sw + u * (se - sw) + v * (ne - se)
end

## Bakes the whole ground into ONE retained instance group (graphics.beginChunk/endChunk): the
## circuit never changes, so this runs once from setup(), not every frame.
##
## Blocky pillars (one flat-topped cube per cell) were tried first and looked exactly like a
## Minecraft grid, wrong for Art of Rally's smooth low-poly hills. graphics.corners fixed the
## GEOMETRY — it bends a cube's TOP face by the bilinear interpolation of 4 corner heights, given
## in LOCAL units, i.e. before the instance's own scale is applied. Every cube here is emitted at
## a FIXED height (SKIRT, so its Y-scale is 1) precisely so a local unit equals a world unit: the
## four corners passed to graphics.corners are then heightAt's own values, unscaled. Two
## neighbouring cells share the SAME lattice point, and therefore the SAME corner height, so their
## tops meet exactly — one continuous surface, no crack, no step.
##
## The COLOR then had the same problem one level up: one flat tint per cube still made the
## road/grass edge and the height tint read as speckle between adjacent cells. graphics.mixCorners
## fixes it the same way corners fixes geometry — it is interpolated by the GPU per PIXEL from the
## cell's own four corners, not decided once for the whole cube.
func bakeTerrain()
    graphics.beginChunk()
    var n = math.floor(WORLD_HALF / CELL)
    ## Heights AND distances-to-track at the LATTICE POINTS (cell corners, not centres):
    ## (2n+2) samples per axis, shared by every cell that touches them — the thing that makes
    ## neighbours line up, for the geometry as well as for the color blend below.
    var latH = []
    var latD = []
    for j = -n, n + 1 do
        for i = -n, n + 1 do
            var d = distanceToTrack(i * CELL, j * CELL)
            var idx = latticeIndex(i, j, n)
            latD[idx] = d
            latH[idx] = heightFromDist(i * CELL, j * CELL, d)
        end
    end
    LATTICE = latH
    LATTICE_N = n
    ## The slope at every lattice point, by central difference (one-sided on the border), in the
    ## LOCAL units graphics.cornerSlopes expects: the height change across one whole cell. Cells
    ## sharing a corner hand it the SAME slopes, hence the same lighting normal — the surface is
    ## shaded as one, instead of every cell being a lit facet of its own.
    var latSX = []
    var latSZ = []
    for j = -n, n + 1 do
        for i = -n, n + 1 do
            var idx = latticeIndex(i, j, n)
            var il = math.max(i - 1, -n)
            var ir = math.min(i + 1, n + 1)
            var jl = math.max(j - 1, -n)
            var jr = math.min(j + 1, n + 1)
            latSX[idx] = (latH[latticeIndex(ir, j, n)] - latH[latticeIndex(il, j, n)]) / (ir - il)
            latSZ[idx] = (latH[latticeIndex(i, jr, n)] - latH[latticeIndex(i, jl, n)]) / (jr - jl)
        end
    end
    for cz = -n, n do
        for cx = -n, n do
            var i00 = latticeIndex(cx, cz, n)
            var i10 = latticeIndex(cx + 1, cz, n)
            var i01 = latticeIndex(cx, cz + 1, n)
            var i11 = latticeIndex(cx + 1, cz + 1, n)
            var sw = latH[i00]
            var se = latH[i10]
            var nw = latH[i01]
            var ne = latH[i11]
            var x = (cx + 0.5) * CELL
            var z = (cz + 0.5) * CELL
            var avgH = (sw + se + nw + ne) / 4
            graphics.fill(grassAt(avgH))
            graphics.mixCorners(roadMixAt(latD[i00]), roadMixAt(latD[i10]),
                                roadMixAt(latD[i01]), roadMixAt(latD[i11]))
            graphics.corners(sw, se, nw, ne)
            graphics.cornerSlopes(latSX[i00], latSX[i10], latSX[i01], latSX[i11],
                                  latSZ[i00], latSZ[i10], latSZ[i01], latSZ[i11])
            graphics.cube(x, -SKIRT / 2, z,  CELL, SKIRT, CELL)
        end
    end
    graphics.mixCorners(0, 0, 0, 0)
    graphics.corners(0, 0, 0, 0)
    graphics.cornerSlopes(0, 0, 0, 0, 0, 0, 0, 0)
    graphics.fill(colors.WHITE)
    return graphics.endChunk()
end
