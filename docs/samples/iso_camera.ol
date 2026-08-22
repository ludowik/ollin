## An interactive isometric camera.
## Drag to orbit - wheel or pinch to zoom - double-click to recentre.

global ISO_DIST  = 18.0      ## orbit radius
global ISO_H     = 14.0      ## the camera's height
global ISO_SIZE  = 14.0      ## the units visible vertically
global ISO_ANGLE = 0.785     ## initial angle, about 45 degrees

global cam    = graphics.cameraOrtho(0, ISO_H, ISO_DIST,  0, 0, 0,  ISO_SIZE)
global angle  = ISO_ANGLE    ## current orbit angle, in radians
global dragging = false
global lastx    = 0
global lasty    = 0

func setup()
    graphics.canvas(W, H, "Isometric camera")
    graphics.ambient(0.3)
    graphics.light("dir", -1, -2, -0.5)
end

func mouse.pressed(x, y)
    dragging = true
    lastx = x
    lasty = y
end

func mouse.released(x, y)
    dragging = false
end

func mouse.moved(x, y)
    if not dragging then return end
    var dx = x - lastx
    lastx = x
    lasty = y
    angle = angle + dx * 0.008
    cam.orbit(angle, ISO_DIST, ISO_H)
end

func mouse.scrolled(x, y, dx, dy)
    ISO_SIZE = math.max(3.0, math.min(40.0, ISO_SIZE * (1.0 - dy * 0.1)))
    cam.fovy = ISO_SIZE
end

func mouse.doubleClicked(x, y)
    angle    = ISO_ANGLE
    ISO_SIZE = 14.0
    cam.fovy = ISO_SIZE
    cam.orbit(angle, ISO_DIST, ISO_H)
end

## Checkerboard offsets, which make the grid easier to read
func checkerColor(x, z)
    if (x + z) % 2 == 0 then
        return Color(0.72, 0.70, 0.65)
    end
    return Color(0.62, 0.60, 0.56)
end

func draw()
    graphics.clear(Color(0.15, 0.16, 0.20))
    graphics.noStroke()

    graphics.begin3d(cam)

        ## Sol en damier 9×9
        for x = -4, 4 do
            for z = -4, 4 do
                graphics.fill(checkerColor(x, z))
                graphics.cube(x, -0.55, z,  1, 0.1, 1)
            end
        end

        ## Buildings of varied heights
        var bldgs = [
            [-2,  0, 1.2, 3.0, Color(0.85, 0.38, 0.22)],
            [ 1,  1, 1.0, 2.0, Color(0.30, 0.60, 0.80)],
            [ 0, -1, 0.8, 1.6, Color(0.55, 0.75, 0.35)],
            [-1,  2, 1.4, 4.0, Color(0.80, 0.65, 0.20)],
            [ 2, -2, 1.0, 2.5, Color(0.70, 0.35, 0.70)],
            [-3, -2, 0.6, 1.2, Color(0.30, 0.70, 0.65)],
            [ 3,  2, 1.2, 3.6, Color(0.90, 0.50, 0.25)],
        ]
        for i = 1, bldgs.len() do
            var b = bldgs[i]
            graphics.fill(b[5])
            graphics.cube(b[1], b[4] / 2, b[2],  b[3], b[4], b[3])
        end

        ## An animated sphere orbiting above the scene
        var t   = elapsedTime * 0.8
        var sx  = math.cos(t) * 3.2
        var sz  = math.sin(t) * 3.2
        var sy  = 4.5 + math.sin(elapsedTime * 2.0) * 0.4
        graphics.fill(Color(1.0, 0.95, 0.40))
        graphics.sphere(sx, sy, sz,  0.55)

        ## A cast shadow: a disc on the ground, with alpha
        graphics.fill(Color(0.0, 0.0, 0.0, 0.30))
        graphics.cylinder(sx, 0.01, sz,  0.45, 0.02)

    graphics.end3d()

    ## HUD
    var hint = "Glisser : orbiter   Molette : zoom   Double-clic : reset"
    graphics.stroke(Color(1, 1, 1, 0.55))
    graphics.fontSize(14)
    graphics.text(hint, 12, H - 28)
end
