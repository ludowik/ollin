## Art of Rally, minimal — one car, one circuit, free exploration. Drive with the ARROW KEYS
## (up/down throttle, left/right steer) or the on-screen touch joystick; the chase camera follows
## on its own, and the engine note follows the revs (the audio starts on the first key or touch).
## On a phone, hold it like a steering wheel in landscape: its tilt steers, and two pedals at the
## bottom corners — brake on the left, throttle on the right — take the thumbs. Straight ahead is
## the phone's standard position, held level, so there is nothing to set up; the button at the top
## right takes the way the phone is held at that moment as straight ahead instead. Turn the phone
## upright and the drawing area follows: the controls and the HUD re-place themselves from W, H and
## SIZE, the camera widens to keep the road in view, and the steering goes back to the standard
## position.
## No lap timing, no opponents, no collision against the verge — just driving the circuit and the
## hills around it.

import "terrain.ol"
import "vehicle.ol"
import "engine.ol"
import "../lib/chasecam.ol"
import "../lib/joystick.ol"
import "../lib/tilt.ol"

global cam = graphics.camera(0, 0, 10,  0, 0, 0)
global ground = nil

## Starts on the circuit's first waypoint, facing towards the next one.
global car = Vehicle(TRACK[1].x, TRACK[1].z,
                     math.atan2(TRACK[2].x - TRACK[1].x, TRACK[2].z - TRACK[1].z))
global engineSound = EngineSound()
global chase = ChaseCamera(14, 5.5, 6.0)
global pad = Joystick()
## Half the library's default size, resting at the bottom edge: the control stays clear of the
## road ahead of the car.
pad.radiusFrac = 0.11
pad.centerFrac = 0.86
global wheel = Tilt(30, 3)
global wasPortrait = false

## The area follows the host (graphics.fitArea in setup), so W, H and SIZE already hold the new size
## when this runs, and everything drawn from them re-places itself. What the script keeps — the
## wheel's neutral — it redoes here: whatever the player had set goes back to the standard position,
## the phone being held differently the other way up.
func window.resized(w, h)
    var portrait = h > w
    if portrait <> wasPortrait then
        wasPortrait = portrait
        wheel.reset()
    end
end

## The phone's tilt drives the car instead of the joystick once the sensors answer.
func tiltOn()
    return motion.state() == "on"
end

## A class cannot receive an engine callback (see joystick.ol), so these one-line relays are
## what actually arms and moves the touch control.
func mouse.pressed(x, y)
    if not tiltOn() then
        pad.press(x, y)
    end
end
func mouse.moved(x, y)
    pad.move(x, y)
end
func mouse.released(x, y)
    pad.release()
end

## The wheel button takes the way the phone is held right now as straight ahead.
func touch.began(id, x, y)
    if tiltOn() and inRect(x, y, wheelButton()) then
        wheel.calibrate(motion.tilt())
    end
end

func setup()
    graphics.canvas(W, H, "Rally")
    graphics.fitArea()
    wasPortrait = H > W
    motion.enable()
    graphics.ambient(0.55)
    graphics.light("dir", -0.5, -1, -0.4)
    ground = bakeTerrain()
    engineSound.start()
end

global HALF_TRACK = 0.95   ## a wheel's lateral offset from the car's centreline
global HALF_BASE = 1.2      ## a wheel's longitudinal offset from the axle midpoint
global WHEEL_R = 0.42
global WHEEL_H = 0.32

## Colours are built once, not every frame: each Color is a class instance.
global BODY_COLOR = Color(0.82, 0.15, 0.15)
global CABIN_COLOR = Color(0.22, 0.24, 0.28)
global TYRE_COLOR = Color(0.12, 0.12, 0.14)
global HUB_COLOR = Color(0.75, 0.75, 0.78)
global HUD_SHADOW = Color(0, 0, 0, 0.6)
global HUD_TEXT = Color(1, 1, 1)
global SKY_COLOR = Color(0.55, 0.72, 0.85)
global PEDAL_IDLE = Color(1, 1, 1, 0.16)
global PEDAL_HELD = Color(0.45, 0.65, 1.0, 0.5)

## Where the car sits on the RENDERED ground: the four wheel contact heights, read from
## surfaceAt (the mesh's own surface, not the smooth heightAt field it only approximates), give
## the body's height, pitch and roll. A tilted plane through four points cannot touch all four
## on a twisted surface, so the body is lifted by however far the worst wheel falls below it —
## a wheel may hover a little, it never sinks.
func carPose(x, z, heading)
    var fx = math.sin(heading)
    var fz = math.cos(heading)
    var rx = fz
    var rz = -fx
    var hFL = surfaceAt(x + rx * HALF_TRACK + fx * HALF_BASE, z + rz * HALF_TRACK + fz * HALF_BASE)
    var hFR = surfaceAt(x - rx * HALF_TRACK + fx * HALF_BASE, z - rz * HALF_TRACK + fz * HALF_BASE)
    var hBL = surfaceAt(x + rx * HALF_TRACK - fx * HALF_BASE, z + rz * HALF_TRACK - fz * HALF_BASE)
    var hBR = surfaceAt(x - rx * HALF_TRACK - fx * HALF_BASE, z - rz * HALF_TRACK - fz * HALF_BASE)
    var mean = (hFL + hFR + hBL + hBR) / 4
    var slopeF = ((hFL + hFR) - (hBL + hBR)) / (4 * HALF_BASE)
    var slopeR = ((hFL + hBL) - (hFR + hBR)) / (4 * HALF_TRACK)
    var lift = 0.0
    lift = math.max(lift, hFL - (mean + slopeF * HALF_BASE + slopeR * HALF_TRACK))
    lift = math.max(lift, hFR - (mean + slopeF * HALF_BASE - slopeR * HALF_TRACK))
    lift = math.max(lift, hBL - (mean - slopeF * HALF_BASE + slopeR * HALF_TRACK))
    lift = math.max(lift, hBR - (mean - slopeF * HALF_BASE - slopeR * HALF_TRACK))
    return mean + lift, math.atan(slopeF), math.atan(slopeR)
end

## The camera's vertical field of view. A narrow area — the phone upright — would squeeze the
## horizontal view to a slot at the usual 45 degrees; it widens as the area narrows so that at least
## FOV_H_MIN degrees stay in view across, within reason. Landscape is left at 45.
global FOV_V = 45.0
global FOV_H_MIN = 60.0
global FOV_MAX = 75.0

func viewFov()
    var wide = 2 * math.atan(math.tan(math.rad(FOV_H_MIN) / 2) / (W / H))
    return math.clamp(math.deg(wide), FOV_V, FOV_MAX)
end

## The two pedals and the recentre button, as {x, y, w, h} in the drawing area's units.
func pedal(right)
    var w = SIZE * 0.34
    var h = SIZE * 0.26
    var margin = SIZE * 0.03
    var x = margin
    if right then
        x = W - w - margin
    end
    return { x: x, y: H - h - margin, w: w, h: h }
end

func wheelButton()
    var size = SIZE * 0.14
    return { x: W - size - SIZE * 0.03, y: SIZE * 0.03, w: size, h: size }
end

func inRect(x, y, r)
    return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

## Whether any finger is on the pedal. touch.points() is read rather than a callback, because the
## thumbs slide on and off the pedals while they are held.
func pedalHeld(right)
    var r = pedal(right)
    for p in touch.points() do
        if inRect(p.x, p.y, r) then
            return true
        end
    end
    return false
end

func update(dt)
    var throttle = 0
    var steer = 0
    if tiltOn() then
        var roll = motion.tilt()
        steer = wheel.update(dt, roll)
        if pedalHeld(true) then throttle = throttle + 1 end
        if pedalHeld(false) then throttle = throttle - 1 end
    else
        throttle = pad.throttle()
        steer = pad.steer()
    end
    if keyboard.isDown("up") then throttle = throttle + 1 end
    if keyboard.isDown("down") then throttle = throttle - 1 end
    if keyboard.isDown("left") then steer = steer - 1 end
    if keyboard.isDown("right") then steer = steer + 1 end
    throttle = math.clamp(throttle, -1, 1)
    car.update(dt, throttle, math.clamp(steer, -1, 1))
    engineSound.update(car.engine)

    chase.update(dt, car.x, surfaceAt(car.x, car.z) + 1.2, car.z, car.heading)
    chase.apply(cam)
    cam.fovy = viewFov()
end

## A wheel that rolls without slipping turns by travelled / radius. A plain cylinder looks the
## same at every angle, so a lighter bar across the tread is what makes the spin visible.
func drawWheel(x, y, z, yaw, spin)
    graphics.push()
    graphics.translate(x, y, z)
    graphics.rotateY(math.deg(yaw))
    graphics.rotateX(math.deg(spin))
    graphics.fill(HUB_COLOR)
    graphics.cube(0, 0, 0,  WHEEL_H + 0.06, 0.1, WHEEL_R * 1.9)
    graphics.fill(TYRE_COLOR)
    graphics.rotateZ(90)
    ## graphics.cylinder is anchored at its BASE, not centred like cube/sphere — offset by -h/2
    ## along its own (pre-rotation) axis so the wheel centres on (x, y, z) once rotated.
    graphics.cylinder(0, -WHEEL_H / 2, 0,  WHEEL_R, WHEEL_H)
    graphics.pop()
end

func drawCar()
    var groundY, pitch, roll = carPose(car.x, car.z, car.heading)
    graphics.push()
    ## The car's local origin sits at AXLE height: a wheel drawn at local y=0 (see drawWheel calls
    ## below) then has its bottom exactly WHEEL_R below, right at the ground. This offset and the
    ## wheel's own radius used to be two unrelated numbers (0.55 here, 0.42 in drawWheel) — out of
    ## sync by WHEEL_R, which is exactly how much of the car sat buried in the terrain.
    graphics.translate(car.x, groundY + WHEEL_R, car.z)
    graphics.rotateY(math.deg(car.heading))
    ## rotateX lowers +Z for a positive angle and rotateZ raises +X, hence the pitch's minus.
    graphics.rotateX(-math.deg(pitch))
    graphics.rotateZ(math.deg(roll))
    graphics.fill(BODY_COLOR)
    graphics.cube(0, 0.4, 0,  1.7, 0.8, 3.6)
    graphics.fill(CABIN_COLOR)
    ## +Z is the car's own forward (heading 0 → sin=0, cos=1 → z increases) — the cabin sits
    ## toward +Z so it leads the nose, not the tail. It was at -0.3 and rode backwards.
    graphics.cube(0, 1.05, 0.3,  1.3, 0.5, 1.6)
    var spin = car.travelled / WHEEL_R
    drawWheel(HALF_TRACK, 0, HALF_BASE, car.steerAngle, spin)
    drawWheel(-HALF_TRACK, 0, HALF_BASE, car.steerAngle, spin)
    drawWheel(HALF_TRACK, 0, -HALF_BASE, 0, spin)
    drawWheel(-HALF_TRACK, 0, -HALF_BASE, 0, spin)
    graphics.pop()
end

## One readout row: the value right-aligned on `xr`, its unit just after it, each with a dark
## copy underneath so the white stays readable over the grass, the road and the sky.
func hudRow(value, unit, xr, y, size)
    graphics.fontSize(size)
    var gap = size * 0.3
    graphics.stroke(HUD_SHADOW)
    graphics.textMode("right", "top")
    graphics.text(value, xr + 2, y + 2)
    graphics.textMode("left", "top")
    graphics.text(unit, xr + gap + 2, y + 2)
    graphics.stroke(HUD_TEXT)
    graphics.textMode("right", "top")
    graphics.text(value, xr, y)
    graphics.textMode("left", "top")
    graphics.text(unit, xr + gap, y)
end

## Speed, engaged gear and revs, top left. The monospaced font keeps the digits from jittering as
## the numbers change.
func drawHud()
    var u = SIZE * 0.04
    var gear = "{car.engine.gear}"
    var of = "/ {#car.engine.ratios}"
    if car.engine.reverse then
        gear = "R"
        of = ""
    end
    graphics.font("mono")
    var xr = u * 5.5
    hudRow("{math.floor(math.abs(car.speed) * 3.6)}", "km/h", xr, u * 0.6, u * 2.2)
    hudRow(gear, of, xr, u * 3.1, u * 1.3)
    hudRow("{math.floor(car.engine.rpm)}", "rpm", xr, u * 4.7, u * 1.3)
end

## One pedal, lit while a thumb is on it.
func drawPedal(right, label)
    var r = pedal(right)
    graphics.noStroke()
    if pedalHeld(right) then
        graphics.fill(PEDAL_HELD)
    else
        graphics.fill(PEDAL_IDLE)
    end
    graphics.rect(r.x, r.y, r.w, r.h, r.h * 0.25)
    graphics.font("mono")
    graphics.fontSize(r.h * 0.22)
    graphics.stroke(HUD_TEXT)
    graphics.textMode("center", "center")
    graphics.text(label, r.x + r.w / 2, r.y + r.h / 2)
end

func drawTiltControls()
    drawPedal(false, "BRAKE")
    drawPedal(true, "GAS")
    var b = wheelButton()
    graphics.noStroke()
    graphics.fill(PEDAL_IDLE)
    graphics.rect(b.x, b.y, b.w, b.h, b.h * 0.5)
    graphics.font("mono")
    graphics.fontSize(b.h * 0.3)
    graphics.stroke(HUD_TEXT)
    graphics.textMode("center", "center")
    graphics.text("RESET", b.x + b.w / 2, b.y + b.h / 2)
end

func draw()
    graphics.clear(SKY_COLOR)
    graphics.begin3d(cam)
    for block in ground do
        if graphics.inFrustum(block.x, block.y, block.z, block.r) then
            graphics.drawChunk(block)
        end
    end
    drawCar()
    graphics.end3d()
    drawHud()
    if tiltOn() then
        drawTiltControls()
    else
        pad.draw()
    end
end
