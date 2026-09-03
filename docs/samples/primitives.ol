## A tour of the 2D primitives: one function per primitive, all called from draw().
## px, py and fs scale everything to the window; the drawing was designed for 700x600.
const g = graphics
const DIM = Color(0.6, 0.65, 0.75)

global t = 0
global tile = nil

## The drawing was designed for 700x600 and is scaled to the window. Nothing is cached: these are
## pure functions of W, H and window.width, so the drawing follows a canvas that changes size
## instead of staying frozen on the values read at startup.
func px(v) return v * W / 700 end
func py(v) return v * H / 600 end
func fs(v) return v * math.min(W / 700, H / 600) end

## The canvas is in PHYSICAL pixels: on a phone with three pixels per CSS pixel, a font scaled
## with the drawing becomes unreadable. W / window.width gives that ratio, and ft() guarantees at
## least the nominal size as it appears on screen.
func ft(v) return math.max(fs(v), v * W / window.width) end

## An 8x8 checkerboard built pixel by pixel, for the spriteMode demonstration.
func buildTile()
    tile = image.create(8, 8)
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
end

func setup()
    graphics.canvas(W, H, "Primitives")
    buildTile()
end

func label(txt, x, y)
    g.stroke(DIM)
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
    ## Many close points: the polyline passes for a smooth curve.
    var wave = []
    for i = 0, 48 do
        wave[#wave+1] = px(30 + i * 3.375)
        wave[#wave+1] = py(305) + math.sin(t * 2 + i * 0.18) * py(22)
    end
    g.polyline(wave)
    label("polyline", 30, 340)
end

## rect's fifth argument is the corner radius, in pixels, clamped to half the shorter side
func demoRoundRect()
    g.stroke(Color(0.9, 0.7, 1), fs(2))
    g.fill(Color(0.9, 0.7, 1, 0.22))
    g.rect(px(30), py(362), px(80), py(45), fs(14))
    label("rounded rect", 120, 378)
end

## The same anchor point, the white dot, in two modes: on the left x,y is the top-left corner, on
## the right x,y is the centre. pushStyle keeps the change of mode local.
func demoRectMode()
    var s = fs(34)
    g.pushStyle()
    do
        g.stroke(Color(0.6, 1, 0.8), fs(2))
        g.noFill()
        g.rect(px(265), py(345), s, s)
        g.rectMode("center")
        g.rect(px(333), py(345), s, s)
    end
    g.popStyle()
    g.stroke(Color(1, 1, 1), fs(3))
    g.point(px(265), py(345))
    g.point(px(333), py(345))
    label("rectMode corner / center", 250, 388)
end

## circle and ellipse are centred by default, unlike rect: the corner mode puts the circle below
## and to the right of the anchor point here.
func demoEllipseMode()
    var r = fs(18)
    g.pushStyle()
    do
        g.stroke(Color(1, 0.85, 0.5), fs(2))
        g.noFill()
        g.circle(px(70), py(430), r)
        g.ellipseMode("corner")
        g.circle(px(138), py(430), r)
    end
    g.popStyle()
    g.stroke(Color(1, 1, 1), fs(3))
    g.point(px(70), py(430))
    g.point(px(138), py(430))
    label("ellipseMode center / corner", 30, 468)
end

## The centre mode for sprites holds for image.draw as well.
func demoSpriteMode()
    var s = fs(40)
    g.pushStyle()
    do
        g.sprite(tile, px(330), py(430), s, s)
        g.spriteMode("center")
        g.sprite(tile, px(408), py(430), s, s)
    end
    g.popStyle()
    ## A bigger dot here: the one for the centre mode falls on the checkerboard.
    g.stroke(Color(1, 1, 1), fs(5))
    g.point(px(330), py(430))
    g.point(px(408), py(430))
    label("spriteMode corner / center", 320, 480)
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
        var y = py(66 + i * 16)
        g.stroke(Color(0.9, 0.6, 0.3), fs(i * 2))
        g.line(px(470), y, px(640), y)
    end
    label("strokeSize", 470, 48)
end

## Two nested squares: the second inherits the first one's transform.
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

## The font is a STYLE, like fill or fontSize: it stays in place until
## the next graphics.font, hence the pushStyle that gives the previous font back to the
## demonstrations that follow.
func demoText()
    label("text / font", 460, 300)
    g.pushStyle()
    do
        g.fontSize(ft(15))
        g.stroke(Color(0.9, 0.9, 1))
        g.font("sans")
        g.text("Ollin — sans", px(460), py(314))
        g.stroke(Color(0.7, 0.85, 1))
        g.font("mono")
        g.text("Ollin — mono", px(460), py(334))
        g.stroke(Color(0.9, 0.9, 1))
        g.font("sans")
        g.fontSize(ft(22))
        g.text("size 22", px(460), py(358))
    end
    g.popStyle()
end

## textMode anchors text on the two axes, and the red marks show the point given to graphics.text:
## a vertical tick for the horizontal modes, a single line for the vertical ones. Each mode is
## paired with its position in one table, so the two can never fall out of step; the positions are
## written out rather than strided from the index, which is how a word once landed off the canvas.
func demoTextMode()
    label("textMode: left / center / right", 30, 512)
    g.pushStyle()
    do
        g.fontSize(ft(16))
        for entry in [[px(205), "left"], [px(295), "center"], [px(385), "right"]] do
            var x = entry[1]
            g.stroke(Color(1, 0.4, 0.4), fs(1))
            g.line(x, py(524), x, py(556))
            g.stroke(Color(0.9, 0.9, 1))
            g.textMode(entry[2])
            g.text("Hxg", x, py(528))
        end
    end
    g.popStyle()

    ## TWO sizes per mark, and that is the whole point: "top" lines up the tops of the boxes,
    ## "bottom" their bottoms, and only "baseline" puts both writings on the same line.
    label("top / center / bottom / baseline", 425, 512)
    g.pushStyle()
    do
        var big = ft(16)
        var small = ft(10)
        g.stroke(Color(1, 0.4, 0.4), fs(1))
        g.line(px(425), py(548), px(690), py(548))
        g.stroke(Color(0.9, 0.9, 1))
        for entry in [[px(427), "top"], [px(493), "center"], [px(559), "bottom"], [px(625), "baseline"]] do
            var x = entry[1]
            g.textMode("left", entry[2])
            g.fontSize(big)
            g.text("Hxg", x, py(548))
            g.fontSize(small)
            g.text("Hxg", x + px(37), py(548))
        end
    end
    g.popStyle()
end

func demoArc()
    g.stroke(Color(1, 0.5, 0.7), fs(2))
    g.fill(Color(1, 0.5, 0.7, 0.25))
    g.arc(px(645), py(355), fs(70), fs(70), t, t + math.rad(250))
    label("arc", 630, 305)
end

## The clock the demonstrations read. A time in SECONDS and not a fixed increment per frame: the
## animations kept their speed only as long as the display ran at 60 Hz. The 1.2 is that speed, in
## radians per second.
func update(dt)
    t += dt * 1.2
end

func draw()
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
    demoTextMode()
    demoArc()
end
