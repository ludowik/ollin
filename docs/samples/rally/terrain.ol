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

global CELL = 4.0           ## one terrain pillar every CELL world units
global WORLD_HALF = 64.0    ## the baked ground spans [-WORLD_HALF; WORLD_HALF] on both axes
global BASE_Y = -20.0       ## the pillars' buried bottom, well below any heightAt

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

## Road grey inside TRACK_WIDTH, grass beyond it — the grass darkens a little with altitude, the
## same idea as terrain.ol's biome-by-height, kept to a plain gradient here.
func colorAt(x, z, h)
    var d = nearestOnTrack(x, z)
    if d < TRACK_WIDTH then
        return Color(0.55, 0.55, 0.58)
    end
    var t = math.clamp((h + 1.0) / 6.0, 0, 1)
    return Color(0.16 + 0.10 * t, 0.40 - 0.06 * t, 0.16)
end

## Bakes the whole ground into ONE retained instance group (graphics.beginChunk/endChunk): the
## circuit never changes, so this runs once from setup(), not every frame.
func bakeTerrain()
    graphics.beginChunk()
    var n = math.floor(WORLD_HALF / CELL)
    for cz = -n, n do
        for cx = -n, n do
            var x = cx * CELL
            var z = cz * CELL
            var h = heightAt(x, z)
            graphics.fill(colorAt(x, z, h))
            graphics.cube(x, (h + BASE_Y) / 2, z,  CELL, h - BASE_Y, CELL)
        end
    end
    graphics.fill(colors.WHITE)
    return graphics.endChunk()
end
