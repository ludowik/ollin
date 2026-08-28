## A solar eclipse: the Moon passes in front of the Sun. As it happens, the two discs look almost
## the same size to us, half a degree across, and from that near-equality come the eclipse's three
## forms. With the Moon slightly larger than the Sun it hides it entirely — the TOTAL eclipse, the
## only moment the corona shows itself. Slightly smaller, a ring of fire remains — the ANNULAR
## one. Off to one side, it bites out no more than a piece: PARTIAL.
##
## This example's counterpart is "Lunar eclipse", where the Earth casts the shadow.
##
## The obscuration is computed exactly: the area where the two discs intersect, over the Sun's own.
## It is that figure which governs the landscape's light.

## Per type: the Moon's radius in SOLAR radii (`ratio`), and the least distance between the
## centres (`offset`). The real ratio runs from 0.95 to 1.08 with the distances of the moment; it
## is exaggerated a little here so that totality lasts longer than an instant, since it otherwise
## takes up about 2 % of the passage.
global TYPES = {
    "total":    {ratio: 1.15, offset: 0.0},
    "annular":  {ratio: 0.92, offset: 0.0},
    "partial":  {ratio: 1.05, offset: 0.80}
}

const TRAVEL = 30.0    ## seconds for the whole passage, at speed 1

global config = {type: "total", speed: 1.0}
global u = 0.0           ## the passage's progress, from 0 to 1
global stars = []
global hills = []     ## the horizon's outline, as sampled heights

func sunRadius()
    return math.min(W, H) * 0.13
end

func sunX()
    return CW
end

func sunY()
    return H * 0.42
end

## The Moon crosses horizontally, offset by the chosen type's own offset.
func moonX()
    var reach = 2.4 * sunRadius()
    return sunX() - reach + 2 * reach * u
end

func moonY()
    return sunY() + TYPES[config.type].offset * sunRadius()
end

func moonRadius()
    return sunRadius() * TYPES[config.type].ratio
end

func centreDist()
    var dx = moonX() - sunX()
    var dy = moonY() - sunY()
    return math.sqrt(dx * dx + dy * dy)
end

## The area two discs share — exact geometry, with no approximation: two circular sectors minus
## the quadrilateral they have in common, the latter through Heron's formula.
func lensArea(r1, r2, d)
    if d >= r1 + r2 then
        return 0.0
    end
    if d <= math.abs(r1 - r2) then
        var rp = math.min(r1, r2)
        return math.PI * rp * rp
    end
    var a1 = math.acos((d * d + r1 * r1 - r2 * r2) / (2 * d * r1))
    var a2 = math.acos((d * d + r2 * r2 - r1 * r1) / (2 * d * r2))
    var h = (r1 + r2 - d) * (d + r1 - r2) * (d - r1 + r2) * (d + r1 + r2)
    return r1 * r1 * a1 + r2 * r2 * a2 - 0.5 * math.sqrt(math.max(h, 0))
end

## The fraction of the solar disc hidden: it is the quantity everything else follows from.
func obscuration()
    var rs = sunRadius()
    return lensArea(rs, moonRadius(), centreDist()) / (math.PI * rs * rs)
end

func phase()
    var d = centreDist()
    var rs = sunRadius()
    var rl = moonRadius()
    if d >= rs + rl then
        return "no eclipse"
    end
    if d <= math.abs(rl - rs) then
        return rl >= rs and "total" or "annular"
    end
    return "partial"
end

## The ambient light, between 0 and 1. The eye is logarithmic: losing half the solar disc does not
## halve the brightness, and the day only collapses in the very last few per cent. Totality, for
## its part, drops the light by a factor of about ten thousand — hence the final step, which is
## quite real.
func light()
    if phase() == "total" then
        return 0.03
    end
    var o = obscuration()
    return math.clamp(0.10 + 0.90 * math.pow(1 - o, 0.45), 0.03, 1.0)
end

func setup()
    graphics.canvas(W, H, "Solar eclipse")
    math.noiseSeed(5)

    for i = 1, 160 do
        stars[#stars + 1] = math.rand(0, W)
        stars[#stars + 1] = math.rand(0, H * 0.72)
        stars[#stars + 1] = math.rand(0.2, 1.0)
    end
    ## The horizon: one height every twelve pixels, drawn from the noise, which gives soft hills.
    for x = 0, W + 12, 12 do
        hills[#hills + 1] = H * 0.80 + math.noise(x * 0.004, 3) * H * 0.10
    end

    var menu = ui.menu("Eclipse")
    menu.list("Type", TYPES, ref config.type)
    menu.slider("Speed", ref config.speed, 0.1, 4)
    ui.show(menu)
end

## The sky: a full-daylight blue that drains of its brightness, never quite black — the corona and
## the horizon keep a glow, as at dusk. The colour is a FUNCTION because the Moon uses it
## as well: away from the Sun, one does not see the Moon at all.
func skyColor(l)
    return Color(0.05 + 0.30 * l, 0.09 + 0.42 * l, 0.16 + 0.62 * l)
end

func drawSky(l)
    graphics.clear(skyColor(l))
end

## The stars only appear with the darkness: invisible by day, plain in totality, like the bright
## planets one discovers then.
func drawStars(l)
    if l > 0.35 then
        return
    end
    var a = (0.35 - l) / 0.32
    for i = 1, #stars, 3 do
        var e = stars[i + 2]
        graphics.stroke(Color(0.9, 0.94, 1, math.clamp(a * e, 0, 1)), e * 2)
        graphics.point(stars[i], stars[i + 1])
    end
end

func drawHorizon(l)
    graphics.noStroke()
    graphics.fill(Color(0.04 + 0.10 * l, 0.05 + 0.12 * l, 0.07 + 0.13 * l))
    var pts = []
    for i, h in hills do
        pts[#pts + 1] = (i - 1) * 12
        pts[#pts + 1] = h
    end
    pts[#pts + 1] = W
    pts[#pts + 1] = H
    pts[#pts + 1] = 0
    pts[#pts + 1] = H
    graphics.polygon(pts)
end

## The halo: concentric discs in ADDITIVE blending, from the widest to the narrowest. Adding
## imitates glare — the light adds to the sky instead of replacing it. MANY steps at a low opacity:
## seven well-marked steps drew concentric rings instead of a gradient.
func drawHalo(l)
    var rs = sunRadius()
    graphics.blendMode(blend.ADD)
    graphics.noStroke()
    for k = 1, 22 do
        var r = rs * (1 + 1.5 * k / 22)
        graphics.fill(Color(0.5, 0.42, 0.24, 0.016 * l))
        graphics.circle(sunX(), sunY(), r)
    end
    graphics.blendMode(blend.ALPHA)
end

## The corona is visible ONLY when the photosphere is entirely hidden. Its streamers are irregular,
## and an angular noise gives that filamentary structure.
func drawCorona()
    var rl = moonRadius()
    graphics.blendMode(blend.ADD)
    ## The inner halo, dense near the limb and fading outwards: it is what gives the corona
    ## its pearly look, the streamers doing no more than streaking it.
    graphics.noStroke()
    for k = 1, 18 do
        var f = k / 18
        graphics.fill(Color(0.48, 0.52, 0.58, 0.05 * (1 - f)))
        graphics.circle(sunX(), sunY(), rl * (1 + 1.5 * f))
    end
    ## The streamers: each in FOUR segments of decreasing opacity — a stroke of constant opacity
    ## ended abruptly, and the whole looked like a brush.
    for i = 0, 419 do
        var ang = i * math.TAU / 420
        var n = math.noise(math.cos(ang) * 1.3 + 8, math.sin(ang) * 1.3 + 8)
        var length = rl * (0.25 + 1.7 * n * n)
        for k = 0, 3 do
            var r0 = rl * 0.99 + length * k / 4
            var r1 = rl * 0.99 + length * (k + 1) / 4
            graphics.stroke(Color(0.62, 0.65, 0.70, 0.13 - 0.028 * k), 1)
            graphics.line(sunX() + math.cos(ang) * r0, sunY() + math.sin(ang) * r0,
                          sunX() + math.cos(ang) * r1, sunY() + math.sin(ang) * r1)
        end
    end
    graphics.blendMode(blend.ALPHA)
end

func draw()
    u += deltaTime * config.speed / TRAVEL
    if u > 1 then
        u = 0.0
    end

    var l = light()
    var rs = sunRadius()
    var rl = moonRadius()
    var isTotal = phase() == "total"

    drawSky(l)
    drawStars(l)

    ## The solar disc, then the corona, then the Moon ON TOP: that is the real stacking order,
    ## and it is enough to carve the crescent out — no intersection need be computed to draw it,
    ## since the Moon hides whatever it covers.
    graphics.noStroke()
    graphics.fill(Color(1, 0.97, 0.86))
    graphics.circle(sunX(), sunY(), rs)

    if isTotal then
        drawCorona()
        ## The chromosphere: a thin pink border the Moon leaves visible just beyond its limb.
        ## Drawn before the Moon, only a fine line of it remains.
        graphics.fill(Color(1, 0.35, 0.35, 0.55))
        graphics.circle(moonX(), moonY(), rl * 1.03)
    end

    ## The Moon takes THE SKY'S COLOUR, barely darkened: away from the Sun one does not see it
    ## at all — a black disc on the blue of day would be an invention. In front of the Sun it
    ## hides it just as well.
    var c = skyColor(l)
    graphics.fill(Color(c.r * 0.90, c.g * 0.90, c.b * 0.92))
    graphics.circle(moonX(), moonY(), rl)

    ## The halo comes AFTER the Moon: the light the atmosphere scatters lies between the Moon and
    ## us, so it veils the Moon as well. In totality there is almost nothing left to scatter.
    drawHalo(l)

    drawHorizon(l)

    graphics.fontSize(H * 0.032)
    graphics.stroke(Color(0.92, 0.93, 0.97))
    graphics.text("{phase()}   obscuration {obscuration() * 100:.1f} %", W * 0.04, H * 0.05)
    graphics.fontSize(H * 0.024)
    graphics.stroke(Color(0.68, 0.72, 0.82))
    graphics.text("{config.type} eclipse   -   light {l * 100:.0f} %", W * 0.04, H * 0.10)
end
