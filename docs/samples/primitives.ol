var W = window.width
var H = window.height

graphics.canvas(W, H, "Primitives")
var g = graphics
var t = 0

func frame()
    t += 0.02
    g.clear({r:0.08, g:0.09, b:0.12, a:1})
    var dim = {r:0.6, g:0.65, b:0.75, a:1}

    ## point
    g.stroke({r:1, g:0.85, b:0.2}, 8)
    g.point(55, 45)
    g.draw_text("point", 75, 38, 13, dim)

    ## line
    g.stroke({r:0.4, g:0.8, b:1}, 2)
    g.line(30, 85, 160, 85)
    g.draw_text("line", 170, 78, 13, dim)

    ## rect (stroke)
    g.stroke({r:1, g:0.4, b:0.4}, 2)
    g.fill()
    g.rect(30, 110, 80, 45)
    g.draw_text("rect", 120, 125, 13, dim)

    ## rect (fill)
    g.stroke()
    g.fill({r:0.3, g:0.8, b:0.45})
    g.rect(30, 170, 80, 45)
    g.draw_text("fill", 120, 185, 13, dim)

    ## rect (stroke+fill)
    g.stroke({r:1, g:0.6, b:0}, 2)
    g.fill({r:1, g:0.6, b:0, a:0.25})
    g.rect(30, 230, 80, 45)
    g.draw_text("stroke+fill", 120, 245, 13, dim)

    ## polyline (animée)
    g.stroke({r:0.5, g:0.9, b:1}, 2)
    var wave = []
    for i = 0, 9 do
        wave[#wave+1] = 30 + i * 18
        wave[#wave+1] = 305 + math.sin(t * 2 + i * 0.9) * 22
    end
    g.polyline(wave)
    g.draw_text("polyline", 30, 340, 13, dim)

    ## circle
    g.stroke({r:0.7, g:0.5, b:1}, 2)
    g.fill({r:0.7, g:0.5, b:1, a:0.2})
    g.circle(310, 55, 38)
    g.draw_text("circle", 355, 48, 13, dim)

    ## ellipse
    g.stroke({r:0.3, g:1, b:0.7}, 2)
    g.fill({r:0.3, g:1, b:0.7, a:0.2})
    g.ellipse(310, 155, 120, 50)
    g.draw_text("ellipse", 375, 148, 13, dim)

    ## polygon (rotation animée)
    g.stroke({r:1, g:0.8, b:0.3}, 2)
    g.fill({r:1, g:0.8, b:0.3, a:0.2})
    var pts = []
    for i = 0, 4 do
        var a = t + i * math.TAU / 5
        pts[#pts+1] = 310 + math.cos(a) * 42
        pts[#pts+1] = 255 + math.sin(a) * 42
    end
    g.polygon(pts)
    g.draw_text("polygon", 358, 250, 13, dim)

    ## strokeSize
    for i = 1, 4 do
        g.stroke({r:0.9, g:0.6, b:0.3}, i * 2)
        g.line(470, 65 + i * 28, 640, 65 + i * 28)
    end
    g.draw_text("strokeSize", 470, 48, 13, dim)

    ## push/pop/translate/rotate/scale
    g.push()
    g.translate(560, 200)
    g.rotate(t * 57.3)
    g.stroke({r:0.8, g:0.9, b:1}, 2)
    g.fill({r:0.5, g:0.7, b:1, a:0.25})
    g.rect(-35, -35, 70, 70)
    g.push()
    g.scale(0.55)
    g.rotate(t * 57.3)
    g.fill({r:1, g:0.5, b:0.5, a:0.5})
    g.stroke()
    g.rect(-35, -35, 70, 70)
    g.pop()
    g.pop()
    g.draw_text("push/pop/translate", 476, 246, 13, dim)
    g.draw_text("rotate/scale", 490, 262, 13, dim)

    ## draw_text
    g.draw_text("draw_text", 460, 310, 13, dim)
    g.draw_text("size 16", 460, 328, 16, {r:0.9, g:0.9, b:1})
    g.draw_text("size 22", 460, 352, 22, {r:0.7, g:0.85, b:1})

    g.draw_text("FPS: " + g.fps(), 4, H-18, 13, {r:0.4, g:0.45, b:0.55})
end

graphics.run(frame)
