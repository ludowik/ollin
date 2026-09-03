## The WORLD's shape: everything that answers "what is at (x, z)?" — the biome, the altitude, the
## blocks of a column, the trees — and the baking of a chunk into a single draw call. It is a closed
## subject: it reads the noise and writes geometry, and touches neither the camera, nor the input,
## nor the display. Kept apart, voxel_world.ol is left with what MOVES (the walk, the streaming, the
## clouds and the drawing).
##
## It reads the constants and the atlas the host declares — CS, SEA, WATER, the tile indices — the
## globals of an imported file being shared, and is wired in with a plain:
##
##   import "terrain.ol"

## The surface biome: 0 desert, 1 plain, 2 forest. The relief, rock and snow, comes
## from the altitude, not from the biome.
func biomeAt(x, z)
    var b = math.noise(x * 0.026 + 50, z * 0.026 + 50)
    if b < 0.38 then return 0 end
    if b < 0.62 then return 1 end
    return 2
end

## A smooth elevation: one large scale for the broad hills plus a slight detail. A single source
## gives gentle slopes and no random cliffs.
func elevation(x, z)
    return math.noise(x * 0.013, z * 0.013) * 0.82
         + math.noise(x * 0.075, z * 0.075) * 0.18
end

## An amplitude of 44 and not 60: since math.noise was normalised to [0,1], the noise
## spreads about 1.35 times further, so 60 made the relief too steep. 44 restores gentle slopes.
func rawHeight(x, z)
    return math.floor((elevation(x, z) - 0.42) * 44 + SEA)
end

## Removes single-column extrema: a lone peak, higher than its four neighbours, is lowered to the
## highest of them, and a lone pit, lower than its four neighbours, is raised to the lowest — so
## neither a solitary cube nor a solitary hole remains. Being a pure function of (x, z), it gives
## the same height to the culling, the collision and the spawn, with no inconsistent seam.
func heightAt(x, z)
    var h = rawHeight(x, z)
    var e = rawHeight(x + 1, z)
    var w = rawHeight(x - 1, z)
    var n = rawHeight(x, z + 1)
    var s = rawHeight(x, z - 1)
    var hi = math.max(math.max(e, w), math.max(n, s))
    var lo = math.min(math.min(e, w), math.min(n, s))
    if h > hi then return hi end   ## a solitary cube, hence removed
    if h < lo then return lo end   ## a solitary pit, hence filled
    return h
end

## The column's baked top: the upper face of the highest cube sits at colTop + 0.5.
func colTop(x, z)
    return math.max(heightAt(x, z), 0)
end

## The height of the GROUND under (x, z): the top of the topmost cube, or the water surface when the
## column is submerged, so one floats. The terrain therefore rises in one-block steps — that is the
## voxel spirit: every cube is the same size.
func ground(x, z)
    return math.max(colTop(math.floor(x), math.floor(z)) + 0.5, WATER)
end

## The tiles, for the top, the sides and the bottom, follow the altitude: beach, then grass, then
## rock, then snow; the biome only sets the desert apart.
func setBlockTiles(b, h, y)
    if y >= h then
        if h < SEA + 1 then
            graphics.tile(T_SAND)
        elseif h >= SEA + 13 then
            graphics.tiles(T_SNOW, T_SNOW, T_ROCK)
        elseif h >= SEA + 8 then
            graphics.tile(T_ROCK)
        elseif b == 0 then
            graphics.tile(T_SAND)
        else
            graphics.tiles(T_GRASS, T_DIRT, T_DIRT)
        end
        return
    end
    if y >= h - 2 then
        if b == 0 then
            graphics.tile(T_SANDD)
        else
            graphics.tile(T_DIRT)
        end
        return
    end
    graphics.tile(T_STONE)
end

func ckey(cx, cz)
    return cx + "," + cz
end

## A well-mixed 2D hash, unlike a linear x*a + z*b, which lined the trees up along diagonals.
## `salt` gives independent streams — position, height, shape — for the same column.
func treeHash(x, z, salt)
    var h = (x * 374761393) ~ (z * 668265263) ~ (salt * 2246822519)
    h = (h ~ (h >> 15)) * 2654435761
    h = h ~ (h >> 13)
    return h & 2147483647
end

## One level of canopy: a square of radius r; round=true takes the corners off, rounding it.
func canopy(x, y, z, r, round)
    for tx = -r, r do
        for tz = -r, r do
            if not (round and math.abs(tx) == r and math.abs(tz) == r) then
                graphics.cube(x + tx, y, z + tz,  1, 1, 1)
            end
        end
    end
end

## A tree at column (x,z), the ground being at h. The trunk's height and the canopy's shape vary,
## derived from the hash, which is deterministic per column, so every tree differs.
func putTree(x, z, h)
    var th = 3 + treeHash(x, z, 1) % 4      ## the trunk, 3 to 6 cubes
    var shape = treeHash(x, z, 2) % 3       ## 0 round, 1 bushy, 2 conical
    graphics.tile(T_TRUNK)
    for k = 1, th do
        graphics.cube(x, h + k, z,  1, 1, 1)
    end
    graphics.tile(T_LEAF)
    var top = h + th
    if shape == 2 then
        canopy(x, top - 1, z, 1, true)       ## conical: a rounded base plus a spire
        graphics.cube(x, top, z,  1, 1, 1)
        graphics.cube(x, top + 1, z,  1, 1, 1)
    else
        var round = shape == 0               ## round, with the corners taken off, or bushy, hence solid
        canopy(x, top - 1, z, 1, round)
        canopy(x, top, z, 1, round)
        graphics.cube(x, top + 1, z,  1, 1, 1)
    end
end

func bakeChunk(cx, cz)
    graphics.beginChunk()
    graphics.fill(colors.WHITE)   ## a neutral tint: the atlas supplies the colour
    var x0 = cx * CS
    var z0 = cz * CS
    ## RAW heights over the area plus a one-cell border (indices -1..CS), used to cull
    ## the hidden faces: a cube is baked only when one of its faces touches empty space — the top of
    ## a column, or a lower neighbour — so only the surface is instanced, not the volume.
    var W2 = CS + 2
    var hg = []
    for lz = -1, CS do
        for lx = -1, CS do
            hg[(lz + 1) * W2 + (lx + 1) + 1] = heightAt(x0 + lx, z0 + lz)
        end
    end
    for lz = 0, CS - 1 do
        for lx = 0, CS - 1 do
            var x = x0 + lx
            var z = z0 + lz
            var b = biomeAt(x, z)
            var h = hg[(lz + 1) * W2 + (lx + 1) + 1]
            var top = math.max(h, 0)
            ## the four neighbours' heights, clamped as the baked columns are, to at least 0
            var he = math.max(hg[(lz + 1) * W2 + (lx + 2) + 1], 0)
            var hw = math.max(hg[(lz + 1) * W2 + lx + 1], 0)
            var hs = math.max(hg[(lz + 2) * W2 + (lx + 1) + 1], 0)
            var hn = math.max(hg[lz * W2 + (lx + 1) + 1], 0)
            var mn = math.min(math.min(he, hw), math.min(hs, hn))
            for y = 0, top do
                if y == top or y > mn then   ## a visible face: the top, OR a lower neighbour
                    setBlockTiles(b, h, y)
                    ## A SUBMERGED cube, darkened with its depth: there is less light down there.
                    ## It is the BOTTOM that darkens with depth, not the water, which is uniform.
                    if y < SEA then
                        var dk = math.clamp((SEA - y) / 5.0, 0, 0.85)   ## it darkens earlier and harder
                        graphics.fill(Color(1 - dk, 1 - dk, 1 - dk))
                    else
                        graphics.fill(colors.WHITE)
                    end
                    graphics.cube(x, y, z,  1, 1, 1)
                end
            end
            ## The sheet is laid as soon as the column's top falls below the surface: the same
            ## comparison as ground uses, so the water-terrain contact cannot fall out of step.
            if top + 0.5 < WATER then
                ## water = ONE UNIFORM semi-transparent plane at sea level, giving a
                ## continuous surface; the fading with depth is carried by the cubes on the bottom.
                graphics.tile(T_WATER)
                graphics.fill(Color(1, 1, 1, 0.72))
                graphics.plane(x, WATER, z,  1, 1)
                graphics.fill(colors.WHITE)
            end
            var hp = treeHash(x, z, 0) % 100    ## a scattered placement, from the mixed hash
            var grassy = h > SEA and h < SEA + 8 and b <> 0
            var tree = grassy and ((b == 2 and hp < 6) or hp == 0)
            if tree then
                putTree(x, z, h)
            end
        end
    end
    var g = graphics.endChunk()
    g.wx = x0 + CS / 2
    g.wz = z0 + CS / 2
    g.cx = cx
    g.cz = cz
    return g
end
