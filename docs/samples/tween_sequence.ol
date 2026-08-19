## Module tween — une SUITE d'étapes : `tween.sequence` joue les étapes l'une après
## l'autre, chacune partant de ce que la précédente a laissé. Le moteur les avance à
## chaque frame ; le dessin ne fait que LIRE des champs, sans jamais parler de temps.
##
## Clique n'importe où pour mettre la scène en pause ou la reprendre.

global balle = {x: 0, y: 0, rx: 0, ry: 0, teinte: Color(0.45, 0.8, 1)}
global ombre = {largeur: 0, opacite: 0.35}

## Les trois points d'attente : le même clignotement pour tous, mais décalé dans le temps
## par un délai proportionnel à leur rang.
global points = []

## Le handle de la séquence : il sert à lire son avancement et à la suspendre.
global rebond = nil
global suspendu = false

func rayon()
    return H * 0.045
end

func sol()
    return H * 0.72
end

func plafond()
    return H * 0.22
end

## Le rebond, en cinq étapes. L'écrasement à l'impact et la détente qui suit ne durent
## qu'un dixième de seconde : c'est ce décalage entre les durées qui donne du poids à la
## balle, et c'est exactement ce qu'une suite d'étapes sait exprimer.
func lancerRebond()
    var r = rayon()
    balle.x = CW
    balle.y = plafond()
    balle.rx = r
    balle.ry = r

    rebond = tween.sequence(balle, [
        ## Chute : la balle accélère, et s'étire un peu dans le sens du mouvement.
        {to: {y: sol(), rx: r * 0.88, ry: r * 1.15}, delay: 0.45, curve: "easeInQuad"},
        ## Impact : elle s'écrase. La cible est lue au démarrage de l'étape, donc elle
        ## part de l'étirement laissé par la chute — aucune valeur à recopier ici.
        {to: {rx: r * 1.45, ry: r * 0.55}, delay: 0.08},
        ## Détente, avant de repartir.
        {to: {rx: r * 0.92, ry: r * 1.1}, delay: 0.1},
        ## Remontée : elle ralentit en approchant du sommet et retrouve sa forme ronde.
        {to: {y: plafond(), rx: r, ry: r}, delay: 0.55, curve: "easeOutQuad"},
        ## Une étape sans `to` : elle ne fait que laisser passer du temps.
        {delay: 0.15},
    ]).repeat()

    ## L'ombre suit le rebond sans en faire partie : deux tweens sur des objets différents
    ## avancent côte à côte. Elle s'élargit quand la balle descend, donc un aller-retour
    ## sans fin d'une durée calée sur la chute suffit.
    ombre.largeur = r * 0.9
    ombre.opacite = 0.12
    tween.to(ombre, {largeur: r * 2.4, opacite: 0.4}, 0.45, "easeInQuad").repeat(nil, true)

    ## Le même clignotement pour les trois points, décalé par un délai croissant : le
    ## départ d'une animation se retarde, sa déclaration n'a pas à attendre.
    for i = 1, #points do
        points[i].r = H * 0.008
        tween.to(points[i], {r: H * 0.02}, 0.4, "easeInOutSine").repeat(nil, true).delay(i * 0.13)
    end
end

func setup()
    graphics.canvas(W, H, "tween.sequence")
    for i = 1, 3 do
        points[i] = {r: 0}
    end
    lancerRebond()
end

func mouse.pressed(x, y)
    suspendu = not suspendu
    if suspendu then
        rebond.pause()
    else
        rebond.resume()
    end
end

func draw()
    graphics.clear(Color(0.08, 0.09, 0.13))
    graphics.noStroke()

    ## Le sol, puis l'ombre : deux repères qui rendent le poids de la balle lisible.
    graphics.fill(Color(1, 1, 1, 0.08))
    graphics.rect(0, sol() + rayon(), W, H)
    graphics.fill(Color(0, 0, 0, ombre.opacite))
    graphics.ellipse(balle.x, sol() + rayon() * 0.9, ombre.largeur * 2, rayon() * 0.45)

    ## La balle : une ellipse, puisque l'écrasement anime ses deux rayons séparément.
    graphics.fill(balle.teinte)
    graphics.ellipse(balle.x, balle.y, balle.rx * 2, balle.ry * 2)

    ## L'avancement de la SUITE entière, en temps : les étapes n'ont pas la même durée,
    ## et la barre progresse pourtant régulièrement.
    var large = W * 0.6
    var gauche = CW - large / 2
    var yb = H * 0.9
    graphics.fill(Color(1, 1, 1, 0.1))
    graphics.rect(gauche, yb, large, H * 0.008)
    graphics.fill(Color(0.45, 0.8, 1))
    graphics.rect(gauche, yb, large * rebond.progress(), H * 0.008)

    ## Les trois points, à droite de la barre : ils clignotent même en pause, car seule la
    ## séquence est suspendue.
    graphics.fill(Color(0.65, 0.72, 0.85))
    for i = 1, #points do
        graphics.circle(gauche + large + H * 0.03 * i, yb + H * 0.004, points[i].r)
    end

    graphics.fontSize(H * 0.028)
    graphics.stroke(Color(0.85, 0.88, 0.95))
    if suspendu then
        graphics.text("en pause — clique pour reprendre", gauche, H * 0.84)
    else
        graphics.text("clique pour mettre en pause", gauche, H * 0.84)
    end
end
