## An interactive isometric camera.
## Drag to orbit - wheel or pinch to zoom - double-click to recentre.

## Every tunable of the sample lives in ONE map: what to change to retune the camera is here, and
## nowhere else. The `size` and `angle` entries are the STARTING values, kept untouched so that a
## double-click can restore them - the current ones live in `view` below.
global config = {
    dist:      18.0,    ## orbit radius
    height:    14.0,    ## the camera's height
    size:      14.0,    ## the units visible vertically
    angle:     0.785,   ## initial orbit angle, about 45 degrees
    minSize:   3.0,     ## closest zoom
    maxSize:   40.0,    ## furthest zoom
    orbitRate: 0.008,   ## radians per pixel dragged
    wheelStep: 0.1      ## zoom fraction per wheel notch
}

## Three globals, one per LIFETIME. `config` never changes once written; `view` is where the
## camera is right now, derived from the gestures; `drag` is a gesture in progress, meaningless
## between two presses. Merging them would blur exactly the distinction the double-click needs.
global cam  = graphics.cameraOrtho(0, config.height, config.dist,  0, 0, 0,  config.size)
global view = { angle: config.angle, size: config.size }
global drag = { active: false, x: 0 }

func setup()
    graphics.canvas(W, H, "Isometric camera")
    graphics.ambient(0.3)
    graphics.light("dir", -1, -2, -0.5)
end

func mouse.pressed(x, y)
    drag.active = true
    drag.x = x
end

func mouse.released(x, y)
    drag.active = false
end

## A pinch is not a drag: while two fingers are down, the orbit must not follow the finger the
## system emulates the mouse with, or the scene would spin as one zooms.
func mouse.moved(x, y)
    if not drag.active or touch.count() > 1 then return end
    var dx = x - drag.x
    drag.x = x
    view.angle = view.angle + dx * config.orbitRate
    cam.orbit(view.angle, config.dist, config.height)
end

## The zoom lives in ONE function, and the two gestures only differ by the factor they hand it:
## a wheel notch is a step, a pinch is a ratio. Anything else — the bounds, the camera update —
## would otherwise be written twice and drift.
func zoomBy(factor)
    view.size = math.max(config.minSize, math.min(config.maxSize, view.size * factor))
    cam.fovy = view.size
end

func mouse.scrolled(x, y, dx, dy)
    zoomBy(1.0 - dy * config.wheelStep)
end

## Two fingers spreading (scale > 1) bring the scene CLOSER, so the visible size shrinks: the
## factor is the inverse of the gesture's, which is what makes the scene follow the fingers.
func touch.pinch(scale, cx, cy)
    zoomBy(1.0 / scale)
end

func mouse.doubleClicked(x, y)
    view.angle = config.angle
    view.size  = config.size
    cam.fovy   = view.size
    cam.orbit(view.angle, config.dist, config.height)
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

        ## A 9x9 checkerboard floor
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
    var hint = "Drag: orbit   Wheel or pinch: zoom   Double-click: reset"
    graphics.stroke(Color(1, 1, 1, 0.55))
    graphics.fontSize(14)
    graphics.text(hint, 12, H - 28)
end
