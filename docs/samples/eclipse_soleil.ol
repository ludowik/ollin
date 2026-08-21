## Éclipse de Soleil — la Lune passe devant le Soleil. Le hasard veut que les deux disques
## nous apparaissent presque de la même taille (un demi-degré) : de ce quasi-égalité naissent
## les trois formes de l'éclipse. Lune un peu plus grosse que le Soleil, elle le cache
## entièrement — c'est la TOTALE, seul moment où la couronne se montre. Un peu plus petite,
## il reste un anneau de feu — l'ANNULAIRE. Décalée, elle n'en mord qu'un morceau : PARTIELLE.
##
## Le pendant de cet exemple est « Éclipse de Lune », où c'est la Terre qui fait l'ombre.
##
## L'obscuration est calculée exactement : aire d'intersection des deux disques, rapportée
## à celle du Soleil. C'est elle qui commande la lumière du paysage.

## Par type : rayon de la Lune en rayons SOLAIRES (`ratio`), et écart minimal des centres
## (`offset`). Le rapport
## réel va de 0,95 à 1,08 selon les distances du moment ; il est ici un peu exagéré pour que
## la totalité dure plus qu'un instant (elle ne représente sinon que ~2 % du passage).
global TYPES = {
    "totale":    {ratio: 1.15, offset: 0.0},
    "annulaire": {ratio: 0.92, offset: 0.0},
    "partielle": {ratio: 1.05, offset: 0.80}
}

const TRAVEL = 30.0    ## secondes pour la traversée complète, à vitesse 1

global config = {type: "totale", speed: 1.0}
global u = 0.0           ## progression du passage, de 0 à 1
global stars = []
global hills = []     ## silhouette de l'horizon, hauteurs échantillonnées

func sunRadius()
    return math.min(W, H) * 0.13
end

func sunX()
    return CW
end

func sunY()
    return H * 0.42
end

## La Lune traverse horizontalement, décalée de l'écart du type choisi.
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

## Aire commune à deux disques — géométrie exacte, sans approximation : deux secteurs
## circulaires moins le quadrilatère qu'ils partagent (formule de Héron pour ce dernier).
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

## Part du disque solaire cachée : c'est la grandeur qui décide de tout le reste.
func obscuration()
    var rs = sunRadius()
    return lensArea(rs, moonRadius(), centreDist()) / (math.PI * rs * rs)
end

func phase()
    var d = centreDist()
    var rs = sunRadius()
    var rl = moonRadius()
    if d >= rs + rl then
        return "hors éclipse"
    end
    if d <= math.abs(rl - rs) then
        return rl >= rs and "totale" or "annulaire"
    end
    return "partielle"
end

## Lumière ambiante, entre 0 et 1. L'œil est logarithmique : perdre la moitié du disque
## solaire ne divise pas la clarté par deux, et le jour ne s'effondre que dans les tout
## derniers pour-cent. La totalité, elle, fait chuter la lumière d'un facteur ~10 000 —
## d'où la marche finale, bien réelle.
func light()
    if phase() == "totale" then
        return 0.03
    end
    var o = obscuration()
    return math.clamp(0.10 + 0.90 * math.pow(1 - o, 0.45), 0.03, 1.0)
end

func setup()
    graphics.canvas(W, H, "Éclipse de Soleil")
    math.noiseSeed(5)

    for i = 1, 160 do
        stars[#stars + 1] = math.rand(0, W)
        stars[#stars + 1] = math.rand(0, H * 0.72)
        stars[#stars + 1] = math.rand(0.2, 1.0)
    end
    ## Horizon : une hauteur tous les 12 pixels, tirée du bruit → collines douces.
    for x = 0, W + 12, 12 do
        hills[#hills + 1] = H * 0.80 + math.noise(x * 0.004, 3) * H * 0.10
    end

    var menu = ui.menu("Éclipse")
    menu.list("Type", TYPES, ref config.type)
    menu.slider("Vitesse", ref config.speed, 0.1, 4)
    ui.show(menu)
end

## Ciel : bleu de plein jour qui se vide de sa clarté, jamais tout à fait noir (la couronne
## et l'horizon gardent une lueur, comme au crépuscule). La couleur est une FONCTION, car la
## Lune s'en sert aussi : hors du Soleil, on ne la voit pas.
func skyColor(l)
    return Color(0.05 + 0.30 * l, 0.09 + 0.42 * l, 0.16 + 0.62 * l)
end

func drawSky(l)
    graphics.clear(skyColor(l))
end

## Étoiles : elles n'apparaissent qu'avec l'obscurité — invisibles de jour, franches en
## totalité, comme les planètes brillantes que l'on découvre alors.
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
    for i = 1, #hills do
        pts[#pts + 1] = (i - 1) * 12
        pts[#pts + 1] = hills[i]
    end
    pts[#pts + 1] = W
    pts[#pts + 1] = H
    pts[#pts + 1] = 0
    pts[#pts + 1] = H
    graphics.polygon(pts)
end

## Halo : disques concentriques en fusion ADDITIVE, du plus large au plus étroit.
## L'addition imite l'éblouissement — la lumière s'ajoute au ciel au lieu de le remplacer.
## BEAUCOUP d'étapes à faible opacité : sept étapes bien marquées dessinaient des anneaux
## concentriques au lieu d'un dégradé.
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

## Couronne : visible SEULEMENT quand la photosphère est entièrement masquée. Ses aigrettes
## sont irrégulières — un bruit angulaire donne cette structure filamenteuse.
func drawCorona()
    var rl = moonRadius()
    graphics.blendMode(blend.ADD)
    ## Halo interne, dense près du limbe et fondu vers l'extérieur : c'est lui qui donne la
    ## nacre de la couronne, les aigrettes ne faisant que la strier.
    graphics.noStroke()
    for k = 1, 18 do
        var f = k / 18
        graphics.fill(Color(0.48, 0.52, 0.58, 0.05 * (1 - f)))
        graphics.circle(sunX(), sunY(), rl * (1 + 1.5 * f))
    end
    ## Aigrettes : chacune en QUATRE segments d'opacité décroissante — un trait d'opacité
    ## constante finissait net, et l'ensemble ressemblait à une brosse.
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
    var totale = phase() == "totale"

    drawSky(l)
    drawStars(l)

    ## Le disque solaire, puis la couronne, puis la Lune PAR-DESSUS : c'est l'empilement
    ## réel, et il suffit à découper le croissant — inutile de calculer une intersection
    ## pour dessiner, la Lune masque ce qu'elle recouvre.
    graphics.noStroke()
    graphics.fill(Color(1, 0.97, 0.86))
    graphics.circle(sunX(), sunY(), rs)

    if totale then
        drawCorona()
        ## Chromosphère : fine bordure rose que la Lune laisse voir juste au-delà de son
        ## limbe. Dessinée avant la Lune, il n'en reste qu'un liseré.
        graphics.fill(Color(1, 0.35, 0.35, 0.55))
        graphics.circle(moonX(), moonY(), rl * 1.03)
    end

    ## La Lune prend la COULEUR DU CIEL, à peine assombrie : hors du Soleil on ne la voit
    ## pas — un disque noir sur le bleu du jour serait une invention. Devant le Soleil, elle
    ## le masque tout aussi bien.
    var c = skyColor(l)
    graphics.fill(Color(c.r * 0.90, c.g * 0.90, c.b * 0.92))
    graphics.circle(moonX(), moonY(), rl)

    ## Halo APRÈS la Lune : la lumière diffusée par l'atmosphère se trouve entre la Lune et
    ## nous, elle la voile donc elle aussi. En totalité il ne reste presque rien à diffuser.
    drawHalo(l)

    drawHorizon(l)

    graphics.fontSize(H * 0.032)
    graphics.stroke(Color(0.92, 0.93, 0.97))
    graphics.text("{phase()}   obscuration {obscuration() * 100:.1f} %", W * 0.04, H * 0.05)
    graphics.fontSize(H * 0.024)
    graphics.stroke(Color(0.68, 0.72, 0.82))
    graphics.text("éclipse {config.type}   -   lumière {l * 100:.0f} %", W * 0.04, H * 0.10)
end
