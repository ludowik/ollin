## Panorama des primitives 2D. px/py/fs mettent tout à l'échelle de la fenêtre
## (dessin conçu pour 700x420). Chaque bloc dessine une primitive + son étiquette.
graphics.canvas(W, H, "Primitives")
var g = graphics
var t = 0

var sx = W / 700
var sy = H / 420
var ss = math.min(sx, sy)

func px(v) return v * sx end
func py(v) return v * sy end
func fs(v) return v * ss end

func draw()
    t += 0.02
    g.clear(Color(0.08, 0.09, 0.12))
    var dim = Color(0.6, 0.65, 0.75)

    g.stroke(Color(1, 0.85, 0.2), fs(8))
    g.point(px(55), py(45))
    g.text("point", px(75), py(38), fs(13), dim)

    g.stroke(Color(0.4, 0.8, 1), fs(2))
    g.line(px(30), py(85), px(160), py(85))
    g.text("line", px(170), py(78), fs(13), dim)

    g.stroke(Color(1, 0.4, 0.4), fs(2))
    g.noFill()
    g.rect(px(30), py(110), px(80), py(45))
    g.text("rect", px(120), py(125), fs(13), dim)

    g.noStroke()
    g.fill(Color(0.3, 0.8, 0.45))
    g.rect(px(30), py(170), px(80), py(45))
    g.text("fill", px(120), py(185), fs(13), dim)

    g.stroke(Color(1, 0.6, 0), fs(2))
    g.fill(Color(1, 0.6, 0, 0.25))
    g.rect(px(30), py(230), px(80), py(45))
    g.text("stroke+fill", px(120), py(245), fs(13), dim)

    g.stroke(Color(0.5, 0.9, 1), fs(2))
    var wave = []
    for i = 0, 9 do
        wave[#wave+1] = px(30 + i * 18)
        wave[#wave+1] = py(305) + math.sin(t * 2 + i * 0.9) * py(22)
    end
    g.polyline(wave)
    g.text("polyline", px(30), py(340), fs(13), dim)

    g.stroke(Color(0.7, 0.5, 1), fs(2))
    g.fill(Color(0.7, 0.5, 1, 0.2))
    g.circle(px(310), py(55), fs(38))
    g.text("circle", px(355), py(48), fs(13), dim)

    g.stroke(Color(0.3, 1, 0.7), fs(2))
    g.fill(Color(0.3, 1, 0.7, 0.2))
    g.ellipse(px(310), py(155), px(120), py(50))
    g.text("ellipse", px(375), py(148), fs(13), dim)

    g.stroke(Color(1, 0.8, 0.3), fs(2))
    g.fill(Color(1, 0.8, 0.3, 0.2))
    var pts = []
    for i = 0, 4 do
        var a = t + i * math.TAU / 5
        pts[#pts+1] = px(310) + math.cos(a) * fs(42)
        pts[#pts+1] = py(255) + math.sin(a) * fs(42)
    end
    g.polygon(pts)
    g.text("polygon", px(358), py(250), fs(13), dim)

    for i = 1, 4 do
        g.stroke(Color(0.9, 0.6, 0.3), fs(i * 2))
        g.line(px(470), py(65 + i * 28), px(640), py(65 + i * 28))
    end
    g.text("strokeSize", px(470), py(48), fs(13), dim)

    g.push()
    g.translate(px(560), py(200))
    g.rotate(t * 57.3)
    g.stroke(Color(0.8, 0.9, 1), fs(2))
    g.fill(Color(0.5, 0.7, 1, 0.25))
    g.rect(-fs(35), -fs(35), fs(70), fs(70))
    g.push()
    g.scale(0.55)
    g.rotate(t * 57.3)
    g.fill(Color(1, 0.5, 0.5, 0.5))
    g.noStroke()
    g.rect(-fs(35), -fs(35), fs(70), fs(70))
    g.pop()
    g.pop()
    g.text("push/pop/translate", px(476), py(246), fs(13), dim)
    g.text("rotate/scale", px(490), py(262), fs(13), dim)

    g.text("text", px(460), py(310), fs(13), dim)
    g.text("size 16", px(460), py(328), fs(16), Color(0.9, 0.9, 1))
    g.text("size 22", px(460), py(352), fs(22), Color(0.7, 0.85, 1))
end
