## Éclipse de Lune — vue depuis la Terre. La Lune traverse le cône d'ombre projeté par
## la Terre : elle s'assombrit d'abord dans la PÉNOMBRE, faiblement en entrant puis très
## nettement en approchant du bord de l'ombre — la Terre y masque presque tout le Soleil.
## Elle mord ensuite l'OMBRE, où elle prend une teinte cuivrée. Ce rouge est celui de la
## lumière solaire réfractée par l'atmosphère terrestre — le bleu y est diffusé, le rouge passe.
##
## Deux échelles suffisent à tout décrire, en rayons lunaires : l'ombre en fait ~2,7 et la
## pénombre ~4,6 à la distance de la Lune. Le reste n'est que géométrie de deux disques.
##
## Le menu choisit le type d'éclipse (l'écart entre la Lune et l'axe de l'ombre), la
## vitesse, et l'affichage des repères.
##
## Le pendant de cet exemple est « Éclipse de Soleil », où c'est la Lune qui masque.

const R_UMBRA = 2.7      ## rayon du cône d'ombre, en rayons lunaires
const R_PENUMBRA = 4.6   ## rayon de la pénombre
const DURATION_H = 6.0      ## heures simulées pour la traversée complète

## Écart de la Lune à l'axe de l'ombre, en rayons lunaires : c'est LUI qui décide du type
## d'éclipse. La liste du menu affiche et renvoie les CLÉS de cette map (règle de `for … in`),
## et le programme lit la valeur associée. Clés entre GUILLEMETS : une clé littérale peut
## être une chaîne, ce qui autorise ici l'accent que refuserait un identifiant.
global OFFSETS = {"totale": 0.15, "partielle": 2.2, "pénombre": 4.2}

## `type` est posé d'avance : une liste respecte la sélection existante et n'impose son
## premier élément qu'à une variable nil (l'ordre alphabétique donnerait « partielle »).
global config = {type: "totale", speed: 1.0, marks: false}

global moon = nil        ## texture du disque lunaire, construite une fois
global stars = []      ## fond fixe : [x, y, éclat, …]
global t = 0.0           ## progression de la simulation, en heures simulées

## Assez petit pour que le cercle de PÉNOMBRE tienne à l'écran (4,6 rayons lunaires) :
## c'est cette échelle qui donne la juste idée des tailles en jeu.
func moonRadius()
    return math.min(W, H) * 0.085
end

## Disque lunaire dessiné UNE fois dans une image : cratères par bruit à deux échelles,
## limbe assombri (la sphère se dérobe), bord adouci d'un pixel (sinon un escalier visible).
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
    menu.checkbox("Repères", ref config.marks)
    ui.show(menu)
end

## Centre de l'ombre : fixe à l'écran. La Lune, elle, défile horizontalement — c'est bien
## elle qui se déplace sur son orbite, l'ombre suivant l'antisoleil beaucoup plus lentement.
func umbraCentre()
    return CH
end

## Position de la Lune à l'instant t : trajectoire rectiligne, décalée de l'écart choisi.
func moonX()
    var rl = moonRadius()
    var reach = (R_PENUMBRA + 1.6) * rl
    return CW - reach + 2 * reach * (t / DURATION_H)
end

func moonY()
    return umbraCentre() + OFFSETS[config.type] * moonRadius()
end

## Intersection de DEUX disques, dessinée par lignes horizontales : pour chaque ligne, on
## garde le segment commun au disque lunaire et au disque d'ombre. C'est ainsi que l'ombre
## reste exactement dans la Lune, sans masque ni découpe.
##
## `trou` évide un disque central concentrique à l'ombre : la fonction dessine alors
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
                ## Le trou coupe la ligne en deux morceaux, l'un ou l'autre pouvant être vide.
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

## Distance des centres, en rayons lunaires : la seule grandeur dont dépendent la phase et
## la magnitude.
func centreDist()
    var rl = moonRadius()
    var dx = moonX() - CW
    var dy = moonY() - umbraCentre()
    return math.sqrt(dx * dx + dy * dy) / rl
end

func phase(d)
    if d <= R_UMBRA - 1 then return "totale" end
    if d < R_UMBRA + 1 then return "partielle" end
    if d < R_PENUMBRA + 1 then return "pénombre" end
    return "hors éclipse"
end

## Magnitude d'une éclipse de Lune : fraction du DIAMÈTRE lunaire couverte par l'ombre.
## Elle DÉPASSE 1 en éclipse totale — la Lune est alors enfoncée dans l'ombre, et la
## grandeur mesure de combien : ne pas la plafonner, ce serait perdre cette information.
func magnitude(d)
    return math.max((R_UMBRA + 1 - d) / 2, 0)
end

## Lumière restant dans la pénombre, à la distance `rho` du centre de l'ombre (en rayons
## lunaires). Vue d'un point de la pénombre, la Terre coupe le disque solaire comme une
## CORDE : la part masquée est celle du segment circulaire ainsi retranché, d'où la formule
## `(acos c − c√(1−c²))/π`. Elle vaut 0 au bord externe (Soleil entier) et 1 au bord de
## l'ombre (Soleil entièrement caché) — le profil est donc tout sauf linéaire.
##
## PENOMBRE_MIN est ce qu'il reste au bord de l'ombre : l'optique géométrique donnerait zéro,
## mais l'atmosphère terrestre y réfracte de la lumière. Sa valeur est celle de la luminance
## de OMBRE_BORD, pour que le dégradé ne saute pas d'un côté à l'autre du bord.
const PENUMBRA_MIN = 0.60

func penumbraLight(rho)
    var c = math.clamp(math.map(rho, R_UMBRA, R_PENUMBRA, -1, 1), -1, 1)
    var covered = (math.acos(c) - c * math.sqrt(math.max(1 - c * c, 0))) / math.PI
    return math.max(1 - covered, PENUMBRA_MIN)
end

## Voile appliqué à la distance `rho` du centre de l'ombre, en facteurs ABSOLUS par canal :
## une seule fonction pour tout le dégradé, pénombre et ombre comprises. C'est elle qui rend
## les couleurs lisibles — « le rouge est peu entamé, le bleu beaucoup » se lit directement
## dans OMBRE_CENTRE, alors qu'un facteur appliqué dix fois de suite ne veut rien dire seul.
const UMBRA_EDGE = Color(0.86, 0.50, 0.40)     ## brun-orangé du pourtour
const UMBRA_CENTRE = Color(0.72, 0.24, 0.15)   ## cuivre du fond de l'ombre
const OZONE = R_UMBRA * 0.97                   ## bande bleutée juste à l'intérieur du bord

func veilA(rho)
    if rho >= R_UMBRA then
        var f = penumbraLight(rho)
        return Color(f, f, f)
    end
    ## Bord FRANC : la teinte atteint presque le cuivre en un tiers de rayon, le reste de
    ## l'ombre étant à peu près uniforme. Étaler ce dégradé donnait une ombre molle.
    var s = math.clamp((R_UMBRA - rho) / (0.35 * R_UMBRA), 0, 1)
    var r = UMBRA_EDGE.r + (UMBRA_CENTRE.r - UMBRA_EDGE.r) * s
    var v = UMBRA_EDGE.g + (UMBRA_CENTRE.g - UMBRA_EDGE.g) * s
    var b = UMBRA_EDGE.b + (UMBRA_CENTRE.b - UMBRA_EDGE.b) * s
    if rho > OZONE then
        ## L'ozone de la haute atmosphère absorbe le rouge : les photographes connaissent
        ## bien cette frange turquoise au bord de l'ombre.
        return Color(r * 0.80, v * 0.98, math.min(b * 1.35, 1))
    end
    return Color(r, v, b)
end

## Le voile est dessiné en anneaux JOINTIFS, chacun peint une fois avec sa couleur absolue —
## et non en disques empilés dont seul le produit aurait un sens. Rayons et couleurs ne
## dépendent que des constantes : la table est donc construite une fois, au démarrage.
## Bandes serrées près du bord de l'ombre, où tout se joue ; lâches ailleurs.
global veil = []   ## [{ext, int, couleur}], du bord de la pénombre vers le centre

func buildVeil()
    var radii = []
    for k = 1, 12 do
        radii[#radii + 1] = R_PENUMBRA - (R_PENUMBRA - R_UMBRA) * k / 12
    end
    for f in [0.985, 0.94, 0.90, 0.86, 0.82, 0.78, 0.74, 0.70, 0.62, 0.52, 0.40, 0.26, 0.12, 0.0] do
        radii[#radii + 1] = R_UMBRA * f
    end
    ## Couleur prise au MILIEU de la bande, pas à son bord interne : au bord, chaque bande
    ## prend la teinte la plus sombre qu'elle contient, et tout le dégradé se trouve décalé
    ## d'une demi-bande vers l'extérieur — le bord de la pénombre partait alors à 0,96 au
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
    graphics.text("pénombre", CW + R_PENUMBRA * rl + 6, umbraCentre() - H * 0.012)
    graphics.stroke(Color(0.85, 0.5, 0.4, 0.9))
    graphics.text("ombre", CW + R_UMBRA * rl + 6, umbraCentre() + H * 0.02)
end

func draw()
    t += deltaTime * config.speed * (DURATION_H / 24)   ## 24 s de simulation par défaut
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

    ## La Lune pleinement éclairée, puis l'ombre PAR-DESSUS : c'est l'ordre de la nature.
    graphics.noStroke()
    graphics.sprite(moon, mx - rl, my - rl, rl * 2, rl * 2)

    ## Le voile MULTIPLIE la lumière lunaire au lieu de la recouvrir : c'est le modèle
    ## physique — la surface reste la même, seul l'éclairement change. Les cratères
    ## demeurent donc visibles à travers le cuivre, comme sur une vraie éclipse.
    ##
    ## Une bande par anneau, peinte UNE fois : chaque pixel n'est multiplié qu'une seule
    ## fois, et sa couleur est celle que `voileA` donne à cette distance. Les bandes sont
    ## exactement jointives (le trou de l'une est le rayon externe de la suivante) : les faire
    ## se chevaucher d'un demi-pixel multipliait deux fois la jointure, d'où des liserés
    ## SOMBRES périodiques, mesurés.
    graphics.blendMode(blend.MULTIPLY)
    for i = 1, #veil do
        var b = veil[i]
        ## La Lune peut tenir tout entière dans le trou de la bande (cas courant en éclipse
        ## totale) : le balayage ne tracerait alors pas un pixel.
        if d + 1 <= b.int then
            continue
        end
        veilIntersection(mx, my, rl, ox, oy, b.ext * rl, b.color, b.int * rl)
    end
    graphics.blendMode(blend.ALPHA)

    ## Bandeau d'information : phase, magnitude, temps simulé.
    graphics.fontSize(H * 0.032)
    graphics.stroke(Color(0.88, 0.9, 0.96))
    ## L'interpolation formate directement : {expr:.2f} évite un arrondi à la main.
    graphics.text("{phase(d)}   magnitude {magnitude(d):.2f}", W * 0.04, H * 0.06)
    graphics.fontSize(H * 0.024)
    graphics.stroke(Color(0.6, 0.65, 0.78))
    ## Les accents français passent (la police embarquée les couvre), mais pas un point
    ## médian : un glyphe absent s'afficherait « ? ».
    graphics.text("T+{t:.1f} h   -   éclipse {config.type}", W * 0.04, H * 0.11)
end
