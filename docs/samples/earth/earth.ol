## The Earth seen from space: a globe turning on its tilted axis, lit by the Sun, with its clouds, the
## glow of its atmosphere and a sky of stars. Everything is computed — the planet's map is not a
## picture but a noise (earth_map.ol), and where the Sun stands comes from the astronomy of the real
## Earth (astro.ol), so the day, the night and the seasons are the right ones for the date shown.
##
## Drag with the mouse or a finger to move around the Earth; the wheel or a pinch zooms; a double
## click puts the view back. The arrows move the view too, and space stops the time. The menu sets how
## fast time runs — a month a second shows the seasons: the day side leans north in summer, south in
## winter — and what is drawn.
##
## The Sun is fixed in space and the camera goes around the globe, not the other way round: it is the
## only way for the light to stay where the Sun is while the view turns.

import "astro.ol"
import "earth_map.ol"
import "../lib/trackball.ol"

const GLOBE = 1.0          ## the radius of the globe: the unit of the scene
const CLOUD_SHELL = 1.012  ## the cloud layer floats a little above the ground
const FOV = 45             ## the camera's vertical field of view, in degrees
const STARS = 2500

## The texture of the ground runs from pole to pole in x and round the globe in y: the mesh of a
## sphere takes its first coordinate along the meridians. The clouds get a rougher one, being soft.
const GROUND_U = 512
const GROUND_V = 1024
const CLOUD_U = 256
const CLOUD_V = 512
const ROWS_PER_FRAME = 24   ## texture rows computed in each frame while the planet forms

## How fast time runs: a label for the menu and a rate in simulated DAYS per real second.
global speeds = [
    {label: "Real time",    rate: 1 / 86400},
    {label: "1 hour / s",   rate: 1 / 24},
    {label: "6 hours / s",  rate: 0.25},
    {label: "1 day / s",    rate: 1},
    {label: "10 days / s",  rate: 10},
    {label: "60 days / s",  rate: 60}
]
global speedLabels = []
global config = {speed: nil, clouds: true, atmosphere: true, stars: true, axis: false, paused: false}

global days = 0.0            ## the simulated time, in days since J2000 (see astro.ol)
global ball = Trackball()
global cam = graphics.camera(0, 0, 4, 0, 0, 0, FOV)
global sun = nil             ## the light
global zoom = {factor: 1.0, min: 0.45, max: 4.0, wheelStep: 0.1}
global ground = nil          ## the textures
global cloudTex = nil
global build = {texture: "ground", row: 0}   ## where the computation of the textures has got to
global stars = []            ## unit vectors then brightnesses: x, y, z, b, x, y, z, b…
global view = {px: 0, py: 0, pz: 4, ux: 0, uy: 1, uz: 0, dist: 4}   ## the camera as the last frame placed it

## ── the planet is computed a few rows at a time ───────────────────────────────────────────────

func paintGround(tex, x, y, lat, lon)
    var r, g, b = earthColor(lat, lon)
    image.setPixel(tex, x, y, r, g, b, 1)
end

func paintClouds(tex, x, y, lat, lon)
    image.setPixel(tex, x, y, 1, 1, 1, cloudDensity(lat, lon) * 0.9)
end

## Fills `count` rows of a texture from `row` on, and says which row is next. x is the latitude
## axis (0 at the north pole), y the longitude (west to east): the layout the sphere's mesh reads.
func fillRows(tex, width, height, row, count, paint)
    var last = math.min(row + count, height) - 1
    image.beginPixels(tex)
    for y = row, last do
        var lon = (y + 0.5) / height * 360 - 180
        for x = 0, width - 1 do
            paint(tex, x, y, 90 - (x + 0.5) / width * 180, lon)
        end
    end
    image.endPixels(tex)
    return last + 1
end

func buildStep()
    if build.texture == "ground" then
        build.row = fillRows(ground, GROUND_U, GROUND_V, build.row, ROWS_PER_FRAME, paintGround)
        if build.row >= GROUND_V then
            build.texture = "clouds"
            build.row = 0
        end
    elseif build.texture == "clouds" then
        build.row = fillRows(cloudTex, CLOUD_U, CLOUD_V, build.row, ROWS_PER_FRAME, paintClouds)
        if build.row >= CLOUD_V then
            build.texture = "done"
        end
    end
end

## How far the computation has got, from 0 to 1, over the two textures.
func buildProgress()
    var total = GROUND_V + CLOUD_V
    if build.texture == "ground" then
        return build.row / total
    elseif build.texture == "clouds" then
        return (GROUND_V + build.row) / total
    end
    return 1
end

## ── the view ──────────────────────────────────────────────────────────────────────────────────

## The camera starts off to one side of the Sun, a little above the ecliptic: the day side, the
## night side and the line between them all show.
func resetView()
    zoom.factor = 1.0
    var lx, ly, lz = sunLightDirection(days)
    var sunAzimuth = math.deg(math.atan2(-lx, -lz))        ## where the Sun is, round the vertical axis
    var camera = graphics.quatAxis(0, 1, 0, sunAzimuth + 55).mul(graphics.quatAxis(1, 0, 0, -18))
    ball.reset()
    ball.q = camera.inverse()
end

func placeCamera()
    var look = ball.orient().inverse()
    var dist = graphics.fitDistance(GLOBE, FOV) * 1.15 / zoom.factor
    var eye = look.rotateVec(0, 0, dist)      ## rotateVec answers an array [x, y, z]
    var up = look.rotateVec(0, 1, 0)
    cam.setPos(eye[1], eye[2], eye[3])
    cam.lookAt(0, 0, 0)
    cam.ux = up[1]
    cam.uy = up[2]
    cam.uz = up[3]
    view = {px: eye[1], py: eye[2], pz: eye[3], ux: up[1], uy: up[2], uz: up[3], dist: dist}
end

func zoomBy(factor)
    zoom.factor = math.max(zoom.min, math.min(zoom.max, zoom.factor * factor))
end

func mouse.pressed(x, y)
    ball.press(x, y)
end

## A pinch is not a drag: with two fingers down the system still emulates the mouse with one of them.
func mouse.moved(x, y)
    if touch.count() > 1 then return end
    ball.move(x, y)
end

func mouse.released(x, y)
    ball.release()
end

func mouse.scrolled(x, y, dx, dy)
    zoomBy(1.0 + dy * zoom.wheelStep)
end

func touch.pinch(scale, cx, cy)
    zoomBy(scale)
end

func mouse.doubleClicked(x, y)
    resetView()
end

func keyboard.keypressed(key)
    if key == "space" then
        config.paused = not config.paused
    elseif key == "return" then
        resetView()
    end
end

## ── the sky ───────────────────────────────────────────────────────────────────────────────────

func seedStars()
    math.seed(11)
    for i = 1, STARS do
        var z = math.rand(-1, 1)
        var a = math.rand(0, math.TAU)
        var r = math.sqrt(1 - z * z)
        stars.push(r * math.cos(a))
        stars.push(z)
        stars.push(r * math.sin(a))
        var b = math.rand(0.2, 1.0)
        stars.push(b * b)
    end
end

## The camera's own axes: where it looks (f), what is up on the screen (u) and what is to the right (r).
func cameraAxes()
    var d = view.dist
    var fx = -view.px / d
    var fy = -view.py / d
    var fz = -view.pz / d
    var ux = view.ux
    var uy = view.uy
    var uz = view.uz
    return fx, fy, fz, fy * uz - fz * uy, fz * ux - fx * uz, fx * uy - fy * ux, ux, uy, uz
end

## The stars are fixed in space, so they are projected by hand, with the same perspective as the
## camera's: a point of the sky straight ahead lands at the centre, and the rest goes out from there.
func drawStars()
    var fx, fy, fz, rx, ry, rz, ux, uy, uz = cameraAxes()
    var focal = (H / 2) / math.tan(math.rad(FOV / 2))
    graphics.noStroke()
    for i = 1, #stars, 4 do
        var x = stars[i]
        var y = stars[i + 1]
        var z = stars[i + 2]
        var ahead = x * fx + y * fy + z * fz
        if ahead > 0.05 then
            var sx = CX + (x * rx + y * ry + z * rz) / ahead * focal
            var sy = CY - (x * ux + y * uy + z * uz) / ahead * focal
            if sx >= 0 and sx < W and sy >= 0 and sy < H then
                var b = stars[i + 3]
                graphics.fill(0.85 * b, 0.9 * b, b)
                if b > 0.6 then
                    graphics.rect(sx, sy, 2, 2)
                else
                    graphics.rect(sx, sy, 1, 1)
                end
            end
        end
    end
end

## The glow of the atmosphere: rings round the globe, brighter on the side the Sun lights, drawn BEFORE
## the globe so that the globe covers their inner half and only the halo outside remains.
func drawHalo()
    var fx, fy, fz, rx, ry, rz, ux, uy, uz = cameraAxes()
    var focal = (H / 2) / math.tan(math.rad(FOV / 2))
    var radius = focal * GLOBE / math.sqrt(view.dist * view.dist - GLOBE * GLOBE)
    var lx, ly, lz = sunLightDirection(days)
    var sx = -lx
    var sy = -ly
    var sz = -lz
    var towardSun = math.deg(math.atan2(sx * ux + sy * uy + sz * uz, sx * rx + sy * ry + sz * rz))   ## on the screen
    var behind = math.max(0, sx * fx + sy * fy + sz * fz)     ## the Sun behind the globe: the whole rim glows
    graphics.noFill()
    for k = 1, 5 do
        var ring = radius * (1 + 0.012 * k)
        var fade = 0.5 / k
        graphics.stroke(0.25, 0.5, 1.0, fade * (0.25 + 0.75 * behind))
        graphics.strokeSize(radius * 0.012 + 1)
        graphics.circle(CX, CY, ring)
        graphics.stroke(0.4, 0.65, 1.0, fade * 0.8)
        graphics.arc(CX, CY, ring * 2, ring * 2, -towardSun - 75, -towardSun + 75)
    end
end

## ── the program ───────────────────────────────────────────────────────────────────────────────

func setup()
    graphics.canvas(W, H, "Earth from space")
    for i, s in speeds do
        speedLabels.push(s.label)
    end
    config.speed = speedLabels[2]
    days = unixToDays(time())
    ground = image.create(GROUND_U, GROUND_V)
    cloudTex = image.create(CLOUD_U, CLOUD_V)
    math.noiseSeed(MAP_SEED)
    seedStars()

    var lx, ly, lz = sunLightDirection(days)
    sun = graphics.light("dir", lx, ly, lz)
    graphics.ambient(0.09)

    var menu = ui.menu("Earth")
    menu.list("Time", speedLabels, ref config.speed)
    menu.button("Now", func() days = unixToDays(time()) end)
    menu.checkbox("Clouds", ref config.clouds)
    menu.checkbox("Atmosphere", ref config.atmosphere)
    menu.checkbox("Stars", ref config.stars)
    menu.checkbox("Axis and equator", ref config.axis)
    menu.button("Reset view", resetView)
    ui.show(menu)
    resetView()
end

func speedRate()
    for i, s in speeds do
        if s.label == config.speed then
            return s.rate
        end
    end
    return 0
end

func update(dt)
    if build.texture <> "done" then
        buildStep()
    end
    if not config.paused then
        days += dt * speedRate()
    end
    var dx = 0
    var dy = 0
    if keyboard.isDown("left") then dx -= 1 end
    if keyboard.isDown("right") then dx += 1 end
    if keyboard.isDown("up") then dy -= 1 end
    if keyboard.isDown("down") then dy += 1 end
    if dx <> 0 or dy <> 0 then
        ball.spin(dx * 60 * dt, dy * 60 * dt)
    end
end

## The equator and the axis, drawn with the globe's own tilt, to make the lean of the planet visible.
func drawAxis()
    graphics.noFill()
    graphics.stroke(1, 0.85, 0.3)
    graphics.strokeSize(0.4)                   ## a 3D line is a tube of strokeSize * 0.02 units: this one is thin
    graphics.line3d(0, -1.5, 0, 0, 1.5, 0)
    var steps = 72
    for i = 0, steps - 1 do
        var a0 = math.TAU * i / steps
        var a1 = math.TAU * (i + 1) / steps
        graphics.line3d(1.01 * math.cos(a0), 0, 1.01 * math.sin(a0), 1.01 * math.cos(a1), 0, 1.01 * math.sin(a1))
    end
end

func drawGlobe()
    var lx, ly, lz = sunLightDirection(days)
    sun.setDir(lx, ly, lz)
    graphics.segments(96)
    graphics.begin3d(cam)
    graphics.noStroke()
    graphics.push()
    graphics.rotateX(-OBLIQUITY)                          ## the tilt of the axis, fixed in space
    graphics.rotateY(greenwichAngle(days) + 180)          ## the turn of the globe: the prime meridian is local −X
    graphics.rotateX(-90)                                 ## the sphere's mesh has its poles on Z: stand it up
    graphics.fill(1, 1, 1)
    graphics.texture(ground)
    graphics.sphere(0, 0, 0, GLOBE)
    if config.clouds then
        graphics.texture(cloudTex)
        graphics.sphere(0, 0, 0, GLOBE * CLOUD_SHELL)
    end
    graphics.noTexture()
    graphics.pop()
    if config.axis then
        graphics.push()
        graphics.rotateX(-OBLIQUITY)
        drawAxis()
        graphics.pop()
    end
    graphics.end3d()
end

func pad(n)
    if n < 10 then
        return "0{n}"
    end
    return "{n}"
end

func degrees(value, positive, negative)
    var hemisphere = positive
    if value < 0 then
        hemisphere = negative
    end
    return "{math.abs(value):.1f}° {hemisphere}"
end

func drawText()
    var t = date.utc(daysToUnix(days))
    var lat, lon = subsolarPoint(days)
    graphics.fill(1, 1, 1)
    graphics.stroke(1, 1, 1)
    graphics.fontSize(16)
    graphics.text("{t.year}-{pad(t.month)}-{pad(t.day)}  {pad(t.hour)}:{pad(t.minute)} UTC", 12, 12)
    graphics.fontSize(13)
    graphics.stroke(0.75, 0.85, 1)
    var line = graphics.fontSize() * 1.5
    graphics.text("The Sun is overhead at {degrees(lat, "N", "S")}, {degrees(lon, "E", "W")}", 12, 12 + line * 1.4)
    if build.texture <> "done" then
        graphics.text("Forming the planet... {math.floor(buildProgress() * 100)} %", 12, 12 + line * 2.4)
    end
    graphics.stroke(0.6, 0.65, 0.75)
    graphics.text("drag: move around   wheel or pinch: zoom   space: stop time   return: reset", 12, H - 22)
end

func draw()
    graphics.clear(0.005, 0.007, 0.02)
    placeCamera()
    if config.stars then
        drawStars()
    end
    if config.atmosphere then
        drawHalo()
    end
    drawGlobe()
    drawText()
end
