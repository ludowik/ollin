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

const R_OMBRE = 2.7      ## rayon du cône d'ombre, en rayons lunaires
const R_PENOMBRE = 4.6   ## rayon de la pénombre
const DUREE_H = 6.0      ## heures simulées pour la traversée complète

## Écart de la Lune à l'axe de l'ombre, en rayons lunaires : c'est LUI qui décide du type
## d'éclipse. La liste du menu affiche et renvoie les CLÉS de cette map (règle de `for … in`),
## et le programme lit la valeur associée. Clés entre GUILLEMETS : une clé littérale peut
## être une chaîne, ce qui autorise ici l'accent que refuserait un identifiant.
global ECARTS = {"totale": 0.15, "partielle": 2.2, "pénombre": 4.2}

## `type` est posé d'avance : une liste respecte la sélection existante et n'impose son
## premier élément qu'à une variable nil (l'ordre alphabétique donnerait « partielle »).
global config = {type: "totale", vitesse: 1.0, reperes: false}

global lune = nil        ## texture du disque lunaire, construite une fois
global etoiles = []      ## fond fixe : [x, y, éclat, …]
global t = 0.0           ## progression de la simulation, en heures simulées

## Assez petit pour que le cercle de PÉNOMBRE tienne à l'écran (4,6 rayons lunaires) :
## c'est cette échelle qui donne la juste idée des tailles en jeu.
func rayonLune()
    return math.min(W, H) * 0.085
end

## Disque lunaire dessiné UNE fois dans une image : cratères par bruit à deux échelles,
## limbe assombri (la sphère se dérobe), bord adouci d'un pixel (sinon un escalier visible).
func construireLune(taille)
    lune = image.create(taille, taille)
    var r = taille / 2.0
    image.beginPixels(lune)
    for y = 0, taille - 1 do
        for x = 0, taille - 1 do
            var dx = x - r + 0.5
            var dy = y - r + 0.5
            var d = math.sqrt(dx * dx + dy * dy)
            if d > r then
                image.setPixel(lune, x, y, 0, 0, 0, 0)
            else
                var n = math.noise(x * 0.05, y * 0.05) * 0.65
                       + math.noise(x * 0.19, y * 0.19) * 0.35
                var g = math.clamp(0.66 + (n - 0.5) * 0.42, 0, 1)
                ## Éclairement du limbe : la normale s'incline vers le bord du disque.
                var f = math.sqrt(math.max(1 - (d / r) * (d / r), 0))
                g = g * (0.55 + 0.45 * f)
                image.setPixel(lune, x, y, g, g * 0.97, g * 0.92, math.clamp(r - d, 0, 1))
            end
        end
    end
    image.endPixels(lune)
end

func setup()
    graphics.canvas(W, H, "Éclipse de Lune")
    math.noiseSeed(11)
    construireLune(256)
    construireVoile()

    for i = 1, 220 do
        etoiles[#etoiles + 1] = math.rand(0, W)
        etoiles[#etoiles + 1] = math.rand(0, H)
        etoiles[#etoiles + 1] = math.rand(0.15, 1.0)
    end

    var menu = ui.menu("Éclipse")
    menu.list("Type", ECARTS, ref config.type)
    menu.slider("Vitesse", ref config.vitesse, 0.1, 4)
    menu.checkbox("Repères", ref config.reperes)
    ui.show(menu)
end

## Centre de l'ombre : fixe à l'écran. La Lune, elle, défile horizontalement — c'est bien
## elle qui se déplace sur son orbite, l'ombre suivant l'antisoleil beaucoup plus lentement.
func centreOmbre()
    return CH
end

## Position de la Lune à l'instant t : trajectoire rectiligne, décalée de l'écart choisi.
func luneX()
    var rl = rayonLune()
    var portee = (R_PENOMBRE + 1.6) * rl
    return CW - portee + 2 * portee * (t / DUREE_H)
end

func luneY()
    return centreOmbre() + ECARTS[config.type] * rayonLune()
end

## Intersection de DEUX disques, dessinée par lignes horizontales : pour chaque ligne, on
## garde le segment commun au disque lunaire et au disque d'ombre. C'est ainsi que l'ombre
## reste exactement dans la Lune, sans masque ni découpe.
##
## `trou` évide un disque central concentrique à l'ombre : la fonction dessine alors
## l'intersection d'une COURONNE et du disque lunaire. C'est ce qui permet de peindre chaque
## bande une seule fois, avec sa couleur absolue, au lieu d'empiler des disques dont seul le
## produit aurait un sens.
func voilerIntersection(mx, my, rl, ox, oy, ro, couleur, trou = 0)
    var y0 = math.max(my - rl, oy - ro)
    var y1 = math.min(my + rl, oy + ro)
    if y1 < y0 then
        return
    end
    var rl2 = rl * rl
    var ro2 = ro * ro
    var tr2 = trou * trou
    ## Pas de 1 px : en fusion multiplicative le bord est net, 2 px feraient un escalier.
    graphics.stroke(couleur, 1)
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
                tracerSegment(a, math.min(b, ox - dt), y)
                tracerSegment(math.max(a, ox + dt), b, y)
            else
                tracerSegment(a, b, y)
            end
        end
    end
end

func tracerSegment(a, b, y)
    if b > a then
        graphics.line(a, y, b, y)
    end
end

## Distance des centres, en rayons lunaires : la seule grandeur dont dépendent la phase et
## la magnitude.
func distanceCentres()
    var rl = rayonLune()
    var dx = luneX() - CW
    var dy = luneY() - centreOmbre()
    return math.sqrt(dx * dx + dy * dy) / rl
end

func phase(d)
    if d <= R_OMBRE - 1 then return "totale" end
    if d < R_OMBRE + 1 then return "partielle" end
    if d < R_PENOMBRE + 1 then return "pénombre" end
    return "hors éclipse"
end

## Magnitude d'une éclipse de Lune : fraction du DIAMÈTRE lunaire couverte par l'ombre.
## Elle DÉPASSE 1 en éclipse totale — la Lune est alors enfoncée dans l'ombre, et la
## grandeur mesure de combien : ne pas la plafonner, ce serait perdre cette information.
func magnitude(d)
    return math.max((R_OMBRE + 1 - d) / 2, 0)
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
const PENOMBRE_MIN = 0.60

func lumierePenombre(rho)
    var c = math.clamp(math.map(rho, R_OMBRE, R_PENOMBRE, -1, 1), -1, 1)
    var masquee = (math.acos(c) - c * math.sqrt(math.max(1 - c * c, 0))) / math.PI
    return math.max(1 - masquee, PENOMBRE_MIN)
end

## Voile appliqué à la distance `rho` du centre de l'ombre, en facteurs ABSOLUS par canal :
## une seule fonction pour tout le dégradé, pénombre et ombre comprises. C'est elle qui rend
## les couleurs lisibles — « le rouge est peu entamé, le bleu beaucoup » se lit directement
## dans OMBRE_CENTRE, alors qu'un facteur appliqué dix fois de suite ne veut rien dire seul.
const OMBRE_BORD = Color(0.86, 0.50, 0.40)     ## brun-orangé du pourtour
const OMBRE_CENTRE = Color(0.72, 0.24, 0.15)   ## cuivre du fond de l'ombre
const OZONE = R_OMBRE * 0.97                   ## bande bleutée juste à l'intérieur du bord

func voileA(rho)
    if rho >= R_OMBRE then
        var f = lumierePenombre(rho)
        return Color(f, f, f)
    end
    ## Bord FRANC : la teinte atteint presque le cuivre en un tiers de rayon, le reste de
    ## l'ombre étant à peu près uniforme. Étaler ce dégradé donnait une ombre molle.
    var s = math.clamp((R_OMBRE - rho) / (0.35 * R_OMBRE), 0, 1)
    var r = OMBRE_BORD.r + (OMBRE_CENTRE.r - OMBRE_BORD.r) * s
    var v = OMBRE_BORD.g + (OMBRE_CENTRE.g - OMBRE_BORD.g) * s
    var b = OMBRE_BORD.b + (OMBRE_CENTRE.b - OMBRE_BORD.b) * s
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
global voile = []   ## [{ext, int, couleur}], du bord de la pénombre vers le centre

func construireVoile()
    var rayons = []
    for k = 1, 12 do
        rayons[#rayons + 1] = R_PENOMBRE - (R_PENOMBRE - R_OMBRE) * k / 12
    end
    for f in [0.985, 0.94, 0.90, 0.86, 0.82, 0.78, 0.74, 0.70, 0.62, 0.52, 0.40, 0.26, 0.12, 0.0] do
        rayons[#rayons + 1] = R_OMBRE * f
    end
    ## Couleur prise au MILIEU de la bande, pas à son bord interne : au bord, chaque bande
    ## prend la teinte la plus sombre qu'elle contient, et tout le dégradé se trouve décalé
    ## d'une demi-bande vers l'extérieur — le bord de la pénombre partait alors à 0,96 au
    ## lieu de 1,00, sans transition.
    var ext = R_PENOMBRE
    for i = 1, #rayons do
        voile[i] = {ext: ext, int: rayons[i], couleur: voileA((ext + rayons[i]) / 2)}
        ext = rayons[i]
    end
end

func dessineEtoiles()
    for i = 1, #etoiles, 3 do
        var e = etoiles[i + 2]
        graphics.stroke(Color(0.85, 0.9, 1, e), e * 2)
        graphics.point(etoiles[i], etoiles[i + 1])
    end
end

func dessineReperes()
    var rl = rayonLune()
    graphics.noFill()
    graphics.stroke(Color(0.45, 0.55, 0.8, 0.55), 1)
    graphics.circle(CW, centreOmbre(), R_PENOMBRE * rl)
    graphics.stroke(Color(0.8, 0.45, 0.35, 0.7), 1)
    graphics.circle(CW, centreOmbre(), R_OMBRE * rl)
    graphics.stroke(Color(0.5, 0.6, 0.85, 0.8))
    graphics.fontSize(H * 0.022)
    graphics.text("pénombre", CW + R_PENOMBRE * rl + 6, centreOmbre() - H * 0.012)
    graphics.stroke(Color(0.85, 0.5, 0.4, 0.9))
    graphics.text("ombre", CW + R_OMBRE * rl + 6, centreOmbre() + H * 0.02)
end

func draw()
    t += deltaTime * config.vitesse * (DUREE_H / 24)   ## 24 s de simulation par défaut
    if t > DUREE_H then
        t = 0.0
    end

    graphics.clear(Color(0.02, 0.02, 0.05))
    dessineEtoiles()
    if config.reperes then
        dessineReperes()
    end

    var rl = rayonLune()
    var mx = luneX()
    var my = luneY()
    var ox = CW
    var oy = centreOmbre()
    var d = distanceCentres()

    ## La Lune pleinement éclairée, puis l'ombre PAR-DESSUS : c'est l'ordre de la nature.
    graphics.noStroke()
    graphics.sprite(lune, mx - rl, my - rl, rl * 2, rl * 2)

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
    for i = 1, #voile do
        var b = voile[i]
        ## La Lune peut tenir tout entière dans le trou de la bande (cas courant en éclipse
        ## totale) : le balayage ne tracerait alors pas un pixel.
        if d + 1 <= b.int then
            continue
        end
        voilerIntersection(mx, my, rl, ox, oy, b.ext * rl, b.couleur, b.int * rl)
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
