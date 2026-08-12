## Éclipse de Lune — vue depuis la Terre. La Lune traverse le cône d'ombre projeté par
## la Terre : elle s'assombrit d'abord dans la PÉNOMBRE (à peine perceptible), puis mord
## l'OMBRE, où elle prend une teinte cuivrée. Ce rouge est celui de la lumière solaire
## réfractée par l'atmosphère terrestre — le bleu y est diffusé, le rouge passe.
##
## Deux échelles suffisent à tout décrire, en rayons lunaires : l'ombre en fait ~2,7 et la
## pénombre ~4,6 à la distance de la Lune. Le reste n'est que géométrie de deux disques.
##
## Le menu choisit le type d'éclipse (l'écart entre la Lune et l'axe de l'ombre), la
## vitesse, et l'affichage des repères.

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
func voilerIntersection(mx, my, rl, ox, oy, ro, couleur)
    var pas = 1   ## en fusion multiplicative, le bord est net : 2 px feraient un escalier
    var y0 = math.max(my - rl, oy - ro)
    var y1 = math.min(my + rl, oy + ro)
    graphics.stroke(couleur, pas)
    for y = y0, y1, pas do
        var dl = rl * rl - (y - my) * (y - my)
        var dm = ro * ro - (y - oy) * (y - oy)
        if dl > 0 and dm > 0 then
            dl = math.sqrt(dl)
            dm = math.sqrt(dm)
            var a = math.max(mx - dl, ox - dm)
            var b = math.min(mx + dl, ox + dm)
            if b > a then
                graphics.line(a, y, b, y)
            end
        end
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

func phase()
    var d = distanceCentres()
    if d <= R_OMBRE - 1 then return "totale" end
    if d < R_OMBRE + 1 then return "partielle" end
    if d < R_PENOMBRE + 1 then return "pénombre" end
    return "hors éclipse"
end

## Magnitude d'une éclipse de Lune : fraction du DIAMÈTRE lunaire couverte par l'ombre.
## Elle DÉPASSE 1 en éclipse totale — la Lune est alors enfoncée dans l'ombre, et la
## grandeur mesure de combien : ne pas la plafonner, ce serait perdre cette information.
func magnitude()
    return math.max((R_OMBRE + 1 - distanceCentres()) / 2, 0)
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

    ## La Lune pleinement éclairée, puis l'ombre PAR-DESSUS : c'est l'ordre de la nature.
    graphics.noStroke()
    graphics.sprite(lune, mx - rl, my - rl, rl * 2, rl * 2)

    ## L'ombre MULTIPLIE la lumière lunaire au lieu de la recouvrir : c'est le modèle
    ## physique — la surface reste la même, seul l'éclairement change. Les cratères
    ## demeurent donc visibles à travers le cuivre, comme sur une vraie éclipse.
    ##
    ## Chaque étape multiplie par un facteur PROCHE DE 1, et c'est leur produit qui creuse
    ## le dégradé du bord vers le centre. Peu d'étapes à fort facteur laisseraient des
    ## bandes concentriques bien visibles (constaté avec six).
    graphics.blendMode(blend.MULTIPLY)

    ## Pénombre : la Terre n'y masque qu'une PART du disque solaire, d'où un affaiblissement
    ## progressif et neutre. À l'œil nu, une éclipse par la seule pénombre passe presque
    ## inaperçue — le produit des 16 étapes ne retire que ~15 % de la lumière.
    for k = 0, 15 do
        var r = R_PENOMBRE - (R_PENOMBRE - R_OMBRE) * k / 16
        voilerIntersection(mx, my, rl, ox, oy, r * rl, Color(0.991, 0.991, 0.995))
    end

    ## Liseré turquoise, juste à l'intérieur du bord de l'ombre : l'ozone de la haute
    ## atmosphère y absorbe le rouge et laisse cette frange bleutée que les photographes
    ## connaissent bien. Dessiné AVANT les étapes rouges, qui commencent un peu en retrait.
    voilerIntersection(mx, my, rl, ox, oy, R_OMBRE * rl, Color(0.86, 0.97, 1.0))

    ## Ombre : plus aucune lumière directe, seulement celle que l'atmosphère terrestre
    ## réfracte — rouge, car le bleu y est diffusé. Le cône d'ombre a un bord FRANC :
    ## l'assombrissement est presque complet dès l'entrée, et seule une bande étroite
    ## adoucit la transition. Étaler ce dégradé sur tout le rayon donnait une ombre molle,
    ## bien plus claire que la réalité.
    for k = 0, 9 do
        var r = R_OMBRE * (1 - 0.10 * k / 10)
        voilerIntersection(mx, my, rl, ox, oy, r * rl, Color(0.90, 0.76, 0.74))
    end
    ## Plancher de l'ombre : l'intérieur, uniformément cuivré, à peine plus sombre au centre.
    for k = 0, 3 do
        var r = R_OMBRE * (0.90 - 0.55 * k / 4)
        voilerIntersection(mx, my, rl, ox, oy, r * rl, Color(0.90, 0.72, 0.68))
    end
    graphics.blendMode(blend.ALPHA)

    ## Bandeau d'information : phase, magnitude, temps simulé.
    graphics.fontSize(H * 0.032)
    graphics.stroke(Color(0.88, 0.9, 0.96))
    ## L'interpolation formate directement : {expr:.2f} évite un arrondi à la main.
    graphics.text("{phase()}   magnitude {magnitude():.2f}", W * 0.04, H * 0.06)
    graphics.fontSize(H * 0.024)
    graphics.stroke(Color(0.6, 0.65, 0.78))
    ## Les accents français passent (la police embarquée les couvre), mais pas un point
    ## médian : un glyphe absent s'afficherait « ? ».
    graphics.text("T+{t:.1f} h   -   éclipse {config.type}", W * 0.04, H * 0.11)
end
