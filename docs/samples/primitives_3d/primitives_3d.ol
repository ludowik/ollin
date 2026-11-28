## The 3D primitives: cube, sphere, cylinder, plane, line, point, cone, torus.

## The mouse rotation lives in trackball.ol, a library shared by the 3D examples: the host
## relays the three mouse callbacks to it.
import "../lib/trackball.ol"
global ball = Trackball()
global cam = gfx.cameraOrtho(12, 12, 12,  0, 0, 0,  16)

## A grid cell (col, row) to world XZ coordinates, for the isometric camera looking from
## (12,12,12) at the origin, where screen_x = (wx - wz) / √2 and screen_y = (-wx - wz) / √6
## with wy = 0. The system below is that pair INVERTED: it solves for wx and wz from the
## position wanted on screen.
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
    gfx.canvas(W, H, "Primitives 3D")
    gfx.ambient(0.25)
    gfx.light("dir", -1, -2, -0.5)
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
    gfx.clear(Color(0.08, 0.08, 0.12))

    ## Four columns in landscape, two in portrait: eight cells either way.
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

    gfx.noStroke()
    gfx.begin3d(cam)

        ## cube
        var p = cellPos(gc(0), gr(0), cols, rows)
        gfx.push()
            gfx.translate(p[1], 0, p[2])
            gfx.rotateQuat(ball.orient())
            gfx.fill(Color(0.9, 0.3, 0.3))
            gfx.cube(0, 0, 0,  2, 2, 2)
        gfx.pop()

        ## sphere
        p = cellPos(gc(1), gr(1), cols, rows)
        gfx.push()
            gfx.translate(p[1], 0, p[2])
            gfx.rotateQuat(ball.orient())
            gfx.fill(Color(0.3, 0.7, 0.9))
            gfx.stroke(Color(1, 1, 1, 0.35))
            gfx.sphere(0, 0, 0,  1.4)
            gfx.noStroke()
        gfx.pop()

        ## cylinder
        p = cellPos(gc(2), gr(2), cols, rows)
        gfx.push()
            gfx.translate(p[1], 0, p[2])
            gfx.rotateQuat(ball.orient())
            gfx.fill(Color(0.4, 0.85, 0.4))
            gfx.cylinder(0, -1.2, 0,  0.9, 2.4)
        gfx.pop()

        ## plane
        p = cellPos(gc(3), gr(3), cols, rows)
        gfx.push()
            gfx.translate(p[1], 0, p[2])
            gfx.rotateQuat(ball.orient())
            gfx.rotateX(90)
            gfx.fill(Color(0.9, 0.7, 0.2, 0.75))
            gfx.plane(0, 0, 0,  2.5, 2.5)
        gfx.pop()

        ## line3d and point3d
        p = cellPos(gc(4), gr(4), cols, rows)
        gfx.push()
            gfx.translate(p[1], 0, p[2])
            gfx.rotateQuat(ball.orient())
            gfx.stroke(Color(1, 0.5, 0.1))
            gfx.strokeSize(4)
            gfx.line3d(-1.8, -1.8, -1.8,   1.8,  1.8,  1.8)
            gfx.line3d(-1.8, -1.8,  1.8,   1.8,  1.8, -1.8)
            gfx.line3d( 1.8, -1.8, -1.8,  -1.8,  1.8,  1.8)
            gfx.strokeSize(6)
            for i = 1, 40 do
                var t = i * 2.399
                var r = 1.0 * math.sqrt(i / 40.0)
                gfx.stroke(Color(0.3 + r * 0.5, 0.5 + r * 0.2, 1.0 - r * 0.4))
                gfx.point3d(r * math.cos(t), r * math.sin(t), math.sin(t * 2) * 0.4)
            end
            gfx.stroke(palette.WHITE)
            gfx.strokeSize(10)
            gfx.point3d(0, 0, 0)
            gfx.strokeSize(1)
            gfx.noStroke()
        gfx.pop()

        ## cone
        p = cellPos(gc(5), gr(5), cols, rows)
        gfx.push()
            gfx.translate(p[1], 0, p[2])
            gfx.rotateQuat(ball.orient())
            gfx.fill(Color(0.9, 0.4, 0.8))
            gfx.cone(0, -1.2, 0,  1.0, 2.4)
        gfx.pop()

        ## torus
        p = cellPos(gc(6), gr(6), cols, rows)
        gfx.push()
            gfx.translate(p[1], 0, p[2])
            gfx.rotateQuat(ball.orient())
            gfx.fill(Color(0.4, 0.9, 0.7))
            gfx.torus(0, 0, 0,  1.1, 0.4)
        gfx.pop()

        ## the same sphere at a low resolution
        p = cellPos(gc(7), gr(7), cols, rows)
        gfx.push()
            gfx.translate(p[1], 0, p[2])
            gfx.rotateQuat(ball.orient())
            gfx.segments(6)
            gfx.fill(Color(0.3, 0.7, 0.9))
            gfx.sphere(0, 0, 0,  1.4)
        gfx.pop()

    gfx.end3d()

    var pad = 4
    var names = ["cube", "sphere", "cylinder", "plane", "line3d/point3d", "cone", "torus", "segments(6)"]
    gfx.fontSize(13)
    for i = 1, 8 do
        var idx = i - 1
        var col = idx % cols
        var row = idx // cols
        var cx = W * (col + 0.5) / cols
        var cy = H * (rows - 0.5 - row) / rows
        ## The label is MEASURED rather than guessed: a hand-written table of half-widths had to be
        ## revised at every rename, and drifted with the font and the size in any case.
        var tw, th = gfx.measureText(names[i])
        gfx.noStroke()
        gfx.fill(Color(1, 1, 1, 0.88))
        gfx.rect(cx - tw/2 - pad, cy - th/2 - pad, tw + pad*2, th + pad*2)
        gfx.stroke(Color(0, 0, 0))
        gfx.text(names[i], cx - tw/2, cy - th/2)
    end

    gfx.stroke(Color(1, 1, 1, 0.5))
    gfx.fontSize(16)
    gfx.text("Drag to turn", 12, 12)
end
