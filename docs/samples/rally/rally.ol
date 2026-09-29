## Art of Rally, minimal — milestone 1: the circuit and a free-flying camera, no car yet. Lets the
## track and heightAt be checked on screen before anything drives on it.
##
## Fly with the ARROW KEYS (turn left/right, move forward/back) and "w"/"s" for altitude.

import "terrain.ol"

global cam = graphics.camera(0, 0, 10,  0, 0, 0)
global ground = nil   ## the baked terrain (graphics.endChunk handle)

global flyX = 0.0
global flyY = 110.0
global flyZ = -280.0
global yaw = 0.0
global pitch = -0.25
global SPEED = 90.0
global TURN = 1.6

func setup()
    graphics.canvas(900, 600, "Rally — terrain")
    graphics.ambient(0.55)
    graphics.light("dir", -0.5, -1, -0.4)
    ground = bakeTerrain()
end

func update(dt)
    var turn = 0
    if keyboard.isDown("left") then turn = turn - 1 end
    if keyboard.isDown("right") then turn = turn + 1 end
    yaw = yaw + turn * TURN * dt

    var thr = 0
    if keyboard.isDown("up") then thr = thr + 1 end
    if keyboard.isDown("down") then thr = thr - 1 end
    flyX = flyX + math.sin(yaw) * thr * SPEED * dt
    flyZ = flyZ + math.cos(yaw) * thr * SPEED * dt

    if keyboard.isDown("w") then flyY = flyY + SPEED * dt end
    if keyboard.isDown("s") then flyY = flyY - SPEED * dt end

    cam.setPos(flyX, flyY, flyZ)
    cam.lookAt(flyX + math.cos(pitch) * math.sin(yaw),
               flyY + math.sin(pitch),
               flyZ + math.cos(pitch) * math.cos(yaw))
end

func draw()
    graphics.clear(Color(0.55, 0.72, 0.85))
    graphics.begin3d(cam)
    ## blendColor is a per-DRAW uniform, not baked into the chunk — set it fresh before every
    ## drawChunk, unlike fill/corners/mixCorners, which were captured per cube back in bakeTerrain.
    graphics.blendColor(ROAD_COLOR)
    graphics.drawChunk(ground)
    graphics.end3d()
end
