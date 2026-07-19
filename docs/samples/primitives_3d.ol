## Primitives 3D : cube, sphère, cylindre, plan, ligne, point, cône, tore.
## Glisse pour faire tourner chaque primitive sur elle-même.

global cam = graphics.cameraOrtho(12, 12, 12,  0, 0, 0,  16)
global orient = graphics.quat()
global dragging = false
global lastx = 0
global lasty = 0

## Grille adaptée à l'orientation : paysage = 4×2, portrait = 2×4
## cell_pos(col, row, cols, rows) → [x, z] dans le plan XZ (vue ortho iso, size=16)
func cell_pos(col, row, cols, rows)
    var size   = 16.0
    var aspect = W / H
    var halfH  = size / 2.0
    var halfW  = halfH * aspect
    var sx = halfW * 2 / cols
    var sz = halfH * 2 / rows
    return [(col - (cols - 1) / 2.0) * sx, (row - (rows - 1) / 2.0) * sz]
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

    ## Paysage 4×2 : cube sphère cylindre plan / lignes cône tore (vide)
    ## Portrait 2×4 : cube sphère / cylindre plan / lignes cône / tore (vide)
    var cols = 4
    var rows = 2
    if H > W then
        cols = 2
        rows = 4
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
            graphics.translate(p[1], 0, p[2])
            graphics.rotateq(orient)
            graphics.fill(Color(0.9, 0.3, 0.3))
            graphics.cube(0, 0, 0,  2, 2, 2)
        graphics.pop()

        ## Sphère (idx 1)
        p = cell_pos(gc(1), gr(1), cols, rows)
        graphics.push()
            graphics.translate(p[1], 0, p[2])
            graphics.rotateq(orient)
            graphics.fill(Color(0.3, 0.7, 0.9))
            graphics.stroke(Color(1, 1, 1, 0.35))
            graphics.sphere(0, 0, 0,  1.4)
            graphics.noStroke()
        graphics.pop()

        ## Cylindre (idx 2)
        p = cell_pos(gc(2), gr(2), cols, rows)
        graphics.push()
            graphics.translate(p[1], 0, p[2])
            graphics.rotateq(orient)
            graphics.fill(Color(0.4, 0.85, 0.4))
            graphics.cylinder(0, -1.2, 0,  0.9, 2.4)
        graphics.pop()

        ## Plan (idx 3)
        p = cell_pos(gc(3), gr(3), cols, rows)
        graphics.push()
            graphics.translate(p[1], 0, p[2])
            graphics.rotateq(orient)
            graphics.rotateX(90)
            graphics.fill(Color(0.9, 0.7, 0.2, 0.75))
            graphics.plane(0, 0, 0,  2.5, 2.5)
        graphics.pop()

        ## line3d + point3d (idx 4)
        p = cell_pos(gc(4), gr(4), cols, rows)
        graphics.push()
            graphics.translate(p[1], 0, p[2])
            graphics.rotateq(orient)
            graphics.stroke(Color(1, 0.5, 0.1))
            graphics.strokeSize(4)
            graphics.line3d(-1.8, -1.8, -1.8,   1.8,  1.8,  1.8)
            graphics.line3d(-1.8, -1.8,  1.8,   1.8,  1.8, -1.8)
            graphics.line3d( 1.8, -1.8, -1.8,  -1.8,  1.8,  1.8)
            graphics.strokeSize(6)
            for i = 1, 40 do
                var t = i * 2.399
                var r = 1.0 * math.sqrt(i / 40.0)
                graphics.stroke(Color(0.3 + r * 0.5, 0.5 + r * 0.2, 1.0 - r * 0.4))
                graphics.point3d(r * math.cos(t), r * math.sin(t), math.sin(t * 2) * 0.4)
            end
            graphics.stroke(colors.WHITE)
            graphics.strokeSize(10)
            graphics.point3d(0, 0, 0)
            graphics.strokeSize(1)
            graphics.noStroke()
        graphics.pop()

        ## Cône (idx 5)
        p = cell_pos(gc(5), gr(5), cols, rows)
        graphics.push()
            graphics.translate(p[1], 0, p[2])
            graphics.rotateq(orient)
            graphics.fill(Color(0.9, 0.4, 0.8))
            graphics.cone(0, -1.2, 0,  1.0, 2.4)
        graphics.pop()

        ## Tore (idx 6)
        p = cell_pos(gc(6), gr(6), cols, rows)
        graphics.push()
            graphics.translate(p[1], 0, p[2])
            graphics.rotateq(orient)
            graphics.fill(Color(0.4, 0.9, 0.7))
            graphics.torus(0, 0, 0,  1.1, 0.4)
        graphics.pop()

        ## segments(8) — même sphère, basse définition (idx 7)
        p = cell_pos(gc(7), gr(7), cols, rows)
        graphics.push()
            graphics.translate(p[1], 0, p[2])
            graphics.rotateq(orient)
            graphics.segments(6)
            graphics.fill(Color(0.3, 0.7, 0.9))
            graphics.sphere(0, 0, 0,  1.4)
        graphics.pop()

    graphics.end3d()

    ## Labels 2D — fond blanc, texte noir, centrés sur la cellule
    var fs = 13
    var pad = 4
    var names = ["cube", "sphere", "cylinder", "plane", "line3d/point3d", "cone", "torus", "segments(6)"]
    var hw = [14, 20, 26, 18, 42, 14, 16, 34]  ## demi-largeur approx du texte
    for i = 1, 8 do
        var idx = i - 1
        var col = idx % cols
        var row = idx // cols
        var cx = W * (col + 0.5) / cols
        var cy = H * (rows - 0.5 - row) / rows
        graphics.noStroke()
        graphics.fill(Color(1, 1, 1, 0.88))
        graphics.rect(cx - hw[i] - pad, cy - fs/2 - pad, hw[i]*2 + pad*2, fs + pad*2)
        graphics.text(names[i], cx - hw[i], cy - fs/2, fs, Color(0, 0, 0))
    end

    graphics.text("Glisse pour tourner", 12, 12, 16, Color(1, 1, 1, 0.5))
end
