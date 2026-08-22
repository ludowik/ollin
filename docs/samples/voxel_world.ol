## An endless voxel world: chunks generated on the fly from Perlin noise, baked around the player
## (beginChunk/endChunk) and freed far away (freeChunk). The view
## distance is self-adapting (the ViewDistance class, view_distance.ol). Touch joystick.
## Movement with inertia: the speed, the turn and the eye height ease towards their target
## instead of taking it up at once (see approach).

import "joystick.ol"
import "view_distance.ol"

global CS = 16
global vd = ViewDistance(4, 1, 24)   ## the radius in chunks: self-adapting, plus - / + buttons

global SEA = 9
global WATER = SEA + 0.45    ## the water surface level, the ONLY threshold for "under water"
global loaded = {}          ## "cx,cz" → the endChunk handle
global cam = graphics.camera(0, 0, 10,  0, 0, 0)
## The CONTROL camera, for debugging: a view from above looking down, oriented like the player's
## camera, so as to CHECK from the outside that only the visible chunks — those in the player
## camera's frustum — are drawn. The "C" key toggles it.
global ctrlCam = graphics.camera(0, 0, 10,  0, 0, 0)
global debugCam = false
global CAMBTN = 46          ## the "C" button, which toggles the control camera, in the top-left corner

global EYE = 2.2
global STEP = 1.2           ## the step one can climb; anything higher is a wall
global camX = 8.5
global camY = 10
global camZ = 8.5
global yaw = 0.0
global saveAcc = 0.0        ## an accumulator, to throttle saving the position
global PITCH = -0.12
global lastcx = 999999
global lastcz = 999999
global streaming = false

global pad = Joystick()
global TURN_MAX = 1.8
global SPEED_MAX = 8.0
## Inertia: the speed and the turn do not follow the joystick's command all at
## once, they ease towards it. The eye then perceives a start and a braking rather than a uniform
## motion switched on and off.
global vel = 0.0            ## the current forward speed
global turnVel = 0.0        ## the current turning speed
global ACCEL = 5.0          ## how eager the forward motion is; higher is sharper
global TURN_ACCEL = 7.0
global EYE_RISE = 6.0       ## smoothing of the eye height, the terrain rising in steps of 1

## Brings `cur` towards `target` by a fraction of the distance left. The fraction depends on
## deltaTime through an exponential, so the result does not change with the frame rate, unlike a
## plain `cur + (target-cur) * 0.1`.
func approach(cur, target, rate)
    return cur + (target - cur) * (1 - math.exp(-rate * deltaTime))
end

global C_SKY = Color(0.55, 0.80, 0.95)
global AMB = 0.5              ## the terrain's ambient light

## The clouds: a layer of semi-transparent white cubes drifting towards +x. They are drawn in
## IMMEDIATE mode every frame, since they move and so cannot be baked into a chunk, in
## one instanced call. Culling works by SECTOR: the sector's bounding box is tested against the
## frustum, which skips both the noise and the cubes of a patch of sky that is off screen.
global CLOUD_Y = SEA + 40     ## the altitude, above the peaks
global CLOUD_SIZE = 4         ## the side of one cloud block
global CLOUD_TH = 2           ## the thickness
global CLOUD_STEP = 4         ## the grid step (= CLOUD_SIZE, so the blocks abut)
global CLOUD_SEC = 32         ## the side of a sector, eight cells, for the frustum culling
global CLOUD_MARGIN = 96      ## the margin beyond the terrain loaded, so clouds reach the horizon
global CLOUD_SCALE = 0.05     ## the frequency of the placement noise
global CLOUD_THRESH = 0.67    ## the coverage threshold; higher means fewer clouds
global CLOUD_SPEED = 1.2      ## the drift, in blocks per second
global CLOUD_ALPHA = 0.9
global CLOUD_TEX = 16         ## the side of the clouds' speckled texture
global cloudTex = nil

global TILE = 16
global ACOLS = 4
global AROWS = 4
global atlas = nil
global T_GRASS = 0
global T_DIRT  = 1
global T_SAND  = 2
global T_ROCK  = 3
global T_SNOW  = 4
global T_WATER = 5
global T_TRUNK = 6
global T_LEAF  = 7
global T_STONE = 8
global T_SANDD = 9

## A base colour plus an INDEPENDENT noise per channel, giving a variation of hue and not only
## of brightness, which makes the tiles look less flat.
##
## `holes`, where 0 means a solid tile, pierces the tile: the engine discards the pixels whose alpha
## falls below 0.5, so the cube lets the sky show through. That is how foliage is opened up without
## removing a single cube — the canopy's shape stays whole, only its substance thins. The holes
## follow a fine noise, giving irregular clusters, where every other pixel would have given a
## grid.
func putTile(idx, br, bg, bb, jit, holes = 0)
    var cx = (idx % ACOLS) * TILE
    var cy = math.floor(idx / ACOLS) * TILE
    for py = 0, TILE - 1 do
        for px = 0, TILE - 1 do
            var wx = (cx + px) * 1.7
            var wy = (cy + py) * 1.7
            var nr = (math.noise(wx + 9,  wy + 9)   - 0.5) * 2 * jit
            var ng = (math.noise(wx + 41, wy + 67)  - 0.5) * 2 * jit
            var nb = (math.noise(wx + 113, wy + 151) - 0.5) * 2 * jit
            var a = 1
            if holes > 0 then
                ## The tile's EDGES stay solid: a hole at the edge would open a slit
                ## continuous between two neighbouring cubes, far more conspicuous than a lone hole.
                var edge = math.min(math.min(px, py), math.min(TILE - 1 - px, TILE - 1 - py))
                var n = math.noise((cx + px) * 0.55 + 200, (cy + py) * 0.55 + 200)
                if edge >= 2 and n > 1 - holes then
                    a = 0
                end
            end
            image.setPixel(atlas, cx + px, cy + py,
                math.clamp(br + nr, 0, 1), math.clamp(bg + ng, 0, 1), math.clamp(bb + nb, 0, 1), a)
        end
    end
end

func buildAtlas()
    atlas = image.create(ACOLS * TILE, AROWS * TILE)
    image.beginPixels(atlas)
    putTile(T_GRASS, 0.42, 0.68, 0.30, 0.16)
    putTile(T_DIRT,  0.46, 0.33, 0.20, 0.15)
    putTile(T_SAND,  0.86, 0.79, 0.53, 0.11)
    putTile(T_ROCK,  0.47, 0.46, 0.45, 0.18)
    putTile(T_SNOW,  0.95, 0.97, 1.00, 0.07)
    putTile(T_WATER, 0.20, 0.45, 0.80, 0.14)
    putTile(T_TRUNK, 0.40, 0.26, 0.13, 0.16)
    putTile(T_LEAF,  0.18, 0.42, 0.16, 0.22, 0.42)   ## the only pierced tile: the foliage
    putTile(T_STONE, 0.36, 0.36, 0.40, 0.16)
    putTile(T_SANDD, 0.72, 0.63, 0.40, 0.12)
    image.endPixels(atlas)
    graphics.tileset(atlas, ACOLS, AROWS)
    graphics.tileAnim(T_WATER)
end

## The cloud texture: white, faintly speckled by a brightness noise, at full alpha. It breaks the
## cubes' flat white without opening a hole.
func buildCloudTex()
    cloudTex = image.create(CLOUD_TEX, CLOUD_TEX)
    image.beginPixels(cloudTex)
    for py = 0, CLOUD_TEX - 1 do
        for px = 0, CLOUD_TEX - 1 do
            var v = 0.78 + math.noise(px * 0.22 + 3, py * 0.22 + 7) * 0.22   ## about 0.78 to 1.0, at a low frequency, hence a soft gradient
            image.setPixel(cloudTex, px, py, v, v, v, 1)
        end
    end
    image.endPixels(cloudTex)
end

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
    if h < lo then return lo end   ## trou solitaire → rempli
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
    var th = 3 + treeHash(x, z, 1) % 4      ## tronc : 3..6 cubes
    var shape = treeHash(x, z, 2) % 3       ## 0 rond · 1 touffu · 2 conique
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

## Bakes the chunks missing from the radius, `budget` of them per frame, giving priority to what is
## in front of the camera, then the nearest, in a bounded sorted buffer. It returns how many were
## baked.
func streamLoad(pcx, pcz, budget)
    if budget < 1 then
        return 0
    end
    var bcx = []
    var bcz = []
    var bsc = []
    var cnt = 0
    var fdx = math.sin(yaw)
    var fdz = math.cos(yaw)
    ## A sweep over growing Chebyshev rings, from the nearest to the farthest. It
    ## walks only the PERIMETER of each ring, which is O(r squared) in total, like a solid square;
    ## as soon as the buffer is full and the current ring can no longer beat the worst score kept
    ## (d squared > bsc[cnt]), it stops — the whole grid is no longer rescanned.
    for d = 0, vd.radius do
        if cnt >= budget and d * d > bsc[cnt] then
            break
        end
        for dz = -d, d do
            var stepx = 1
            if d > 0 and dz > -d and dz < d then
                stepx = 2 * d       ## the middle rows: only the columns at ±d
            end
            for dx = -d, d, stepx do
                var cx = pcx + dx
                var cz = pcz + dz
                if loaded[ckey(cx, cz)] == nil then
                    var score = dx * dx + dz * dz
                    if dx * fdx + dz * fdz < 0 then
                        score = score + 100000         ## behind the camera, hence later
                    end
                    if cnt < budget or score < bsc[cnt] then
                        var p = budget
                        if cnt < budget then
                            cnt = cnt + 1
                            p = cnt
                        end
                        while p > 1 and bsc[p - 1] > score do
                            bcx[p] = bcx[p - 1]
                            bcz[p] = bcz[p - 1]
                            bsc[p] = bsc[p - 1]
                            p = p - 1
                        end
                        bcx[p] = cx
                        bcz[p] = cz
                        bsc[p] = score
                    end
                end
            end
        end
    end
    for i = 1, cnt do
        loaded[ckey(bcx[i], bcz[i])] = bakeChunk(bcx[i], bcz[i])
    end
    return cnt
end

## Frees the chunks outside the radius. `margin` is the hysteresis: 1 while moving, which gives a
## buffer ring and avoids churn when stepping back, and 0 when the radius shrinks, freeing at once.
func streamUnload(pcx, pcz, margin)
    var keep = {}
    for k, c in loaded do
        if math.abs(c.cx - pcx) <= vd.radius + margin and math.abs(c.cz - pcz) <= vd.radius + margin then
            keep[k] = c
        else
            graphics.freeChunk(c)
        end
    end
    loaded = keep
end

func setup()
    graphics.canvas(W, H, "Endless voxels")
    graphics.ambient(AMB)
    graphics.light("dir", -0.5, -1, -0.35)
    math.noiseSeed(7)
    buildAtlas()
    buildCloudTex()
    ## The spawn: dry land, low and near the origin, with a heavy penalty on altitude
    ## so it is never under water.
    var best = 1000000000.0
    for z = 0, 60 do
        for x = 0, 60 do
            var h = heightAt(x, z)
            if h > SEA then
                var cx = x - 30
                var cz = z - 30
                var score = cx * cx + cz * cz + (h - SEA) * (h - SEA) * 40
                if score < best then
                    best = score
                    camX = x + 0.5
                    camZ = z + 0.5
                end
            end
        end
    end
    ## looking towards the clearest direction, the one of least summed altitude
    var bestSum = 1000000.0
    for a = 0, 15 do
        var ang = a / 16.0 * 6.28319
        var sum = 0.0
        for k = 3, 18, 3 do
            sum = sum + ground(camX + math.sin(ang) * k, camZ + math.cos(ang) * k)
        end
        if sum < bestSum then
            bestSum = sum
            yaw = ang
        end
    end
    ## restores the remembered position, from the data module, when there is one, overriding the default spawn
    if data.has("camX") then
        camX = data.get("camX", camX)
        camZ = data.get("camZ", camZ)
        yaw = data.get("yaw", yaw)
    end
    camY = ground(camX, camZ) + EYE   ## without this the eye would drop from the sky on the first frame
    lastcx = math.floor(camX / CS)
    lastcz = math.floor(camZ / CS)
    loaded[ckey(lastcx, lastcz)] = bakeChunk(lastcx, lastcz)   ## the ground is there from the spawn on
    streaming = true
end

## The camera button, a debug toggle: a square at the top left, below the HUD.
func camBtnHit(x, y)
    return x >= 12 and x <= 12 + CAMBTN and y >= 36 and y <= 36 + CAMBTN
end

func drawCamButton()
    graphics.noStroke()
    graphics.fill(Color(0, 0, 0, 0.38))
    graphics.rect(12, 36, CAMBTN, CAMBTN)
    if debugCam then                   ## lit means the control camera is on
        graphics.fill(Color(0.30, 0.70, 1.00, 0.55))
        graphics.rect(12, 36, CAMBTN, CAMBTN)
    end
    graphics.stroke(colors.WHITE)
    graphics.fontSize(28)
    graphics.text("C", 12 + CAMBTN / 2 - 8, 36 + CAMBTN / 2 - 15)
end

func mouse.pressed(x, y)
    if camBtnHit(x, y) then          ## the camera button toggles it, and is reachable by touch
        debugCam = not debugCam
        return
    end
    var ev = vd.hit(x, y)              ## the - and + buttons, handled by ViewDistance
    if ev == 1 then
        streaming = true               ## rayon agrandi → charger le nouvel anneau
    elseif ev == -1 then
        streamUnload(lastcx, lastcz, 0)   ## the radius shrank, so free at once
    elseif ev == 0 then
        pad.press(x, y)                ## hors boutons → joystick (ev == 2 : borne atteinte, rien)
    end
end
func mouse.released(x, y)
    pad.release()
end
## The C key toggles the control camera; the movement itself reads keyboard.isDown.
func keyboard.keypressed(key)
    if string.upper(key) == "C" then
        debugCam = not debugCam
    end
end
func mouse.moved(x, y)
    pad.move(x, y)
end

## Advances the player, turning and speed together, combining the touch joystick AND the arrow
## keys, sliding along slopes that can be climbed and stopping at walls.
func movePlayer()
    var turn = pad.steer()
    if keyboard.isDown("left") then turn = turn - 1 end
    if keyboard.isDown("right") then turn = turn + 1 end
    turnVel = approach(turnVel, math.clamp(turn, -1, 1) * TURN_MAX, TURN_ACCEL)
    yaw = yaw - turnVel * deltaTime

    var thr = pad.throttle()      ## the joystick, in [-1;1], forwards and backwards
    if keyboard.isDown("up") then thr = thr + 1 end
    if keyboard.isDown("down") then thr = thr - 1 end   ## the down arrow goes backwards
    vel = approach(vel, math.clamp(thr, -1, 1) * SPEED_MAX, ACCEL)
    ## Below a millimetre a second we are at a standstill: cutting out avoids running the collision
    ## test for an invisible move.
    if math.abs(vel) < 0.001 then
        vel = 0.0
        return
    end
    var sp = vel * deltaTime
    ## The move is cut into sub-steps of at most HALF A BLOCK. The guard below compares only the
    ## starting ground with the arriving one: a step wider than a block can stride over a narrow wall
    ## without ever sampling it. That only happens below eight frames a second — a very long frame,
    ## during the baking of
    ## chunks — but the player then ends up INSIDE the terrain.
    var steps = math.max(math.ceil(math.abs(sp) / 0.5), 1)
    var dx = math.sin(yaw) * sp / steps
    var dz = math.cos(yaw) * sp / steps
    var moved = false
    for i = 1, steps do
        var g0 = ground(camX, camZ)
        var nx = camX + dx
        var nz = camZ + dz
        var blocked = true
        if ground(nx, camZ) - g0 <= STEP then
            camX = nx
            moved = true
            blocked = false
        end
        if ground(camX, nz) - g0 <= STEP then
            camZ = nz
            moved = true
            blocked = false
        end
        ## A wall reached: the remaining sub-steps would get no further.
        if blocked then
            break
        end
    end
    ## Against a wall we fall back to zero: the speed would otherwise keep climbing against nothing,
    ## and the player would leap on getting free.
    if not moved then
        vel = 0.0
    end
end

## Remembers the position, through the data module, at most once a second: it avoids a write to
## localStorage or to a file on every frame.
func savePlayer()
    saveAcc = saveAcc + deltaTime
    if saveAcc < 1.0 then
        return
    end
    saveAcc = 0.0
    data.set("camX", camX)
    data.set("camZ", camZ)
    data.set("yaw", yaw)
end

## The clouds: a FROZEN noise pattern sampled at the cells' home positions (cx,cz), rendered offset
## by `drift` along x, which gives a continuous, smooth translation.
##
## Culling by SECTOR is done HERE, like the chunks: BEFORE begin3d(rcam), hence against
## the PLAYER's FROZEN frustum. Otherwise, with the control camera, rendering from ctrlCam,
## inFrustum would read the control camera's frustum and reject no sector at all.
##
## We do not scan the full square of side 2*reach, about half of which lies BEHIND the player and
## always fails inFrustum: each row is clipped to the forward half-plane, through a dot product with
## the viewing direction f. Only sectors behind the camera are dropped — the very ones inFrustum
## already rejected — so the visible coverage is unchanged.
## It returns a flat array [sx0, sz0, sx1, sz1, …] of the visible sectors.
global cloudStats = {"tested": 0, "kept": 0, "full": 0}

func cullCloudSectors()
    var drift = elapsedTime * CLOUD_SPEED
    var reach = vd.radius * CS + CLOUD_MARGIN   ## it follows the terrain's view distance
    var fx = math.sin(yaw)                       ## the viewing direction, in XZ
    var fz = math.cos(yaw)
    var secs = []
    var tested = 0
    var s0z = math.floor((camZ - reach) / CLOUD_SEC) * CLOUD_SEC
    ## the full square, with no half-plane: every row from s0z to camZ+reach
    var fullW = math.floor(2 * reach / CLOUD_SEC) + 1
    var fullRows = math.floor(2 * reach / CLOUD_SEC) + 1
    var fullTotal = fullW * fullRows
    for sz = s0z, camZ + reach, CLOUD_SEC do
        var wz = sz + CLOUD_SEC / 2
        ## span x du demi-plan avant : (wx-camX)*fx + (wz-camZ)*fz >= -CLOUD_SEC
        var rhs = 0 - CLOUD_SEC - (wz - camZ) * fz
        var wlo = camX - reach
        var whi = camX + reach
        if fx > 0.001 then
            wlo = math.max(wlo, camX + rhs / fx)
        elseif fx < -0.001 then
            whi = math.min(whi, camX + rhs / fx)
        elseif rhs > 0 then
            wlo = whi + 1                         ## the row lies entirely behind, hence empty
        end
        var s0x = math.floor((wlo - drift) / CLOUD_SEC) * CLOUD_SEC
        for sx = s0x, whi - drift, CLOUD_SEC do
            tested = tested + 1
            if graphics.inFrustum(sx + CLOUD_SEC / 2 + drift, CLOUD_Y, wz, CLOUD_SEC * 0.72 + 4) then
                secs[#secs + 1] = sx
                secs[#secs + 1] = sz
            end
        end
    end
    cloudStats.tested = tested
    cloudStats.full = fullTotal
    cloudStats.kept = #secs // 2
    return secs
end

func drawClouds(secs)
    var drift = elapsedTime * CLOUD_SPEED
    graphics.ambient(0.8)                        ## below 1, so the directional light gives the clouds some volume
    graphics.fill(Color(1, 1, 1, CLOUD_ALPHA))
    graphics.texture(cloudTex)                    ## a soft speckle, which breaks the flat white
    for i = 1, #secs, 2 do
        var sx = secs[i]
        var sz = secs[i + 1]
        for cx = sx, sx + CLOUD_SEC - CLOUD_STEP, CLOUD_STEP do
            for cz = sz, sz + CLOUD_SEC - CLOUD_STEP, CLOUD_STEP do
                if math.noise(cx * CLOUD_SCALE, cz * CLOUD_SCALE) > CLOUD_THRESH then
                    graphics.cube(cx + drift, CLOUD_Y, cz,  CLOUD_SIZE, CLOUD_TH, CLOUD_SIZE)
                end
            end
        end
    end
    graphics.noTexture()
    graphics.fill(colors.WHITE)
end

func draw()
    graphics.clear(C_SKY)
    movePlayer()
    savePlayer()

    var pcx = math.floor(camX / CS)
    var pcz = math.floor(camZ / CS)
    if pcx <> lastcx or pcz <> lastcz then
        lastcx = pcx
        lastcz = pcz
        streamUnload(pcx, pcz, 1)
        streaming = true
    end
    var budget = 6
    if vd.manual then budget = 10 end
    if streaming and streamLoad(pcx, pcz, budget) == 0 then
        streaming = false
    end
    var ev = vd.update(deltaTime, streaming)
    if ev == 1 then
        streaming = true
    elseif ev == -1 then
        streamUnload(pcx, pcz, 0)
    end

    ## The terrain rises in one-block steps: putting the eye straight on it would make it jump
    ## a whole notch at once. It is left to reach the step gradually.
    camY = approach(camY, ground(camX, camZ) + EYE, EYE_RISE)
    cam.setPos(camX, camY, camZ)
    cam.lookAt(camX + math.cos(PITCH) * math.sin(yaw),
               camY + math.sin(PITCH),
               camZ + math.cos(PITCH) * math.cos(yaw))

    graphics.noStroke()
    ## The rendering camera: the player's, or the control camera up high, looking down, with up set
    ## to the player's heading so the orientation on screen matches. The culling ALWAYS remains the
    ## player's: in control mode we render from ANOTHER camera, so the player's frustum is frozen
    ## first, through an empty 3D block that freezes the view and projection inFrustum reads. In
    ## player mode that is needless: inFrustum reuses the frustum the previous frame's rendering
    ## froze, so the normal path has no empty 3D pass.
    var rcam = cam
    if debugCam then
        graphics.begin3d(cam)
        graphics.end3d()
        var high = vd.radius * CS * 2.0 + 40
        ctrlCam.setPos(camX, camY + high, camZ)
        ctrlCam.lookAt(camX, camY, camZ)
        ctrlCam.ux = math.sin(yaw)
        ctrlCam.uy = 0
        ctrlCam.uz = math.cos(yaw)
        rcam = ctrlCam
    end

    var vis = []
    for k, c in loaded do
        if graphics.inFrustum(c.wx, SEA, c.wz, CS + 24) then
            vis[#vis + 1] = c
        end
    end
    var cloudSecs = cullCloudSectors()   ## culled before begin3d(rcam), the player's frustum being frozen
    graphics.begin3d(rcam)
    do
        for i = 1, #vis do
            graphics.drawChunk(vis[i])
        end
        for i = 1, #vis do
            graphics.drawChunkAlpha(vis[i])
        end
        drawClouds(cloudSecs)
    end
    graphics.end3d()
    graphics.ambient(AMB)           ## drawClouds lowered the ambient, so restore it for the terrain

    pad.draw()
    vd.draw()                          ## the - / + buttons (ViewDistance)
    drawCamButton()                  ## the "C" button, which toggles the control camera
    var camlbl = "player"
    if debugCam then camlbl = "control" end
    graphics.stroke(colors.WHITE)
    graphics.fontSize(15)
    graphics.text("view " + vd.radius + " " + vd.mode() + " " + vd.hz() + "Hz  chunks " + #vis +
                  "  cam " + camlbl, 12, 12)
    graphics.stroke(colors.WHITE)
    graphics.fontSize(13)
    graphics.text("clouds: " + cloudStats.tested + "/" + cloudStats.full + " tested  " + cloudStats.kept + " drawn", 12, 30)
end
