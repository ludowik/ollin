## Roadside posts. The ground is smooth colour with no texture and the camera keeps one distance
## behind the car, so without anything near the road the eye has nothing to compare against: nothing
## passes the view, and 100 km/h reads the same as 180. A post every few metres on both sides is
## what makes the speed readable, because how fast they stream by is the speed.
import "terrain.ol"

global POST_SPACING = 9.0
global POST_OFFSET = TRACK_WIDTH + 2.0    ## from the centreline: just outside the road bed
global POST_SIZE = 0.4
global POST_HEIGHT = 1.4
global POST_SEE = 160.0                   ## beyond this distance a post is not drawn
global POST_COLORS = [Color(0.92, 0.92, 0.92), Color(0.85, 0.15, 0.15)]
global posts = []

## Walks the loop once, dropping a pair of posts every POST_SPACING metres. `along` is the distance
## to the next post measured on the current segment, so the spacing carries over a waypoint instead
## of restarting there. A post that a bend would leave on top of another stretch of road is skipped.
## Needs the ground baked already: each post rests on the rendered surface.
func bakePosts()
    posts = []
    var n = #TRACK
    var along = 0.0
    var count = 0
    for i = 1, n do
        var a = TRACK[i]
        var b = TRACK[i % n + 1]
        var dx = b.x - a.x
        var dz = b.z - a.z
        var len = math.sqrt(dx * dx + dz * dz)
        var nx = -dz / len
        var nz = dx / len
        while along <= len do
            var px = a.x + dx * along / len
            var pz = a.z + dz * along / len
            for side = -1, 1, 2 do
                var x = px + nx * POST_OFFSET * side
                var z = pz + nz * POST_OFFSET * side
                if distanceToTrack(x, z) > TRACK_WIDTH + 1.5 then
                    posts.push({ x: x, y: surfaceAt(x, z), z: z, color: POST_COLORS[count % 2 + 1] })
                end
            end
            count += 1
            along += POST_SPACING
        end
        along -= len
    end
end

func drawPosts(cx, cz)
    var see2 = POST_SEE * POST_SEE
    var mid = POST_HEIGHT / 2
    for p in posts do
        var dx = p.x - cx
        var dz = p.z - cz
        if dx * dx + dz * dz < see2 and graphics.inFrustum(p.x, p.y + mid, p.z, POST_HEIGHT) then
            graphics.fill(p.color)
            graphics.cube(p.x, p.y + mid, p.z,  POST_SIZE, POST_HEIGHT, POST_SIZE)
        end
    end
end
