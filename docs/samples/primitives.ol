## Panorama des primitives 2D : une fonction par primitive, appelées depuis draw().
## px/py/fs mettent tout à l'échelle de la fenêtre (dessin conçu pour 700x520).
graphics.canvas(W, H, "Primitives")
var g = graphics
var t = 0

var sx = W / 700
var sy = H / 520
var ss = math.min(sx, sy)

func px(v) return v * sx end
func py(v) return v * sy end
func fs(v) return v * ss end

## Le canvas est en pixels PHYSIQUES : sur un mobile à 3 pixels par pixel CSS,
## une police mise à l'échelle du dessin devient illisible. dpr donne le rapport,
## et ft() garantit au moins la taille nominale telle qu'on la voit à l'écran.
var dpr = W / window.width
func ft(v) return math.max(v * ss, v * dpr) end

var dim = Color(0.6, 0.65, 0.75)

## Damier 8x8 construit pixel par pixel, pour la démonstration de spriteMode.
var tile = image.create(8, 8)
image.beginPixels(tile)
for y = 0, 7 do
    for x = 0, 7 do
        if (x + y) % 2 == 0 then
            image.setPixel(tile, x, y, 1, 0.6, 0.25, 1)
        else
            image.setPixel(tile, x, y, 0.25, 0.3, 0.5, 1)
        end
    end
end
image.endPixels(tile)

## Étiquette d'un bloc : coordonnées en unités du dessin, style commun à toutes.
func label(txt, x, y)
    g.stroke(dim)
    g.fontSize(ft(13))
    g.text(txt, px(x), py(y))
end

func demoPoint()
    g.stroke(Color(1, 0.85, 0.2), fs(8))
    g.point(px(55), py(45))
    label("point", 75, 38)
end

func demoLine()
    g.stroke(Color(0.4, 0.8, 1), fs(2))
    g.line(px(30), py(85), px(160), py(85))
    label("line", 170, 78)
end

func demoRect()
    g.stroke(Color(1, 0.4, 0.4), fs(2))
    g.noFill()
    g.rect(px(30), py(110), px(80), py(45))
    label("rect", 120, 125)
end

func demoFill()
    g.noStroke()
    g.fill(Color(0.3, 0.8, 0.45))
    g.rect(px(30), py(170), px(80), py(45))
    label("fill", 120, 185)
end

func demoStrokeFill()
    g.stroke(Color(1, 0.6, 0), fs(2))
    g.fill(Color(1, 0.6, 0, 0.25))
    g.rect(px(30), py(230), px(80), py(45))
    label("stroke+fill", 120, 245)
end

func demoPolyline()
    g.stroke(Color(0.5, 0.9, 1), fs(2))
    var wave = []
    for i = 0, 9 do
        wave[#wave+1] = px(30 + i * 18)
        wave[#wave+1] = py(305) + math.sin(t * 2 + i * 0.9) * py(22)
    end
    g.polyline(wave)
    label("polyline", 30, 340)
end

## 5e argument de rect = rayon des coins, en pixels (borné à la moitié du petit côté)
func demoRoundRect()
    g.stroke(Color(0.9, 0.7, 1), fs(2))
    g.fill(Color(0.9, 0.7, 1, 0.22))
    g.rect(px(30), py(362), px(80), py(45), fs(14))
    label("rect arrondi", 120, 378)
end

## Même point d'ancrage (le point blanc), deux modes : à gauche x,y = coin supérieur
## gauche, à droite x,y = centre. pushStyle isole le changement de mode.
func demoRectMode()
    var s = fs(34)
    g.pushStyle()
    do
        g.stroke(Color(0.6, 1, 0.8), fs(2))
        g.noFill()
        g.rect(px(265), py(345), s, s)
        g.rectMode("center")
        g.rect(px(365), py(345), s, s)
    end
    g.popStyle()
    g.stroke(Color(1, 1, 1), fs(3))
    g.point(px(265), py(345))
    g.point(px(365), py(345))
    label("rectMode corner / center", 250, 400)
end

## circle/ellipse sont centrés par défaut, à l'inverse de rect : le mode coin
## place ici le cercle en bas à droite du point d'ancrage.
func demoEllipseMode()
    var r = fs(18)
    g.pushStyle()
    do
        g.stroke(Color(1, 0.85, 0.5), fs(2))
        g.noFill()
        g.circle(px(70), py(430), r)
        g.ellipseMode("corner")
        g.circle(px(170), py(430), r)
    end
    g.popStyle()
    g.stroke(Color(1, 1, 1), fs(3))
    g.point(px(70), py(430))
    g.point(px(170), py(430))
    label("ellipseMode center / corner", 30, 480)
end

## Le mode centre des images vaut aussi pour image.draw.
func demoSpriteMode()
    var s = fs(40)
    g.pushStyle()
    do
        g.sprite(tile, px(330), py(430), s, s)
        g.spriteMode("center")
        g.sprite(tile, px(450), py(430), s, s)
    end
    g.popStyle()
    ## Point plus gros ici : celui du mode centre tombe sur le damier.
    g.stroke(Color(1, 1, 1), fs(5))
    g.point(px(330), py(430))
    g.point(px(450), py(430))
    label("spriteMode corner / center", 320, 503)
end

func demoCircle()
    g.stroke(Color(0.7, 0.5, 1), fs(2))
    g.fill(Color(0.7, 0.5, 1, 0.2))
    g.circle(px(310), py(55), fs(38))
    label("circle", 355, 48)
end

func demoEllipse()
    g.stroke(Color(0.3, 1, 0.7), fs(2))
    g.fill(Color(0.3, 1, 0.7, 0.2))
    g.ellipse(px(310), py(155), px(120), py(50))
    label("ellipse", 375, 148)
end

func demoPolygon()
    g.stroke(Color(1, 0.8, 0.3), fs(2))
    g.fill(Color(1, 0.8, 0.3, 0.2))
    var pts = []
    for i = 0, 4 do
        var a = t + i * math.TAU / 5
        pts[#pts+1] = px(310) + math.cos(a) * fs(42)
        pts[#pts+1] = py(255) + math.sin(a) * fs(42)
    end
    g.polygon(pts)
    label("polygon", 358, 250)
end

func demoStrokeSize()
    for i = 1, 4 do
        g.stroke(Color(0.9, 0.6, 0.3), fs(i * 2))
        g.line(px(470), py(65 + i * 28), px(640), py(65 + i * 28))
    end
    label("strokeSize", 470, 48)
end

## Deux carrés imbriqués : le second hérite de la transformation du premier.
func demoTransforms()
    g.push()
    do
        g.translate(px(560), py(200))
        g.rotate(t * 57.3)
        g.stroke(Color(0.8, 0.9, 1), fs(2))
        g.fill(Color(0.5, 0.7, 1, 0.25))
        g.rect(-fs(35), -fs(35), fs(70), fs(70))
        g.push()
        do
            g.scale(0.55)
            g.rotate(t * 57.3)
            g.fill(Color(1, 0.5, 0.5, 0.5))
            g.noStroke()
            g.rect(-fs(35), -fs(35), fs(70), fs(70))
        end
        g.pop()
    end
    g.pop()
    label("push/pop", 476, 246)
    label("translate", 476, 262)
    label("rotate/scale", 476, 278)
end

func demoText()
    label("text", 460, 310)
    g.stroke(Color(0.9, 0.9, 1))
    g.fontSize(ft(16))
    g.text("size 16", px(460), py(328))
    g.stroke(Color(0.7, 0.85, 1))
    g.fontSize(ft(22))
    g.text("size 22", px(460), py(352))
end

func demoArc()
    g.stroke(Color(1, 0.5, 0.7), fs(2))
    g.fill(Color(1, 0.5, 0.7, 0.25))
    g.arc(px(645), py(355), fs(70), fs(70), t, t + math.rad(250))
    label("arc", 630, 305)
end

func draw()
    t += 0.02
    g.clear(Color(0.08, 0.09, 0.12))
    demoPoint()
    demoLine()
    demoRect()
    demoFill()
    demoStrokeFill()
    demoPolyline()
    demoRoundRect()
    demoRectMode()
    demoEllipseMode()
    demoSpriteMode()
    demoCircle()
    demoEllipse()
    demoPolygon()
    demoStrokeSize()
    demoTransforms()
    demoText()
    demoArc()
end
