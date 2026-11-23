## The 3D part of the graphics module for real: cameras, the solids and their lighting, textures and tile
## atlases, chunks, terrain meshes, models. It needs a window, so it runs under Xvfb with the raylib build
## (tests/run_gfx.sh). Each frame ends in a screenshot read back with image.load on the next one, so what is
## checked is what reached the screen — with the smoothing off, to keep the edges exact.

const SHOT = "/tmp/ollin_gfx_3d_"
const MODELS = "../docs/samples/model_3d/"
const Q = string.fromCode(34)   ## a double quote: a string has no escape for it

global frames = 0
global cam = nil
global pattern = nil
global atlas = nil
global chunk = nil
global water = nil
global ground = nil

func refusal(f)
    var msg = ""
    try
        f()
    catch e
        msg = e
    end
    return msg
end

func expect(got, want)
    assert(got == want, "want [{want}] got [{got}]")
end

func near(a, b)
    return math.abs(a - b) < 0.02
end

## How many pixels of the box are within 0.1 of (r, g, b).
func count(img, x0, y0, x1, y1, r, g, b)
    var n = 0
    for y = y0, y1 do
        for x = x0, x1 do
            var pr, pg, pb, pa = image.getPixel(img, x, y)
            if math.abs(pr - r) < 0.1 and math.abs(pg - g) < 0.1 and math.abs(pb - b) < 0.1 then
                n += 1
            end
        end
    end
    return n
end

func setup()
    gfx.canvas(120, 90, "3d test")
    gfx.antialias(false)
    cam = gfx.camera(0, 0, 10, 0, 0, 0)
    pattern = image.fromPattern(["ab", "cd"], {"a": Color(1, 0, 0), "b": Color(0, 1, 0), "c": Color(0, 0, 1), "d": Color(1, 1, 0)})
    atlas = image.fromPattern(["ab"], {"a": Color(1, 0, 0), "b": Color(0, 1, 0)})
end

## ── cameras, lights and what is refused ───────────────────────────────────
func check_state()
    var c = gfx.camera(0, 0, 10, 0, 0, 0)
    assert(c.px == 0 and c.pz == 10 and c.fovy == 45)
    assert(gfx.camera(0, 0, 10, 0, 0, 0, 30).fovy == 30)
    c.setPos(1, 2, 3).lookAt(4, 5, 6)
    assert(c.px == 1 and c.py == 2 and c.pz == 3 and c.tx == 4 and c.ty == 5 and c.tz == 6)
    c.move(1, 1, 1)
    assert(c.px == 2 and c.tx == 5 and c.ty == 6 and c.tz == 7)
    c.zoom(2)                                          ## twice as far from the target
    assert(near(c.px, -1) and near(c.py, 0) and near(c.pz, 1))
    c.zoom(0)                                          ## not a factor: nothing changes
    assert(near(c.px, -1))
    c.orbit(0, 5)
    assert(near(c.px, 10) and near(c.py, 0) and near(c.pz, 7))
    c.orbit(0, 5, 2)                                   ## the height is relative to the target
    assert(near(c.py, 8))
    var d = c.getViewDir()
    assert(near(d.x * d.x + d.y * d.y + d.z * d.z, 1) and d.x < 0 and d.z == 0)
    ## The three axes are unit vectors, square to one another, whatever the up the camera was given.
    var axes = gfx.camera(0, 0, 10, 0, 0, 0)
    var f = axes.getViewDir()
    var r = axes.getRight()
    var u = axes.getUp()
    assert(near(f.x, 0) and near(f.y, 0) and near(f.z, -1))        ## looking down -Z, up being +Y: right is +X
    assert(near(r.x, 1) and near(r.y, 0) and near(r.z, 0))
    assert(near(u.x, 0) and near(u.y, 1) and near(u.z, 0))
    axes.setPos(3, 4, 5).lookAt(1, 1, 1)
    axes.uy = 0.2                                                   ## an up that is not square to the view
    axes.uz = 1
    f = axes.getViewDir()
    r = axes.getRight()
    u = axes.getUp()
    assert(near(r.x * r.x + r.y * r.y + r.z * r.z, 1) and near(u.x * u.x + u.y * u.y + u.z * u.z, 1))
    assert(near(f.x * r.x + f.y * r.y + f.z * r.z, 0) and near(f.x * u.x + f.y * u.y + f.z * u.z, 0) and near(r.x * u.x + r.y * u.y + r.z * u.z, 0))
    var straight = gfx.camera(0, 5, 0, 0, 0, 0)               ## looking straight down with the default up: no right to find
    var none = straight.getRight()
    assert(none.x == 0 and none.y == 0 and none.z == 0)
    var o = gfx.cameraOrtho(0, 0, 10, 0, 0, 0)
    assert(o.ortho == 1 and o.fovy == 10)
    o.zoom(0.5)                                        ## for an orthographic camera it narrows the view
    assert(o.fovy == 5)
    assert(gfx.cameraOrtho(0, 0, 10, 0, 0, 0, 20).fovy == 20)
    assert(near(gfx.fitDistance(2), 5.226) and near(gfx.fitDistance(2, 30), 7.727))

    ## The classes build the objects the module factories build, with the same checks.
    var cc = Camera(1, 2, 3, 4, 5, 6)
    assert(instanceOf(cc, Camera) and classOf(cc) == classOf(gfx.camera(0, 0, 10, 0, 0, 0)))
    assert(cc.px == 1 and cc.tz == 6 and cc.fovy == 45 and Camera(0, 0, 1, 0, 0, 0, 30).fovy == 30)
    expect(refusal(func() Camera(1, 2) end), "Camera: missing argument")
    var cl = Light("point", 1, 2, 3)
    assert(instanceOf(cl, Light) and classOf(cl) == classOf(gfx.light("dir", 0, -1, 0)) and cl.type == 1 and cl.dz == 3)
    expect(refusal(func() Light("zzz", 0, 0, 1) end), "Light: unknown kind 'zzz' — expected {Q}dir{Q} or {Q}point{Q}")
    var cq = Quat()
    assert(instanceOf(cq, Quat) and classOf(cq) == classOf(gfx.quat()) and cq.w == 1 and cq.x == 0)
    expect(refusal(func() Quat(1, 2, 3, 4) end), "Quat: takes no argument, it is the identity (gfx.quatAxis and gfx.quatEuler build a rotation)")

    var l = gfx.light("dir", 0, -1, 0)
    assert(l.type == 0 and l.dy == -1 and l.enabled == true)
    l.setPos(1, 2, 3)
    assert(l.type == 1 and l.dx == 1)
    l.setDir(0, 0, 1).setColor(Color(1, 0, 0)).enable(false)
    assert(l.type == 0 and l.dz == 1 and l.r == 1 and l.g == 0 and l.enabled == false)
    l.setColor()
    l.enable()
    assert(l.enabled == true)
    ## A refused direction leaves the light as it was.
    expect(refusal(func() l.setDir(0, 0, 0) end), "gfx.light: a directional light needs a direction, and (0, 0, 0) is none")
    assert(l.dz == 1)
    ## A direction too small for a float is no direction either, and the light still keeps its old one.
    expect(refusal(func() l.setDir(1e-46, 0, 0) end), "gfx.light: a directional light needs a direction, and (0, 0, 0) is none")
    assert(l.dz == 1 and l.dx == 0)
    l.enable(true)
    gfx.light("point", 1, 2, 3, Color(0, 1, 0))
    gfx.ambient(Color(0.2, 0.2, 0.2))
    gfx.ambient()
    gfx.tiles()
    gfx.tileAnim()

    expect(refusal(func() gfx.begin3d() end), "gfx.begin3d: expected a camera (gfx.camera)")
    expect(refusal(func() gfx.begin3d(5) end), "gfx.begin3d: expected a camera (gfx.camera)")
    expect(refusal(func() gfx.camera(1, 2) end), "gfx.camera: missing argument")
    expect(refusal(func() gfx.light(5) end), "gfx.light: expected {Q}dir{Q} or {Q}point{Q}")
    expect(refusal(func() gfx.light("spot", 1, 1, 1) end), "gfx.light: unknown kind 'spot' — expected {Q}dir{Q} or {Q}point{Q}")
    expect(refusal(func() gfx.light("dir", 0, 0, 0) end), "gfx.light: a directional light needs a direction, and (0, 0, 0) is none")
    expect(refusal(func() gfx.rotateQuat(5) end), "gfx.rotateQuat: expected a Quat (gfx.quat / quatAxis / quatEuler)")
    expect(refusal(func() gfx.model(5) end), "gfx.model: expected a model name (string)")
    expect(refusal(func() gfx.model("nope.glb") end), "gfx.model: model not found or unreadable: nope.glb")
    expect(refusal(func() gfx.drawModel(5, 0, 0, 0) end), "gfx.drawModel: expected a model handle (gfx.model)")
    expect(refusal(func() gfx.drawModel({}, 0, 0, 0) end), "gfx.drawModel: invalid model handle")
    expect(refusal(func() gfx.modelSize(5) end), "gfx.modelSize: expected a model handle (gfx.model)")
    expect(refusal(func() gfx.modelSize({}) end), "gfx.modelSize: invalid model handle")
    expect(refusal(func() gfx.drawChunk(5) end), "gfx.drawChunk: expected a chunk handle (gfx.endChunk)")
    expect(refusal(func() gfx.drawChunk({}) end), "gfx.drawChunk: invalid chunk handle")
    for name in ["cube", "plane", "cylinder", "cone", "torus", "line3d", "point3d", "terrainHeight", "inFrustum", "fitDistance"] do
        expect(refusal(func() gfx[name]() end), "gfx.{name}: missing argument")
    end
    expect(refusal(func() gfx.sphere(1, 2, 3) end), "gfx.sphere: missing argument")

    var field = {cols: 1, rows: 1, x: 0, z: 0, cell: 1, heights: [0, 0, 0, 0]}
    expect(refusal(func() gfx.heightfield(5) end), "gfx.heightfield: expected a map \{cols, rows, x, z, cell, heights, ...}")
    expect(refusal(func() gfx.heightfield({cols: "a"}) end), "gfx.heightfield: 'cols' must be a number")
    expect(refusal(func() gfx.heightfield({cols: 1, rows: 1, x: 0, z: 0, cell: 1}) end), "gfx.heightfield: 'heights' must be an array")
    expect(refusal(func() gfx.heightfield({cols: 2, rows: 2, x: 0, z: 0, cell: 1, heights: [1, 2]}) end), "gfx.heightfield: 'heights' needs 9 values, got 2")
    expect(refusal(func() gfx.heightfield({cols: 300, rows: 300, x: 0, z: 0, cell: 1, heights: [1]}) end), "gfx.heightfield: at most 65535 vertices per patch (a mesh indexes with 16 bits), got 90601")
    expect(refusal(func() gfx.heightfield({cols: 1, rows: 1, x: 0, z: 0, cell: 1, heights: [0, 0, 0, "a"]}) end), "gfx.heightfield: 'heights' must hold numbers only")
    expect(refusal(func() gfx.heightfield({cols: 1, rows: 1, x: 0, z: 0, cell: 1, heights: [0, 0, 0, 0], slopesX: [0, 0, 0, 0]}) end), "gfx.heightfield: give both slopesX and slopesZ, or neither")
    expect(refusal(func() gfx.heightfield({cols: 1, rows: 1, x: 0, z: 0, cell: 1, heights: [0, 0, 0, 0], colors: [1, 2, 3, 4]}) end), "gfx.heightfield: 'colors' must hold Color objects only")
    expect(refusal(func() gfx.heightfield({cols: 0, rows: 1, x: 0, z: 0, cell: 1, heights: [0, 0]}) end), "gfx.heightfield: cols and rows must be between 1 and 65535 and cell positive")
    expect(refusal(func() gfx.heightfield({cols: 1, rows: 1, x: 0, z: 0, cell: 0, heights: [0, 0, 0, 0]}) end), "gfx.heightfield: cols and rows must be between 1 and 65535 and cell positive")
    var slopes = gfx.heightfield({cols: 1, rows: 1, x: 0, z: 0, cell: 1, heights: [0, 0, 0, 0],
        slopesX: [0, 0, 0, 0], slopesZ: [0, 0, 0, 0]})
    gfx.freeChunk(slopes)
    gfx.freeChunk({})
    gfx.freeChunk(5)
    gfx.freeChunk(slopes)
end

## ── scene A: the solids, unlit ─────────────────────────────────────────────
func scene_a()
    gfx.clear(0, 0, 0)
    gfx.begin3d(cam)
    gfx.noStroke()
    gfx.fill(1, 0, 0)
    gfx.cube(-3, 2, 0, 1.5, 1.5, 1.5)
    gfx.fill(0, 1, 0)
    gfx.sphere(0, 2, 0, 1)
    gfx.fill(0, 0, 1)
    gfx.cylinder(3, 2, 0, 0.7, 1.5)
    gfx.fill(1, 1, 0)
    gfx.cone(-3, -1.5, 0, 0.8, 1.6)
    gfx.fill(1, 0, 1)
    gfx.torus(0, -1.5, 0, 0.8, 0.25)
    gfx.fill(0, 1, 1)
    gfx.push()
    gfx.rotateX(90)
    gfx.plane(3, 0, 1.5, 1.5, 1.5)
    gfx.pop()
    gfx.end3d()
    gfx.screenshot(SHOT + "a.png")
end

func check_a()
    var s = image.load(SHOT + "a.png")
    assert(count(s, 17, 12, 38, 33, 1, 0, 0) > 150)       ## the cube
    assert(count(s, 50, 12, 70, 33, 0, 1, 0) > 150)       ## the sphere
    assert(count(s, 82, 6, 102, 28, 0, 0, 1) > 100)       ## the cylinder
    assert(count(s, 17, 45, 38, 65, 1, 1, 0) > 100)       ## the cone
    assert(count(s, 48, 48, 72, 72, 1, 0, 1) > 100)       ## the torus
    assert(count(s, 82, 50, 102, 70, 0, 1, 1) > 100)      ## the plane, turned to face the camera
    assert(count(s, 0, 0, 119, 89, 1, 1, 1) == 0)
    check_project(s)
    image.unload(s)
end

## gfx.project must agree with what begin3d drew: the centre of each solid projects onto its own colour.
func check_project(s)
    var sx, sy, depth = gfx.project(cam, 0, 0, 0)
    assert(near(sx, 60) and near(sy, 45) and near(depth, 10))         ## the target is at the middle of the screen, 10 away
    for p in [[-3, 2, 0, 1, 0, 0], [0, 2, 0, 0, 1, 0], [3, 2, 0, 0, 0, 1], [-3, -1.5, 0, 1, 1, 0]] do
        var px, py, pd = gfx.project(cam, p[1], p[2], p[3])
        assert(count(s, math.floor(px) - 1, math.floor(py) - 1, math.floor(px) + 1, math.floor(py) + 1, p[4], p[5], p[6]) >= 4,
            "the solid at {p[1]}, {p[2]} is not where gfx.project says: {px}, {py}")
    end
    var bx, by, behind = gfx.project(cam, 0, 0, 20)             ## behind the camera: no place, and a depth that says so
    assert(bx == nil and by == nil and near(behind, -10))
    var ox, oy, od = gfx.project(cam, 0, 0, 10)                 ## at the camera itself: not in front either
    assert(ox == nil and near(od, 0))
    ## The last camera read is kept, and every change to it must show: a field written directly, a method, another camera in between.
    var left = gfx.camera(0, 0, 10, 0, 0, 0)
    var right = gfx.camera(0, 0, 10, 4, 0, 0)
    var lx = gfx.project(left, 0, 0, 0)
    assert(near(lx, 60) and gfx.project(right, 0, 0, 0) < 59 and near(gfx.project(left, 0, 0, 0), 60))
    left.tx = 3
    assert(gfx.project(left, 0, 0, 0) < 59)
    left.lookAt(0, 0, 0)
    assert(near(gfx.project(left, 0, 0, 0), 60))
    for i = 1, 20 do                                                 ## cameras made and dropped: a recycled map must not hit the cache
        var made = gfx.camera(i, 0, 10, i, 0, 0)
        assert(near(gfx.project(made, i, 0, 0), 60))
    end
    expect(refusal(func() gfx.project(5, 0, 0, 0) end), "gfx.project: expected a camera (gfx.camera)")
    expect(refusal(func() gfx.project(cam, 0, 0) end), "gfx.project: missing argument")
end

## ── scene B: lighting ──────────────────────────────────────────────────────
## The light is ONE state for the frame, read when the block ends: setDir between two solids of the same
## block changes both. So each picture gets its own frame.
global lamp = nil

func scene_b(name, dx, dy, dz)
    gfx.clear(0, 0, 0)
    gfx.ambient(0.1)
    if lamp == nil then
        lamp = gfx.light("dir", dx, dy, dz, Color(1, 1, 1))
    else
        lamp.setDir(dx, dy, dz)
    end
    gfx.begin3d(cam)
    gfx.noStroke()
    gfx.fill(1, 1, 1)
    gfx.sphere(0, 0, 0, 4)
    gfx.end3d()
    gfx.screenshot(SHOT + name)
end

func grey(img, x, y)
    var r, g, b, a = image.getPixel(img, x, y)
    return r
end

func check_b_front()
    var s = image.load(SHOT + "b1.png")
    assert(grey(s, 60, 45) > 0.8)                      ## facing the light
    assert(grey(s, 60 + 43, 45) < grey(s, 60, 45) - 0.1)    ## the rim turns away from it
    assert(grey(s, 5, 5) == 0)                         ## no sphere there: nothing is drawn
    image.unload(s)
end

func check_b_side()
    var s = image.load(SHOT + "b2.png")
    assert(grey(s, 60 - 25, 45) > grey(s, 60 + 25, 45) + 0.3)   ## light travelling to +x lights the left side
    image.unload(s)
end

## The highlight is its own setting: a half-bright sphere facing the light, whose centre is where the
## highlight lands. The light is already on (scene B), and the setting is put back to its default after.
func scene_specular(name, strength, shininess)
    gfx.clear(0, 0, 0)
    gfx.ambient(0.1)
    lamp.setDir(0, 0, -1)
    gfx.specular(strength, shininess)
    gfx.begin3d(cam)
    gfx.noStroke()
    gfx.fill(0.5, 0.5, 0.5)
    gfx.sphere(0, 0, 0, 4)
    gfx.end3d()
    gfx.screenshot(SHOT + name)
    gfx.specular()
end

func check_specular()
    var none = image.load(SHOT + "b3.png")
    var soft = image.load(SHOT + "b4.png")
    var tight = image.load(SHOT + "b5.png")
    assert(near(grey(none, 60, 45), 0.55))                      ## the diffuse light alone: 0.5 x (0.1 + 1)
    assert(near(grey(soft, 60, 45), 0.85))                      ## plus the highlight, 0.3 at its peak
    assert(near(grey(tight, 60, 45), 0.85))                     ## as strong at the peak...
    assert(grey(soft, 60 + 8, 45) > grey(tight, 60 + 8, 45) + 0.05)   ## ...but narrower: less of it off the peak
    assert(grey(tight, 60 + 8, 45) >= grey(none, 60 + 8, 45) - 0.01)
    image.unload(none)
    image.unload(soft)
    image.unload(tight)
    expect(refusal(func() gfx.specular(-1) end), "gfx.specular: the strength must be 0 or more")
    expect(refusal(func() gfx.specular(math.sqrt(-1)) end), "gfx.specular: the strength must be 0 or more")
    expect(refusal(func() gfx.specular(1, math.sqrt(-1)) end), "gfx.specular: the shininess must be at least 1")
    expect(refusal(func() gfx.specular(1, 0) end), "gfx.specular: the shininess must be at least 1")
    expect(refusal(func() gfx.specular("a") end), "gfx.specular: argument 1 expected number, got string")
end

## Relief drawn from the texture: a lit sphere wrapped in the two-by-two pattern, whose colours differ in
## brightness, so that the edges between them become steps that the light catches.
func scene_bump(name, height, textured)
    gfx.clear(0, 0, 0)
    gfx.ambient(0.1)
    lamp.setDir(0.5, 0.5, -1)
    gfx.bump(height, height)
    gfx.begin3d(cam)
    gfx.noStroke()
    gfx.fill(1, 1, 1)
    if textured then
        gfx.texture(pattern)
    end
    gfx.sphere(0, 0, 0, 4)
    gfx.noTexture()
    gfx.end3d()
    gfx.screenshot(SHOT + name)
    gfx.bump()
end

func differing(a, b)
    var n = 0
    for y = 20, 70 do
        for x = 25, 95 do
            if math.abs(grey(a, x, y) - grey(b, x, y)) > 0.03 then
                n += 1
            end
        end
    end
    return n
end

func check_bump()
    var flat = image.load(SHOT + "b6.png")
    var bumpy = image.load(SHOT + "b7.png")
    var plain = image.load(SHOT + "b8.png")
    var blank = image.load(SHOT + "b9.png")
    var differ = differing(flat, bumpy)
    assert(differ > 50, "the relief changed {differ} pixels")
    assert(differing(plain, blank) == 0, "the relief marked a surface that has no texture")
    image.unload(plain)
    image.unload(blank)
    assert(grey(flat, 5, 5) == 0 and grey(bumpy, 5, 5) == 0)      ## nothing is drawn off the sphere
    image.unload(flat)
    image.unload(bumpy)
    expect(refusal(func() gfx.bump(-1) end), "gfx.bump: the height must be 0 or more")
    expect(refusal(func() gfx.bump(math.sqrt(-1)) end), "gfx.bump: the height must be 0 or more")
    expect(refusal(func() gfx.bump(1, -1) end), "gfx.bump: the grain must be 0 or more")
    expect(refusal(func() gfx.bump("a") end), "gfx.bump: argument 1 expected number, got string")
end

## ── scene C: textures, flat ────────────────────────────────────────────────
func scene_c()
    lamp.enable(false)
    gfx.ambient(1)                                ## light off, ambient full: the colours as painted
    gfx.clear(0, 0, 0)
    gfx.begin3d(cam)
    gfx.noStroke()
    gfx.fill(1, 1, 1)
    gfx.texture(pattern)
    gfx.push()
    gfx.rotateX(90)
    gfx.plane(-3, 0, 0, 4, 4)                     ## a textured plane facing the camera
    gfx.pop()
    gfx.noTexture()
    gfx.fill(1, 0, 0)
    gfx.cube(3, 0, 0, 3, 3, 3)                    ## untextured again
    gfx.end3d()
    gfx.screenshot(SHOT + "c.png")
end

func check_c()
    var s = image.load(SHOT + "c.png")
    ## the four colours of the pattern are all there, each over a quarter of the plane
    assert(count(s, 8, 20, 62, 70, 1, 0, 0) > 100)
    assert(count(s, 8, 20, 62, 70, 0, 1, 0) > 100)
    assert(count(s, 8, 20, 62, 70, 0, 0, 1) > 100)
    assert(count(s, 8, 20, 62, 70, 1, 1, 0) > 100)
    assert(count(s, 75, 20, 115, 70, 1, 0, 0) > 200)
    assert(count(s, 75, 20, 115, 70, 0, 1, 0) == 0)
    image.unload(s)
end

## ── scene D: atlas tiles, chunks, transparency and a terrain mesh ─────────
global cam2 = nil

func scene_d_setup()
    cam2 = gfx.camera(0, 6, 8, 0, 0, 0)
    gfx.tileset(atlas, 2, 1)
    gfx.tiles(0, 1, 0)                            ## top: tile 0 (red), sides: tile 1 (green)
    gfx.beginChunk()
    gfx.fill(1, 1, 1)
    gfx.cube(-2, 1, 0, 2, 2, 2)
    gfx.tile(1)
    gfx.cube(2, 1, 0, 2, 2, 2)                    ## the one tile everywhere: green
    var block = gfx.endChunk()
    chunk = block
    gfx.beginChunk()
    gfx.fill(0, 0, 1, 0.5)
    gfx.plane(0, 0.2, 3, 6, 2)
    water = gfx.endChunk()
    ground = gfx.heightfield({cols: 2, rows: 2, x: -4, z: -4, cell: 4,
        heights: [0, 0, 0, 0, 0.5, 0, 0, 0, 0],
        colors: [Color(0.5, 0.5, 0.5), Color(0.5, 0.5, 0.5), Color(0.5, 0.5, 0.5),
                 Color(0.5, 0.5, 0.5), Color(1, 1, 1), Color(0.5, 0.5, 0.5),
                 Color(0.5, 0.5, 0.5), Color(0.5, 0.5, 0.5), Color(0.5, 0.5, 0.5)]})
end

func scene_d()
    gfx.clear(0, 0, 0)
    gfx.begin3d(cam2)
    ## A chunk is drawn with the atlas bound at that moment as its texture: the terrain and the water carry
    ## no tile, so they are drawn with no atlas (a handle without an id unbinds it).
    gfx.tileset({}, 1, 1)
    gfx.drawChunk(ground)
    gfx.tileset(atlas, 2, 1)
    gfx.drawChunk(chunk)
    gfx.tileset({}, 1, 1)
    gfx.drawChunkAlpha(water)
    gfx.end3d()
    gfx.screenshot(SHOT + "d.png")
end

func check_d()
    assert(chunk.count == 2 and chunk.wcount == 0 and chunk.idw == 0)
    assert(water.wcount == 1 and water.count == 0 and water.id <> nil)
    assert(near(gfx.terrainHeight(0, 0), 0.5))
    assert(near(gfx.terrainHeight(-4, -4), 0))
    assert(gfx.terrainHeight(50, 50) == nil)
    assert(ground.r > 0 and ground.x == 0 and ground.z == 0)
    var s = image.load(SHOT + "d.png")
    assert(count(s, 0, 0, 119, 89, 1, 0, 0) > 50)      ## the tops of the first cube: tile 0
    assert(count(s, 0, 0, 119, 89, 0, 1, 0) > 100)     ## the sides: tile 1
    assert(count(s, 0, 0, 119, 89, 0.5, 0.5, 0.5) > 100)   ## the terrain
    image.unload(s)
end

## ── scene E: models, wires, transforms and quaternions ────────────────────
global cube_model = nil

func scene_e()
    gfx.clear(0, 0, 0)
    cube_model = gfx.model(MODELS + "rubik.glb")
    var size = gfx.modelSize(cube_model)
    assert(size.w > 0 and size.h > 0 and size.d > 0 and size.radius > size.w / 2)
    var eye = gfx.camera(size.cx, size.cy, size.cz + gfx.fitDistance(size.radius), size.cx, size.cy, size.cz)
    gfx.begin3d(eye)
    gfx.fill(1, 1, 1)
    gfx.noStroke()
    gfx.drawModel(cube_model, 0, 0, 0, 1)
    gfx.drawModel(gfx.model(MODELS + "rubik.glb"), 0, 0, 0)
    gfx.end3d()
    gfx.screenshot(SHOT + "e.png")
end

func check_e()
    var s = image.load(SHOT + "e.png")
    assert(count(s, 0, 0, 119, 89, 0, 0, 0) < 120 * 90 - 1500)   ## the model covers a good part of the picture
    image.unload(s)
end

## Wires use the stroke, solids the fill; the transforms move a solid as the 2D ones move a rectangle.
func scene_f()
    gfx.clear(0, 0, 0)
    gfx.begin3d(cam)
    gfx.stroke(1, 0, 0)
    gfx.line3d(-5, -3, 0, -1, -3, 0)
    gfx.stroke(0, 1, 0)
    gfx.strokeSize(20)                            ## a point is a sphere of strokeSize * 0.015, a line a tube of * 0.02
    gfx.point3d(0, -3, 0)
    gfx.strokeSize(2)
    gfx.grid(4, 1)                                ## drawn in its own grey, edge-on from here: one line
    gfx.noStroke()
    gfx.fill(1, 1, 0)
    gfx.push()
    gfx.translate(3, 2, 0)
    gfx.rotateY(45)
    gfx.rotateZ(10)
    gfx.rotate(10, 0, 1, 0)
    gfx.scale(1, 2, 1)
    gfx.cube(0, 0, 0, 1, 1, 1)
    gfx.pop()
    gfx.fill(0, 1, 1)
    gfx.push()
    gfx.translate(-3, 2, 0)
    gfx.rotateQuat(gfx.quatAxis(0, 0, 1, 45))
    gfx.cube(0, 0, 0, 2, 0.5, 0.5)
    gfx.pop()
    gfx.end3d()
    assert(gfx.inFrustum(0, 0, 0) == true)
    assert(gfx.inFrustum(0, 0, 0, 1) == true)
    assert(gfx.inFrustum(500, 0, 0) == false)
    assert(gfx.inFrustum(0, 0, 500, 2) == false)
    gfx.screenshot(SHOT + "f.png")
end

func check_f()
    var s = image.load(SHOT + "f.png")
    assert(count(s, 0, 74, 50, 80, 1, 0, 0) > 30)      ## the red line
    assert(count(s, 54, 72, 66, 84, 0, 1, 0) > 10)     ## the point
    assert(count(s, 30, 43, 90, 47, 0.75, 0.75, 0.75) > 30)   ## the grid
    assert(count(s, 80, 0, 115, 40, 1, 1, 0) > 100)    ## the transformed cube, tall and turned
    assert(count(s, 10, 0, 45, 40, 0, 1, 1) > 100)     ## the cube turned by the quaternion
    image.unload(s)
end

## ── scene G: wires, an animated tile, a chunk slot reused, a block left open ─
func scene_g()
    gfx.clear(0, 0, 0)
    gfx.begin3d(cam)
    gfx.noFill()
    gfx.stroke(1, 1, 1)
    gfx.cube(-3, 2, 0, 1.5, 1.5, 1.5)
    gfx.sphere(0, 2, 0, 1)
    gfx.cylinder(3, 2, 0, 0.7, 1.5)
    gfx.cone(-3, -1.5, 0, 0.8, 1.6)
    gfx.torus(0, -1.5, 0, 0.8, 0.25)
    gfx.plane(3, -1.5, 0, 1.5, 1.5)
    gfx.tileAnim(0, 0.2, 2, 4, 0.05)
    gfx.tileAnim(-1)
    gfx.freeChunk(chunk)                          ## its slot is the first free one when the next chunk is placed
    gfx.beginChunk()
    gfx.noStroke()
    gfx.fill(0, 1, 0)
    gfx.cube(0, 0, 0, 1, 1, 1)
    var again = gfx.endChunk()
    assert(again.count == 1)
    ## No end3d(): the engine closes the block at the end of draw().
    gfx.screenshot(SHOT + "g.png")
end

func check_g()
    var s = image.load(SHOT + "g.png")
    assert(count(s, 0, 0, 119, 89, 1, 1, 1) > 100)     ## the wires
    assert(count(s, 0, 0, 119, 89, 0, 0, 0) > 120 * 90 - 1500)
    image.unload(s)
end

func draw()
    frames += 1
    if frames == 1 then
        scene_a()
    elseif frames == 2 then
        check_a()
        scene_b("b1.png", 0, 0, -1)
    elseif frames == 3 then
        check_b_front()
        scene_b("b2.png", 1, 0, 0)
    elseif frames == 4 then
        check_b_side()
        scene_specular("b3.png", 0, 16)
    elseif frames == 5 then
        scene_specular("b4.png", 0.3, 16)
    elseif frames == 6 then
        scene_specular("b5.png", 0.3, 64)
    elseif frames == 7 then
        check_specular()
        scene_bump("b6.png", 0, true)
    elseif frames == 8 then
        scene_bump("b7.png", 3, true)
    elseif frames == 9 then
        scene_bump("b8.png", 0, false)
    elseif frames == 10 then
        scene_bump("b9.png", 3, false)
    elseif frames == 11 then
        check_bump()
        scene_c()
    elseif frames == 12 then
        check_c()
        scene_d_setup()
        scene_d()
    elseif frames == 13 then
        check_d()
        scene_e()
    elseif frames == 14 then
        check_e()
        scene_f()
    elseif frames == 15 then
        check_f()
        scene_g()
    elseif frames == 16 then
        check_g()
        check_state()                                  ## last: creating a light turns the lighting on for good
        gfx.quit()
    end
end
