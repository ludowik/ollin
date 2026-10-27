## The Earth seen from space: a globe turning on its tilted axis, lit by the Sun, with its clouds, the
## glow of its atmosphere and a sky of stars. The continents are the real ones (earth_day.jpg, NASA's
## Blue Marble) and so are the clouds, a snapshot of a real cloud cover, and the lights of the cities
## that come on over the night side — see tools/convert_earth_textures.py for where they come from.
## Where the Sun stands is computed from the astronomy of the real Earth (astro.ol), so the day, the
## night and the seasons are the right ones for the date shown. The pictures are what is fixed: the snow
## is the snow of a northern winter, and the clouds do not move with the weather.
##
## Drag with the mouse or a finger to move around the Earth; the wheel or a pinch zooms; a double
## click puts the view back. The arrows move the view too, and space stops the time. The menu sets how
## fast time runs — a month a second shows the seasons: the day side leans north in summer, south in
## winter — and what is drawn.
##
## The Sun is fixed in space and the camera goes around the globe, not the other way round: it is the
## only way for the light to stay where the Sun is while the view turns.

import "astro.ol"
import "../lib/trackball.ol"

const GLOBE = 1.0          ## the radius of the globe: the unit of the scene
const CLOUD_SHELL = 1.012  ## the cloud layer floats a little above the ground
const GLINT_SHELL = 1.002  ## the reflection of the Sun lies on the sea, under the lights and the clouds
const LIGHTS_SHELL = 1.003 ## the lights of the cities lie between the two, so the clouds hide them
const GLINT_STRENGTH = 0.45  ## how bright the Sun's reflection is on the sea, and how wide: a rough sea
const GLINT_SHININESS = 60
const AMBIENT = 0.09       ## what the night side keeps of the light: a little earthshine
const FOV = 45             ## the camera's vertical field of view, in degrees
const STARS = 2500
const KEY_PIXELS_PER_SECOND = 400   ## the arrows move the view like a drag of this speed

## The pictures are laid out the way the sphere's mesh reads them: the latitude along x (0 at the
## north pole), the longitude along y, west to east — the opposite of the usual equirectangular map,
## which the converter turns once so that nothing has to be turned here.
const GROUND_FILE = "earth_day.jpg"
const CLOUDS_FILE = "earth_clouds.png"
const NIGHT_FILE = "earth_night.jpg"      ## the lights of the cities, on black
const WATER_FILE = "earth_water.png"      ## the open water, as the alpha of a black picture

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
global config = {speed: nil, clouds: true, lights: true, atmosphere: true, stars: true, axis: false, paused: false}

global days = 0.0            ## the simulated time, in days since J2000 (see astro.ol)
global ball = Trackball()
global cam = graphics.camera(0, 0, 4, 0, 0, 0, FOV)
global sun = nil             ## the light
global zoom = {factor: 1.0, min: 0.45, max: 2.2, wheelStep: 0.1}
global ground = nil          ## the textures
global cloudTex = nil
global nightTex = nil
global waterTex = nil
global stars = []            ## unit vectors then brightnesses: x, y, z, b, x, y, z, b…
global view = {px: 0, py: 0, pz: 4, ux: 0, uy: 1, uz: 0, dist: 4}   ## the camera as the last frame placed it

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

## How far the globe turns for a pixel of drag, in degrees: the point of the surface under the finger
## follows it. The same pixel is a far smaller angle when the camera is close, the globe being so much
## bigger on the screen, so a fixed sensitivity made a close view race away from the finger.
func degreesPerPixel()
    var dist = graphics.fitDistance(GLOBE, FOV) * 1.15 / zoom.factor
    var focal = (H / 2) / math.tan(math.rad(FOV / 2))
    return math.deg((dist - GLOBE) / (GLOBE * focal))
end

func mouse.pressed(x, y)
    ball.press(x, y)
end

## A pinch is not a drag: with two fingers down the system still emulates the mouse with one of them.
func mouse.moved(x, y)
    if touch.count() > 1 then return end
    ball.sensitivity = degreesPerPixel()
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

func smooth(lo, hi, x)
    var t = math.clamp((x - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)
end

## The glow of the atmosphere: a few thin rings round the globe, drawn BEFORE the globe so that it covers
## their inner half. The air only glows where the Sun lights it: bright on the day side, warm towards
## the terminator, nothing on the night side — except when the Sun is behind the globe, which lights the
## whole rim from behind.
func drawHalo()
    var fx, fy, fz, rx, ry, rz, ux, uy, uz = cameraAxes()
    var focal = (H / 2) / math.tan(math.rad(FOV / 2))
    var radius = focal * GLOBE / math.sqrt(view.dist * view.dist - GLOBE * GLOBE)
    var lx, ly, lz = sunLightDirection(days)
    var sx = -lx
    var sy = -ly
    var sz = -lz
    var behind = math.max(0, sx * fx + sy * fy + sz * fz)     ## 1: the Sun is straight behind the globe
    var steps = 120
    var thickness = radius * 0.006 + 1
    graphics.noFill()
    graphics.strokeSize(thickness)
    for k = 0, 5 do
        var ring = radius * (1 + 0.004 * k) + thickness / 2
        var fade = (1 - k / 6) * (1 - k / 6)
        var lastX = 0
        var lastY = 0
        for i = 0, steps do
            var a = i / steps * math.TAU
            var c = math.cos(a)
            var s = math.sin(a)
            var px = CX + c * ring
            var py = CY - s * ring
            if i > 0 then
                var lit = (c * (sx * rx + sy * ry + sz * rz) + s * (sx * ux + sy * uy + sz * uz))   ## the Sun, along this part of the rim
                var glow = math.max(smooth(-0.25, 0.55, lit), behind * behind * 0.9)
                var warm = math.max(0, 1 - math.abs(lit - 0.02) / 0.2) * (1 - behind)
                if glow > 0.01 then
                    graphics.stroke(0.3 + 0.7 * warm, 0.6 - 0.1 * warm, 1.0 - 0.7 * warm, 0.55 * fade * glow)
                    graphics.line(lastX, lastY, px, py)
                end
            end
            lastX = px
            lastY = py
        end
    end
end

## ── the program ───────────────────────────────────────────────────────────────────────────────

func setup()
    graphics.canvas(W, H, "Earth from space")
    for i, s in speeds do
        speedLabels.push(s.label)
    end
    config.speed = speedLabels[1]
    days = unixToDays(time())
    ground = image.load(GROUND_FILE)
    cloudTex = image.load(CLOUDS_FILE)
    nightTex = image.load(NIGHT_FILE)
    waterTex = image.load(WATER_FILE)
    for tex in [ground, cloudTex, nightTex, waterTex] do
        image.filter(tex, "mipmap")    ## the default would show the pixels squared when close and sparkling from afar
    end
    seedStars()

    var lx, ly, lz = sunLightDirection(days)
    sun = graphics.light("dir", lx, ly, lz)
    graphics.ambient(AMBIENT)
    graphics.specular(0)    ## the land does not shine: only the layer of the sea turns the highlight on

    var menu = ui.menu("Earth")
    menu.list("Time", speedLabels, ref config.speed)
    menu.button("Now", func() days = unixToDays(time()) end)
    menu.checkbox("Clouds", ref config.clouds)
    menu.checkbox("City lights", ref config.lights)
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
        var speed = KEY_PIXELS_PER_SECOND * degreesPerPixel() * dt
        ball.spin(dx * speed, dy * speed)
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

## The globe takes its place in space: tilted, turned, and stood up on its poles.
func orientGlobe()
    graphics.rotateX(-OBLIQUITY)                          ## the tilt of the axis, fixed in space
    graphics.rotateY(greenwichAngle(days) + 180)          ## the turn of the globe: the prime meridian is local −X
    graphics.rotateX(-90)                                 ## the sphere's mesh has its poles on Z: stand it up
end

## Four layers, one block each, because the light and the highlight are ONE setting for a whole block.
## The ground and the clouds are lit by the Sun, and the ground does not shine. The reflection of the Sun
## is its own layer: a black picture whose alpha is the open water, drawn with the engine's highlight on
## and added, so that what is added is the highlight where there is water and nothing on the land. The
## lights of the cities are lit by a sun on the other side of the Earth, and added: where the Sun shines
## the night side's light is nil, so nothing is added there, and it grows towards midnight. The clouds
## come last, so they cover the reflection and the lights they float above.
func drawGlobe()
    var lx, ly, lz = sunLightDirection(days)
    sun.setDir(lx, ly, lz)
    graphics.segments(96)
    graphics.begin3d(cam)
    graphics.noStroke()
    graphics.push()
    orientGlobe()
    graphics.fill(1, 1, 1)
    graphics.texture(ground)
    graphics.sphere(0, 0, 0, GLOBE)
    graphics.noTexture()
    graphics.pop()
    graphics.end3d()

    graphics.specular(GLINT_STRENGTH, GLINT_SHININESS)
    graphics.ambient(0)
    graphics.blendMode("add")
    graphics.begin3d(cam)
    graphics.noStroke()
    graphics.push()
    orientGlobe()
    graphics.fill(1, 1, 1)
    graphics.texture(waterTex)
    graphics.sphere(0, 0, 0, GLOBE * GLINT_SHELL)
    graphics.noTexture()
    graphics.pop()
    graphics.end3d()
    graphics.blendMode("alpha")
    graphics.specular(0)
    graphics.ambient(AMBIENT)

    if config.lights then
        sun.setDir(-lx, -ly, -lz)
        graphics.ambient(0)
        graphics.blendMode("add")
        graphics.begin3d(cam)
        graphics.noStroke()
        graphics.push()
        orientGlobe()
        graphics.fill(1, 1, 1)
        graphics.texture(nightTex)
        graphics.sphere(0, 0, 0, GLOBE * LIGHTS_SHELL)
        graphics.noTexture()
        graphics.pop()
        graphics.end3d()
        graphics.blendMode("alpha")
        graphics.ambient(AMBIENT)
        sun.setDir(lx, ly, lz)
    end

    graphics.begin3d(cam)
    graphics.noStroke()
    if config.clouds then
        graphics.push()
        orientGlobe()
        graphics.fill(1, 1, 1)
        graphics.texture(cloudTex)
        graphics.sphere(0, 0, 0, GLOBE * CLOUD_SHELL)
        graphics.noTexture()
        graphics.pop()
    end
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
