## The 3D primitives: cube, sphere, cylinder, plane, line, point, cone, torus.
## Drag to spin each primitive on itself.

## The mouse rotation lives in trackball.ol, a library shared by the 3D examples: the host
## relays the three mouse callbacks to it.
import "trackball.ol"
global ball = Trackball()
global cam = graphics.cameraOrtho(12, 12, 12,  0, 0, 0,  16)

## A grid suited to the orientation: 4x2 in landscape, 2x4 in portrait
## cellPos(col, row, cols, rows) → [x, z] in the XZ plane (isometric ortho view, size=16)
## Converts a grid position (col, row) into world XZ coordinates for the isometric camera
## looking from (12,12,12) at (0,0,0):
##   screen_x = (wx - wz) / √2  ;  screen_y = (-wx - wz) / √6  (with wy=0)
## We invert that system to get wx and wz from the target on screen.
func cellPos(col, row, cols, rows)
    var size  = 16.0
    var aspect = W / H
    var sx = (col - (cols - 1) / 2.0) * (size * aspect / cols)
    var sy = (row - (rows - 1) / 2.0) * (size / rows)
    var sqrt2 = 1.41421356
    var sqrt6 = 2.44948975
    var wx = (sx * sqrt2 - sy * sqrt6) / 2.0
    var wz = -(sx * sqrt2 + sy * sqrt6) / 2.0
    return [wx, wz]
end

func setup()
    graphics.canvas(W, H, "Primitives 3D")
    graphics.ambient(0.25)
    graphics.light("dir", -1, -2, -0.5)
end

## Mouse AND touch: on the web a finger drives the pointer, hence the same callbacks.
func mouse.pressed(x, y)
    ball.press(x, y)
end

func mouse.moved(x, y)
    ball.move(x, y)
end

func mouse.released(x, y)
    ball.release()
end

func draw()
    graphics.clear(Color(0.08, 0.08, 0.12))

    ## Landscape 4x2: cube sphere cylinder plane / lines cone torus (empty)
    ## Portrait 2x4: cube sphere / cylinder plane / lines cone / torus (empty)
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
        var p = cellPos(gc(0), gr(0), cols, rows)
        graphics.push()
            graphics.translate(p[1], 0, p[2])
            graphics.rotateq(ball.orient())
            graphics.fill(Color(0.9, 0.3, 0.3))
            graphics.cube(0, 0, 0,  2, 2, 2)
        graphics.pop()

        ## The sphere, index 1
        p = cellPos(gc(1), gr(1), cols, rows)
        graphics.push()
            graphics.translate(p[1], 0, p[2])
            graphics.rotateq(ball.orient())
            graphics.fill(Color(0.3, 0.7, 0.9))
            graphics.stroke(Color(1, 1, 1, 0.35))
            graphics.sphere(0, 0, 0,  1.4)
            graphics.noStroke()
        graphics.pop()

        ## Cylindre (idx 2)
        p = cellPos(gc(2), gr(2), cols, rows)
        graphics.push()
            graphics.translate(p[1], 0, p[2])
            graphics.rotateq(ball.orient())
            graphics.fill(Color(0.4, 0.85, 0.4))
            graphics.cylinder(0, -1.2, 0,  0.9, 2.4)
        graphics.pop()

        ## Plan (idx 3)
        p = cellPos(gc(3), gr(3), cols, rows)
        graphics.push()
            graphics.translate(p[1], 0, p[2])
            graphics.rotateq(ball.orient())
            graphics.rotateX(90)
            graphics.fill(Color(0.9, 0.7, 0.2, 0.75))
            graphics.plane(0, 0, 0,  2.5, 2.5)
        graphics.pop()

        ## line3d + point3d (idx 4)
        p = cellPos(gc(4), gr(4), cols, rows)
        graphics.push()
            graphics.translate(p[1], 0, p[2])
            graphics.rotateq(ball.orient())
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

        ## The cone, index 5
        p = cellPos(gc(5), gr(5), cols, rows)
        graphics.push()
            graphics.translate(p[1], 0, p[2])
            graphics.rotateq(ball.orient())
            graphics.fill(Color(0.9, 0.4, 0.8))
            graphics.cone(0, -1.2, 0,  1.0, 2.4)
        graphics.pop()

        ## Tore (idx 6)
        p = cellPos(gc(6), gr(6), cols, rows)
        graphics.push()
            graphics.translate(p[1], 0, p[2])
            graphics.rotateq(ball.orient())
            graphics.fill(Color(0.4, 0.9, 0.7))
            graphics.torus(0, 0, 0,  1.1, 0.4)
        graphics.pop()

        ## segments(8): the same sphere at a low resolution, index 7
        p = cellPos(gc(7), gr(7), cols, rows)
        graphics.push()
            graphics.translate(p[1], 0, p[2])
            graphics.rotateq(ball.orient())
            graphics.segments(6)
            graphics.fill(Color(0.3, 0.7, 0.9))
            graphics.sphere(0, 0, 0,  1.4)
        graphics.pop()

    graphics.end3d()

    ## The 2D labels: a white background, black text, centred on the cell
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
        graphics.stroke(Color(0, 0, 0))
        graphics.fontSize(fs)
        graphics.text(names[i], cx - hw[i], cy - fs/2)
    end

    graphics.stroke(Color(1, 1, 1, 0.5))
    graphics.fontSize(16)
    graphics.text("Glisse pour tourner", 12, 12)
end
