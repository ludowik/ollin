## Primitives 3D : cube, sphère, cylindre, plan, ligne, point.
## Glisse à la souris pour tourner la scène (trackball).

global cam = graphics.camera(0, 8, 28,  0, 0, 0)
global orient = graphics.quat()
global dragging = false
global lastx = 0
global lasty = 0

func setup()
    graphics.canvas(W, H, "Primitives 3D")
    graphics.ambient(0.2)
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
    var dy = y - lasty
    lastx = x
    lasty = y
    var spin = graphics.quatAxis(0, 1, 0, dx * 0.5).mul(graphics.quatAxis(1, 0, 0, dy * 0.5))
    orient = spin.mul(orient)
end

func draw()
    graphics.clear(Color(0.08, 0.08, 0.12))

    graphics.noStroke()
    graphics.begin3d(cam)
        graphics.grid(20, 2)

        graphics.rotateq(orient)

        ## Cube
        graphics.push()
            graphics.translate(-7, 0, 0)
            graphics.rotateY(elapsedTime * 40)
            graphics.fill(Color(0.9, 0.3, 0.3))
            graphics.cube(0, 1, 0,  2, 2, 2)
        graphics.pop()

        ## Sphère (fill + contour fil de fer)
        graphics.push()
            graphics.translate(-3.5, 0, 0)
            graphics.fill(Color(0.3, 0.7, 0.9))
            graphics.stroke(Color(1, 1, 1, 0.3))
            graphics.sphere(0, 1.2, 0,  1.2)
            graphics.noStroke()
        graphics.pop()

        ## Cylindre
        graphics.push()
            graphics.translate(0, 0, 0)
            graphics.rotateY(elapsedTime * 30)
            graphics.fill(Color(0.4, 0.85, 0.4))
            graphics.cylinder(0, 0, 0,  0.9, 2.4)
        graphics.pop()

        ## Plan semi-transparent
        graphics.push()
            graphics.translate(3.5, 0, 0)
            graphics.fill(Color(0.9, 0.7, 0.2, 0.7))
            graphics.plane(0, 1.5, 0,  2.5, 2.5)
        graphics.pop()

        ## Ligne 3D + point 3D
        graphics.push()
            graphics.translate(6.5, 0, 0)
            graphics.stroke(Color(1, 0.5, 0.1))
            graphics.strokeSize(2)
            graphics.line3d(-1, 0, 0,  1, 0, 0)
            graphics.line3d(0, 0, -1,  0, 2.4, 1)
            graphics.line3d(-1, 2.4, -1,  1, 0, 1)
            graphics.stroke(colors.WHITE)
            graphics.point3d(0, 1.2, 0)
            graphics.strokeSize(1)
            graphics.noStroke()
        graphics.pop()

    graphics.end3d()

    ## Labels 2D sous chaque primitive
    var y = H - 28
    var step = W / 5
    graphics.text("cube",     step * 0.5 - 14, y, 14, colors.WHITE)
    graphics.text("sphere",   step * 1.5 - 20, y, 14, colors.WHITE)
    graphics.text("cylinder", step * 2.5 - 26, y, 14, colors.WHITE)
    graphics.text("plane",    step * 3.5 - 18, y, 14, colors.WHITE)
    graphics.text("line3d / point3d", step * 4.5 - 50, y, 14, colors.WHITE)

    graphics.text("Glisse pour tourner", 12, 12, 16, Color(1, 1, 1, 0.6))
end
