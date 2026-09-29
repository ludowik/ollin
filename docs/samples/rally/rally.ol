## Art of Rally, minimal — one car, one circuit, free exploration. Drive with the ARROW KEYS
## (up/down throttle, left/right steer) or the on-screen touch joystick; the chase camera follows
## on its own. No lap timing, no opponents, no collision against the verge — just driving the
## circuit and the hills around it.

import "terrain.ol"
import "vehicle.ol"
import "../lib/chasecam.ol"
import "../lib/joystick.ol"

global cam = graphics.camera(0, 0, 10,  0, 0, 0)
global ground = nil

## Starts on the circuit's first waypoint, facing towards the next one.
global car = Vehicle(TRACK[1].x, TRACK[1].z,
                     math.atan2(TRACK[2].x - TRACK[1].x, TRACK[2].z - TRACK[1].z))
global chase = ChaseCamera(9, 3.5, 6.0)
global pad = Joystick()

## A class cannot receive an engine callback (see joystick.ol), so these one-line relays are
## what actually arms and moves the touch control.
func mouse.pressed(x, y)
    pad.press(x, y)
end
func mouse.moved(x, y)
    pad.move(x, y)
end
func mouse.released(x, y)
    pad.release()
end

func setup()
    graphics.canvas(900, 600, "Rally")
    graphics.ambient(0.55)
    graphics.light("dir", -0.5, -1, -0.4)
    ground = bakeTerrain()
end

## The ground's slope in the car's OWN forward/right directions, from heightAt sampled a short
## distance either side — the same finite-difference idea bakeTerrain already uses for the mesh's
## corner heights, just at the scale of a car instead of a grid cell, and read straight from
## heightAt rather than from the baked lattice (the car isn't standing on a lattice point).
func groundSlope(x, z, heading)
    var e = 0.6
    var fx = math.sin(heading)
    var fz = math.cos(heading)
    var rx = fz
    var rz = -fx
    var hF = heightAt(x + fx * e, z + fz * e)
    var hB = heightAt(x - fx * e, z - fz * e)
    var hR = heightAt(x + rx * e, z + rz * e)
    var hL = heightAt(x - rx * e, z - rz * e)
    var pitch = math.atan((hF - hB) / (2 * e))
    var roll = math.atan((hR - hL) / (2 * e))
    return pitch, roll
end

func update(dt)
    var throttle = pad.throttle()
    if keyboard.isDown("up") then throttle = throttle + 1 end
    if keyboard.isDown("down") then throttle = throttle - 1 end
    var steer = pad.steer()
    if keyboard.isDown("left") then steer = steer - 1 end
    if keyboard.isDown("right") then steer = steer + 1 end
    car.update(dt, math.clamp(throttle, -1, 1), math.clamp(steer, -1, 1))

    var groundY = heightAt(car.x, car.z)
    chase.update(dt, car.x, groundY + 1.2, car.z, car.heading)
    chase.apply(cam)
end

func drawWheel(x, y, z)
    var h = 0.32
    graphics.push()
    graphics.translate(x, y, z)
    graphics.rotateZ(90)
    ## graphics.cylinder is anchored at its BASE, not centred like cube/sphere — offset by -h/2
    ## along its own (pre-rotation) axis so the wheel centres on (x, y, z) once rotated.
    graphics.cylinder(0, -h / 2, 0,  0.42, h)
    graphics.pop()
end

func drawCar()
    var groundY = heightAt(car.x, car.z)
    var pitch, roll = groundSlope(car.x, car.z, car.heading)
    graphics.push()
    graphics.translate(car.x, groundY + 0.55, car.z)
    graphics.rotateY(math.deg(car.heading))
    graphics.rotateX(math.deg(pitch))
    graphics.rotateZ(-math.deg(roll))
    graphics.fill(Color(0.82, 0.15, 0.15))
    graphics.cube(0, 0, 0,  1.7, 0.8, 3.6)
    graphics.fill(Color(0.22, 0.24, 0.28))
    ## +Z is the car's own forward (heading 0 → sin=0, cos=1 → z increases) — the cabin sits
    ## toward +Z so it leads the nose, not the tail. It was at -0.3 and rode backwards.
    graphics.cube(0, 0.55, 0.3,  1.3, 0.5, 1.6)
    graphics.fill(Color(0.12, 0.12, 0.14))
    drawWheel(0.95, -0.55, 1.2)
    drawWheel(-0.95, -0.55, 1.2)
    drawWheel(0.95, -0.55, -1.2)
    drawWheel(-0.95, -0.55, -1.2)
    graphics.pop()
end

func draw()
    graphics.clear(Color(0.55, 0.72, 0.85))
    graphics.begin3d(cam)
    graphics.blendColor(ROAD_COLOR)
    graphics.drawChunk(ground)
    drawCar()
    graphics.end3d()
    pad.draw()
end
