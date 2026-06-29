var W = window.width
var H = window.height

graphics.canvas(W, H, "Primitives")
var g = graphics
var t = 0

var sx = W / 700
var sy = H / 420
var ss = math.min(sx, sy)

func px(v) return v * sx end
func py(v) return v * sy end
func fs(v) return v * ss end

func frame()
    t += 0.02
    g.clear({r:0.08, g:0.09, b:0.12, a:1})
    var dim = {r:0.6, g:0.65, b:0.75, a:1}

    ## point
    g.stroke({r:1, g:0.85, b:0.2}, fs(8))
    g.point(px(55), py(45))
    g.draw_text("point", px(75), py(38), fs(13), dim)

    ## line
    g.stroke({r:0.4, g:0.8, b:1}, fs(2))
    g.line(px(30), py(85), px(160), py(85))
    g.draw_text("line", px(170), py(78), fs(13), dim)

    ## rect (stroke)
    g.stroke({r:1, g:0.4, b:0.4}, fs(2))
    g.fill()
    g.rect(px(30), py(110), px(80), py(45))
    g.draw_text("rect", px(120), py(125), fs(13), dim)

    ## rect (fill)
    g.stroke()
    g.fill({r:0.3, g:0.8, b:0.45})
    g.rect(px(30), py(170), px(80), py(45))
    g.draw_text("fill", px(120), py(185), fs(13), dim)

    ## rect (stroke+fill)
    g.stroke({r:1, g:0.6, b:0}, fs(2))
    g.fill({r:1, g:0.6, b:0, a:0.25})
    g.rect(px(30), py(230), px(80), py(45))
    g.draw_text("stroke+fill", px(120), py(245), fs(13), dim)

    ## polyline (animée)
    g.stroke({r:0.5, g:0.9, b:1}, fs(2))
    var wave = []
    for i = 0, 9 do
        wave[#wave+1] = px(30 + i * 18)
        wave[#wave+1] = py(305) + math.sin(t * 2 + i * 0.9) * py(22)
    end
    g.polyline(wave)
    g.draw_text("polyline", px(30), py(340), fs(13), dim)

    ## circle
    g.stroke({r:0.7, g:0.5, b:1}, fs(2))
    g.fill({r:0.7, g:0.5, b:1, a:0.2})
    g.circle(px(310), py(55), fs(38))
    g.draw_text("circle", px(355), py(48), fs(13), dim)

    ## ellipse
    g.stroke({r:0.3, g:1, b:0.7}, fs(2))
    g.fill({r:0.3, g:1, b:0.7, a:0.2})
    g.ellipse(px(310), py(155), px(120), py(50))
    g.draw_text("ellipse", px(375), py(148), fs(13), dim)

    ## polygon (rotation animée)
    g.stroke({r:1, g:0.8, b:0.3}, fs(2))
    g.fill({r:1, g:0.8, b:0.3, a:0.2})
    var pts = []
    for i = 0, 4 do
        var a = t + i * math.TAU / 5
        pts[#pts+1] = px(310) + math.cos(a) * fs(42)
        pts[#pts+1] = py(255) + math.sin(a) * fs(42)
    end
    g.polygon(pts)
    g.draw_text("polygon", px(358), py(250), fs(13), dim)

    ## strokeSize
    for i = 1, 4 do
        g.stroke({r:0.9, g:0.6, b:0.3}, fs(i * 2))
        g.line(px(470), py(65 + i * 28), px(640), py(65 + i * 28))
    end
    g.draw_text("strokeSize", px(470), py(48), fs(13), dim)

    ## push/pop/translate/rotate/scale
    g.push()
    g.translate(px(560), py(200))
    g.rotate(t * 57.3)
    g.stroke({r:0.8, g:0.9, b:1}, fs(2))
    g.fill({r:0.5, g:0.7, b:1, a:0.25})
    g.rect(-fs(35), -fs(35), fs(70), fs(70))
    g.push()
    g.scale(0.55)
    g.rotate(t * 57.3)
    g.fill({r:1, g:0.5, b:0.5, a:0.5})
    g.stroke()
    g.rect(-fs(35), -fs(35), fs(70), fs(70))
    g.pop()
    g.pop()
    g.draw_text("push/pop/translate", px(476), py(246), fs(13), dim)
    g.draw_text("rotate/scale", px(490), py(262), fs(13), dim)

    ## draw_text
    g.draw_text("draw_text", px(460), py(310), fs(13), dim)
    g.draw_text("size 16", px(460), py(328), fs(16), {r:0.9, g:0.9, b:1})
    g.draw_text("size 22", px(460), py(352), fs(22), {r:0.7, g:0.85, b:1})
end

graphics.run(frame)
