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
const LIGHTS_SHELL = 1.003 ## the lights of the cities lie just above the ground, so the clouds hide them
const RELIEF = 0.004       ## how high the brightest ground stands, in globe radii: the map's own brightness is the height
const GRAIN = 0.0003       ## the fine grain that fills a close view with more than the map holds
const AMBIENT = 0.09       ## what the night side keeps of the light: a little earthshine
const FOV = 45             ## the camera's vertical field of view, in degrees
const STARS = 2500
const HALO_STEPS = 120     ## the segments of each ring of the halo
const KEY_PIXELS_PER_SECOND = 400   ## the arrows move the view like a drag of this speed

## The pictures are laid out the way the sphere's mesh reads them: the latitude along x (0 at the
## north pole), the longitude along y, west to east — the opposite of the usual equirectangular map,
## which the converter turns once so that nothing has to be turned here.
const GROUND_FILE = "earth_day.jpg"
const CLOUDS_FILE = "earth_clouds.png"
const NIGHT_FILE = "earth_night.jpg"      ## the lights of the cities, on black

## How fast time runs: a label for the menu and a rate in simulated DAYS per real second.
global speeds = [
    {label: "Real time",    rate: 1 / 86400},
    {label: "1 hour / s",   rate: 1 / 24},
    {label: "6 hours / s",  rate: 0.25},
    {label: "1 day / s",    rate: 1},
    {label: "10 days / s",  rate: 10},
    {label: "60 days / s",  rate: 60}
]
global speedLabels = speeds.map(func(s) return s.label end)
global config = {speed: nil, clouds: true, lights: true, atmosphere: true, stars: true, axis: false, paused: false}

global days = 0.0            ## the simulated time, in days since J2000 (see astro.ol)
global ball = Trackball()
global cam = graphics.camera(0, 0, 4, 0, 0, 0, FOV)
global sun = nil             ## the light
global zoom = {factor: 1.0, min: 0.45, max: 2.7, wheelStep: 0.1}
global ground = nil          ## the textures
global cloudTex = nil
global nightTex = nil
global stars = []            ## unit vectors then brightnesses: x, y, z, b, x, y, z, b…
global HALO_COS = []         ## the points of a ring of the halo, on the unit circle: they never change
global HALO_SIN = []

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

## How far the camera stands from the centre of the globe.
func cameraDistance()
    return graphics.fitDistance(GLOBE, FOV) * 1.15 / zoom.factor
end

func placeCamera()
    var look = ball.orient().inverse()
    var eye = look.rotateVec(0, 0, cameraDistance())      ## rotateVec answers an array [x, y, z]
    var up = look.rotateVec(0, 1, 0)
    cam.setPos(eye[1], eye[2], eye[3])
    cam.lookAt(0, 0, 0)
    cam.ux = up[1]
    cam.uy = up[2]
    cam.uz = up[3]
end

func zoomBy(factor)
    zoom.factor = math.max(zoom.min, math.min(zoom.max, zoom.factor * factor))
end

func screenDistance(x0, y0, x1, y1)
    return math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0))
end

## How far the globe turns for a pixel of drag, in degrees: the point of the surface under the finger
## follows it. The same pixel is a far smaller angle when the camera is close, the globe being so much
## bigger on the screen, so a fixed sensitivity made a close view race away from the finger.
func degreesPerPixel()
    var fx, fy, fz, rx, ry, rz = cameraAxes()
    var x0, y0 = graphics.project(cam, -fx * GLOBE, -fy * GLOBE, -fz * GLOBE)     ## the surface nearest to the camera
    var step = GLOBE * math.rad(1)                                                  ## and the point one degree off it, along the tangent
    var x1, y1 = graphics.project(cam, -fx * GLOBE + rx * step, -fy * GLOBE + ry * step, -fz * GLOBE + rz * step)
    return 1 / screenDistance(x0, y0, x1, y1)
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

## The camera's own axes: where it looks (f), what is to the right of the screen (r) and what is up on it (u).
func cameraAxes()
    var f = cam.getViewDir()
    var r = cam.getRight()
    var u = cam.getUp()
    return f.x, f.y, f.z, r.x, r.y, r.z, u.x, u.y, u.z
end

## The stars are fixed in space, at infinity: one unit from the camera along their direction, a star
## lands where it would on the sky. A star behind the camera has no place on the screen.
func drawStars()
    graphics.noStroke()
    for i = 1, #stars, 4 do
        var sx, sy, ahead = graphics.project(cam, cam.px + stars[i], cam.py + stars[i + 1], cam.pz + stars[i + 2])
        if ahead > 0 and sx >= 0 and sx < W and sy >= 0 and sy < H then
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

func smooth(lo, hi, x)
    var t = math.clamp((x - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)
end

## The radius of the globe's disc on the screen: the limb is where the view just grazes the surface, at the
## point on the side of the globe that stands back from the centre by GLOBE²/distance towards the camera.
## The centre of the globe is the camera's target, so it is the centre of the screen.
func limbRadius()
    var fx, fy, fz, rx, ry, rz = cameraAxes()
    var back = GLOBE * GLOBE / cameraDistance()
    var side = math.sqrt(GLOBE * GLOBE - back * back)
    var x, y = graphics.project(cam, -fx * back + rx * side, -fy * back + ry * side, -fz * back + rz * side)
    return screenDistance(CX, CY, x, y)
end

## The glow of the atmosphere: a few thin rings round the globe, drawn BEFORE the globe so that it covers
## their inner half. The air only glows where the Sun lights it: bright on the day side, warm towards
## the terminator, nothing on the night side — except when the Sun is behind the globe, which lights the
## whole rim from behind.
func drawHalo()
    var fx, fy, fz, rx, ry, rz, ux, uy, uz = cameraAxes()
    var radius = limbRadius()
    var lx, ly, lz = sunLightDirection(days)
    var behind = math.max(0, -(lx * fx + ly * fy + lz * fz))     ## 1: the Sun is straight behind the globe
    var sunRight = -(lx * rx + ly * ry + lz * rz)
    var sunUp = -(lx * ux + ly * uy + lz * uz)
    ## What the rim is, segment by segment, does not depend on the ring: worked out once, drawn six times.
    ## Segment i runs from the point i - 1 to the point i, and is lit like the point i.
    var glows = []
    var warms = []
    for i = 1, HALO_STEPS do
        var lit = HALO_COS[i + 1] * sunRight + HALO_SIN[i + 1] * sunUp     ## the Sun, along this part of the rim
        glows.push(math.max(smooth(-0.25, 0.55, lit), behind * behind * 0.9))
        warms.push(math.max(0, 1 - math.abs(lit - 0.02) / 0.2) * (1 - behind))
    end
    var thickness = radius * 0.006 + 1
    graphics.noFill()
    graphics.strokeSize(thickness)
    for k = 0, 5 do
        var ring = radius * (1 + 0.004 * k) + thickness / 2
        var fade = (1 - k / 6) * (1 - k / 6)
        for i = 1, HALO_STEPS do
            var glow = glows[i]
            if glow > 0.01 then
                var warm = warms[i]
                graphics.stroke(0.3 + 0.7 * warm, 0.6 - 0.1 * warm, 1.0 - 0.7 * warm, 0.55 * fade * glow)
                graphics.line(CX + HALO_COS[i] * ring, CY - HALO_SIN[i] * ring, CX + HALO_COS[i + 1] * ring, CY - HALO_SIN[i + 1] * ring)
            end
        end
    end
end

## ── the program ───────────────────────────────────────────────────────────────────────────────

func setup()
    graphics.canvas(W, H, "Earth from space")
    config.speed = speedLabels[1]
    days = unixToDays(time())
    ground = image.load(GROUND_FILE)
    cloudTex = image.load(CLOUDS_FILE)
    nightTex = image.load(NIGHT_FILE)
    for tex in [ground, cloudTex, nightTex] do
        image.filter(tex, "mipmap")    ## the default would show the pixels squared when close and sparkling from afar
    end
    seedStars()
    for i = 0, HALO_STEPS do
        HALO_COS.push(math.cos(i / HALO_STEPS * math.TAU))
        HALO_SIN.push(math.sin(i / HALO_STEPS * math.TAU))
    end

    var lx, ly, lz = sunLightDirection(days)
    sun = graphics.light("dir", lx, ly, lz)
    graphics.ambient(AMBIENT)
    graphics.specular(0)    ## the Earth seen from space shows no highlight of its own

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
    placeCamera()    ## a drag can come before the first frame: it is measured on the camera that will be drawn
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

## One sphere of the globe, in the tilt and the turn of the Earth, wrapped in a picture.
func drawLayer(tex, radius)
    graphics.push()
    orientGlobe()
    graphics.fill(1, 1, 1)
    graphics.texture(tex)
    graphics.sphere(0, 0, 0, radius)
    graphics.noTexture()
    graphics.pop()
end

## Three layers, one block each, because the light is ONE setting for a whole block. The ground and the
## clouds are lit by the Sun. The lights of the cities are lit by a sun on the other side of the Earth, and
## added: where the Sun shines the night side's light is nil, so nothing is added there, and it grows
## towards midnight. The clouds come last, so they cover the lights they float above.
func drawGlobe()
    var lx, ly, lz = sunLightDirection(days)
    sun.setDir(lx, ly, lz)
    graphics.segments(96)
    graphics.begin3d(cam)
    graphics.noStroke()
    graphics.bump(RELIEF, GRAIN)
    drawLayer(ground, GLOBE)
    graphics.end3d()
    graphics.bump()

    if config.lights then
        sun.setDir(-lx, -ly, -lz)
        graphics.ambient(0)
        graphics.blendMode("add")
        graphics.begin3d(cam)
        graphics.noStroke()
        drawLayer(nightTex, GLOBE * LIGHTS_SHELL)
        graphics.end3d()
        graphics.blendMode("alpha")
        graphics.ambient(AMBIENT)
        sun.setDir(lx, ly, lz)
    end

    graphics.begin3d(cam)
    graphics.noStroke()
    if config.clouds then
        drawLayer(cloudTex, GLOBE * CLOUD_SHELL)
    end
    if config.axis then
        graphics.push()
        graphics.rotateX(-OBLIQUITY)
        drawAxis()
        graphics.pop()
    end
    graphics.end3d()
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
    graphics.text("{t.year}-{t.month:02d}-{t.day:02d}  {t.hour:02d}:{t.minute:02d} UTC", 12, 12)
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
