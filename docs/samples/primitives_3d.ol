## Primitives 3D : cube, sphère, cylindre, plan, ligne, point.
## Glisse pour faire tourner chaque primitive sur elle-même.

global cam = graphics.camera(0, 0, 24,  0, 0, 0)
global orient = graphics.quat()
global dragging = false
global lastx = 0
global lasty = 0

## Grille adaptée à l'orientation : paysage = 3×2, portrait = 2×3
## cell_pos(col, row, cols, rows) → [x, y] en unités monde, centré sur (0,0)
func cell_pos(col, row, cols, rows)
    var fov = 45.0
    var aspect = W / H
    ## demi-largeur et demi-hauteur visibles à z=0 depuis la caméra en z=24
    var depth = 24.0
    var halfH = depth * math.tan(fov * 0.5 * math.PI / 180)
    var halfW = halfH * aspect
    var sx = halfW * 2 / cols
    var sy = halfH * 2 / rows
    return [(col - (cols - 1) / 2.0) * sx, (row - (rows - 1) / 2.0) * sy]
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

    ## idx → col/row selon l'orientation
    ## Paysage 3×2 : cube sphère cylindre / plan lignes fil
    ## Portrait 2×3 : cube sphère / cylindre plan / lignes fil
    var cols = 3
    var rows = 2
    if H > W then
        cols = 2
        rows = 3
    end

    func gc(idx)
        return idx % cols
    end
    func gr(idx)
        return idx // cols
    end

    graphics.noStroke()
    graphics.begin3d(cam)

        ## Cube (idx 0)
        var p = cell_pos(gc(0), gr(0), cols, rows)
        graphics.push()
            graphics.translate(p[1], p[2], 0)
            graphics.rotateq(orient)
            graphics.fill(Color(0.9, 0.3, 0.3))
            graphics.cube(0, 0, 0,  2, 2, 2)
        graphics.pop()

        ## Sphère (idx 1)
        p = cell_pos(gc(1), gr(1), cols, rows)
        graphics.push()
            graphics.translate(p[1], p[2], 0)
            graphics.rotateq(orient)
            graphics.fill(Color(0.3, 0.7, 0.9))
            graphics.stroke(Color(1, 1, 1, 0.35))
            graphics.sphere(0, 0, 0,  1.4)
            graphics.noStroke()
        graphics.pop()

        ## Cylindre (idx 2)
        p = cell_pos(gc(2), gr(2), cols, rows)
        graphics.push()
            graphics.translate(p[1], p[2], 0)
            graphics.rotateq(orient)
            graphics.fill(Color(0.4, 0.85, 0.4))
            graphics.cylinder(0, -1.2, 0,  0.9, 2.4)
        graphics.pop()

        ## Plan (idx 3)
        p = cell_pos(gc(3), gr(3), cols, rows)
        graphics.push()
            graphics.translate(p[1], p[2], 0)
            graphics.rotateq(orient)
            graphics.rotateX(90)
            graphics.fill(Color(0.9, 0.7, 0.2, 0.75))
            graphics.plane(0, 0, 0,  2.5, 2.5)
        graphics.pop()

        ## line3d + point3d (idx 4)
        p = cell_pos(gc(4), gr(4), cols, rows)
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

        ## Cube fil de fer (idx 5)
        p = cell_pos(gc(5), gr(5), cols, rows)
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

    ## Labels 2D — un par primitive, centrés horizontalement sur la colonne
    ## row 0 = bas de l'écran (Y élevé), row rows-1 = haut (Y faible)
    var lc = Color(1, 1, 1, 0.75)
    var fs = 13
    var names = ["cube", "sphere", "cylinder", "plane", "line3d/point3d", "cube (stroke)"]
    var offsets = [-14, -20, -26, -18, -42, -38]
    for i = 1, 6 do
        var idx = i - 1
        var col = idx % cols
        var row = idx // cols
        var cx = W * (col + 0.5) / cols
        var cy = H * (rows - 0.5 - row) / rows - H * 0.05
        graphics.text(names[i], cx + offsets[i], cy, fs, lc)
    end

    graphics.text("Glisse pour tourner", 12, 12, 16, Color(1, 1, 1, 0.5))
end
