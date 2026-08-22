## A lunar eclipse, seen from the Earth. The Moon crosses the shadow cone the Earth casts: it first
## darkens in the PENUMBRA, faintly on entering and then very
## nettement en approchant du bord de l'ombre — la Terre y masque presque tout le Soleil.
## It then bites into the UMBRA, where it takes a coppery hue. That red is the sunlight refracted by
## the Earth's atmosphere: the blue is scattered there, the red goes through.
##
## Two scales describe everything, in lunar radii: the umbra is about 2.7 across and the penumbra
## about 4.6 at the Moon's distance. The rest is nothing but the geometry of two discs.
##
## The menu chooses the kind of eclipse — the offset between the Moon and the shadow's axis — the
## speed, and whether the markers are shown.
##
## Le pendant de cet exemple est « Éclipse de Soleil », où c'est la Lune qui masque.

const R_UMBRA = 2.7      ## the shadow cone's radius, in lunar radii
const R_PENUMBRA = 4.6   ## the penumbra's radius
const DURATION_H = 6.0      ## the simulated hours of the whole passage

## The Moon's offset from the shadow's axis, in lunar radii: it is THAT which decides the kind of
## eclipse. The menu's list shows and returns this map's KEYS, following the `for … in` rule, and
## the program reads the value attached. The keys are QUOTED: a literal key may be a string, which
## allows a space here where an identifier would refuse one.
global OFFSETS = {"total": 0.15, "partial": 2.2, "penumbral": 4.2}

## `type` is set in advance: a list honours an existing selection and only imposes its first item on
## a nil variable — alphabetical order would give "partial".
global config = {type: "total", speed: 1.0, marks: false}

global moon = nil        ## texture du disque lunaire, construite une fois
global stars = []      ## the fixed background: [x, y, brightness, …]
global t = 0.0           ## the simulation's progress, in simulated hours

## Small enough for the PENUMBRA's circle to fit on screen, at 4.6 lunar radii: it is that scale
## which gives a fair idea of the sizes involved.
func moonRadius()
    return math.min(W, H) * 0.085
end

## The lunar disc is drawn ONCE into an image: craters from noise at two scales, a darkened limb
## since the sphere turns away, and an edge softened by one pixel, without which stair-steps show.
func buildMoon(size)
    moon = image.create(size, size)
    var r = size / 2.0
    image.beginPixels(moon)
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            var dx = x - r + 0.5
            var dy = y - r + 0.5
            var d = math.sqrt(dx * dx + dy * dy)
            if d > r then
                image.setPixel(moon, x, y, 0, 0, 0, 0)
            else
                var n = math.noise(x * 0.05, y * 0.05) * 0.65
                       + math.noise(x * 0.19, y * 0.19) * 0.35
                var g = math.clamp(0.66 + (n - 0.5) * 0.42, 0, 1)
                ## Éclairement du limbe : la normale s'incline vers le bord du disque.
                var f = math.sqrt(math.max(1 - (d / r) * (d / r), 0))
                g = g * (0.55 + 0.45 * f)
                image.setPixel(moon, x, y, g, g * 0.97, g * 0.92, math.clamp(r - d, 0, 1))
            end
        end
    end
    image.endPixels(moon)
end

func setup()
    graphics.canvas(W, H, "Éclipse de Lune")
    math.noiseSeed(11)
    buildMoon(256)
    buildVeil()

    for i = 1, 220 do
        stars[#stars + 1] = math.rand(0, W)
        stars[#stars + 1] = math.rand(0, H)
        stars[#stars + 1] = math.rand(0.15, 1.0)
    end

    var menu = ui.menu("Éclipse")
    menu.list("Type", OFFSETS, ref config.type)
    menu.slider("Vitesse", ref config.speed, 0.1, 4)
    menu.checkbox("Markers", ref config.marks)
    ui.show(menu)
end

## The shadow's centre is fixed on screen. The Moon, for its part, drifts horizontally: it really is
## the Moon that moves along its orbit, the shadow following the antisolar point far more slowly.
func umbraCentre()
    return CH
end

## The Moon's position at time t: a straight path, offset by the chosen amount.
func moonX()
    var rl = moonRadius()
    var reach = (R_PENUMBRA + 1.6) * rl
    return CW - reach + 2 * reach * (t / DURATION_H)
end

func moonY()
    return umbraCentre() + OFFSETS[config.type] * moonRadius()
end

## The intersection of TWO discs, drawn as horizontal lines: for each line we
## garde le segment commun au disque lunaire et au disque d'ombre. C'est ainsi que l'ombre
## stays exactly inside the Moon, with no mask and no clipping.
##
## `hole` hollows out a central disc concentric with the shadow: the function then draws
## l'intersection d'une COURONNE et du disque lunaire. C'est ce qui permet de peindre chaque
## bande une seule fois, avec sa couleur absolue, au lieu d'empiler des disques dont seul le
## produit aurait un sens.
func veilIntersection(mx, my, rl, ox, oy, ro, color, hole = 0)
    var y0 = math.max(my - rl, oy - ro)
    var y1 = math.min(my + rl, oy + ro)
    if y1 < y0 then
        return
    end
    var rl2 = rl * rl
    var ro2 = ro * ro
    var tr2 = hole * hole
    ## Pas de 1 px : en fusion multiplicative le bord est net, 2 px feraient un escalier.
    graphics.stroke(color, 1)
    for y = y0, y1 do
        var dy = (y - oy) * (y - oy)
        var dl = rl2 - (y - my) * (y - my)
        var dm = ro2 - dy
        if dl > 0 and dm > 0 then
            dl = math.sqrt(dl)
            dm = math.sqrt(dm)
            var a = math.max(mx - dl, ox - dm)
            var b = math.min(mx + dl, ox + dm)
            var dt = tr2 - dy
            if dt > 0 then
                ## The hole cuts the line in two pieces, either of which may be empty.
                dt = math.sqrt(dt)
                drawSegment(a, math.min(b, ox - dt), y)
                drawSegment(math.max(a, ox + dt), b, y)
            else
                drawSegment(a, b, y)
            end
        end
    end
end

func drawSegment(a, b, y)
    if b > a then
        graphics.line(a, y, b, y)
    end
end

## The distance between the centres, in lunar radii: the only quantity the phase and
## la magnitude.
func centreDist()
    var rl = moonRadius()
    var dx = moonX() - CW
    var dy = moonY() - umbraCentre()
    return math.sqrt(dx * dx + dy * dy) / rl
end

func phase(d)
    if d <= R_UMBRA - 1 then return "total" end
    if d < R_UMBRA + 1 then return "partial" end
    if d < R_PENUMBRA + 1 then return "penumbral" end
    return "no eclipse"
end

## A lunar eclipse's magnitude: the fraction of the lunar DIAMETER the umbra covers. It EXCEEDS 1
## in a total eclipse — the Moon is then deep inside the shadow, and the
## grandeur mesure de combien : ne pas la plafonner, ce serait perdre cette information.
func magnitude(d)
    return math.max((R_UMBRA + 1 - d) / 2, 0)
end

## The light left in the penumbra, at a distance `rho` from the shadow's centre, in lunar radii.
## Seen from a point in the penumbra, the Earth cuts the solar disc like a CHORD: the part hidden is
## the circular segment thus taken away, hence the formula
## `(acos c − c√(1−c²))/π`. Elle vaut 0 au bord externe (Soleil entier) et 1 au bord de
## the umbra, where the Sun is entirely hidden — so the profile is anything but linear.
##
## PENUMBRA_MIN is what remains at the umbra's edge: geometric optics would give zero, but the
## Earth's atmosphere refracts light there. Its value is the luminance of UMBRA_EDGE, so that the
## gradient does not jump from one side of the edge to the other.
const PENUMBRA_MIN = 0.60

func penumbraLight(rho)
    var c = math.clamp(math.map(rho, R_UMBRA, R_PENUMBRA, -1, 1), -1, 1)
    var covered = (math.acos(c) - c * math.sqrt(math.max(1 - c * c, 0))) / math.PI
    return math.max(1 - covered, PENUMBRA_MIN)
end

## The veil applied at a distance `rho` from the shadow's centre, as ABSOLUTE factors per channel:
## one function for the whole gradient, penumbra and umbra alike. It is what makes the colours
## legible — "the red is barely eaten into, the blue a great deal" reads straight off UMBRA_CENTRE,
## whereas a factor applied ten times over means nothing on its own.
const UMBRA_EDGE = Color(0.86, 0.50, 0.40)     ## the orange-brown of the rim
const UMBRA_CENTRE = Color(0.72, 0.24, 0.15)   ## cuivre du fond de l'ombre
const OZONE = R_UMBRA * 0.97                   ## the bluish band just inside the edge

func veilA(rho)
    if rho >= R_UMBRA then
        var f = penumbraLight(rho)
        return Color(f, f, f)
    end
    ## Bord FRANC : la teinte atteint presque le cuivre en un tiers de rayon, le reste de
    ## the umbra being roughly uniform. Spreading that gradient gave a soft, mushy shadow.
    var s = math.clamp((R_UMBRA - rho) / (0.35 * R_UMBRA), 0, 1)
    var r = UMBRA_EDGE.r + (UMBRA_CENTRE.r - UMBRA_EDGE.r) * s
    var v = UMBRA_EDGE.g + (UMBRA_CENTRE.g - UMBRA_EDGE.g) * s
    var b = UMBRA_EDGE.b + (UMBRA_CENTRE.b - UMBRA_EDGE.b) * s
    if rho > OZONE then
        ## Ozone in the upper atmosphere absorbs red: photographers know
        ## bien cette frange turquoise au bord de l'ombre.
        return Color(r * 0.80, v * 0.98, math.min(b * 1.35, 1))
    end
    return Color(r, v, b)
end

## The veil is drawn as ABUTTING rings, each painted once in its absolute colour — not as stacked
## discs, of which only the product would mean anything. The radii and the colours depend on the
## constants alone, so the table is built once, at startup. The bands are tight near the umbra's
## edge, where everything happens, and loose elsewhere.
global veil = []   ## [{ext, int, color}], from the penumbra's edge towards the centre

func buildVeil()
    var radii = []
    for k = 1, 12 do
        radii[#radii + 1] = R_PENUMBRA - (R_PENUMBRA - R_UMBRA) * k / 12
    end
    for f in [0.985, 0.94, 0.90, 0.86, 0.82, 0.78, 0.74, 0.70, 0.62, 0.52, 0.40, 0.26, 0.12, 0.0] do
        radii[#radii + 1] = R_UMBRA * f
    end
    ## The colour is taken at the MIDDLE of the band, not at its inner edge: at the edge each band
    ## takes the darkest hue it holds, and the whole gradient shifts outwards by half a band — the
    ## penumbra's edge then started at 0.96 instead
    ## lieu de 1,00, sans transition.
    var ext = R_PENUMBRA
    for i = 1, #radii do
        veil[i] = {ext: ext, int: radii[i], color: veilA((ext + radii[i]) / 2)}
        ext = radii[i]
    end
end

func drawStars()
    for i = 1, #stars, 3 do
        var e = stars[i + 2]
        graphics.stroke(Color(0.85, 0.9, 1, e), e * 2)
        graphics.point(stars[i], stars[i + 1])
    end
end

func drawMarks()
    var rl = moonRadius()
    graphics.noFill()
    graphics.stroke(Color(0.45, 0.55, 0.8, 0.55), 1)
    graphics.circle(CW, umbraCentre(), R_PENUMBRA * rl)
    graphics.stroke(Color(0.8, 0.45, 0.35, 0.7), 1)
    graphics.circle(CW, umbraCentre(), R_UMBRA * rl)
    graphics.stroke(Color(0.5, 0.6, 0.85, 0.8))
    graphics.fontSize(H * 0.022)
    graphics.text("penumbra", CW + R_PENUMBRA * rl + 6, umbraCentre() - H * 0.012)
    graphics.stroke(Color(0.85, 0.5, 0.4, 0.9))
    graphics.text("ombre", CW + R_UMBRA * rl + 6, umbraCentre() + H * 0.02)
end

func draw()
    t += deltaTime * config.speed * (DURATION_H / 24)   ## 24 s of simulation by default
    if t > DURATION_H then
        t = 0.0
    end

    graphics.clear(Color(0.02, 0.02, 0.05))
    drawStars()
    if config.marks then
        drawMarks()
    end

    var rl = moonRadius()
    var mx = moonX()
    var my = moonY()
    var ox = CW
    var oy = umbraCentre()
    var d = centreDist()

    ## The Moon fully lit, then the shadow ON TOP: that is nature's own order.
    graphics.noStroke()
    graphics.sprite(moon, mx - rl, my - rl, rl * 2, rl * 2)

    ## The veil MULTIPLIES the Moon's light instead of covering it: that is the physical model — the
    ## surface stays the same, only the illumination changes. The craters therefore remain visible
    ## through the copper, as in a real eclipse.
    ##
    ## One band per ring, painted ONCE: each pixel is multiplied a single time, and its colour is the
    ## one `veilA` gives at that distance. The bands are
    ## exactement jointives (le trou de l'une est le rayon externe de la suivante) : les faire
    ## overlapping by half a pixel multiplied the joint twice, hence periodic DARK lines, which were
    ## measured.
    graphics.blendMode(blend.MULTIPLY)
    for i = 1, #veil do
        var b = veil[i]
        ## The Moon may fit entirely inside the band's hole, which is common in a
        ## totale) : le balayage ne tracerait alors pas un pixel.
        if d + 1 <= b.int then
            continue
        end
        veilIntersection(mx, my, rl, ox, oy, b.ext * rl, b.color, b.int * rl)
    end
    graphics.blendMode(blend.ALPHA)

    ## The information strip: the phase, the magnitude, the simulated time.
    graphics.fontSize(H * 0.032)
    graphics.stroke(Color(0.88, 0.9, 0.96))
    ## The interpolation formats directly: {expr:.2f} saves rounding by hand.
    graphics.text("{phase(d)}   magnitude {magnitude(d):.2f}", W * 0.04, H * 0.06)
    graphics.fontSize(H * 0.024)
    graphics.stroke(Color(0.6, 0.65, 0.78))
    ## Accented letters go through, the embedded font covering them, but not a middle dot: a missing
    ## glyph would show as a "?".
    graphics.text("T+{t:.1f} h   -   {config.type} eclipse", W * 0.04, H * 0.11)
end
