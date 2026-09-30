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
global ROAD_COLOR = Color(0.55, 0.55, 0.58)   ## the road surface, flat — see roadMixAt/tintAt
global FEATHER = 6.0        ## world units over which the road blends into the grass

global CELL = 6.0           ## the terrain lattice's spacing, in world units
global WORLD_HALF = 260.0   ## the baked ground spans [-WORLD_HALF; WORLD_HALF] on both axes
global BLOCK = 11          ## cells per side of one baked block — the unit of off-screen culling

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

## How much of ROAD_COLOR to blend in AT THIS LATTICE POINT: 1 on the centreline, fading to 0 over
## FEATHER world units past the verge. It is a per-POINT value, not a cell average: the mesh
## interpolates the resulting colour across each triangle, so the road's edge follows the actual
## position inside a cell.
func roadMixAt(d)
    if d <= TRACK_WIDTH then
        return 1.0
    end
    if d >= TRACK_WIDTH + FEATHER then
        return 0.0
    end
    return 1.0 - (d - TRACK_WIDTH) / FEATHER
end

## The ground colour at a lattice point of height h, d away from the track: grass tinted by altitude,
## blended towards the road colour by roadMixAt.
func tintAt(h, d)
    var grass = grassAt(h)
    var t = roadMixAt(d)
    return Color(grass.r + (ROAD_COLOR.r - grass.r) * t,
                 grass.g + (ROAD_COLOR.g - grass.g) * t,
                 grass.b + (ROAD_COLOR.b - grass.b) * t)
end

## Where lattice point (i, j), each in [-n; n + 1], lives in the flat arrays: (2n + 2) points per row.
func latticeIndex(i, j, n)
    return (j + n) * (2 * n + 2) + (i + n) + 1
end

## The height of the RENDERED ground at (x, z), asked of the engine, which reads it from the very
## triangles it draws. heightAt is the true field, but the mesh only reproduces it at the lattice
## points: between them it is flat triangles, and on the road bed, where the height changes quickly,
## the two differ by more than a wheel's radius — which is what buried the car when it read heightAt.
## Past the baked world there is no mesh to ask, so the true field answers.
func surfaceAt(x, z)
    var h = graphics.terrainHeight(x, z)
    if h == nil then
        return heightAt(x, z)
    end
    return h
end

## Bakes the ground into BLOCKS of BLOCK x BLOCK cells, each one retained mesh
## (graphics.heightfield), and returns their handles: each carries a bounding sphere (x, y, z, r),
## so a frame can skip the blocks outside the camera's view (graphics.inFrustum) instead of pushing
## the whole world through the vertex shader. The circuit never changes, so this runs once from
## setup(), not every frame.
##
## One mesh vertex per lattice point, shared by the four cells around it: a cube per cell was tried
## (and, before it, blocky pillars that looked exactly like a Minecraft grid) and cost 24 vertices a
## cell for a top face of four. Neighbouring cells, and neighbouring blocks, share the SAME lattice
## point and therefore the SAME height, slope and colour, so the surface is continuous — no crack,
## no step, no visible block edge — and surfaceAt asks the engine for the height of those same
## triangles.
func bakeTerrain()
    var n = math.floor(WORLD_HALF / CELL)
    ## Height and colour at the LATTICE POINTS (cell corners, not centres): (2n+2) samples per
    ## axis, shared by every cell and every block that touches them — the thing that makes
    ## neighbours line up, for the geometry as well as for the colour.
    var latH = []
    var latTint = []
    for j = -n, n + 1 do
        for i = -n, n + 1 do
            var d = distanceToTrack(i * CELL, j * CELL)
            var idx = latticeIndex(i, j, n)
            latH[idx] = heightFromDist(i * CELL, j * CELL, d)
            latTint[idx] = tintAt(latH[idx], d)
        end
    end
    ## The slope at every lattice point, dh/dx and dh/dz per world unit, by central difference
    ## (one-sided on the border). Cells and blocks sharing a point hand it the SAME slope, hence the
    ## same lighting normal — the surface is shaded as one, instead of every cell being a lit facet
    ## of its own.
    var latSX = []
    var latSZ = []
    for j = -n, n + 1 do
        for i = -n, n + 1 do
            var idx = latticeIndex(i, j, n)
            var il = math.max(i - 1, -n)
            var ir = math.min(i + 1, n + 1)
            var jl = math.max(j - 1, -n)
            var jr = math.min(j + 1, n + 1)
            latSX[idx] = (latH[latticeIndex(ir, j, n)] - latH[latticeIndex(il, j, n)]) / ((ir - il) * CELL)
            latSZ[idx] = (latH[latticeIndex(i, jr, n)] - latH[latticeIndex(i, jl, n)]) / ((jr - jl) * CELL)
        end
    end

    var blocks = []
    var perSide = math.floor((2 * n + BLOCK) / BLOCK)   ## blocks per side: ceil((2n + 1) / BLOCK)
    for bz = 0, perSide - 1 do
        for bx = 0, perSide - 1 do
            var x0 = -n + bx * BLOCK
            var z0 = -n + bz * BLOCK
            var x1 = math.min(x0 + BLOCK - 1, n)
            var z1 = math.min(z0 + BLOCK - 1, n)
            ## The block's lattice points, row by row: height, slopes and the colour AT each point —
            ## interpolated across the triangles, so the road fades into the grass without a flat
            ## tint per cell.
            var heights = []
            var slopesX = []
            var slopesZ = []
            var tints = []
            for j = z0, z1 + 1 do
                for i = x0, x1 + 1 do
                    var idx = latticeIndex(i, j, n)
                    heights.push(latH[idx])
                    slopesX.push(latSX[idx])
                    slopesZ.push(latSZ[idx])
                    tints.push(latTint[idx])
                end
            end
            blocks.push(graphics.heightfield({
                cols: x1 - x0 + 1, rows: z1 - z0 + 1,
                x: x0 * CELL, z: z0 * CELL, cell: CELL,
                heights: heights, slopesX: slopesX, slopesZ: slopesZ, colors: tints
            }))
        end
    end
    return blocks
end
