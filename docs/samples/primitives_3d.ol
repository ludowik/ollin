## Primitives 3D : cube, sphère, cylindre, plan, ligne, point.
## Glisse pour faire tourner chaque primitive sur elle-même.

global cam = graphics.camera(0, 3, 24,  0, 3, 0)
global orient = graphics.quat()
global dragging = false
global lastx = 0
global lasty = 0

## Grille 3 colonnes × 2 rangées — plan XY face à la caméra
global SX = 5.5    ## espacement x
global SY = 4.5    ## espacement y

func cell_pos(col, row)
    return [(col - 1) * SX, row * SY - 1.5]
end

func setup()
    graphics.canvas(W, H, "Primitives 3D")
    graphics.ambient(0.25)
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

        ## Cube  (col 0, row 0)
        var p = cell_pos(0, 0)
        graphics.push()
            graphics.translate(p[1], p[2], 0)
            graphics.rotateq(orient)
            graphics.fill(Color(0.9, 0.3, 0.3))
            graphics.cube(0, 0, 0,  2, 2, 2)
        graphics.pop()

        ## Sphère  (col 1, row 0)
        p = cell_pos(1, 0)
        graphics.push()
            graphics.translate(p[1], p[2], 0)
            graphics.rotateq(orient)
            graphics.fill(Color(0.3, 0.7, 0.9))
            graphics.stroke(Color(1, 1, 1, 0.35))
            graphics.sphere(0, 0, 0,  1.4)
            graphics.noStroke()
        graphics.pop()

        ## Cylindre  (col 2, row 0)
        p = cell_pos(2, 0)
        graphics.push()
            graphics.translate(p[1], p[2], 0)
            graphics.rotateq(orient)
            graphics.fill(Color(0.4, 0.85, 0.4))
            graphics.cylinder(0, -1.2, 0,  0.9, 2.4)
        graphics.pop()

        ## Plan (incliné 45° pour être visible face caméra)  (col 0, row 1)
        p = cell_pos(0, 1)
        graphics.push()
            graphics.translate(p[1], p[2], 0)
            graphics.rotateq(orient)
            graphics.rotateX(45)
            graphics.fill(Color(0.9, 0.7, 0.2, 0.75))
            graphics.plane(0, 0, 0,  2.5, 2.5)
        graphics.pop()

        ## line3d + point3d  (col 1, row 1)
        p = cell_pos(1, 1)
        graphics.push()
            graphics.translate(p[1], p[2], 0)
            graphics.rotateq(orient)
            graphics.stroke(Color(1, 0.5, 0.1))
            graphics.strokeSize(2)
            graphics.line3d(-1, -1, -1,   1, -1,  1)
            graphics.line3d(-1, -1,  1,   1,  1, -1)
            graphics.line3d( 1, -1, -1,  -1,  1,  1)
            graphics.stroke(colors.WHITE)
            graphics.point3d(0, 0, 0)
            graphics.strokeSize(1)
            graphics.noStroke()
        graphics.pop()

        ## Cube fil de fer  (col 2, row 1)
        p = cell_pos(2, 1)
        graphics.push()
            graphics.translate(p[1], p[2], 0)
            graphics.rotateq(orient)
            graphics.noFill()
            graphics.stroke(Color(0.7, 0.4, 1.0))
            graphics.strokeSize(2)
            graphics.cube(0, 0, 0,  2.5, 2.5, 2.5)
            graphics.strokeSize(1)
            graphics.noStroke()
        graphics.pop()

    graphics.end3d()

    ## Labels 2D centrés sous chaque colonne
    var lc = Color(1, 1, 1, 0.75)
    var fs = 13
    var col0 = W / 6
    var col1 = W / 2
    var col2 = W * 5 / 6
    ## row 1 (y>0) est en haut de l'écran, row 0 (y<0) en bas
    var rowTop = H * 0.28
    var rowBot = H * 0.72
    graphics.text("plane",          col0 - 18, rowTop, fs, lc)
    graphics.text("line3d/point3d", col1 - 42, rowTop, fs, lc)
    graphics.text("cube (stroke)",  col2 - 38, rowTop, fs, lc)
    graphics.text("cube",           col0 - 14, rowBot, fs, lc)
    graphics.text("sphere",         col1 - 20, rowBot, fs, lc)
    graphics.text("cylinder",       col2 - 26, rowBot, fs, lc)

    graphics.text("Glisse pour tourner", 12, 12, 16, Color(1, 1, 1, 0.5))
end
